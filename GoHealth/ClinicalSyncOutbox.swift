import Foundation
import CryptoKit

struct ClinicalDisplayValue: Codable, Equatable {
    let event_id: UUID
    let key: String
    let display_kind: String
    let title: String
    let section: String
    let value: String
    let unit: String
    let source: String
    let measured_at: String?
    let observed_at: String
    var record_id: String? = nil

    var fingerprint: String {
        let parts = [key, display_kind, title, section, value, unit, source, measured_at ?? ""]
        return SHA256.hash(data: Data(parts.joined(separator: "\u{0}").utf8)).map { String(format: "%02x", $0) }.joined()
    }
    var identity: String { display_kind + ":" + key + ":" + (record_id ?? measured_at ?? "") }
}

// Per-account, protected, excluded from backup. Persist before transmission and
// remove only after the backend acknowledges the exact event IDs.
final class ClinicalSyncOutbox {
    private struct State: Codable {
        var pending: [ClinicalDisplayValue] = []
        var fingerprints: [String: String] = [:]
    }
    private let file: URL
    private var state: State
    init(accountID: UUID, directory: URL? = nil) throws {
        let root = try directory ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("ClinicalSync", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var protectedRoot = root
        var rootAttributes = URLResourceValues(); rootAttributes.isExcludedFromBackup = true
        try protectedRoot.setResourceValues(rootAttributes)
        file = root.appendingPathComponent(accountID.uuidString + ".json")
        if FileManager.default.fileExists(atPath: file.path) {
            state = try JSONDecoder().decode(State.self, from: Data(contentsOf: file))
        } else { state = State() }
    }
    var pendingCount: Int { state.pending.count }
    func enqueue(_ values: [ClinicalDisplayValue]) throws {
        var next = state
        var changed = false
        for value in values where next.fingerprints[value.identity] != value.fingerprint {
            changed = true
            next.pending.append(value)
            next.fingerprints[value.identity] = value.fingerprint
        }
        if changed { try persist(next) }
    }
    func page(limit: Int = 200) -> [ClinicalDisplayValue] { Array(state.pending.prefix(limit)) }
    func acknowledge(_ values: [ClinicalDisplayValue]) throws {
        let accepted = Set(values.map(\.event_id))
        var next = state
        next.pending.removeAll { accepted.contains($0.event_id) }
        try persist(next)
    }
    private func persist(_ next: State) throws {
        try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        state = next
    }
}
