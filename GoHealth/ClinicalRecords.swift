import Foundation
import CryptoKit
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
    var calendar_day: String? = nil
}
struct ClinicalVitalsBatch: Encodable {
    let p_samples: [ClinicalVitalSample]
    let p_deleted: [UUID]
}

@MainActor
final class ClinicalStore: ObservableObject {
    @Published private(set) var records: [ClinicalRecord] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var syncMessage: String?
    @Published private(set) var isSyncing = false
    @Published var sharingEnabled: Bool {
        didSet { preferences.set(sharingEnabled, forKey: "clinicalSharing.\(accountID)") }
    }
    @Published var stepSharingEnabled: Bool {
        didSet { preferences.set(stepSharingEnabled, forKey: "clinicalStepSharing.\(accountID)") }
    }
    private let accountID: UUID
    private let isBeta: Bool
    private let preferences = UserDefaults.standard
    private let fetch: () async throws -> ClinicalEnvelope
    private let upload: (ClinicalVitalsBatch) async throws -> Void
    let downloadArchive: (ClinicalArchiveAttachment) async throws -> Data
    private let health = HKHealthStore()

    init(accountID: UUID, isBeta: Bool, fetch: @escaping () async throws -> ClinicalEnvelope,
         upload: @escaping (ClinicalVitalsBatch) async throws -> Void,
         downloadArchive: @escaping (ClinicalArchiveAttachment) async throws -> Data) {
        self.accountID = accountID; self.isBeta = isBeta; self.fetch = fetch; self.upload = upload
        self.downloadArchive = downloadArchive
        self.sharingEnabled = !isBeta && UserDefaults.standard.bool(forKey: "clinicalSharing.\(accountID)")
        self.stepSharingEnabled = !isBeta && UserDefaults.standard.bool(forKey: "clinicalStepSharing.\(accountID)")
    }
    var imageRecords: [ClinicalRecord] { records.filter { $0.imageArchive != nil } }

