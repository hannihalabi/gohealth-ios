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
    var metadata: ClinicalVitalMetadata? = nil
}
struct ClinicalVitalMetadata: Encodable {
    let user_entered: Bool
    let source_bundle: String
    let healthkit_type: String
    let import_timezone: String
    var workout_activity: UInt? = nil
    var sleep_stage: Int? = nil
    var device: String? = nil
}
struct ClinicalVitalsBatch: Encodable {
    let p_samples: [ClinicalVitalSample]
    let p_deleted: [UUID]
    var expandedHistory: Bool = false
    enum CodingKeys: String, CodingKey { case p_samples, p_deleted }
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
    @Published var allHistorySharingEnabled: Bool {
        didSet { preferences.set(allHistorySharingEnabled, forKey: "clinicalAllHistorySharing.\(accountID)") }
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
        self.allHistorySharingEnabled = !isBeta && UserDefaults.standard.bool(forKey: "clinicalAllHistorySharing.\(accountID)")
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
        guard !isBeta, (sharingEnabled || stepSharingEnabled || allHistorySharingEnabled), !isSyncing,
              HKHealthStore.isHealthDataAvailable() else { return }
        isSyncing = true; defer { isSyncing = false }
        do {
            if allHistorySharingEnabled { try await syncAllHistory(); return }
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
    private struct SharedQuantity {
        let type: HKQuantityType
        let kind: String
        let unit: HKUnit
        let unitName: String
        var multiplier: Double = 1
    }
    private static var sharedQuantities: [SharedQuantity] {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        var types: [SharedQuantity] = [
            .init(type: HKQuantityType(.heartRate), kind: "heart-rate", unit: perMinute, unitName: "beats/min"),
            .init(type: HKQuantityType(.restingHeartRate), kind: "resting-heart-rate", unit: perMinute, unitName: "beats/min"),
            .init(type: HKQuantityType(.heartRateVariabilitySDNN), kind: "hrv", unit: .secondUnit(with: .milli), unitName: "ms"),
            .init(type: HKQuantityType(.respiratoryRate), kind: "respiratory-rate", unit: perMinute, unitName: "breaths/min"),
            .init(type: HKQuantityType(.oxygenSaturation), kind: "oxygen", unit: .percent(), unitName: "%", multiplier: 100),
            .init(type: HKQuantityType(.vo2Max), kind: "vo2-max", unit: HKUnit(from: "ml/kg*min"), unitName: "ml/kg/min"),
            .init(type: HKQuantityType(.bodyMass), kind: "weight", unit: .gramUnit(with: .kilo), unitName: "kg"),
            .init(type: HKQuantityType(.bodyTemperature), kind: "temperature", unit: .degreeCelsius(), unitName: "degC"),
            .init(type: HKQuantityType(.forcedExpiratoryVolume1), kind: "fev1", unit: .liter(), unitName: "L"),
            .init(type: HKQuantityType(.forcedVitalCapacity), kind: "fvc", unit: .liter(), unitName: "L"),
            .init(type: HKQuantityType(.peakExpiratoryFlowRate), kind: "pef", unit: .liter().unitDivided(by: .minute()), unitName: "L/min"),
            .init(type: HKQuantityType(.stepCount), kind: "step-count", unit: .count(), unitName: "count"),
            .init(type: HKQuantityType(.distanceWalkingRunning), kind: "distance", unit: .meterUnit(with: .kilo), unitName: "km"),
            .init(type: HKQuantityType(.activeEnergyBurned), kind: "active-energy", unit: .kilocalorie(), unitName: "kcal"),
            .init(type: HKQuantityType(.flightsClimbed), kind: "flights", unit: .count(), unitName: "count")
        ]
        if #available(iOS 27.0, *) {
            types.append(.init(type: HKQuantityType(.heartRateVariabilityRMSSD), kind: "hrv-rmssd", unit: .secondUnit(with: .milli), unitName: "ms"))
        }
        return types
    }
    func restartAllHistory() async {
        guard allHistorySharingEnabled, !isSyncing else { return }
        let types: [HKSampleType] = Self.sharedQuantities.map(\.type) + [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        for type in types {
            preferences.removeObject(forKey: "clinicalAllHistoryAnchor.v2.\(accountID).\(type.identifier)")
        }
        await sync()
    }
    private func syncAllHistory() async throws {
        let types: [HKSampleType] = Self.sharedQuantities.map(\.type) + [HKCategoryType(.sleepAnalysis), HKObjectType.workoutType()]
        try await health.requestAuthorization(toShare: [], read: Set(types))
        var pending = types
        var sent = 0
        // Interleave the types so dense pulse history cannot starve the rest.
        // Versioned anchors have no 90-day predicate and survive app restarts.
        while !pending.isEmpty {
            var remaining: [HKSampleType] = []
            for type in pending {
                try Task.checkCancellation()
                guard allHistorySharingEnabled else { return }
                let key = "clinicalAllHistoryAnchor.v2.\(accountID).\(type.identifier)"
                let anchor = try preferences.data(forKey: key).flatMap {
                    try NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: $0)
                }
                let page = try await readAllHistoryPage(type: type, anchor: anchor)
                let samples = page.0.compactMap(Self.convertAllHistory)
                try Task.checkCancellation()
                guard allHistorySharingEnabled else { return }
                try await upload(ClinicalVitalsBatch(p_samples: samples, p_deleted: page.1.map(\.uuid), expandedHistory: true))
                // An acknowledged upload must precede every checkpoint.
                if let next = page.2 {
                    preferences.set(try NSKeyedArchiver.archivedData(withRootObject: next, requiringSecureCoding: true), forKey: key)
                }
                sent += samples.count
                syncMessage = "Delar hela läsbara historiken: \(sent.formatted()) mätningar i denna körning. Håll appen öppen."
                if page.0.count + page.1.count >= 500 { remaining.append(type) }
                // Keep below the shared per-user 120 requests/minute limit.
                try await Task.sleep(for: .milliseconds(750))
            }
            pending = remaining
        }
        syncMessage = "Genomgång av hela historiken klar. \(sent.formatted()) mätningar behandlades. Endast uppgifter som Apple Hälsa tillåter GoHealth att läsa har kunnat delas."
    }
    private func readAllHistoryPage(type: HKSampleType, anchor: HKQueryAnchor?) async throws -> ([HKSample], [HKDeletedObject], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: nil, anchor: anchor, limit: 500) { _, samples, deleted, next, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (samples ?? [], deleted ?? [], next)) }
            }
            health.execute(query)
        }
    }
    private static func convertAllHistory(_ sample: HKSample) -> ClinicalVitalSample? {
        let kind: String; let value: Double?; let unit: String; let definition: String
        var metadata = ClinicalVitalMetadata(
            user_entered: sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false,
            source_bundle: sample.sourceRevision.source.bundleIdentifier,
            healthkit_type: sample.sampleType.identifier, import_timezone: TimeZone.current.identifier,
            device: sample.device?.name
        )
        if let quantity = sample as? HKQuantitySample {
            guard let metric = sharedQuantities.first(where: { $0.type == quantity.quantityType }) else { return nil }
            let number = quantity.quantity.doubleValue(for: metric.unit) * metric.multiplier
            guard number.isFinite else { return nil }
            kind = metric.kind; value = number; unit = metric.unitName; definition = kind
        } else if let sleep = sample as? HKCategorySample {
            metadata.sleep_stage = sleep.value
            value = nil; unit = "interval"
            switch sleep.value {
            case HKCategoryValueSleepAnalysis.asleepCore.rawValue: kind = "sleep"; definition = "asleep-core"
            case HKCategoryValueSleepAnalysis.asleepDeep.rawValue: kind = "sleep"; definition = "asleep-deep"
            case HKCategoryValueSleepAnalysis.asleepREM.rawValue: kind = "sleep"; definition = "asleep-rem"
            case HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue: kind = "sleep"; definition = "asleep-unspecified"
            case HKCategoryValueSleepAnalysis.awake.rawValue: kind = "sleep-awake"; definition = "awake"
            case HKCategoryValueSleepAnalysis.inBed.rawValue: kind = "sleep-in-bed"; definition = "in-bed"
            default: return nil
            }
        } else if let workout = sample as? HKWorkout {
            kind = "workout"; value = workout.duration / 60; unit = "min"; definition = kind
            metadata.workout_activity = workout.workoutActivityType.rawValue
        } else { return nil }
        let formatter = ISO8601DateFormatter()
        return ClinicalVitalSample(source_id: sample.uuid, kind: kind, value: value, unit: unit,
            start_at: formatter.string(from: sample.startDate), end_at: formatter.string(from: sample.endDate),
            source: "\(sample.sourceRevision.source.name) · \(sample.sourceRevision.source.bundleIdentifier)", definition: definition, metadata: metadata)
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
    @State private var showAllHistoryConfirmation = false
    @State private var showStepSharingConfirmation = false
    var body: some View {
        List {
            Section("Dela mätningar med vårdteamet") {
                Toggle("Dela alla mätvärden och hela historiken", isOn: Binding(get: { store.allHistorySharingEnabled }, set: { enabled in
                    if enabled { showAllHistoryConfirmation = true } else { store.allHistorySharingEnabled = false }
                }))
                .confirmationDialog("Dela alla mätvärden och hela historiken?", isPresented: $showAllHistoryConfirmation, titleVisibility: .visible) {
                    Button("Dela hela min läsbara historik") { store.allHistorySharingEnabled = true; Task { await store.sync() } }
                    Button("Avbryt", role: .cancel) {}
                } message: {
                    Text("Puls, HRV, andning, syremättnad, kondition, vikt, temperatur, lungfunktion, aktivitet, sömnstadier och träningspass delas med GoHealths behöriga vårdteam så långt bak Apple Hälsa har läsbara data. Tid, källa och manuellt inmatade värden bevaras. Uppgifterna kan användas som underlag för kommande analys; ingen extern AI-överföring aktiveras med detta val. Dela bara dina egna uppgifter. Avstängning stoppar framtida överföring men tar inte bort redan delade data.")
                }
                Text("Hela historiken importeras i återupptagbara omgångar när appen är öppen. Det kan ta tid första gången. Apple Hälsas läsbehörigheter avgör vilka uppgifter som kan delas.").font(.caption).foregroundStyle(.secondary)
                if store.allHistorySharingEnabled {
                    Button("Importera om hela tillgängliga historiken") { Task { await store.restartAllHistory() } }.disabled(store.isSyncing)
                    Text("Använd efter ändrade läsbehörigheter i Apple Hälsa. Redan delade råmätningar dubbleras inte.").font(.caption).foregroundStyle(.secondary)
                }

                Toggle("Dela puls, vilopuls och sömn (90 dagar)", isOn: Binding(get: { store.sharingEnabled }, set: { enabled in
                    if enabled { showSharingConfirmation = true } else { store.sharingEnabled = false }
                }))
                Toggle("Dela steg per dag (90 dagar)", isOn: Binding(get: { store.stepSharingEnabled }, set: { enabled in
                    if enabled { showStepSharingConfirmation = true } else { store.stepSharingEnabled = false }
                }))
                .confirmationDialog("Dela steg med vårdteamet?", isPresented: $showStepSharingConfirmation, titleVisibility: .visible) {
                    Button("Dela mina steg") { store.stepSharingEnabled = true; Task { await store.sync() } }
                    Button("Avbryt", role: .cancel) {}
                } message: {
                    Text("Dagliga stegsummor från de senaste 90 dagarna överförs från Apple Hälsa till GoHealth och kan läsas av ditt behöriga vårdteam.")
                }
                Text("De begränsade delningsvalen delar högst 90 dagar. Valet att dela hela historiken har ingen sådan datumgräns. Mätningarna uppdateras när appen är öppen. Vårdteamet behöver ha verifierat din kontokoppling. När du stänger av ett val stoppas nästa överföring av den typen. Tidigare delade mätningar finns kvar.").font(.caption).foregroundStyle(.secondary)
                if store.sharingEnabled || store.stepSharingEnabled || store.allHistorySharingEnabled {
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
