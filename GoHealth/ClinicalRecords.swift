import Foundation
import HealthKit
import SwiftUI

struct ClinicalEnvelope: Decodable { let records: [ClinicalRecord] }
struct ClinicalArchiveAttachment: Decodable, Identifiable {
    let id: UUID
    let size: Int
    let imageCount: Int
}
struct ClinicalRecord: Decodable, Identifiable {
    let id: UUID
    let kind: String
    let version: Int
    let payload: ClinicalPayload
    let published_at: String?
    let correction_reason: String?
    let imageArchive: ClinicalArchiveAttachment?

    enum CodingKeys: String, CodingKey {
        case id, kind, version, payload, published_at, correction_reason
        case imageArchive = "image_archive"
    }
}
struct ClinicalPayload: Decodable {
    let title: String
    let sampledAt: String
    let source: String
    let comment: String
    let observations: [ClinicalObservation]?
    let vaccine: String?
    let dose: String?
    let batch: String?
    let location: String?
    let modality: String?
    let bodyPart: String?
    let conclusion: String?

    var date: Date? { ClinicalDates.parse(sampledAt) }
}
enum ClinicalDates {
    static func parse(_ text: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
struct ClinicalObservation: Decodable, Identifiable {
    let code: String
    let name: String
    let value: String
    let comparator: String
    let unit: String
    let referenceLow: Double?
    let referenceHigh: Double?
    let referenceText: String
    var id: String { code }
    var numericValue: Double? {
        guard comparator == "=", let number = Double(value), number.isFinite else { return nil }
        return number
    }
    var formattedValue: String { "\(comparator == "=" || comparator == "text" ? "" : comparator)\(value) \(unit)" }
    var reference: String {
        if !referenceText.isEmpty { return referenceText }
        if referenceLow == nil && referenceHigh == nil { return "Referensintervall saknas" }
        return "\(referenceLow.map { $0.formatted() } ?? "—") – \(referenceHigh.map { $0.formatted() } ?? "—") \(unit)"
    }
    var outsideReference: Bool {
        guard let number = numericValue else { return false }
        return referenceLow.map { number < $0 } == true || referenceHigh.map { number > $0 } == true
    }
}
struct ClinicalVitalSample: Encodable {
    let source_id: UUID
    let kind: String
    let value: Double?
    let unit: String
    let start_at: String
    let end_at: String
    let source: String
    let definition: String
    let metadata: ClinicalPortalMetadata
}
struct ClinicalPortalMetadata: Encodable {
    let title: String
    let display_unit: String
    let healthkit_type: String
    let source_bundle: String
    let source_version: String?
    let device_id: String?
    let user_entered: Bool
    let sample_class: String
    var category_value: Int? = nil
    var workout_activity: UInt? = nil
}
struct ClinicalVitalsBatch: Encodable {
    var p_samples: [ClinicalVitalSample] = []
    var p_deleted: [UUID] = []
    var p_display: [ClinicalDisplayValue] = []
    var p_state: String = "syncing"
}

@MainActor
final class ClinicalStore: ObservableObject {
    @Published private(set) var records: [ClinicalRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var syncMessage: String?
    @Published private(set) var isSyncing = false
    private let accountID: UUID
    private let isBeta: Bool
    private let preferences = UserDefaults.standard
    private let fetch: () async throws -> ClinicalEnvelope
    private let upload: (ClinicalVitalsBatch) async throws -> Void
    let downloadArchive: (ClinicalArchiveAttachment) async throws -> Data
    private let health = HKHealthStore()
    private weak var source: HealthStore?
    private var outbox: ClinicalSyncOutbox?
    private var syncPending = false
    private var retry: Task<Void, Never>?

    init(accountID: UUID, isBeta: Bool, fetch: @escaping () async throws -> ClinicalEnvelope,
         upload: @escaping (ClinicalVitalsBatch) async throws -> Void,
         downloadArchive: @escaping (ClinicalArchiveAttachment) async throws -> Data) {
        self.accountID = accountID; self.isBeta = isBeta; self.fetch = fetch; self.upload = upload
        self.downloadArchive = downloadArchive
    }
    deinit { retry?.cancel() }
    var imageRecords: [ClinicalRecord] { records.filter { $0.imageArchive != nil } }
    func attach(to source: HealthStore) {
        guard !isBeta, !source.isBeta else { return }
        self.source = source
        source.onMeasurementsChanged = { [weak self] in
            Task { await self?.sync() }
        }
    }
    func refresh() async {
        guard !isBeta, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let result = try await fetch()
            try Task.checkCancellation()
            records = result.records.sorted { ($0.payload.date ?? .distantPast) > ($1.payload.date ?? .distantPast) }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = "Svar kunde inte hämtas. Kontrollera din kontokoppling och försök igen." }
        }
    }
    func sync() async {
        guard !isBeta, let source, !source.isBeta, HKHealthStore.isHealthDataAvailable() else { return }
        if isSyncing { syncPending = true; return }
        retry?.cancel(); retry = nil
        isSyncing = true
        defer {
            isSyncing = false
            if syncPending && !Task.isCancelled { Task { [weak self] in await self?.sync() } }
        }
        var failures: [String] = []
        do {
            if outbox == nil { outbox = try ClinicalSyncOutbox(accountID: accountID) }
            repeat {
                syncPending = false
                try enqueueDisplayValues(source)
                try await flushDisplayValues()
                var pending = source.portalSampleTypes
                let descriptors = Dictionary(source.portalQuantityDefinitions.map { ($0.type.identifier, $0) }, uniquingKeysWith: { first, _ in first })
                while !pending.isEmpty {
                    var remaining: [HKSampleType] = []
                    for type in pending {
                        try Task.checkCancellation()
                        do {
                            let key = "clinicalAutomaticAnchor.v3.\(accountID).\(type.identifier)"
                            let anchor = try preferences.data(forKey: key).flatMap { try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0) }
                            let page = try await readPage(type: type, anchor: anchor)
                            let fallbackUnits: [HKQuantityType: HKUnit]
                            if let quantity = type as? HKQuantityType, descriptors[type.identifier] == nil {
                                fallbackUnits = try await health.preferredUnits(for: Set([quantity]))
                            } else { fallbackUnits = [:] }
                            let samples = try page.0.map { try Self.convert($0, descriptor: descriptors[$0.sampleType.identifier], fallbackUnits: fallbackUnits) }
                            try Task.checkCancellation()
                            try await upload(ClinicalVitalsBatch(p_samples: samples, p_deleted: page.1.map(\.uuid)))
                            if let next = page.2 {
                                preferences.set(try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true), forKey: key)
                            }
                            if page.0.count + page.1.count >= 500 { remaining.append(type) }
                        } catch is CancellationError { throw CancellationError() }
                        catch { failures.append(type.identifier) }
                        // Below the shared account request limit. No age restriction.
                        try await Task.sleep(for: .milliseconds(800))
                    }
                    pending = remaining
                    try enqueueDisplayValues(source)
                    try await flushDisplayValues()
                }
            } while syncPending && failures.isEmpty
            if failures.isEmpty {
                try await upload(ClinicalVitalsBatch(p_state: "complete"))
                syncMessage = "Appens läsbara mätvärden och historik är synkroniserade till vårdteamet."
            } else { throw URLError(.cannotLoadFromNetwork) }
        } catch {
            try? await upload(ClinicalVitalsBatch(p_state: "retrying"))
            syncMessage = "Synkningen är inte klar. Väntande värden sparas och försöks igen automatiskt. " + (failures.isEmpty ? error.localizedDescription : "Kunde inte slutföra \(Set(failures).count) datatyper.")
            if !Task.isCancelled {
                retry = Task { [weak self] in
                    do { try await Task.sleep(for: .seconds(60)); guard let self else { return }; self.retry = nil; await self.sync() } catch {}
                }
            }
        }
    }
    private func enqueueDisplayValues(_ source: HealthStore) throws {
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; let now = formatter.string(from: Date())
        var values = source.readings.map { reading in
            ClinicalDisplayValue(event_id: UUID(), key: reading.id, display_kind: "current", title: reading.title,
                section: reading.section, value: reading.value, unit: reading.unit, source: reading.detail,
                measured_at: nil, observed_at: now)
        }
        // Raw quantities already have full HealthKit history. Derived/app-only
        // histories are discovered from the same dictionary used by the UI.
        let rawIDs = Set(source.portalQuantityDefinitions.map(\.id))
        for (key, entries) in source.metricHistory where !rawIDs.contains(key) {
            let reading = source.readings.first { $0.id == key }
            values += entries.map { entry in
                ClinicalDisplayValue(event_id: UUID(), key: key, display_kind: "history", title: reading?.title ?? key,
                    section: reading?.section ?? "Appvärden", value: entry.value, unit: reading?.unit ?? "",
                    source: entry.detail, measured_at: formatter.string(from: entry.date), observed_at: now, record_id: entry.id)
            }
        }
        try outbox?.enqueue(values)
    }
    private func flushDisplayValues() async throws {
        while let page = outbox?.page(), !page.isEmpty {
            try Task.checkCancellation()
            try await upload(ClinicalVitalsBatch(p_display: page))
            try outbox?.acknowledge(page)
            try await Task.sleep(for: .milliseconds(800))
        }
    }
    private func readPage(type: HKSampleType, anchor: HKQueryAnchor?) async throws -> ([HKSample], [HKDeletedObject], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: 500) { _, samples, deleted, next, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], deleted ?? [], next)) }
            }
            health.execute(query)
        }
    }
    private static func convert(_ sample: HKSample, descriptor: PortalQuantityDefinition?, fallbackUnits: [HKQuantityType: HKUnit]) throws -> ClinicalVitalSample {
        var kind: String; let value: Double?; let unit: String; let definition: String
        var title = descriptor?.title ?? sample.sampleType.identifier
        var metadata = ClinicalPortalMetadata(title: title, display_unit: descriptor?.unitLabel ?? "",
            healthkit_type: sample.sampleType.identifier, source_bundle: sample.sourceRevision.source.bundleIdentifier,
            source_version: sample.sourceRevision.version, device_id: sample.device?.localIdentifier,
            user_entered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false, sample_class: String(describing: type(of: sample)))
        if let quantity = sample as? HKQuantitySample {
            guard let hkUnit = descriptor?.unit ?? fallbackUnits[quantity.quantityType] else { throw URLError(.cannotDecodeContentData) }
            var number = quantity.quantity.doubleValue(for: hkUnit)
            if hkUnit == .percent() { number *= 100 }
            guard number.isFinite else { throw URLError(.cannotDecodeContentData) }
            kind = descriptor.map { ($0.cumulative ? "raw." : "") + $0.id } ?? quantity.quantityType.identifier
            unit = descriptor?.unitLabel ?? hkUnit.unitString
            if descriptor?.cumulative == true { title += " – råmätningar" }
            value = number; definition = kind
        } else if let category = sample as? HKCategorySample {
            metadata.category_value = category.value
            if category.categoryType == HKCategoryType(.sleepAnalysis) {
                let stages = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: "asleep-unspecified", HKCategoryValueSleepAnalysis.asleepCore.rawValue: "asleep-core", HKCategoryValueSleepAnalysis.asleepDeep.rawValue: "asleep-deep", HKCategoryValueSleepAnalysis.asleepREM.rawValue: "asleep-rem"]
                if let stage = stages[category.value] { kind = "sleep"; title = "Registrerad sömn"; value = nil; unit = "interval"; definition = stage }
                else if category.value == HKCategoryValueSleepAnalysis.awake.rawValue || category.value == HKCategoryValueSleepAnalysis.inBed.rawValue {
                    kind = category.value == HKCategoryValueSleepAnalysis.awake.rawValue ? "sleep-awake" : "sleep-in-bed"; title = kind == "sleep-awake" ? "Vaken under sömnregistrering" : "Tid i säng"; value = nil; unit = "interval"; definition = kind
                } else { kind = "sleep-other"; title = "Sömn – övrig registrering"; value = Double(category.value); unit = "category"; definition = kind }
            } else { kind = category.categoryType.identifier; value = Double(category.value); unit = "category"; definition = kind }
        } else if let workout = sample as? HKWorkout {
            kind = "workout"; title = "Träningspass"; value = workout.duration / 60; unit = "min"; definition = kind
            metadata.workout_activity = workout.workoutActivityType.rawValue
        } else { throw URLError(.cannotDecodeContentData) }
        metadata = ClinicalPortalMetadata(title: title, display_unit: unit == "interval" ? "" : unit,
            healthkit_type: metadata.healthkit_type, source_bundle: metadata.source_bundle,
            source_version: metadata.source_version, device_id: metadata.device_id,
            user_entered: metadata.user_entered, sample_class: metadata.sample_class,
            category_value: metadata.category_value, workout_activity: metadata.workout_activity)
        let formatter = ISO8601DateFormatter()
        return ClinicalVitalSample(source_id: sample.uuid, kind: kind, value: value, unit: unit,
            start_at: formatter.string(from: sample.startDate), end_at: formatter.string(from: sample.endDate),
            source: "\(sample.sourceRevision.source.name) · \(sample.sourceRevision.source.bundleIdentifier)", definition: definition, metadata: metadata)
    }
}