    func refresh() async {
        guard !isBeta, !isLoading else { return }
        isLoading = true; defer { isLoading = false }
        do {
            let result = try await fetch()
            try Task.checkCancellation()
            records = result.records.sorted { ($0.payload.date ?? .distantPast) > ($1.payload.date ?? .distantPast) }
            error = nil
        } catch {
            if !Task.isCancelled { self.error = "Svar kunde inte hämtas. Ditt konto behöver en verifierad koppling hos vårdteamet. Försök igen eller kontakta mottagningen." }
        }
    }
    func sync() async {
        guard !isBeta, (sharingEnabled || stepSharingEnabled), !isSyncing,
              HKHealthStore.isHealthDataAvailable() else { return }
        isSyncing = true; defer { isSyncing = false }
        do {
            let types: [HKSampleType] = [HKQuantityType(.heartRate), HKQuantityType(.restingHeartRate), HKCategoryType(.sleepAnalysis)]
            let steps = HKQuantityType(.stepCount)
            let shareSamples = sharingEnabled
            let shareSteps = stepSharingEnabled
            var readTypes = Set<HKObjectType>(shareSamples ? types : [])
            if shareSteps { readTypes.insert(steps) }
            try await health.requestAuthorization(toShare: [], read: readTypes)
            if shareSamples && sharingEnabled { try await syncSamples(types) }
            if shareSteps && stepSharingEnabled {
                let daily = try await dailyStepSamples(type: steps)
                try Task.checkCancellation()
                if stepSharingEnabled && !daily.isEmpty {
                    try await upload(ClinicalVitalsBatch(p_samples: daily, p_deleted: []))
                }
                if stepSharingEnabled && daily.isEmpty {
                    syncMessage = shareSamples && sharingEnabled
                        ? "Övriga mätningar är uppdaterade. Inga läsbara steg hittades i Apple Hälsa."
                        : "Inga läsbara steg hittades i Apple Hälsa."
                    return
                }
            }
            syncMessage = "Delade mätningar är uppdaterade. Bara läsbara värden från Apple Hälsa kan delas."
        } catch {
            if !Task.isCancelled { syncMessage = "Delningen kunde inte slutföras. Redan mottagna mätningar dubbleras inte vid nästa försök. Kontrollera kontokopplingen och nätverket." }
        }
    }
    private func syncSamples(_ types: [HKSampleType]) async throws {
        // Keep the predicate fixed for existing anchors and checkpoint after upload.
        let startKey = "clinicalSyncStart.\(accountID)"
        let start = preferences.object(forKey: startKey) as? Date ?? Date().addingTimeInterval(-90 * 86400)
        preferences.set(start, forKey: startKey)
        for type in types {
            let key = "clinicalAnchor.\(accountID).\(type.identifier)"
            var anchor: HKQueryAnchor?
            if let data = preferences.data(forKey: key) {
                anchor = try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
            }
            var more = true
            while more {
                try Task.checkCancellation()
                guard sharingEnabled else { return }
                let page = try await readPage(type: type, anchor: anchor, start: start)
                let samples = page.0.compactMap(Self.convert)
                try Task.checkCancellation()
                guard sharingEnabled else { return }
                try await upload(ClinicalVitalsBatch(p_samples: samples, p_deleted: page.1.map(\.uuid)))
                if let next = page.2 {
                    let data = try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true)
                    preferences.set(data, forKey: key)
                }
                anchor = page.2
                more = page.0.count + page.1.count >= 500
            }
        }
    }

    private func dailyStepSamples(type: HKQuantityType) async throws -> [ClinicalVitalSample] {
        let now = Date()
        let timeZoneKey = "clinicalStepTimeZone.\(accountID)"
        let timeZone = preferences.string(forKey: timeZoneKey).flatMap(TimeZone.init(identifier:)) ?? .current
        preferences.set(timeZone.identifier, forKey: timeZoneKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.startOfDay(for: now)
        guard let start = calendar.date(byAdding: .day, value: -89, to: today) else { return [] }
        let interval = DateComponents(calendar: calendar, timeZone: timeZone, day: 1)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: type, quantitySamplePredicate: predicate,
                options: .cumulativeSum, anchorDate: today, intervalComponents: interval
            )
            query.initialResultsHandler = { _, collection, error in
                if let error {
                    let nsError = error as NSError
                    if nsError.domain == HKErrorDomain && nsError.code == HKError.Code.errorNoData.rawValue {
                        continuation.resume(returning: [])
                    } else {
                        continuation.resume(throwing: error)
                    }
                    return
                }
                var samples: [ClinicalVitalSample] = []
                let formatter = ISO8601DateFormatter()
                let dayFormatter = DateFormatter()
                dayFormatter.locale = Locale(identifier: "en_US_POSIX")
                dayFormatter.calendar = Calendar(identifier: .gregorian)
                dayFormatter.timeZone = timeZone
                dayFormatter.dateFormat = "yyyy-MM-dd"
                collection?.enumerateStatistics(from: start, to: now) { statistics, _ in
                    guard let quantity = statistics.sumQuantity() else { return }
                    let value = quantity.doubleValue(for: .count()).rounded()
                    let end = min(now, statistics.endDate)
                    guard value.isFinite, (0..<1_000_000).contains(value),
                          end.timeIntervalSince(statistics.startDate) >= 1 else { return }
                    let day = dayFormatter.string(from: statistics.startDate)
                    samples.append(ClinicalVitalSample(
                        source_id: Self.stepDayID(day), kind: "steps", value: value, unit: "count",
                        start_at: formatter.string(from: statistics.startDate), end_at: formatter.string(from: end),
                        source: "Apple Hälsa", definition: "steps-daily", calendar_day: day
                    ))
                }
                continuation.resume(returning: samples)
            }
            health.execute(query)
        }
    }

    // A day keeps the same ID when its total changes, so a new sync replaces the day's value.
    nonisolated private static func stepDayID(_ day: String) -> UUID {
        let key = "gohealth.steps-daily.\(day)"
        var bytes = Array(SHA256.hash(data: Data(key.utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0f) | 0x80
        bytes[8] = (bytes[8] & 0x3f) | 0x80
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
    private func readPage(type: HKSampleType, anchor: HKQueryAnchor?, start: Date) async throws -> ([HKSample], [HKDeletedObject], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: HKQuery.predicateForSamples(withStart: start, end: nil), anchor: anchor, limit: 500) { _, samples, deleted, next, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], deleted ?? [], next)) }
            }
            health.execute(query)
        }
    }
    private static func convert(_ sample: HKSample) -> ClinicalVitalSample? {
        guard (sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool) != true else { return nil }
        let kind: String; let value: Double?; let unit: String; let definition: String
        if let quantity = sample as? HKQuantitySample {
            kind = quantity.quantityType.identifier == HKQuantityTypeIdentifier.heartRate.rawValue ? "heart-rate" : "resting-heart-rate"
            let number = quantity.quantity.doubleValue(for: .count().unitDivided(by: .minute()))
            guard number.isFinite, number > 0, number < 1000 else { return nil }
            value = number; unit = "beats/min"; definition = kind
        } else if let sleep = sample as? HKCategorySample {
            let asleep = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
            guard asleep.contains(sleep.value) else { return nil }
            kind = "sleep"; value = nil; unit = "interval"; definition = "asleep"
        } else { return nil }
        let formatter = ISO8601DateFormatter()
        return ClinicalVitalSample(source_id: sample.uuid, kind: kind, value: value, unit: unit,
            start_at: formatter.string(from: sample.startDate), end_at: formatter.string(from: sample.endDate),
            source: "\(sample.sourceRevision.source.name) · \(sample.sourceRevision.source.bundleIdentifier)", definition: definition)
    }
}

