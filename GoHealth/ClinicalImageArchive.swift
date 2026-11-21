import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import zlib

/// Reads image entries in memory. No filename from the archive is used on the filesystem.
struct ClinicalImageArchive: Sendable {
    enum Failure: LocalizedError {
        case invalidArchive, invalidImage, unsupportedDICOM, tooLarge

        var errorDescription: String? {
            switch self {
            case .invalidArchive: "Bildarkivet kunde inte läsas."
            case .invalidImage: "Den här bilden kunde inte läsas."
            case .unsupportedDICOM: "Appen kan inte visa det här DICOM-formatet."
            case .tooLarge: "Filen är för stor för bildvisaren."
            }
        }
    }

    private enum ImageKind: Sendable { case jpeg, png, dicom }

    private struct Entry: Sendable {
        let name: String
        let kind: ImageKind
        let bytes: Range<Int>
        let imageSize: Int
        let crc: UInt32
        let method: UInt16
    }

    static let maximumArchiveBytes = 50 * 1024 * 1024
    private static let maximumImageBytes = 32 * 1024 * 1024
    private let data: Data
    private let entries: [Entry]
    var imageCount: Int { entries.count }

    init(data: Data) throws {
        guard data.count <= Self.maximumArchiveBytes else { throw Failure.tooLarge }
        self.data = data
        entries = try data.withUnsafeBytes { try Self.readDirectory(ArchiveBytes(bytes: $0)) }
    }