struct ClinicalRecordsView: View {
    @ObservedObject var store: ClinicalStore
    var body: some View {
        List {
            Section("Automatisk synkning till vårdteamet") {
                Text("Alla appens läsbara mätvärden och hela den tillgängliga historiken delas automatiskt. Nya mätvärden följer med utan separata val.")
                if let message = store.syncMessage { Text(message).font(.caption) }
                Button(store.isSyncing ? "Synkroniserar…" : "Försök synkronisera nu") { Task { await store.sync() } }.disabled(store.isSyncing)
            }
            if let error = store.error { Section { Text(error).foregroundStyle(.secondary); Button("Försök igen") { Task { await store.refresh() } } } }
            if store.isLoading { ProgressView("Hämtar svar…") }
            if store.records.isEmpty && !store.isLoading { Section { Text("Inga publicerade svar från vårdteamet finns att visa.").foregroundStyle(.secondary) } }
            ForEach(store.records) { record in
                Section {
                    if let date = record.payload.date { Text(date, format: .dateTime.day().month().year()).font(.caption).foregroundStyle(.secondary) }
                    Text(record.payload.source).font(.caption)
                    ForEach(record.payload.observations ?? []) { observation in
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(observation.name); Spacer(); Text(observation.formattedValue).fontWeight(.semibold) }
                            Text(observation.reference).font(.caption).foregroundStyle(.secondary)
                            if observation.outsideReference { Text("Utanför laboratoriets referensintervall").font(.caption).foregroundStyle(.orange) }
                        }
                    }
                    if let vaccine = record.payload.vaccine { Text("\(vaccine) · dos \(record.payload.dose ?? "—")"); Text(record.payload.location ?? "").font(.caption) }
                    if let conclusion = record.payload.conclusion { Text("\(record.payload.modality ?? "") · \(record.payload.bodyPart ?? "")").font(.caption); Text(conclusion) }
                    if let archive = record.imageArchive {
                        NavigationLink {
                            PublishedImageArchiveView(record: record, archive: archive, download: store.downloadArchive)
                        } label: {
                            Label("Visa bilder (\(archive.imageCount))", systemImage: "viewfinder")
                        }
                    }
                    if !record.payload.comment.isEmpty { Text(record.payload.comment) }
                    Text("Manuellt registrerat och publicerat av vårdteamet · version \(record.version)").font(.caption2).foregroundStyle(.secondary)
                    if let reason = record.correction_reason { Text("Rättat: \(reason)").font(.caption) }
                } header: { Text(record.payload.title) }
            }
        }
        .navigationTitle("Svar från vårdteamet")
        .task { await store.refresh() }
        .refreshable { await store.refresh() }

    }
}
