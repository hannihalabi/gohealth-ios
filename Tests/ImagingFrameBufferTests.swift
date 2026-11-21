import Foundation
import CoreGraphics
import ImageIO

@main
enum ImagingFrameBufferTests {
    static func main() throws {
        var bounded = ImagingFrameBuffer<String, String>(costLimit: 10)
        bounded.insert("one", for: "one", cost: 4)
        bounded.insert("two", for: "two", cost: 4)
        precondition(bounded.value(for: "one") == "one")
        bounded.insert("three", for: "three", cost: 4)
        precondition(bounded.value(for: "two") == nil, "Recently accessed images must survive eviction")
        precondition(bounded.totalCost == 8)
        precondition(!bounded.insert("oversized", for: "huge", cost: 11))
        bounded.insert("replacement", for: "one", cost: 6)
        precondition(bounded.totalCost == 10)
        bounded.removeAll()
        precondition(bounded.count == 0 && bounded.totalCost == 0)
        do {
            _ = try ImagingFrameDecoder.decode(Data("corrupt".utf8))
            preconditionFailure("Corrupt frame decoded")
        } catch ImagingFrameDecoder.Failure.invalidImage {}
        print("Frame buffer: eviction, accounting, oversized input and corrupt-image tests passed")

        guard CommandLine.arguments.count == 2 else { return }
        let paths = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1])))
        var buffer = ImagingFrameBuffer<Int, PreparedImagingFrame>(costLimit: 192 * 1024 * 1024)
        let loadStart = DispatchTime.now().uptimeNanoseconds
        for (index, path) in paths.enumerated() {
            let frame = try autoreleasepool { try ImagingFrameDecoder.decode(Data(contentsOf: URL(fileURLWithPath: path))) }
            precondition(buffer.insert(frame, for: index, cost: frame.cost))
        }
        let loadMs = Double(DispatchTime.now().uptimeNanoseconds - loadStart) / 1_000_000
        precondition(buffer.count == paths.count, "Test series does not fit the decoded memory budget")
        var samples: [Double] = []
        // Jump through the complete real test series, including reverse and non-adjacent selections.
        for turn in 0..<10_000 {
            let index = (turn * 197) % paths.count
            let start = DispatchTime.now().uptimeNanoseconds
            guard let frame = buffer.value(for: index) else { preconditionFailure("Warm selection missed cache") }
            precondition(frame.image.width > 0)
            samples.append(Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000)
        }
        samples.sort()
        print(String(format: "%d real frames decoded in %.0f ms; memory %.1f MiB; 10,000 warm selections: p95 %.4f ms, max %.4f ms",
                     paths.count, loadMs, Double(buffer.totalCost) / 1_048_576, samples[9500], samples.last!))
    }
}
