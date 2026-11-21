import Foundation
import CoreGraphics
import ImageIO

@MainActor
private final class TestImageSource: ImagingFrameSource {
    let data: Data
    let delay: Duration
    var calls = 0
    var active = 0
    var maximumActive = 0
    init(data: Data, delay: Duration = .milliseconds(1)) { self.data = data; self.delay = delay }
    func imageData(frame: ImagingFrame, center: Double, width: Double, preview: Bool) async throws -> Data {
        calls += 1
        active += 1
        maximumActive = max(maximumActive, active)
        defer { active -= 1 }
        // Deliberately return even after cancellation to test stale-response protection.
        try? await Task.sleep(for: delay)
        return data
    }
}

@main
@MainActor
enum RadiologyPlaybackTests {
    static func makeImage(width: Int) -> Data {
        let context = CGContext(data: nil, width: width, height: 20, bitsPerComponent: 8, bytesPerRow: width,
                                space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    static func frames(_ count: Int, prefix: String = "frame") -> [ImagingFrame] {
        (0..<count).map { ImagingFrame(id: "\(prefix)-\($0)", index: $0, positionMm: nil, rows: 20, columns: 30,
                                      spacing: [], windowCenter: 40, windowWidth: 400) }
    }

    static func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(10)
        while !condition() {
            precondition(ContinuousClock.now < deadline, "Playback preparation timed out")
            try await Task.sleep(for: .milliseconds(5))
        }
    }

    static func main() async throws {
        let source = TestImageSource(data: makeImage(width: 30))
        let model = RadiologyPlayback()
        model.prepare(api: source, frames: frames(500), window: .standard, preview: true, index: 0)
        try await waitUntil { !model.isPreparing }
        precondition(model.preparedCount == 500 && source.calls == 500)
        precondition(source.maximumActive <= 4, "Unbounded prefetch requests")
        let fetchesBeforeScrubbing = source.calls
        for turn in 0..<10_000 {
            let index = (turn * 197) % 500
            model.select(index)
            precondition(model.displayedIndex == index && model.image != nil && !model.isLoading,
                         "Warm selection must publish the matching frame synchronously without a blank image")
        }
        await Task.yield()
        precondition(source.calls == fetchesBeforeScrubbing, "Warm scrubbing performed network requests")

        let previewSource = TestImageSource(data: makeImage(width: 30))
        let preview = RadiologyPlayback(bufferCostLimit: 24 * 1024 * 1024)
        preview.prepare(api: previewSource, frames: frames(500), window: .standard, preview: true, index: 250,
                        preloadWholeSeries: false)
        try await waitUntil { preview.preparedCount == 17 }
        precondition(!preview.isPreparing && preview.displayedIndex == 250 && previewSource.calls == 17,
                     "The overview must load only the selected slice and its neighbors")
        preview.select(251)
        precondition(preview.displayedIndex == 251 && !preview.isLoading)
        preview.select(480)
        precondition(preview.displayedIndex == 251 && preview.image != nil,
                     "Keep the displayed slice visible while fetching a new one")
        try await waitUntil { preview.displayedIndex == 480 }
        preview.stop()

        let old = TestImageSource(data: makeImage(width: 30), delay: .milliseconds(100))
        let next = TestImageSource(data: makeImage(width: 10))
        model.prepare(api: old, frames: frames(20, prefix: "old"), window: .standard, preview: true, index: 0)
        await Task.yield()
        model.prepare(api: next, frames: frames(1, prefix: "new"), window: .standard, preview: true, index: 0)
        try await waitUntil { !model.isPreparing }
        try await Task.sleep(for: .milliseconds(150))
        precondition(model.image?.width == 10 && model.preparedCount == 1, "A cancelled generation overwrote the current image")

        model.prepare(api: old, frames: frames(10), window: .standard, preview: false, index: 0)
        await Task.yield()
        model.stop()
        try await Task.sleep(for: .milliseconds(150))
        precondition(model.image == nil && model.preparedCount == 0 && !model.isLoading)
        print("Playback tests passed: 500-frame prefetch; 10,000 synchronous matching selections; neighborhood-only preview; max four fetches; stale/cancelled responses rejected.")
    }
}
