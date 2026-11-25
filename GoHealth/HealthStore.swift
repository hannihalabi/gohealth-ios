import Foundation
import HealthKit
import Combine

struct PortalQuantityDefinition {
    let id: String
    let title: String
    let type: HKQuantityType
    let unit: HKUnit
    let unitLabel: String
    let cumulative: Bool
}
struct HealthReading: Identifiable {
    let id: String
    let section: String
    let title: String
    let icon: String
    let value: String
    let unit: String
    let detail: String
}

struct HeartRateReading: Identifiable {
    let id: UUID
    let date: Date
    let beatsPerMinute: Double
    let source: String
}

struct StepDay: Identifiable {
    let date: Date
    let count: Double
    var id: Date { date }
}

struct MetricHistoryEntry: Identifiable {
    let id: String
    let date: Date
    let value: String
    let detail: String
    var numericValue: Double? = nil
}

struct WorkoutReading: Identifiable {
    let id: UUID
    let title: String
    let detail: String
}

@MainActor
final class HealthStore: ObservableObject {
    @Published var metricHistory: [String: [MetricHistoryEntry]] = [:]
    @Published var metricHistoryErrors: [String: String] = [:]
    @Published var readings: [HealthReading] = []
    @Published var heartRateHistory: [HeartRateReading] = []
    @Published var heartRateHistoryError: String?
    @Published var restingHeartRateHistory: [HeartRateReading] = []
    @Published var restingHeartRateHistoryError: String?
    @Published var stepHistory: [StepDay] = []
    @Published var stepHistoryError: String?
    @Published var workouts: [WorkoutReading] = []
    @Published var isLoading = false
    @Published var message = "Hämtar mätningar från Apple Hälsa…"

    var onMeasurementsChanged: (() -> Void)?
    var portalQuantityDefinitions: [PortalQuantityDefinition] {
        latestMetrics.map { .init(id: $0.id, title: $0.title, type: $0.type, unit: $0.unit, unitLabel: $0.unitLabel, cumulative: false) }
        + dailyMetrics.map { .init(id: $0.id, title: $0.title, type: $0.type, unit: $0.unit, unitLabel: $0.unitLabel, cumulative: true) }
    }
    var portalSampleTypes: [HKSampleType] { readTypes.compactMap { $0 as? HKSampleType } }
    let isBeta: Bool
    private let store = HKHealthStore()
    private let sleepType = HKCategoryType(.sleepAnalysis)
    private let workoutType = HKWorkoutType.workoutType()
    private var observationQueries: [HKObserverQuery] = []
    private var refreshPending = false

    init(isBeta: Bool = false) {
        self.isBeta = isBeta
        if isBeta { loadBetaData() }
    }

