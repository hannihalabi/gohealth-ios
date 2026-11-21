import FoundationModels
import SwiftUI

struct HealthSummaryView: View {
    @ObservedObject var health: HealthStore
    @ObservedObject var vaccinations: VaccinationStore
    @StateObject private var imaging: RadiologyStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var featured: Focus?
    @State private var visible = false

    let healthLinked: Bool
    let age: Int?
    let connect: () -> Void
    let refreshHealth: () async -> Void
    let openVaccinations: () -> Void
    let openImaging: () -> Void

    init(health: HealthStore, vaccinations: VaccinationStore, healthLinked: Bool, age: Int?,
         isBeta: Bool, imagingToken: @escaping () async throws -> String,
         connect: @escaping () -> Void, refreshHealth: @escaping () async -> Void,
         openVaccinations: @escaping () -> Void, openImaging: @escaping () -> Void) {
        self.health = health
        self.vaccinations = vaccinations
        self.healthLinked = healthLinked
        self.age = age
        self.connect = connect
        self.refreshHealth = refreshHealth
        self.openVaccinations = openVaccinations
        self.openImaging = openImaging
        _imaging = StateObject(wrappedValue: RadiologyStore(isBeta: isBeta, token: imagingToken))
    }

    private struct Day: Identifiable {
        let id: Date
        let value: Double?
    }

    private enum Focus: String {
        case sleep, activity, vitals, imaging, vaccination

        var title: String {
            switch self {
            case .sleep: "Din sömn den senaste veckan"
            case .activity: "Din rörelse den senaste veckan"
            case .vitals: "Dina senaste mätningar"
            case .imaging: "Dina bildundersökningar"
            case .vaccination: "Din vaccinationsöversikt"
            }
        }

        var symbol: String {
            switch self {
            case .sleep: "moon.stars.fill"
            case .activity: "figure.walk"
            case .vitals: "waveform.path.ecg"
            case .imaging: "viewfinder"
            case .vaccination: "syringe"
            }
        }
    }

    private static let sleepReference = 7.0
    private let plum = Color(red: 0.28, green: 0.12, blue: 0.31)
    private let pink = Color(red: 0.91, green: 0.47, blue: 0.66)
    private let lavender = Color(red: 0.72, green: 0.65, blue: 0.99)
    private let ink = Color(red: 0.15, green: 0.12, blue: 0.21)

    private var sleepDays: [Day] {
        let values = (health.metricHistory["sleep"] ?? []).compactMap { entry in
            entry.numericValue.map { (entry.date, $0) }
        }
        return week(values)
    }

    private var stepDays: [Day] { steps() }

    private func steps(endingDaysAgo: Int = 0) -> [Day] {
        week(health.stepHistory.map { ($0.date, $0.count) }, endingDaysAgo: endingDaysAgo)
    }