struct ClinicalRecordsView: View {
    @ObservedObject var store: ClinicalStore
    @State private var showSharingConfirmation = false
    @State private var showStepSharingConfirmation = false
    var body: some View {
        List {
            Section("Dela mätningar med vårdteamet") {
                Toggle("Dela puls, vilopuls och sömn", isOn: Binding(get: { store.sharingEnabled }, set: { enabled in
                    if enabled { showSharingConfirmation = true } else { store.sharingEnabled = false }
                }))
                Toggle("Dela steg per dag", isOn: Binding(get: { store.stepSharingEnabled }, set: { enabled in
                    if enabled { showStepSharingConfirmation = true } else { store.stepSharingEnabled = false }
                }))
                .confirmationDialog("Dela steg med vårdteamet?", isPresented: $showStepSharingConfirmation, titleVisibility: .visible) {
                    Button("Dela mina steg") { store.stepSharingEnabled = true; Task { await store.sync() } }
                    Button("Avbryt", role: .cancel) {}
                } message: {
                    Text("Dagliga stegsummor från de senaste 90 dagarna överförs från Apple Hälsa till GoHealth och kan läsas av ditt behöriga vårdteam.")
                }
                Text("Vid första delningen hämtas högst 90 dagars läsbar historik. Mätningarna uppdateras när appen är öppen. Vårdteamet behöver ha verifierat din kontokoppling. När du stänger av ett val stoppas nästa överföring av den typen. Tidigare delade mätningar finns kvar.").font(.caption).foregroundStyle(.secondary)
                if store.sharingEnabled || store.stepSharingEnabled {
                    Button(store.isSyncing ? "Synkroniserar…" : "Uppdatera delade mätningar") { Task { await store.sync() } }.disabled(store.isSyncing)
                }
                if let message = store.syncMessage { Text(message).font(.caption) }
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
        .confirmationDialog("Dela hälsomätningar?", isPresented: $showSharingConfirmation, titleVisibility: .visible) {
            Button("Aktivera delning till mitt vårdteam") { store.sharingEnabled = true; Task { await store.sync() } }
            Button("Avbryt", role: .cancel) {}
        } message: { Text("Puls, vilopuls och registrerade sömnintervall överförs från din iPhone till GoHealths backend och kan läsas av ditt behöriga vårdteam. Anslut bara om uppgifterna på den här iPhonen är dina.") }
    }
}