    // In-memory fixtures only. These never read HealthKit or upload to an account.
    private func loadBetaData(now: Date = Date()) {
        guard isBeta else { return }
        let calendar = Calendar.current
        let wave = [0.0, -0.4, 0.3, -0.7, 0.5, -0.2, 0.8]
        func date(_ daysAgo: Int) -> Date {
            calendar.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        }
        func day(_ daysAgo: Int) -> Date { calendar.startOfDay(for: date(daysAgo)) }
        func variation(_ daysAgo: Int) -> Double {
            wave[daysAgo % wave.count] - Double(daysAgo) * 0.015
        }
        let quantities: [String: (base: Double, amplitude: Double)] = [
            "heart-rate": (62, 12), "resting-heart-rate": (59, 4), "hrv": (57, 14),
            "respiratory-rate": (15.2, 1.2), "oxygen": (0.98, 0.015),
            "fev1": (3.25, 0.15), "fvc": (4.12, 0.18), "pef": (500, 35),
            "vo2-max": (42.4, 1.6), "weight": (76.4, 0.8), "temperature": (36.7, 0.3),
            "steps": (8432, 3200), "distance": (6.2, 2.2),
            "active-energy": (534, 180), "flights": (9, 5)
        ]
        func value(_ id: String, _ daysAgo: Int) -> Double {
            guard let quantity = quantities[id] else { return 0 }
            return quantity.base + variation(daysAgo) * quantity.amplitude
        }
        metricHistoryErrors = [:]
        heartRateHistoryError = nil
        restingHeartRateHistoryError = nil
        stepHistoryError = nil
        var histories: [String: [MetricHistoryEntry]] = [:]
        for metric in latestMetrics {
            histories[metric.id] = (0..<30).map { offset in
                let number = value(metric.id, offset)
                return MetricHistoryEntry(id: "beta-\(metric.id)-\(offset)", date: date(offset),
                                          value: metric.transform(number), detail: "Testdata · Betaprofil",
                                          numericValue: number)
            }
        }
        for metric in dailyMetrics {
            histories[metric.id] = (0..<30).map { offset in
                let number = value(metric.id, offset)
                return MetricHistoryEntry(id: "beta-\(metric.id)-\(offset)", date: day(offset),
                                          value: metric.transform(number), detail: "Testdata · Dagssumma",
                                          numericValue: number)
            }
        }
        histories["sleep"] = (0..<30).map { offset in
            let hours = (offset < 8 ? 6.5 : 7.7) + variation(offset) * 0.8
            return MetricHistoryEntry(id: "beta-sleep-\(offset)", date: day(offset), value: oneDecimal(hours),
                                      detail: "Testdata · Sovtid", numericValue: hours)
        }
        histories["fev1-fvc"] = (0..<30).map { offset in
            let percent = value("fev1", offset) / value("fvc", offset) * 100
            return MetricHistoryEntry(id: "beta-fev1-fvc-\(offset)", date: date(offset), value: oneDecimal(percent),
                                      detail: "Testdata · Beräknad FEV₁/FVC", numericValue: percent)
        }
        metricHistory = histories
        heartRateHistory = (0..<120).map { offset in
            HeartRateReading(id: UUID(), date: now.addingTimeInterval(-Double(offset) * 6 * 3600),
                             beatsPerMinute: value("heart-rate", offset % 30), source: "Testdata · Betaprofil")
        }
        restingHeartRateHistory = (0..<30).map { offset in
            HeartRateReading(id: UUID(), date: date(offset), beatsPerMinute: value("resting-heart-rate", offset),
                             source: "Testdata · Betaprofil")
        }
        stepHistory = (0..<30).map { StepDay(date: day($0), count: value("steps", $0)) }
        readings = latestMetrics.map { metric in
            HealthReading(id: metric.id, section: metric.section, title: metric.title, icon: metric.icon,
                          value: histories[metric.id]?.first?.value ?? "—", unit: metric.unitLabel,
                          detail: "Testdata · \(now.formatted(date: .abbreviated, time: .shortened)) · Visa historik")
        } + dailyMetrics.map { metric in
            HealthReading(id: metric.id, section: "Aktivitet idag", title: metric.title, icon: metric.icon,
                          value: histories[metric.id]?.first?.value ?? "—", unit: metric.unitLabel,
                          detail: "Testdata · Idag · Visa historik")
        }
        readings.append(HealthReading(id: "sleep", section: "Sömn", title: "Registrerad sömn", icon: "moon.fill",
                                      value: histories["sleep"]?.first?.value ?? "—", unit: "timmar",
                                      detail: "Testdata · Senaste natten · Visa historik"))
        readings.append(HealthReading(id: "fev1-fvc", section: "Lungfunktion", title: "FEV₁/FVC", icon: "lungs.fill",
                                      value: histories["fev1-fvc"]?.first?.value ?? "—", unit: "%",
                                      detail: "Testdata · Beräknad kvot · Visa historik"))
        let sessions = [("Löpning", 1, "35 min · 5,2 km"), ("Styrketräning", 2, "45 min"),
                        ("Promenad", 3, "52 min · 4,1 km"), ("Cykling", 5, "60 min · 22 km")]
        workouts = sessions.map { title, offset, summary in
            WorkoutReading(id: UUID(), title: title,
                           detail: "\(date(offset).formatted(date: .abbreviated, time: .shortened)) · \(summary) · Testdata")
        }
        message = "Betaprofil med testvärden och 30 dagars historik."
    }

    private struct LatestMetric {
        let id: String
        let section: String
        let title: String
        let icon: String
        let type: HKQuantityType
        let unit: HKUnit
        let unitLabel: String
        let transform: (Double) -> String
    }

    private struct DailyMetric {
        let id: String
        let title: String
        let icon: String
        let type: HKQuantityType
        let unit: HKUnit
        let unitLabel: String
        let transform: (Double) -> String
    }

