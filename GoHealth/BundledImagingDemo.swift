import Foundation
import CryptoKit

/// Public test material shipped only in Debug builds, read without a network client.
final class BundledImagingDemo: @unchecked Sendable {
    private struct Manifest: Decodable {
        struct Image: Decodable {
            let index: Int
            let file: String
            let sha256: String
            let sourceImageId: Int
            let width: Int
            let height: Int
        }
        let schemaVersion: Int
        let kind: String
        let title: String
        let sourceUrl: String
        let attribution: String
        let rightsNote: String
        let clinicalUse: Bool
        let aiAnalysis: Bool
        let imageCount: Int
        let images: [Image]
    }

    enum Failure: LocalizedError {
        case missing, invalidManifest, unknownResource, invalidImage
        var errorDescription: String? {
            switch self {
            case .missing: "Testbilderna saknas i den här betaversionen. Installera den uppdaterade appen."
            case .invalidManifest: "Testseriens innehåll kunde inte verifieras."
            case .unknownResource: "Testbilden kunde inte hittas."
            case .invalidImage: "En testbild kunde inte verifieras. Installera om betaversionen."
            }
        }
    }

    static let studyID = "beta-radiopaedia-240575"
    static let seriesID = "beta-radiopaedia-182355"
    let root: URL
    private let manifest: Manifest
    private let images: [String: Manifest.Image]

    convenience init(bundle: Bundle = .main) throws {
        guard let root = bundle.url(forResource: "RadiologyDemo", withExtension: nil) else { throw Failure.missing }
        try self.init(root: root)
    }

    init(root: URL) throws {
        guard root.isFileURL else { throw Failure.invalidManifest }
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        let data = try Data(contentsOf: self.root.appendingPathComponent("manifest.json"))
        guard data.count < 2 * 1024 * 1024 else { throw Failure.invalidManifest }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(Manifest.self, from: data)
        guard manifest.schemaVersion == 1, manifest.kind == "jpeg_preview", !manifest.clinicalUse, !manifest.aiAnalysis,
              manifest.imageCount == 500, manifest.images.count == manifest.imageCount,
              manifest.sourceUrl == "https://radiopaedia.org/cases/240575/studies/182355",
              manifest.images.map(\.index) == Array(0..<manifest.imageCount),
              Set(manifest.images.map(\.file)).count == manifest.imageCount else { throw Failure.invalidManifest }
        for image in manifest.images {
            guard image.file.range(of: #"^images/[0-9]{4}\.(jpg|png)$"#, options: .regularExpression) != nil,
                  image.sha256.range(of: #"^[a-f0-9]{64}$"#, options: .regularExpression) != nil,
                  image.width > 0, image.height > 0, image.width <= 4096, image.height <= 4096 else {
                throw Failure.invalidManifest
            }
        }
        self.manifest = manifest
        images = Dictionary(uniqueKeysWithValues: manifest.images.map { (Self.frameID($0.index), $0) })
    }

    private static func frameID(_ index: Int) -> String { "beta-image-\(index)" }

    func responseData(for path: String) throws -> Data {
        let path = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let value: Any
        switch path {
        case "v1/capabilities":
            value = ["can_import": false, "patient_id": NSNull(), "mode": "offline_demo", "ai_enabled": false] as [String: Any]
        case "v1/studies":
            value = [["id": Self.studyID, "description": manifest.title, "study_date": "", "modality": "JPEG",
                      "synthetic": false,
                      "series": [["id": Self.seriesID, "description": manifest.title, "modality": "JPEG",
                                  "kind": "preview", "frame_count": manifest.imageCount]]]] as [[String: Any]]
        case "v1/series/\(Self.seriesID)":
            value = ["id": Self.seriesID, "description": manifest.title, "modality": "JPEG", "kind": "preview",
                     "regular_spacing": NSNull(), "ai_status": "Inte tillgänglig för JPEG-testbilder",
                     "source_url": manifest.sourceUrl, "attribution": manifest.attribution, "rights_note": manifest.rightsNote,
                     "frames": manifest.images.map { image in
                         ["id": Self.frameID(image.index), "index": image.index, "position_mm": NSNull(),
                          "rows": image.height, "columns": image.width, "spacing": [], "window_center": 0, "window_width": 1] as [String: Any]
                     }] as [String: Any]
        default: throw Failure.unknownResource
        }
        return try JSONSerialization.data(withJSONObject: value)
    }

    func frameData(id: String) throws -> Data {
        guard let image = images[id] else { throw Failure.unknownResource }
        let url = root.appendingPathComponent(image.file).standardizedFileURL.resolvingSymlinksInPath()
        guard url.path.hasPrefix(root.path + "/") else { throw Failure.invalidImage }
        let data = try Data(contentsOf: url)
        guard data.count <= 10 * 1024 * 1024,
              SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == image.sha256 else {
            throw Failure.invalidImage
        }
        return data
    }
}