    private func week(_ readings: [(Date, Double)], endingDaysAgo: Int = 0) -> [Day] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let firstDay = calendar.date(byAdding: .day, value: -(endingDaysAgo + 7), to: today) ?? today
        let end = calendar.date(byAdding: .day, value: -endingDaysAgo, to: today) ?? today
        let recent = readings.filter { $0.0 >= firstDay && $0.0 < end }
        let values = Dictionary(recent.map { (calendar.startOfDay(for: $0.0), $0.1) },
                                uniquingKeysWith: { latest, _ in latest })
        return (1...7).reversed().compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: -(endingDaysAgo + offset), to: today) else { return nil }
            return Day(id: day, value: values[day])
        }
    }

    private var sleepValues: [Double] { sleepDays.compactMap(\.value) }
    private var shortSleepDays: Int { sleepValues.filter { $0 < Self.sleepReference }.count }
    private var usesAdultSleepReference: Bool { age.map { $0 >= 18 } ?? true }
    private var highlightSleep: Bool {
        usesAdultSleepReference && sleepValues.count >= 4 && shortSleepDays > sleepValues.count / 2
    }

    private var highlightActivity: Bool {
        let recent = stepDays.compactMap(\.value)
        let earlier = steps(endingDaysAgo: 7).compactMap(\.value)
        guard recent.count >= 4, earlier.count >= 4 else { return false }
        let previousAverage = earlier.reduce(0, +) / Double(earlier.count)
        return previousAverage > 0 && recent.reduce(0, +) / Double(recent.count) <= previousAverage * 0.8
    }

    private var takenCount: Int { vaccinations.records.filter { !$0.isPlanned }.count }
    private var nextDose: VaccinationRecord? {
        vaccinations.records.filter(\.isPlanned).min { $0.date < $1.date }
    }

    private let vitalIDs = ["heart-rate", "resting-heart-rate", "respiratory-rate", "oxygen", "hrv"]

    private var vitals: [HealthReading] {
        vitalIDs.compactMap { id in health.readings.first { $0.id == id } }
    }

    private var imagingCount: Int { imaging.error == nil ? imaging.studies.count : 0 }

    private var options: [Focus] {
        var values: [Focus] = []
        if !sleepValues.isEmpty { values.append(.sleep) }
        if stepDays.contains(where: { $0.value != nil }) { values.append(.activity) }
        if highlightActivity, !highlightSleep {
            values.removeAll { $0 == .activity }
            values.insert(.activity, at: 0)
        }
        if !vitals.isEmpty { values.append(.vitals) }
        if nextDose != nil { values.insert(.vaccination, at: highlightSleep ? min(1, values.count) : 0) }
        else if takenCount > 0 { values.append(.vaccination) }
        if imagingCount > 0 { values.append(.imaging) }
        return values
    }

    private var aiContext: String {
        """
        Eligible keys: \(options.map(\.rawValue).joined(separator: ", ")).
        Sleep: \(shortSleepDays) of \(sleepValues.count) recorded days below the display reference, repeated short sleep: \(highlightSleep).
        Activity: \(stepDays.compactMap(\.value).count) recorded days, fewer daily steps than the previous week: \(highlightActivity).
        Vital metrics available: \(vitals.count).
        Imaging: \(imagingCount) available studies.
        Vaccination: \(takenCount) recorded doses, planned dose: \(nextDose != nil).
        """
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overview
                if highlightSleep { sleepTip }
                if highlightActivity { activityTip }
                if !healthLinked {
                    Button(action: connect) {
                        Label("Anslut Apple Hälsa", systemImage: "heart.text.square")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                }
                if healthLinked { metrics }
                sourceCards
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(Color(red: 0.965, green: 0.956, blue: 0.978))
        .refreshable {
            vaccinations.load()
            await refreshHealth()
            await imaging.load()
        }
        .task {
            vaccinations.load()
            await imaging.load()
        }
        .task(id: aiContext) {
            featured = nil
            await selectFocus(context: aiContext, options: options)
        }
        .onAppear {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.55)) { visible = true }
        }
    }

    private var overview: some View {
        let focus = featured.flatMap { options.contains($0) ? $0 : nil } ?? options.first
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(featured == nil ? "Din hälsoöversikt" : "AI-valt fokus", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if health.isBeta {
                    Text("Testdata")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.white.opacity(0.14), in: Capsule())
                }
            }
            Text(focus?.title ?? "Inga data ännu")
                .font(.largeTitle.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
                .contentTransition(.opacity)
            if let focus {
                switch focus {
                case .sleep:
                    heroValue(average(sleepValues, decimals: 1), unit: "timmar i snitt")
                    chart(sleepDays, isSleep: true, color: lavender)
                case .activity:
                    heroValue(average(stepDays.compactMap(\.value), decimals: 0), unit: "steg i snitt")
                    chart(stepDays, color: pink)
                case .vitals:
                    if let first = vitals.first { heroValue(first.value, unit: "\(first.title) · \(first.unit)") }
                case .imaging:
                    heroValue(imagingCount.formatted(), unit: imagingCount == 1 ? "undersökning" : "undersökningar")
                case .vaccination:
                    if let nextDose {
                        heroValue(nextDose.date.formatted(VaccinationRecord.dateFormat.day().month(.abbreviated)),
                                  unit: "\(doseStatus(nextDose)) · \(nextDose.vaccine)")
                    } else {
                        heroValue(takenCount.formatted(), unit: "registrerade doser")
                    }
                }
            } else {
                Text("Mätningar och registrerade händelser samlas här när de finns tillgängliga.")
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
        .background {
            RoundedRectangle(cornerRadius: 28)
                .fill(LinearGradient(colors: [ink, plum, Color(red: 0.45, green: 0.20, blue: 0.43)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 116, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.10))
                        .padding(.trailing, 8)
                        .accessibilityHidden(true)
                }
        }
    }

    private func heroValue(_ value: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(.largeTitle, design: .rounded, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText())
            Text(unit).font(.subheadline).foregroundStyle(.white.opacity(0.82))
        }
        .accessibilityElement(children: .combine)
    }

    private var sleepTip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Ett steg för sömnen", systemImage: "moon.stars")
                .font(.headline)
                .foregroundStyle(plum)
            Text("\(shortSleepDays) av \(sleepValues.count) dagar med mätningar visar under 7 timmars registrerad sömn.")
                .font(.subheadline)
            Text("7 timmar används här som referens för vuxna.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Prova att gå upp vid ungefär samma tid de närmaste dagarna.")
                .font(.subheadline.weight(.medium))
            Link("Om sömnvanor", destination: URL(string: "https://www.1177.se/Vasternorrland/liv--halsa/stresshantering-och-somn/somnsvarigheter/")!)
                .font(.caption.weight(.semibold))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.94, green: 0.88, blue: 0.97), in: RoundedRectangle(cornerRadius: 20))
    }

    private var activityTip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Plats för mer rörelse", systemImage: "figure.walk")
                .font(.headline).foregroundStyle(plum)
            Text("Du registrerade färre steg per dag än veckan före.")
                .font(.subheadline)
            Text("Prova en kort promenad vid en tid som passar dig.")
                .font(.subheadline.weight(.medium))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.97, green: 0.90, blue: 0.94), in: RoundedRectangle(cornerRadius: 20))
    }

    private var metrics: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Senaste 7 avslutade dagar").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                metricCard("Sömn", icon: "moon.stars.fill", value: average(sleepValues, decimals: 1),
                           unit: "tim/dag i snitt", days: sleepDays, color: plum, isSleep: true)
                metricCard("Aktivitet", icon: "figure.walk", value: average(stepDays.compactMap(\.value), decimals: 0),
                           unit: "steg/dag i snitt", days: stepDays, color: Color(red: 0.66, green: 0.16, blue: 0.42))
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("Vitalparametrar", systemImage: "waveform.path.ecg").font(.headline)
                if vitals.isEmpty {
                    Text(health.isLoading ? "Hämtar mätningar…" : "Inga mätningar tillgängliga")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                ForEach(vitals) { reading in
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline) {
                            vitalLabel(reading)
                            Spacer(minLength: 8)
                            vitalValue(reading)
                        }
                        VStack(alignment: .leading, spacing: 4) {
                            vitalLabel(reading)
                            vitalValue(reading)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private func vitalLabel(_ reading: HealthReading) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(reading.title).font(.subheadline)
            if let date = health.metricHistory[reading.id]?.first?.date {
                Text(date, format: .dateTime.day().month(.abbreviated))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func vitalValue(_ reading: HealthReading) -> some View {
        Text("\(reading.value) \(reading.unit)")
            .font(.subheadline.weight(.semibold)).monospacedDigit()
    }

    private func metricCard(_ title: String, icon: String, value: String, unit: String,
                            days: [Day], color: Color, isSleep: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(value).font(.title2.weight(.semibold)).monospacedDigit().contentTransition(.numericText())
            Text(value == "—" ? "Inga mätningar" : unit).font(.caption).foregroundStyle(.secondary)
            chart(days, isSleep: isSleep, color: color)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func chart(_ days: [Day], isSleep: Bool = false, color: Color) -> some View {
        let height = 42.0
        let reference = isSleep && usesAdultSleepReference ? Self.sleepReference : nil
        let ceiling = max(days.compactMap(\.value).max() ?? 0, reference ?? 0, 1)
        return HStack(spacing: 4) {
            ForEach(days) { day in
                let belowReference = day.value.map { value in reference.map { value < $0 } ?? false } ?? false
                VStack(spacing: 4) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color.opacity(day.value == nil ? 0.13 : belowReference ? 0.52 : 1))
                        .frame(height: visible ? max(3, height * (day.value ?? 0) / ceiling) : 3)
                        .frame(maxWidth: .infinity)
                        .frame(height: height, alignment: .bottom)
                    Text(day.id, format: .dateTime.weekday(.narrow))
                        .font(.caption2)
                        .lineLimit(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(day.id.formatted(.dateTime.weekday(.wide).day().month()))
                .accessibilityValue(day.value.map {
                    isSleep ? "\($0.formatted(.number.precision(.fractionLength(1)))) timmar"
                        : "\($0.formatted(.number.precision(.fractionLength(0)))) steg"
                } ?? "Ingen mätning")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Dagliga värden, äldst först")
    }

    private var sourceCards: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Undersökningar och vaccination").font(.headline)
            sourceCard("Röntgen", icon: "viewfinder", detail: imagingDetail, action: openImaging)
            sourceCard("Vaccination", icon: "syringe", detail: vaccinationDetail, action: openVaccinations)
        }
    }

    private var imagingDetail: String {
        if imaging.isLoading { return "Hämtar undersökningar…" }
        if imaging.api == nil || imaging.error != nil { return "Undersökningar är inte tillgängliga" }
        if imagingCount == 0 { return "Inga undersökningar registrerade" }
        let count = imagingCount == 1 ? "1 undersökning" : "\(imagingCount) undersökningar"
        if let latest = imaging.studies.max(by: { $0.studyDate < $1.studyDate }),
           latest.studyDate.count == 8, latest.studyDate.utf8.allSatisfy({ (48...57).contains($0) }) {
            let date = "\(latest.studyDate.prefix(4))-\(latest.studyDate.dropFirst(4).prefix(2))-\(latest.studyDate.suffix(2))"
            return "\(count) · \(latest.modality) · \(date)"
        }
        return count
    }

    private var vaccinationDetail: String {
        if vaccinations.loadFailed { return "Doserna kunde inte hämtas" }
        if !vaccinations.isLoaded { return "Hämtar doser…" }
        if let nextDose {
            let date = nextDose.date.formatted(VaccinationRecord.dateFormat.day().month(.abbreviated).year())
            return "\(doseStatus(nextDose)) · \(nextDose.vaccine) · \(date)"
        }
        return takenCount == 0 ? "Inga doser registrerade" : "\(takenCount) registrerade doser"
    }

    private func doseStatus(_ dose: VaccinationRecord) -> String {
        dose.date < VaccinationRecord.today ? "Ej bekräftad" : "Planerad"
    }

    private func sourceCard(_ title: String, icon: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(plum)
                    .frame(width: 40, height: 40)
                    .background(plum.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.subheadline.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(plum)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private func average(_ values: [Double], decimals: Int) -> String {
        guard !values.isEmpty else { return "—" }
        return (values.reduce(0, +) / Double(values.count))
            .formatted(.number.precision(.fractionLength(decimals)))
    }

    private func selectFocus(context: String, options: [Focus]) async {
        guard #available(iOS 26, *), options.count > 1,
              SystemLanguageModel.default.availability == .available else { return }
        do {
            try await Task.sleep(for: .milliseconds(500))
            let session = LanguageModelSession(instructions: """
                Pick one eligible key for a personal health dashboard. Prioritize repeated short recorded sleep,
                then a planned appointment, then decreased activity, then the best populated trend. Return only the exact key.
                """)
            let result = try await session.respond(to: context)
            try Task.checkCancellation()
            let key = result.content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard let focus = Focus(rawValue: key), options.contains(focus) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { featured = focus }
        } catch {
            // The overview already has a local fallback when a model is unavailable.
        }
    }
}