    private var latestMetrics: [LatestMetric] {
        let perMinute = HKUnit.count().unitDivided(by: .minute())
        return [
            .init(id: "heart-rate", section: "Hjärta och återhämtning", title: "Senaste puls", icon: "heart.fill", type: HKQuantityType(.heartRate), unit: perMinute, unitLabel: "slag/min", transform: integer),
            .init(id: "resting-heart-rate", section: "Hjärta och återhämtning", title: "Vilopuls", icon: "heart.text.square.fill", type: HKQuantityType(.restingHeartRate), unit: perMinute, unitLabel: "slag/min", transform: integer),
            .init(id: "hrv", section: "Hjärta och återhämtning", title: "HRV", icon: "waveform.path.ecg", type: HKQuantityType(.heartRateVariabilitySDNN), unit: HKUnit.secondUnit(with: .milli), unitLabel: "ms", transform: integer),
            .init(id: "respiratory-rate", section: "Hjärta och återhämtning", title: "Andningsfrekvens", icon: "lungs.fill", type: HKQuantityType(.respiratoryRate), unit: perMinute, unitLabel: "andetag/min", transform: oneDecimal),
            .init(id: "oxygen", section: "Hjärta och återhämtning", title: "Syremättnad", icon: "drop.fill", type: HKQuantityType(.oxygenSaturation), unit: .percent(), unitLabel: "%", transform: { ($0 * 100).formatted(.number.precision(.fractionLength(0))) }),
            .init(id: "fev1", section: "Lungfunktion", title: "FEV₁", icon: "lungs.fill", type: HKQuantityType(.forcedExpiratoryVolume1), unit: .liter(), unitLabel: "L", transform: twoDecimals),
            .init(id: "fvc", section: "Lungfunktion", title: "FVC", icon: "lungs.fill", type: HKQuantityType(.forcedVitalCapacity), unit: .liter(), unitLabel: "L", transform: twoDecimals),
            .init(id: "pef", section: "Lungfunktion", title: "PEF", icon: "wind", type: HKQuantityType(.peakExpiratoryFlowRate), unit: HKUnit.liter().unitDivided(by: .minute()), unitLabel: "L/min", transform: integer),
            .init(id: "vo2-max", section: "Kropp och kondition", title: "VO₂ max", icon: "figure.run", type: HKQuantityType(.vo2Max), unit: HKUnit(from: "ml/kg*min"), unitLabel: "ml/kg/min", transform: oneDecimal),
            .init(id: "weight", section: "Kropp och kondition", title: "Vikt", icon: "scalemass.fill", type: HKQuantityType(.bodyMass), unit: HKUnit.gramUnit(with: .kilo), unitLabel: "kg", transform: oneDecimal),
            .init(id: "temperature", section: "Kropp och kondition", title: "Kroppstemperatur", icon: "thermometer.medium", type: HKQuantityType(.bodyTemperature), unit: .degreeCelsius(), unitLabel: "°C", transform: oneDecimal)
        ]
    }

    private var dailyMetrics: [DailyMetric] {
        [
            .init(id: "steps", title: "Steg", icon: "figure.walk", type: HKQuantityType(.stepCount), unit: .count(), unitLabel: "steg", transform: integer),
            .init(id: "distance", title: "Gång och löpning", icon: "location.fill", type: HKQuantityType(.distanceWalkingRunning), unit: HKUnit.meterUnit(with: .kilo), unitLabel: "km", transform: oneDecimal),
            .init(id: "active-energy", title: "Aktiv energi", icon: "flame.fill", type: HKQuantityType(.activeEnergyBurned), unit: .kilocalorie(), unitLabel: "kcal", transform: integer),
            .init(id: "flights", title: "Trappor", icon: "stairs", type: HKQuantityType(.flightsClimbed), unit: .count(), unitLabel: "våningar", transform: integer)
        ]
    }

    private var readTypes: Set<HKObjectType> {
        var types = Set<HKObjectType>(latestMetrics.map(\.type) + dailyMetrics.map(\.type) + [sleepType, workoutType])
        if #available(iOS 27.0, *) { types.insert(HKQuantityType(.heartRateVariabilityRMSSD)) }
        return types
    }

    func biologicalSexForBodyFigure() -> HKBiologicalSex? {
        if isBeta { return .male }
        guard HKHealthStore.isHealthDataAvailable() else { return nil }
        return try? store.biologicalSex().biologicalSex
    }

    func connect() async {
        if isBeta {
            loadBetaData()
            return
        }
        guard HKHealthStore.isHealthDataAvailable() else {
            message = "Apple Hälsa är inte tillgängligt på den här enheten."
            return
        }
        guard !isLoading else { return }
        isLoading = true
        message = "Hämtar mätningar från Apple Hälsa…"
        defer { isLoading = false }
        do {
            // HealthKit only prompts for types the user has not already answered.
            var dashboardReadTypes = readTypes
            if let biologicalSex = HKObjectType.characteristicType(forIdentifier: .biologicalSex) {
                dashboardReadTypes.insert(biologicalSex)
            }
            try await store.requestAuthorization(toShare: [], read: dashboardReadTypes)
            startObservation()
            await readPendingChanges()
        } catch {
            message = "Apple Hälsa kunde inte anslutas: " + error.localizedDescription
        }
    }