    func imageData(at index: Int) throws -> Data {
        try Task.checkCancellation()
        guard entries.indices.contains(index) else { throw Failure.invalidImage }
        let entry = entries[index]
        guard entry.imageSize <= Self.maximumImageBytes else { throw Failure.tooLarge }
        let image = try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            let source = UnsafeRawBufferPointer(rebasing: bytes[entry.bytes])
            if entry.method == 0 { return Data(source) }
            return try Self.inflate(source, size: entry.imageSize)
        }
        let checksum = image.withUnsafeBytes { bytes in
            crc32(0, bytes.bindMemory(to: UInt8.self).baseAddress, uInt(bytes.count))
        }
        guard checksum == entry.crc else { throw Failure.invalidImage }
        try Task.checkCancellation()
        switch entry.kind {
        case .jpeg:
            guard image.starts(with: [0xff, 0xd8, 0xff]) else { throw Failure.invalidImage }
            return image
        case .png:
            guard image.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { throw Failure.invalidImage }
            return image
        case .dicom:
            return try DICOMPreview.imageData(image)
        }
    }

    private static func inflate(_ input: UnsafeRawBufferPointer, size: Int) throws -> Data {
        var stream = z_stream()
        let rawDeflateWindowBits: Int32 = -15
        guard inflateInit2_(&stream, rawDeflateWindowBits, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK
        else { throw Failure.invalidImage }
        defer { inflateEnd(&stream) }
        var output = Data(count: size)
        let status = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: UInt8.self).baseAddress)
            stream.avail_in = uInt(input.count)
            stream.next_out = destination.bindMemory(to: UInt8.self).baseAddress
            stream.avail_out = uInt(destination.count)
            return zlib.inflate(&stream, Z_FINISH)
        }
        guard status == Z_STREAM_END, stream.total_out == size, stream.avail_in == 0 else { throw Failure.invalidImage }
        return output
    }

    private static func readDirectory(_ reader: ArchiveBytes) throws -> [Entry] {
        let endRecordSize = 22
        let directoryHeaderSize = 46
        let localHeaderSize = 30
        guard reader.count >= endRecordSize + localHeaderSize else { throw Failure.invalidArchive }
        let lastOffset = reader.count - endRecordSize
        let end = stride(from: lastOffset, through: max(0, lastOffset - 65535), by: -1).first {
            reader.uint32($0) == 0x06054b50 && $0 + endRecordSize + Int(reader.uint16($0 + 20)) == reader.count
        }
        guard let end else { throw Failure.invalidArchive }
        let entryCount = Int(reader.uint16(end + 10))
        let directorySize = Int(reader.uint32(end + 12))
        let directoryStart = Int(reader.uint32(end + 16))
        guard reader.uint16(end + 4) == 0, reader.uint16(end + 6) == 0,
              entryCount == Int(reader.uint16(end + 8)), (1...10000).contains(entryCount),
              directoryStart >= localHeaderSize, directoryStart + directorySize == end,
              directorySize <= 4 * 1024 * 1024 else { throw Failure.invalidArchive }

        var cursor = directoryStart
        var allPaths = Set<String>()
        var localRanges: [Range<Int>] = []
        var images: [Entry] = []
        var uncompressedTotal = 0
        for _ in 0..<entryCount {
            try Task.checkCancellation()
            guard cursor + directoryHeaderSize <= end, reader.uint32(cursor) == 0x02014b50 else {
                throw Failure.invalidArchive
            }
            let flags = reader.uint16(cursor + 8)
            let method = reader.uint16(cursor + 10)
            let crc = reader.uint32(cursor + 16)
            let compressed = Int(reader.uint32(cursor + 20))
            let uncompressed = Int(reader.uint32(cursor + 24))
            let nameStart = cursor + directoryHeaderSize
            let nameEnd = nameStart + Int(reader.uint16(cursor + 28))
            let next = nameEnd + Int(reader.uint16(cursor + 30)) + Int(reader.uint16(cursor + 32))
            let local = Int(reader.uint32(cursor + 42))
            guard nameEnd > nameStart, next <= end, reader.uint16(cursor + 34) == 0,
                  flags & 0x2041 == 0, method == 0 || method == 8, method != 0 || compressed == uncompressed,
                  local + localHeaderSize <= directoryStart, reader.uint32(local) == 0x04034b50,
                  reader.uint16(local + 6) == flags, reader.uint16(local + 8) == method else {
                throw Failure.invalidArchive
            }

            let localNameLength = Int(reader.uint16(local + 26))
            let localNameEnd = local + localHeaderSize + localNameLength
            let dataStart = localNameEnd + Int(reader.uint16(local + 28))
            let dataEnd = dataStart + compressed
            guard dataEnd <= directoryStart, nameEnd - nameStart == localNameLength,
                  reader.bytes[nameStart..<nameEnd].elementsEqual(reader.bytes[(local + localHeaderSize)..<localNameEnd]) else {
                throw Failure.invalidArchive
            }
            if flags & 8 == 0 && (reader.uint32(local + 14) != crc || reader.uint32(local + 18) != compressed ||
                                reader.uint32(local + 22) != uncompressed) { throw Failure.invalidArchive }

            guard let name = String(bytes: reader.bytes[nameStart..<nameEnd], encoding: flags & 0x800 == 0 ? .isoLatin1 : .utf8)
            else { throw Failure.invalidArchive }
            let isFolder = name.hasSuffix("/")
            let path = isFolder ? String(name.dropLast()) : name
            let components = path.split(separator: "/", omittingEmptySubsequences: false)
            let madeBy = reader.bytes[cursor + 5]
            let fileType = (reader.uint32(cursor + 38) >> 16) & 0xf000
            guard !components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }),
                  !path.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 || $0 == ":" || $0 == "\\" }),
                  allPaths.insert(path.precomposedStringWithCanonicalMapping.uppercased()).inserted,
                  (madeBy != 3 && madeBy != 19) || fileType == 0 || fileType == (isFolder ? 0x4000 : 0x8000)
            else { throw Failure.invalidArchive }

            uncompressedTotal += uncompressed
            guard uncompressedTotal <= 2 * 1024 * 1024 * 1024 else { throw Failure.tooLarge }
            if !isFolder, let kind = imageKind(components) {
                guard compressed > 0, uncompressed > 0 else { throw Failure.invalidArchive }
                images.append(Entry(name: path, kind: kind, bytes: dataStart..<dataEnd,
                                    imageSize: uncompressed, crc: crc, method: method))
            }
            localRanges.append(local..<dataEnd)
            cursor = next
        }
        let ranges = localRanges.sorted { $0.lowerBound < $1.lowerBound }
        guard cursor == end, !images.isEmpty, ranges.first?.lowerBound == 0,
              zip(ranges, ranges.dropFirst()).allSatisfy({ $0.upperBound <= $1.lowerBound }) else {
            throw Failure.invalidArchive
        }
        let locale = Locale(identifier: "en_US_POSIX")
        return images.sorted {
            let order = $0.name.compare($1.name, options: [.caseInsensitive, .numeric], locale: locale)
            return order == .orderedSame ? $0.name < $1.name : order == .orderedAscending
        }
    }

    private static func imageKind(_ components: [Substring]) -> ImageKind? {
        let parts = components.map { $0.uppercased() }
        guard let name = parts.last, !parts.contains("__MACOSX"), !name.hasPrefix("._"),
              !["DICOMDIR", "README", "LICENSE", "THUMBS.DB", ".DS_STORE"].contains(name) else { return nil }
        switch (name as NSString).pathExtension {
        case "JPG", "JPEG", "JPE": return .jpeg
        case "PNG": return .png
        case "DCM", "DICOM", "IMA": return .dicom
        default:
            if name.range(of: #"^(?:IM|IMG|I)\d+$|^\d+(?:\.\d+)+$"#, options: .regularExpression) != nil { return .dicom }
            if parts.dropLast().contains("DICOM"), name.range(of: #"^[A-Z\d_-]+$"#, options: .regularExpression) != nil {
                return .dicom
            }
            return nil
        }
    }
}

