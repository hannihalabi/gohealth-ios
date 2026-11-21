import Foundation

@main
enum BundledImagingDemoTests {
    static func main() throws {
        precondition(CommandLine.arguments.count == 2, "Pass the bundled RadiologyDemo directory")
        let input = URL(fileURLWithPath: CommandLine.arguments[1])
        let demo: BundledImagingDemo
        if input.pathExtension == "app", let bundle = Bundle(url: input) {
            demo = try BundledImagingDemo(bundle: bundle)
        } else {
            demo = try BundledImagingDemo(root: input)
        }
        let root = demo.root
        let capabilities = try JSONSerialization.jsonObject(with: demo.responseData(for: "v1/capabilities")) as! [String: Any]
        precondition(capabilities["mode"] as? String == "offline_demo")
        precondition(capabilities["can_import"] as? Bool == false)
        precondition(capabilities["patient_id"] is NSNull, "Test data must not pretend to belong to a patient")
        let studies = try JSONSerialization.jsonObject(with: demo.responseData(for: "v1/studies")) as! [[String: Any]]
        precondition(studies.count == 1 && studies[0]["synthetic"] as? Bool == false)
        let metadata = try JSONSerialization.jsonObject(with: demo.responseData(for: "v1/series/\(BundledImagingDemo.seriesID)")) as! [String: Any]
        let frames = metadata["frames"] as! [[String: Any]]
        precondition(frames.count == 500)
        let started = DispatchTime.now().uptimeNanoseconds
        for (index, frame) in frames.enumerated() {
            precondition(frame["index"] as? Int == index)
            precondition(frame["position_mm"] is NSNull && (frame["spacing"] as? [Double]) == [])
            let data = try demo.frameData(id: frame["id"] as! String)
            let decoded = try ImagingFrameDecoder.decode(data)
            precondition(decoded.image.width == frame["columns"] as? Int)
            precondition(decoded.image.height == frame["rows"] as? Int)
        }
        do {
            _ = try demo.frameData(id: "../manifest.json")
            preconditionFailure("Unknown frame read")
        } catch BundledImagingDemo.Failure.unknownResource {}
        do {
            _ = try demo.responseData(for: "v1/series/\(BundledImagingDemo.seriesID)/analysis")
            preconditionFailure("Demo exposed analysis")
        } catch BundledImagingDemo.Failure.unknownResource {}
        do {
            _ = try BundledImagingDemo(root: URL(string: "https://example.invalid/demo")!)
            preconditionFailure("Demo accepted a network resource")
        } catch BundledImagingDemo.Failure.invalidManifest {}

        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary.appendingPathComponent("images"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporary) }
        var manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("manifest.json"))) as! [String: Any]
        var entries = manifest["images"] as! [[String: Any]]
        let firstFile = entries[0]["file"] as! String
        try FileManager.default.copyItem(at: root.appendingPathComponent(firstFile), to: temporary.appendingPathComponent(firstFile))
        entries[0]["sha256"] = String(repeating: "0", count: 64)
        manifest["images"] = entries
        try JSONSerialization.data(withJSONObject: manifest).write(to: temporary.appendingPathComponent("manifest.json"))
        let corrupted = try BundledImagingDemo(root: temporary)
        do {
            _ = try corrupted.frameData(id: frames[0]["id"] as! String)
            preconditionFailure("Corrupt checksum accepted")
        } catch BundledImagingDemo.Failure.invalidImage {}
        entries[0]["file"] = "../outside.jpg"
        manifest["images"] = entries
        try JSONSerialization.data(withJSONObject: manifest).write(to: temporary.appendingPathComponent("manifest.json"))
        do {
            _ = try BundledImagingDemo(root: temporary)
            preconditionFailure("Traversal path accepted")
        } catch BundledImagingDemo.Failure.invalidManifest {}
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000
        print(String(format: "Offline tests passed: all 500 bundled frames verified and decoded in %.0f ms; no network source; no patient ID/import/AI; corrupt metadata and checksums rejected.", elapsed))
    }
}
