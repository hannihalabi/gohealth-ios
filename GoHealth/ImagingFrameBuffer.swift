import Foundation
import CoreGraphics
import ImageIO

struct ImagingFrame: Decodable, Identifiable {
    let id: String
    let index: Int
    let positionMm: Double?
    let rows: Int
    let columns: Int
    let spacing: [Double]
    let windowCenter: Double
    let windowWidth: Double

    var displayAspectRatio: Double {
        guard rows > 0 else { return 1 }
        if spacing.count == 2, spacing[0] > 0, spacing[1] > 0 {
            return Double(columns) * spacing[1] / (Double(rows) * spacing[0])
        }
        return Double(columns) / Double(rows)
    }
}


enum ImagingWindow: String, CaseIterable {
    case standard = "Standard", lungs = "Lunga", bone = "Skelett"
    func settings(_ frame: ImagingFrame) -> (Double, Double) {
        switch self {
        case .standard: (frame.windowCenter, frame.windowWidth)
        case .lungs: (-600, 1500)
        case .bone: (300, 1500)
        }
    }
}


/// A strict memory budget; the currently displayed frame is retained by the view separately.
struct ImagingFrameBuffer<Key: Hashable, Value> {
    private struct Entry {
        let value: Value
        let cost: Int
        var access: UInt64
    }
    let costLimit: Int
    private var entries: [Key: Entry] = [:]
    private var clock: UInt64 = 0
    private(set) var totalCost = 0
    var count: Int { entries.count }

    func contains(_ key: Key) -> Bool { entries[key] != nil }

    mutating func value(for key: Key) -> Value? {
        guard var entry = entries[key] else { return nil }
        clock &+= 1
        entry.access = clock
        entries[key] = entry
        return entry.value
    }

    @discardableResult
    mutating func insert(_ value: Value, for key: Key, cost: Int) -> Bool {
        guard cost > 0, cost <= costLimit else { return false }
        if let old = entries.removeValue(forKey: key) { totalCost -= old.cost }
        while totalCost + cost > costLimit, let oldest = entries.min(by: { $0.value.access < $1.value.access }) {
            totalCost -= oldest.value.cost
            entries.removeValue(forKey: oldest.key)
        }
        clock &+= 1
        entries[key] = Entry(value: value, cost: cost, access: clock)
        totalCost += cost
        return true
    }

    mutating func removeAll() {
        entries.removeAll()
        totalCost = 0
    }
}

struct PreparedImagingFrame: @unchecked Sendable {
    let image: CGImage
    var cost: Int { image.bytesPerRow * image.height }
}

enum ImagingFrameDecoder {
    enum Failure: Error { case invalidImage }

    /// ImageIO decodes before the image reaches SwiftUI. Monochrome data stays monochrome.
    static func decode(_ data: Data) throws -> PreparedImagingFrame {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 4096, height <= 4096 else { throw Failure.invalidImage }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let image: CGImage?
        if orientation == 1 {
            image = CGImageSourceCreateImageAtIndex(source, 0, [
                kCGImageSourceShouldCache: true,
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        } else {
            image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: max(width, height),
                kCGImageSourceShouldCacheImmediately: true
            ] as CFDictionary)
        }
        guard let image else { throw Failure.invalidImage }
        try Task.checkCancellation()
        return PreparedImagingFrame(image: image)
    }
}