private struct ArchiveBytes {
    let bytes: UnsafeRawBufferPointer
    var count: Int { bytes.count }
    func uint16(_ offset: Int) -> UInt16 { bytes.loadUnaligned(fromByteOffset: offset, as: UInt16.self).littleEndian }
    func uint32(_ offset: Int) -> UInt32 { bytes.loadUnaligned(fromByteOffset: offset, as: UInt32.self).littleEndian }
}

/// Native single-frame monochrome DICOM can be shown as a display preview.
/// Unsupported transfer syntaxes or presentation transforms are rejected explicitly.
private enum DICOMPreview {
    private typealias Failure = ClinicalImageArchive.Failure

    private struct Element {
        let tag: UInt32
        let valueStart: Int
        let valueEnd: Int?
    }

    static func imageData(_ dicom: Data) throws -> Data {
        try dicom.withUnsafeBytes {
            let reader = ArchiveBytes(bytes: $0)
            let (pixels, width, height) = try grayscalePixels(reader)
            guard let provider = CGDataProvider(data: pixels as CFData),
                  let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 8, bytesPerRow: width,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: [], provider: provider, decode: nil,
                                      shouldInterpolate: true, intent: .defaultIntent) else { throw Failure.invalidImage }
            let output = NSMutableData()
            guard let encoder = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil)
            else { throw Failure.invalidImage }
            CGImageDestinationAddImage(encoder, image, nil)
            guard CGImageDestinationFinalize(encoder) else { throw Failure.invalidImage }
            return output as Data
        }
    }

    private static func grayscalePixels(_ reader: ArchiveBytes) throws -> (pixels: Data, width: Int, height: Int) {
        guard reader.count >= 132, reader.bytes[128..<132].elementsEqual("DICM".utf8) else { throw Failure.unsupportedDICOM }
        var cursor = 132
        var syntax: String?
        while cursor + 8 <= reader.count, reader.uint16(cursor) == 2 {
            let element = try readElement(reader, at: cursor, explicit: true)
            guard let end = element.valueEnd else { throw Failure.invalidImage }
            if element.tag == 0x00020010 { syntax = string(element, reader) }
            cursor = end
        }
        let explicit: Bool
        switch syntax {
        case "1.2.840.10008.1.2": explicit = false
        case "1.2.840.10008.1.2.1": explicit = true
        default: throw Failure.unsupportedDICOM
        }

        var elements: [UInt32: Element] = [:]
        let relevant: Set<UInt32> = [0x00280002, 0x00280004, 0x00280008, 0x00280010, 0x00280011, 0x00280100,
                                     0x00280101, 0x00280102, 0x00280103, 0x00281050, 0x00281051, 0x00281052,
                                     0x00281053, 0x00281056, 0x00283000, 0x00283010, 0x20500020, 0x7fe00010]
        while cursor + 8 <= reader.count {
            try Task.checkCancellation()
            let element = try readElement(reader, at: cursor, explicit: explicit)
            if relevant.contains(element.tag) {
                guard elements.updateValue(element, forKey: element.tag) == nil else { throw Failure.invalidImage }
            }
            if element.tag == 0x7fe00010 { break }
            if let end = element.valueEnd {
                cursor = end
            } else {
                cursor = try skipUndefined(reader, at: element.valueStart, until: 0xfffee0dd, explicit: explicit, depth: 0)
            }
        }

        func integer(_ tag: UInt32) -> Int? {
            guard let element = elements[tag], element.valueEnd == element.valueStart + 2 else { return nil }
            return Int(reader.uint16(element.valueStart))
        }
        func text(_ tag: UInt32) -> String? { elements[tag].flatMap { string($0, reader) } }
        func decimal(_ tag: UInt32) -> Double? {
            guard let first = text(tag)?.split(separator: "\\", omittingEmptySubsequences: false).first,
                  let value = Double(first.trimmingCharacters(in: .whitespaces)), value.isFinite else { return nil }
            return value
        }

        guard let pixelData = elements[0x7fe00010], let end = pixelData.valueEnd,
              let height = integer(0x00280010), let width = integer(0x00280011),
              (1...4096).contains(height), (1...4096).contains(width),
              let allocated = integer(0x00280100), allocated == 8 || allocated == 16,
              let stored = integer(0x00280101), (1...allocated).contains(stored), integer(0x00280102) == stored - 1,
              let representation = integer(0x00280103), (0...1).contains(representation),
              integer(0x00280002) == 1, elements[0x00280008] == nil || text(0x00280008) == "1",
              let photometric = text(0x00280004), photometric == "MONOCHROME1" || photometric == "MONOCHROME2",
              elements[0x00283000] == nil, elements[0x20500020] == nil || text(0x20500020) == "IDENTITY",
              elements[0x00281056] == nil || text(0x00281056) == "LINEAR"
        else { throw Failure.unsupportedDICOM }

        let count = width * height
        let bytesPerPixel = allocated / 8
        let expectedBytes = count * bytesPerPixel
        guard end - pixelData.valueStart == expectedBytes + expectedBytes % 2 else { throw Failure.invalidImage }
        let mask = (1 << stored) - 1
        let sign = 1 << (stored - 1)
        let invert = photometric == "MONOCHROME1"
        let slope = decimal(0x00281053) ?? 1
        let intercept = decimal(0x00281052) ?? 0
        guard slope != 0, abs(slope) <= 1e12, abs(intercept) <= 1e12,
              elements[0x00281053] == nil || decimal(0x00281053) != nil,
              elements[0x00281052] == nil || decimal(0x00281052) != nil else { throw Failure.unsupportedDICOM }

        func sample(_ index: Int) -> Double {
            let offset = pixelData.valueStart + index * bytesPerPixel
            let raw = bytesPerPixel == 1 ? Int(reader.bytes[offset]) : Int(reader.uint16(offset))
            let value = raw & mask
            let signed = representation == 1 && value & sign != 0 ? value - (mask + 1) : value
            return Double(signed) * slope + intercept
        }

        let lower: Double
        let upper: Double
        if let center = decimal(0x00281050), let span = decimal(0x00281051), span >= 1,
           abs(center) <= 1e18, span <= 1e18 {
            lower = center - 0.5 - (span - 1) / 2
            upper = center - 0.5 + (span - 1) / 2
        } else {
            guard elements[0x00281050] == nil, elements[0x00281051] == nil, elements[0x00283010] == nil
            else { throw Failure.unsupportedDICOM }
            var minimum = sample(0)
            var maximum = minimum
            for index in 1..<count {
                if index.isMultiple(of: 16384) { try Task.checkCancellation() }
                let value = sample(index)
                minimum = min(minimum, value)
                maximum = max(maximum, value)
            }
            lower = minimum
            upper = maximum
        }

        var pixels = Data(count: count)
        try pixels.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            for index in 0..<count {
                if index.isMultiple(of: 16384) { try Task.checkCancellation() }
                let value = sample(index)
                let shade: UInt8
                if value <= lower { shade = 0 }
                else if value >= upper { shade = 255 }
                else { shade = UInt8(((value - lower) / (upper - lower) * 255).rounded()) }
                destination[index] = invert ? 255 - shade : shade
            }
        }
        return (pixels, width, height)
    }

    private static func string(_ element: Element, _ reader: ArchiveBytes) -> String? {
        guard let end = element.valueEnd, end - element.valueStart <= 256 else { return nil }
        return String(bytes: reader.bytes[element.valueStart..<end], encoding: .ascii)?
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
    }

    private static func readElement(_ reader: ArchiveBytes, at offset: Int, explicit: Bool) throws -> Element {
        guard offset + 8 <= reader.count else { throw Failure.invalidImage }
        let group = UInt32(reader.uint16(offset))
        let tag = group << 16 | UInt32(reader.uint16(offset + 2))
        let valueStart: Int
        let length: UInt32
        if explicit, group != 0xfffe {
            let vr = reader.uint16(offset + 4)
            let letters = [reader.bytes[offset + 4], reader.bytes[offset + 5]]
            guard letters.allSatisfy({ (65...90).contains($0) }) else { throw Failure.invalidImage }
            // These explicit value representations have two reserved bytes and a 32-bit length.
            if [0x424f, 0x444f, 0x464f, 0x4c4f, 0x564f, 0x574f, 0x5153, 0x4355, 0x4e55, 0x5255, 0x5455, 0x5653, 0x5655].contains(Int(vr)) {
                guard offset + 12 <= reader.count, reader.uint16(offset + 6) == 0 else { throw Failure.invalidImage }
                valueStart = offset + 12
                length = reader.uint32(offset + 8)
            } else {
                valueStart = offset + 8
                length = UInt32(reader.uint16(offset + 6))
            }
        } else {
            valueStart = offset + 8
            length = reader.uint32(offset + 4)
        }
        if length == UInt32.max { return Element(tag: tag, valueStart: valueStart, valueEnd: nil) }
        let end = valueStart + Int(length)
        guard length.isMultiple(of: 2), end <= reader.count else { throw Failure.invalidImage }
        return Element(tag: tag, valueStart: valueStart, valueEnd: end)
    }

    private static func skipUndefined(_ reader: ArchiveBytes, at start: Int, until delimiter: UInt32,
                                      explicit: Bool, depth: Int) throws -> Int {
        guard depth < 12 else { throw Failure.unsupportedDICOM }
        var cursor = start
        while cursor + 8 <= reader.count {
            try Task.checkCancellation()
            let element = try readElement(reader, at: cursor, explicit: explicit)
            if element.tag == delimiter {
                guard element.valueEnd == element.valueStart else { throw Failure.invalidImage }
                return element.valueStart
            }
            if let end = element.valueEnd {
                cursor = end
            } else {
                let nextDelimiter: UInt32 = element.tag == 0xfffee000 ? 0xfffee00d : 0xfffee0dd
                cursor = try skipUndefined(reader, at: element.valueStart, until: nextDelimiter, explicit: explicit, depth: depth + 1)
            }
        }
        throw Failure.invalidImage
    }
}