    func refresh() async {
        if isBeta {
            loadBetaData()
            return
        }
        guard !isBeta, HKHealthStore.isHealthDataAvailable() else { return }
        guard !isLoading else {
            refreshPending = true
            return
        }
        isLoading = true
        message = "Uppdaterar mätningar…"
        defer { isLoading = false }
        await readPendingChanges()
    }

    private func readPendingChanges() async {
        repeat {
            refreshPending = false
            await readAll()
            onMeasurementsChanged?()
        } while refreshPending
    }

    private func startObservation() {
        guard observationQueries.isEmpty else { return }
        observationQueries = readTypes.compactMap { type in
            guard let sampleType = type as? HKSampleType else { return nil }
            let query = HKObserverQuery(sampleType: sampleType, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor in
                    defer { completion() }
                    guard error == nil else { return }
                    await self?.refresh()
                }
            }
            store.execute(query)
            store.enableBackgroundDelivery(for: sampleType, frequency: .immediate) { _, _ in }
            return query
        }
    }

    func observeRecoveryChanges(onChange: @escaping @MainActor () -> Void) -> [HKQuery] {
        guard !isBeta else { return [] }
        var types: [HKSampleType] = [HKQuantityType(.heartRateVariabilitySDNN), HKQuantityType(.restingHeartRate), sleepType, workoutType]
        if #available(iOS 27.0, *) { types.append(HKQuantityType(.heartRateVariabilityRMSSD)) }
        return types.map { type in
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, error in
                if error == nil { Task { @MainActor in onChange() } }
                completion()
            }
            store.execute(query)
            return query
        }
    }

    func stopRecoveryObservation(_ queries: [HKQuery]) {
        for query in queries { store.stop(query) }
    }

    // Recovery reads a bounded history automatically. Nothing is sent to a server or logs.
    func recoverySensorData() async throws -> [String: Any] {
        guard !isBeta, HKHealthStore.isHealthDataAvailable() else {
            throw NSError(domain: "GoHealth", code: 1, userInfo: [NSLocalizedDescriptionKey: "Apple Hälsa är inte tillgängligt på den här enheten."])
        }
        let status: HKAuthorizationRequestStatus = try await withCheckedThrowingContinuation { continuation in
            store.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: status) }
            }
        }
        if status == .shouldRequest { try await store.requestAuthorization(toShare: [], read: readTypes) }
        let calendar = Calendar.current
        let now = Date()
        let todayMorning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: now)!
        let morning = todayMorning <= now ? todayMorning : calendar.date(byAdding: .day, value: -1, to: todayMorning)!
        let start = calendar.date(byAdding: .day, value: -44, to: morning)!
        let formatter = ISO8601DateFormatter()
        var errors: [String: String] = [:]
        func read(_ type: HKSampleType, key: String) async -> [HKSample] {
            do {
                return try await withCheckedThrowingContinuation { continuation in
                    let query = HKSampleQuery(sampleType: type,
                        predicate: HKQuery.predicateForSamples(withStart: start, end: now),
                        limit: HKObjectQueryNoLimit,
                        sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                        if let error, !self.isNoData(error) { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: samples ?? []) }
                    }
                    store.execute(query)
                }
            } catch { errors[key] = "Mätningarna kunde inte läsas"; return [] }
        }
        func source(_ sample: HKSample) -> [String: Any] {
            let device = sample.device
            let stableDevice = device?.localIdentifier ?? device?.udiDeviceIdentifier ?? ""
            let algorithm = sample.metadata?[HKMetadataKeyAlgorithmVersion] as? String
                ?? (sample.metadata?[HKMetadataKeyAlgorithmVersion] as? NSNumber)?.stringValue
                ?? "unspecified"
            return ["source": sample.sourceRevision.source.name,
                    "sourceIdentifier": sample.sourceRevision.source.bundleIdentifier,
                    "device": stableDevice.isEmpty ? NSNull() : stableDevice as Any,
                    "deviceLabel": device?.model ?? device?.name ?? "Enhet saknas i källdata",
                    "algorithm": algorithm,
                    "sourceVersion": sample.sourceRevision.version ?? "unspecified",
                    "userEntered": sample.metadata?[HKMetadataKeyWasUserEntered] as? Bool ?? false]
        }
        func quantities(_ samples: [HKSample], definition: String, unit: HKUnit, unitLabel: String) -> [[String: Any]] {
            samples.compactMap { sample in
                guard let sample = sample as? HKQuantitySample else { return nil }
                let value = sample.quantity.doubleValue(for: unit)
                guard value.isFinite, value > 0 else { return nil }
                var row = source(sample)
                row.merge(["id": sample.uuid.uuidString, "start": formatter.string(from: sample.startDate),
                           "end": formatter.string(from: sample.endDate), "value": value,
                           "definition": definition, "unit": unitLabel]) { _, new in new }
                return row
            }
        }
        var hrv = quantities(await read(HKQuantityType(.heartRateVariabilitySDNN), key: "hrv"), definition: "SDNN", unit: .secondUnit(with: .milli), unitLabel: "ms")
        if #available(iOS 27.0, *) {
            hrv += quantities(await read(HKQuantityType(.heartRateVariabilityRMSSD), key: "rmssd"), definition: "RMSSD", unit: .secondUnit(with: .milli), unitLabel: "ms")
        }
        let rhr = quantities(await read(HKQuantityType(.restingHeartRate), key: "rhr"), definition: "resting-heart-rate", unit: HKUnit.count().unitDivided(by: .minute()), unitLabel: "beats/min")
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let sleep = await read(sleepType, key: "sleep").compactMap { sample -> [String: Any]? in
            guard let sample = sample as? HKCategorySample, asleep.contains(sample.value), sample.startDate < morning else { return nil }
            var row = source(sample)
            row.merge(["id": sample.uuid.uuidString, "start": formatter.string(from: sample.startDate), "end": formatter.string(from: min(sample.endDate, morning))]) { _, new in new }
            return row
        }
        let workouts = await read(workoutType, key: "workouts").compactMap { sample -> [String: Any]? in
            guard let workout = sample as? HKWorkout, workout.endDate <= now else { return nil }
            var row = source(sample)
            row.merge(["id": workout.uuid.uuidString, "start": formatter.string(from: workout.startDate), "end": formatter.string(from: workout.endDate), "minutes": workout.duration / 60, "title": workoutName(workout.workoutActivityType)]) { _, new in new }
            return row
        }
        return ["calculationTime": formatter.string(from: morning), "retrievedAt": formatter.string(from: now),
                "timezone": calendar.timeZone.identifier, "hrvSamples": hrv, "restingSamples": rhr,
                "sleepSamples": sleep, "workouts": workouts, "readErrors": errors]
    }

    func readings(in section: String) -> [HealthReading] {
        readings.filter { $0.section == section }
    }

    private func readAll() async {
        let now = Date()
        var result: [HealthReading] = []
        await readHeartRateHistory(end: now)
        let pulse = heartRateHistory.first
        result.append(HealthReading(id: "heart-rate", section: "Hjärta och återhämtning", title: "Senaste puls", icon: "heart.fill", value: pulse.map { integer($0.beatsPerMinute) } ?? "—", unit: "slag/min", detail: pulse.map { "\($0.source) · \($0.date.formatted(date: .abbreviated, time: .shortened)) · Visa historik" } ?? "Ingen läsbar mätning · Visa historik"))
        await readRestingHeartRateHistory(end: now)
        let restingPulse = restingHeartRateHistory.first
        result.append(HealthReading(id: "resting-heart-rate", section: "Hjärta och återhämtning", title: "Vilopuls", icon: "heart.text.square.fill", value: restingPulse.map { integer($0.beatsPerMinute) } ?? "—", unit: "slag/min", detail: restingPulse.map { "\($0.source) · \($0.date.formatted(date: .abbreviated, time: .shortened)) · Visa historik" } ?? "Ingen läsbar mätning · Visa historik"))
        var spirometrySamples: [String: [HKQuantitySample]] = [:]
        for metric in latestMetrics where metric.id != "heart-rate" && metric.id != "resting-heart-rate" {
            let samples = await readMetricHistory(metric, end: now)
            if metric.id == "fev1" || metric.id == "fvc" { spirometrySamples[metric.id] = samples }
            let entry = metricHistory[metric.id]?.first
            result.append(HealthReading(id: metric.id, section: metric.section, title: metric.title, icon: metric.icon, value: entry?.value ?? "—", unit: metric.unitLabel, detail: entry.map { "\($0.detail) · \($0.date.formatted(date: .abbreviated, time: .shortened)) · Visa historik" } ?? "Ingen läsbar mätning · Visa historik"))
        }
        readSpirometryRatio(fev1: spirometrySamples["fev1", default: []], fvc: spirometrySamples["fvc", default: []])
        let ratio = metricHistory["fev1-fvc"]?.first
        result.append(HealthReading(id: "fev1-fvc", section: "Lungfunktion", title: "FEV₁/FVC", icon: "lungs.fill", value: ratio?.value ?? "—", unit: "%", detail: ratio.map { "\($0.detail) · \($0.date.formatted(date: .abbreviated, time: .shortened)) · Visa historik" } ?? "Kräver matchande FEV₁ och FVC · Visa historik"))
        await readStepHistory(end: now)
        let today = stepHistory.first { Calendar.current.isDate($0.date, inSameDayAs: now) }
        result.append(HealthReading(id: "steps", section: "Aktivitet idag", title: "Steg", icon: "figure.walk", value: today.map { integer($0.count) } ?? "—", unit: "steg", detail: today == nil ? "Ingen läsbar mätning idag · Visa historik" : "Idag · Visa hela steghistoriken"))
        for metric in dailyMetrics where metric.id != "steps" {
            await readDailyHistory(metric, end: now)
            let today = metricHistory[metric.id]?.first { Calendar.current.isDate($0.date, inSameDayAs: now) }
            result.append(HealthReading(id: metric.id, section: "Aktivitet idag", title: metric.title, icon: metric.icon, value: today?.value ?? "—", unit: metric.unitLabel, detail: today == nil ? "Ingen läsbar mätning idag · Visa historik" : "Idag · Visa hela historiken"))
        }
        await readSleepHistory(end: now)
        if let sleep = await sleep(end: now) {
            result.append(HealthReading(id: sleep.id, section: sleep.section, title: sleep.title, icon: sleep.icon, value: sleep.value, unit: sleep.unit, detail: "\(sleep.detail) · Visa historik"))
        } else {
            result.append(HealthReading(id: "sleep", section: "Sömn", title: "Registrerad sömn", icon: "moon.fill", value: "—", unit: "timmar", detail: "Ingen aktuell läsbar sömn · Visa historik"))
        }

        readings = result
        workouts = await recentWorkouts(end: now)
        let available = result.filter { $0.value != "—" }.count + workouts.count
        message = available == 0
            ? "Inga läsbara mätningar hittades. Kontrollera åtkomsten i Apple Hälsa och synkronisera Garmin Connect."
            : "\(available) mätvärden hittades i Apple Hälsa. Tryck på ett mätvärde för att se hela historiken."
    }

    private func readHeartRateHistory(end: Date) async {
        heartRateHistoryError = nil
        do {
            heartRateHistory = try await readPulseHistory(type: HKQuantityType(.heartRate), end: end)
        } catch {
            heartRateHistory = []
            heartRateHistoryError = "Pulshistoriken kunde inte läsas: \(error.localizedDescription)"
        }
    }

    private func readRestingHeartRateHistory(end: Date) async {
        restingHeartRateHistoryError = nil
        do {
            restingHeartRateHistory = try await readPulseHistory(type: HKQuantityType(.restingHeartRate), end: end)
        } catch {
            restingHeartRateHistory = []
            restingHeartRateHistoryError = "Vilopulshistoriken kunde inte läsas: \(error.localizedDescription)"
        }
    }

    private func readPulseHistory(type: HKQuantityType, end: Date) async throws -> [HeartRateReading] {
        try await withCheckedThrowingContinuation { continuation in
                let query = HKSampleQuery(
                    sampleType: type,
                    predicate: HKQuery.predicateForSamples(withStart: nil, end: end),
                    limit: HKObjectQueryNoLimit,
                    sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
                ) { _, samples, error in
                    if let error {
                        if self.isNoData(error) { continuation.resume(returning: [] as [HeartRateReading]) }
                        else { continuation.resume(throwing: error) }
                        return
                    }
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    let readings = (samples ?? []).compactMap { sample -> HeartRateReading? in
                        guard let sample = sample as? HKQuantitySample else { return nil }
                        return HeartRateReading(id: sample.uuid, date: sample.endDate,
                                                beatsPerMinute: sample.quantity.doubleValue(for: unit),
                                                source: sample.sourceRevision.source.name)
                    }
                    continuation.resume(returning: readings)
                }
                store.execute(query)
            }
    }

    private func readStepHistory(end: Date) async {
        stepHistoryError = nil
        do {
            stepHistory = try await dailyHistory(type: HKQuantityType(.stepCount), unit: .count(), end: end)
        } catch {
            stepHistory = []
            stepHistoryError = "Steghistoriken kunde inte läsas: \(error.localizedDescription)"
        }
    }

    private func dailyHistory(type: HKQuantityType, unit: HKUnit, end: Date) async throws -> [StepDay] {
        try await withCheckedThrowingContinuation { continuation in
                let predicate = HKQuery.predicateForSamples(withStart: nil, end: end)
                let first = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, samples, error in
                    if let error {
                        if self.isNoData(error) { continuation.resume(returning: [] as [StepDay]) }
                        else { continuation.resume(throwing: error) }
                        return
                    }
                    guard let earliest = samples?.first else {
                        continuation.resume(returning: [] as [StepDay])
                        return
                    }
                    let calendar = Calendar.current
                    let start = calendar.startOfDay(for: earliest.startDate)
                    let query = HKStatisticsCollectionQuery(quantityType: type, quantitySamplePredicate: HKQuery.predicateForSamples(withStart: nil, end: end), options: .cumulativeSum, anchorDate: calendar.startOfDay(for: end), intervalComponents: DateComponents(day: 1))
                    query.initialResultsHandler = { _, collection, error in
                        if let error { continuation.resume(throwing: error); return }
                        var days: [StepDay] = []
                        collection?.enumerateStatistics(from: start, to: end) { statistics, _ in
                            if let sum = statistics.sumQuantity() {
                                days.append(StepDay(date: statistics.startDate, count: sum.doubleValue(for: unit)))
                            }
                        }
                        continuation.resume(returning: days.sorted { $0.date > $1.date })
                    }
                    self.store.execute(query)
                }
                store.execute(first)
            }
    }

    private func allSamples(type: HKSampleType, end: Date) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: HKQuery.predicateForSamples(withStart: nil, end: end), limit: HKObjectQueryNoLimit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error, !self.isNoData(error) { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    private func readMetricHistory(_ metric: LatestMetric, end: Date) async -> [HKQuantitySample] {
        metricHistoryErrors[metric.id] = nil
        do {
            let samples = try await allSamples(type: metric.type, end: end).compactMap { $0 as? HKQuantitySample }
            metricHistory[metric.id] = samples.map { sample in
                let value = sample.quantity.doubleValue(for: metric.unit)
                return MetricHistoryEntry(id: sample.uuid.uuidString, date: sample.endDate, value: metric.transform(value), detail: sample.sourceRevision.source.name, numericValue: value)
            }
            return samples
        } catch {
            metricHistory[metric.id] = []
            metricHistoryErrors[metric.id] = "Historiken kunde inte läsas: \(error.localizedDescription)"
            return []
        }
    }

    private func readSpirometryRatio(fev1: [HKQuantitySample], fvc: [HKQuantitySample]) {
        func measurement(_ sample: HKQuantitySample) -> SpirometrySample {
            let revision = sample.sourceRevision
            let os = revision.operatingSystemVersion
            let device = sample.device
            return SpirometrySample(
                id: sample.uuid.uuidString,
                measurement: .init(start: sample.startDate, end: sample.endDate,
                                   source: [revision.source.bundleIdentifier, revision.version, revision.productType,
                                            "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"],
                                   device: [device?.name, device?.manufacturer, device?.model, device?.hardwareVersion,
                                            device?.firmwareVersion, device?.softwareVersion, device?.localIdentifier,
                                            device?.udiDeviceIdentifier]),
                sourceName: revision.source.name, liters: sample.quantity.doubleValue(for: .liter()))
        }
        metricHistoryErrors["fev1-fvc"] = metricHistoryErrors["fev1"] ?? metricHistoryErrors["fvc"]
        metricHistory["fev1-fvc"] = SpirometryRatio.history(fev1: fev1.map(measurement), fvc: fvc.map(measurement)).map {
            MetricHistoryEntry(id: $0.id, date: $0.date, value: oneDecimal($0.percent),
                               detail: "\($0.sourceName) · Beräknad FEV₁/FVC", numericValue: $0.percent)
        }
    }

    private func readDailyHistory(_ metric: DailyMetric, end: Date) async {
        metricHistoryErrors[metric.id] = nil
        do {
            metricHistory[metric.id] = try await dailyHistory(type: metric.type, unit: metric.unit, end: end).map {
                MetricHistoryEntry(id: String($0.date.timeIntervalSince1970), date: $0.date, value: metric.transform($0.count), detail: "Dagssumma · Apple Hälsa")
            }
        } catch {
            metricHistory[metric.id] = []
            metricHistoryErrors[metric.id] = "Historiken kunde inte läsas: \(error.localizedDescription)"
        }
    }

    private func readSleepHistory(end: Date) async {
        metricHistoryErrors["sleep"] = nil
        do {
            let samples = try await allSamples(type: sleepType, end: end).compactMap { $0 as? HKCategorySample }
            let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
            let calendar = Calendar.current
            var intervalsByDay: [Date: [DateInterval]] = [:]
            var sourcesByDay: [Date: Set<String>] = [:]
            for sample in samples where asleep.contains(sample.value) {
                var cursor = sample.startDate
                let finish = min(sample.endDate, end)
                while cursor < finish {
                    let day = calendar.startOfDay(for: cursor)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    let stop = min(next, finish)
                    intervalsByDay[day, default: []].append(DateInterval(start: cursor, end: stop))
                    sourcesByDay[day, default: []].insert(sample.sourceRevision.source.name)
                    cursor = stop
                }
            }
            metricHistory["sleep"] = intervalsByDay.map { day, intervals in
                let hours = Self.mergedSleepDuration(intervals) / 3600
                return MetricHistoryEntry(id: String(day.timeIntervalSince1970), date: day, value: oneDecimal(hours), detail: sourcesByDay[day, default: []].sorted().joined(separator: ", "),
                                          numericValue: hours)
            }.sorted { $0.date > $1.date }
        } catch {
            metricHistory["sleep"] = []
            metricHistoryErrors["sleep"] = "Historiken kunde inte läsas: \(error.localizedDescription)"
        }
    }

    // Count overlapping sleep stages and sources once, excluding awake and in-bed time.
    nonisolated static func mergedSleepDuration(_ intervals: [DateInterval]) -> TimeInterval {
        var merged: [DateInterval] = []
        for interval in intervals.sorted(by: { $0.start < $1.start }) where interval.duration > 0 {
            if let previous = merged.last, interval.start <= previous.end {
                merged[merged.count - 1] = DateInterval(start: previous.start, end: max(previous.end, interval.end))
            } else { merged.append(interval) }
        }
        return merged.reduce(0) { $0 + $1.duration }
    }

    private func sleep(end: Date) async -> HealthReading? {
        let start = end.addingTimeInterval(-36 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        let samples = await samples(type: sleepType, predicate: predicate).compactMap { $0 as? HKCategorySample }
        let asleep: Set<Int> = [HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue, HKCategoryValueSleepAnalysis.asleepCore.rawValue, HKCategoryValueSleepAnalysis.asleepDeep.rawValue, HKCategoryValueSleepAnalysis.asleepREM.rawValue]
        let intervals = samples.filter { asleep.contains($0.value) }.map { DateInterval(start: max(start, $0.startDate), end: min(end, $0.endDate)) }.sorted { $0.start < $1.start }
        guard !intervals.isEmpty else { return nil }
        let hours = Self.mergedSleepDuration(intervals) / 3600
        let sources = Array(Set(samples.filter { asleep.contains($0.value) }.map { $0.sourceRevision.source.name })).sorted().joined(separator: ", ")
        return HealthReading(id: "sleep", section: "Sömn", title: "Registrerad sömn", icon: "moon.fill", value: oneDecimal(hours), unit: "timmar", detail: "\(sources) · senaste 36 timmarna")
    }

    private func recentWorkouts(end: Date) async -> [WorkoutReading] {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: end)!
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return await samples(type: workoutType, predicate: predicate, limit: 10).compactMap { sample in
            guard let workout = sample as? HKWorkout else { return nil }
            return WorkoutReading(id: workout.uuid, title: workoutName(workout.workoutActivityType), detail: "\((workout.duration / 60).formatted(.number.precision(.fractionLength(0)))) min · \(workout.sourceRevision.source.name) · \(workout.startDate.formatted(date: .abbreviated, time: .shortened))")
        }
    }

    private func samples(type: HKSampleType, predicate: NSPredicate, limit: Int = HKObjectQueryNoLimit) async -> [HKSample] {
        await withCheckedContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error, !self.isNoData(error) { print("HealthKit query failed: \(error)") }
                continuation.resume(returning: samples ?? [])
            }
            store.execute(query)
        }
    }

    private nonisolated func isNoData(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == HKErrorDomain && error.code == HKError.Code.errorNoData.rawValue
    }

    private func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: "Promenad"
        case .running: "Löpning"
        case .cycling: "Cykling"
        case .swimming: "Simning"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Styrketräning"
        case .hiking: "Vandring"
        default: "Träningspass"
        }
    }

    private func integer(_ value: Double) -> String { Int(value.rounded()).formatted() }
    private func oneDecimal(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(1))) }
    private func twoDecimals(_ value: Double) -> String { value.formatted(.number.precision(.fractionLength(2))) }
}
