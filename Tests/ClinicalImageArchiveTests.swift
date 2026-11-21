import Compression
import Foundation
import zlib

private extension Data {
    mutating func littleEndian<T: FixedWidthInteger>(_ value: T) {
        var value = value.littleEndian
        Swift.withUnsafeBytes(of: &value) { append(contentsOf: $0) }
    }
}

@main
enum ClinicalImageArchiveTests {
    static func main() throws {
        let firstJPEG = Data([255, 216, 255, 1])
        let lastJPEG = Data([255, 216, 255, 10])
        let fixture = makeZIP([
            ("images/10.jpg", lastJPEG, false),
            ("images/2.jpg", firstJPEG, true),
            ("README.txt", Data("metadata".utf8), false),
        ])
        let archive = try ClinicalImageArchive(data: fixture)
        let first = try archive.imageData(at: 0)
        let last = try archive.imageData(at: 1)
        precondition(archive.imageCount == 2 && first == firstJPEG && last == lastJPEG)

        var corrupt = fixture
        corrupt[30 + "images/10.jpg".utf8.count + lastJPEG.count - 1] ^= 1
        let corruptArchive = try ClinicalImageArchive(data: corrupt)
        do {
            _ = try corruptArchive.imageData(at: 1)
            preconditionFailure("ZIP CRC mismatch accepted")
        } catch ClinicalImageArchive.Failure.invalidImage {}
        for invalid in [fixture.dropLast(), makeZIP([("../1.png", firstJPEG, true)])] {
            do {
                _ = try ClinicalImageArchive(data: invalid)
                preconditionFailure("Malformed ZIP accepted")
            } catch ClinicalImageArchive.Failure.invalidArchive {}
        }
        let dicom = try ClinicalImageArchive(data: makeZIP([
            ("IM2", makeDICOM(explicit: true), true),
            ("IM1", makeDICOM(explicit: false), true),
            ("IM3", makeDICOM(explicit: true, compressed: true), true),
        ]))
        for index in 0..<2 {
            let data = try dicom.imageData(at: index)
            let image = try ImagingFrameDecoder.decode(data).image
            precondition(image.width == 2 && image.height == 2)
        }
        do {
            _ = try dicom.imageData(at: 2)
            preconditionFailure("Unsupported DICOM transfer syntax accepted")
        } catch ClinicalImageArchive.Failure.unsupportedDICOM {}

        if let path = CommandLine.arguments.dropFirst().first {
            let exported = try ClinicalImageArchive(data: Data(contentsOf: URL(fileURLWithPath: path)))
            precondition(exported.imageCount == 500)
            for index in 0..<exported.imageCount {
                _ = try ImagingFrameDecoder.decode(exported.imageData(at: index))
            }
        }
        print("Clinical image archive tests passed")
    }

    private static func makeZIP(_ entries: [(String, Data, Bool)]) -> Data {
        var zip = Data()
        var directory = Data()
        for (path, content, compressed) in entries {
            let filename = Data(path.utf8)
            let method: UInt16 = compressed ? 8 : 0
            let bytes = compressed ? deflate(content) : content
            let crc = content.withUnsafeBytes { (buffer: UnsafeRawBufferPointer) in
                UInt32(crc32(0, buffer.bindMemory(to: UInt8.self).baseAddress, uInt(buffer.count)))
            }
            let offset = zip.count
            zip.littleEndian(UInt32(0x04034b50))
            zip.littleEndian(UInt16(20))
            zip.littleEndian(UInt16(0x800))
            zip.littleEndian(method)
            zip.littleEndian(UInt32(0))
            zip.littleEndian(crc)
            zip.littleEndian(UInt32(bytes.count))
            zip.littleEndian(UInt32(content.count))
            zip.littleEndian(UInt16(filename.count))
            zip.littleEndian(UInt16(0))
            zip.append(filename)
            zip.append(bytes)

            directory.littleEndian(UInt32(0x02014b50))
            directory.littleEndian(UInt16(20))
            directory.append(zip[(offset + 4)..<(offset + 28)])
            directory.append(Data(repeating: 0, count: 12))
            directory.littleEndian(UInt32(offset))
            directory.append(filename)
        }
        let offset = zip.count
        zip.append(directory)
        zip.littleEndian(UInt32(0x06054b50))
        zip.littleEndian(UInt32(0))
        zip.littleEndian(UInt16(entries.count))
        zip.littleEndian(UInt16(entries.count))
        zip.littleEndian(UInt32(directory.count))
        zip.littleEndian(UInt32(offset))
        zip.littleEndian(UInt16(0))
        return zip
    }

    private static func deflate(_ data: Data) -> Data {
        var output = Data(count: data.count + 64)
        let count = output.withUnsafeMutableBytes { (destination: UnsafeMutableRawBufferPointer) in
            data.withUnsafeBytes { (source: UnsafeRawBufferPointer) in
                compression_encode_buffer(destination.bindMemory(to: UInt8.self).baseAddress!, destination.count,
                                          source.bindMemory(to: UInt8.self).baseAddress!, source.count, nil, COMPRESSION_ZLIB)
            }
        }
        precondition(count > 0)
        return output.prefix(count)
    }

    private static func makeDICOM(explicit: Bool, compressed: Bool = false) -> Data {
        var image = Data(repeating: 0, count: 128)
        image.append(Data("DICM".utf8))
        func element(_ group: UInt16, _ tag: UInt16, _ vr: String, _ value: Data, explicit: Bool) {
            image.littleEndian(group)
            image.littleEndian(tag)
            if explicit {
                image.append(Data(vr.utf8))
                if vr == "OW" { image.littleEndian(UInt16(0)) }
            }
            if !explicit || vr == "OW" { image.littleEndian(UInt32(value.count)) }
            else { image.littleEndian(UInt16(value.count)) }
            image.append(value)
        }
        let syntax = compressed ? "1.2.840.10008.1.2.4.50" : explicit ? "1.2.840.10008.1.2.1" : "1.2.840.10008.1.2"
        var syntaxData = Data(syntax.utf8)
        if !syntaxData.count.isMultiple(of: 2) { syntaxData.append(0) }
        element(2, 0x10, "UI", syntaxData, explicit: true)
        element(0x28, 0x0002, "US", Data([1, 0]), explicit: explicit)
        element(0x28, 0x0004, "CS", Data("MONOCHROME2 ".utf8), explicit: explicit)
        for (tag, value): (UInt16, UInt8) in [(0x10, 2), (0x11, 2), (0x100, 16), (0x101, 12), (0x102, 11), (0x103, 1)] {
            element(0x28, tag, "US", Data([value, 0]), explicit: explicit)
        }
        element(0x7fe0, 0x10, "OW", Data([0, 8, 0, 0, 0xff, 7, 0x40, 0]), explicit: explicit)
        return image
    }
}
