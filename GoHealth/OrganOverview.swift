import SwiftUI

struct OrganMetric: Identifiable {
    enum Specimen {
        case blood
    }

    enum Status {
        case optimal, normal, outside, measured, missing

        var title: String {
            switch self {
            case .optimal: "Optimalt"
            case .normal: "Normalt"
            case .outside: "Utanför intervall"
            case .measured: "Mätt"
            case .missing: "Saknas"
            }
        }

        var color: Color {
            switch self {
            case .optimal: Color(red: 0.02, green: 0.49, blue: 0.30)
            case .normal: Color(red: 0.59, green: 0.37, blue: 0.03)
            case .outside: Color(red: 0.73, green: 0.09, blue: 0.37)
            case .measured: Color(red: 0.22, green: 0.38, blue: 0.61)
            case .missing: .secondary
            }
        }
    }

    let id: String
    let title: String
    var source: String
    let unit: String
    var samples: [Double]
    var demoStatus: Status? = nil
    // Collection date supplied with the latest result, independently of entry/import time.
    var sampledAt: Date? = nil
    var specimen: Specimen? = nil
    var clinicalObservation: ClinicalObservation? = nil

    var subtitle: String {
        guard specimen == .blood else { return source }
        guard let sampledAt, !samples.isEmpty || clinicalObservation != nil else { return "Provtagningsdatum saknas" }
        let date = sampledAt.formatted(.dateTime.locale(Locale(identifier: "sv_SE"))
            .day().month(.abbreviated).year())
        return "Senast tagen \(date)"
    }

    var withoutDemoData: Self {
        var metric = self
        metric.samples = []
        metric.demoStatus = nil
        metric.sampledAt = nil
        return metric
    }

    var status: Status { clinicalObservation.map { $0.outsideReference ? .outside : .measured } ?? demoStatus ?? (samples.isEmpty ? .missing : .measured) }

    var currentValue: String {
        if let clinicalObservation { return clinicalObservation.formattedValue }
        guard let latest = samples.last else { return "—" }
        let number = latest.formatted(.number.precision(.fractionLength(0...2)))
        return unit.isEmpty ? number : "\(number) \(unit)"
    }
}

struct ThyroidAntibodyResult: Identifiable {
    enum Marker: Hashable {
        case tpo, trak

        var title: String {
            switch self {
            case .tpo: "TPO-antikroppar"
            case .trak: "TRAK"
            }
        }

        var explanation: String {
            switch self {
            case .tpo:
                "TPO-antikroppar riktar sig mot ett enzym som sköldkörteln använder för att bilda hormoner. Provet kan ge stöd för en autoimmun orsak, till exempel Hashimotos tyreoidit."
            case .trak:
                "TRAK är antikroppar mot den receptor i sköldkörteln som tar emot signaler från hormonet TSH. Provet används framför allt vid misstanke om Graves sjukdom."
            }
        }
    }

    let id: Marker
    let value: String
    let sampledAt: Date
    let referenceLimit: String

    static let demoResults: [Self] = {
        let calendar = Calendar(identifier: .gregorian)
        guard let date = DateComponents(calendar: calendar, year: 2026, month: 11, day: 3, hour: 12).date else { return [] }
        return [
            .init(id: .tpo, value: "180 kE/L", sampledAt: date, referenceLimit: "< 20 kE/L"),
            .init(id: .trak, value: "0,7 E/L", sampledAt: date, referenceLimit: "< 1,8 E/L")
        ]
    }()
}

extension BodyOrgan {
    private static let demoBloodSampleDate = DateComponents(
        calendar: Calendar(identifier: .gregorian),
        timeZone: TimeZone(identifier: "Europe/Stockholm"),
        year: 2026, month: 11, day: 3, hour: 12
    ).date

    var overviewTitle: String {
        switch self {
        case .heart: "Hjärthälsa"
        case .liver: "Leverhälsa"
        case .lungs: "Andning"
        case .kidneys: "Njurfunktion"
        case .thyroid: "Sköldkörtelfunktion"
        }
    }

    var demoMetrics: [OrganMetric] {
        switch self {
        case .heart:
            [
                .init(id: "biological-age", title: "Biologisk ålder", source: "Fenotypisk ålder", unit: "år", samples: [31, 30.6, 30, 29.7, 28.9], demoStatus: .optimal),
                .init(id: "heart-rate", title: "Puls", source: "Dagligt genomsnitt", unit: "slag/min", samples: [67, 65, 66, 63, 62], demoStatus: .optimal),
                .init(id: "hrv", title: "Hjärtfrekvens­variabilitet", source: "RMSSD · 7 dagar", unit: "ms", samples: [49, 53, 51, 55, 57], demoStatus: .normal),
                .init(id: "apob", title: "Apolipoprotein B", source: "Blodprov", unit: "mg/dL", samples: [102, 99, 100, 97, 94], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "total-cholesterol", title: "Totalkolesterol", source: "Blodprov", unit: "mg/dL", samples: [202, 214, 220, 218, 238], demoStatus: .outside, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "ldl", title: "LDL-kolesterol", source: "Blodprov", unit: "mg/dL", samples: [120, 117, 109, 112, 105], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "resting-heart-rate", title: "Vilopuls", source: "Senaste mätning", unit: "slag/min", samples: [63, 62, 64, 60, 59], demoStatus: .optimal)
            ]
        case .liver:
            [
                .init(id: "alt", title: "ALAT", source: "Blodprov", unit: "µkat/L", samples: [0.55, 0.47, 0.51, 0.44, 0.41], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "ast", title: "ASAT", source: "Blodprov", unit: "µkat/L", samples: [0.48, 0.43, 0.45, 0.39, 0.36], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "alp", title: "ALP", source: "Blodprov", unit: "µkat/L", samples: [1.18, 1.21, 1.16, 1.12, 1.14], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "ggt", title: "GT", source: "Blodprov", unit: "µkat/L", samples: [0.59, 0.51, 0.48, 0.52, 0.45], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "bilirubin", title: "Bilirubin", source: "Blodprov", unit: "µmol/L", samples: [12, 13, 10, 11, 10], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "albumin", title: "Albumin", source: "Blodprov", unit: "g/L", samples: [41, 42, 42, 43, 44], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "inr", title: "PK (INR)", source: "Blodprov", unit: "", samples: [1, 1.05, 1, 1, 1.02], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood)
            ]
        case .lungs:
            [
                .init(id: "respiratory-rate", title: "Andningsfrekvens", source: "Senaste mätning", unit: "andetag/min", samples: [15.3, 15.7, 15.1, 14.9, 15.2], demoStatus: .normal),
                .init(id: "oxygen", title: "Syremättnad", source: "Senaste mätning", unit: "%", samples: [97, 98, 97, 96, 98], demoStatus: .normal),
                .init(id: "vo2-max", title: "VO₂ max", source: "Kondition", unit: "ml/kg/min", samples: [40.8, 41.2, 41.0, 41.9, 42.4]),
                .init(id: "fev1", title: "FEV₁", source: "Utandad volym · 1 sekund", unit: "L", samples: [3.10, 3.18, 3.15, 3.22, 3.25]),
                .init(id: "fvc", title: "FVC", source: "Total forcerad utandning", unit: "L", samples: [4.00, 4.05, 4.02, 4.10, 4.12]),
                .init(id: "fev1-fvc", title: "FEV₁/FVC", source: "Andel utandad första sekunden", unit: "%", samples: zip([3.10, 3.18, 3.15, 3.22, 3.25], [4.00, 4.05, 4.02, 4.10, 4.12]).map { $0 / $1 * 100 }),
                .init(id: "pef", title: "PEF", source: "Högsta utandningsflöde", unit: "L/min", samples: [460, 480, 470, 490, 500])
            ]
        case .kidneys:
            [
                .init(id: "creatinine", title: "Kreatinin", source: "Blodprov", unit: "µmol/L", samples: [80, 85, 81, 83, 84], demoStatus: .normal, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "egfr", title: "eGFR", source: "Skattad filtration", unit: "mL/min/1,73 m²", samples: [96, 89, 95, 92, 90], demoStatus: .normal),
                .init(id: "urine-acr", title: "Albumin/kreatinin-kvot", source: "Urinprov", unit: "mg/mmol", samples: [1.2, 1.6, 2.3, 2.1, 5.4], demoStatus: .outside)
            ]
        case .thyroid:
            [
                .init(id: "tsh", title: "TSH", source: "Blodprov", unit: "mIE/L", samples: [4.1, 4.8, 5.4, 6.2, 7.1], demoStatus: .outside, sampledAt: Self.demoBloodSampleDate, specimen: .blood),
                .init(id: "free-t4", title: "Fritt T4", source: "Blodprov", unit: "pmol/L", samples: [14, 13, 12, 11, 9], demoStatus: .outside, sampledAt: Self.demoBloodSampleDate, specimen: .blood)
            ]
        }
    }
}

struct OrganOverview: View {
    private enum DemoGrade: String {
        case a = "A", b = "B", c = "C"

        var color: Color {
            switch self {
            case .a: OrganMetric.Status.optimal.color
            case .b: OrganMetric.Status.normal.color
            case .c: OrganMetric.Status.outside.color
            }
        }
    }

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedAntibodies: Set<ThyroidAntibodyResult.Marker> = []
    let organ: BodyOrgan
    let metrics: [OrganMetric]
    let isDemo: Bool
    let healthLinked: Bool
    let isLoading: Bool
    let close: () -> Void
    let connectHealth: () -> Void
    var latestAntibodyResults: [ThyroidAntibodyResult] = []

    private let historyWidth: CGFloat = 52
    private let statusWidth: CGFloat = 83

    private var displayedAntibodies: [ThyroidAntibodyResult] {
        guard organ == .thyroid else { return [] }
        return isDemo ? ThyroidAntibodyResult.demoResults : latestAntibodyResults
    }

    private var demoGrade: DemoGrade {
        switch metrics.filter({ $0.demoStatus == .outside }).count {
        case 0: .a
        case 1: .b
        default: .c
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if !isDemo {
                Text(organ == .lungs
                     ? "Betyg kräver ett validerat underlag."
                     : "Betyg kräver ett validerat underlag. Ingen provsvarskälla är ansluten.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                if organ == .heart || organ == .lungs {
                    if !healthLinked {
                        Button("Anslut Apple Hälsa", action: connectHealth)
                            .buttonStyle(.bordered)
                    } else if isLoading {
                        ProgressView("Hämtar mätvärden…").font(.footnote)
                    }
                }
            }
            VStack(spacing: 0) {
                if !dynamicTypeSize.isAccessibilitySize {
                    HStack(spacing: 8) {
                        Text("Markör").frame(maxWidth: .infinity, alignment: .leading)
                        Text("Status").frame(width: statusWidth, alignment: .leading)
                        Text("Historik").frame(width: historyWidth, alignment: .leading)
                    }
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                    .accessibilityHidden(true)
                }
                ForEach(metrics) { metric in
                    if organ == .lungs && metric.id == "fev1" {
                        Text("Lungfunktion")
                            .font(.subheadline.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, 16)
                            .padding(.bottom, 8)
                            .accessibilityAddTraits(.isHeader)
                    }
                    Divider()
                    metricRow(metric)
                        .padding(.vertical, 10)
                        .accessibilityElement(children: .combine)
                }
            }
            if organ == .lungs {
                Text("FEV₁, FVC och PEF kräver spirometri eller PEF-mätare. FEV₁/FVC beräknas från matchande mätningar. Status Mätt innebär att värdet saknar bedömning mot referensvärden.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !displayedAntibodies.isEmpty {
                antibodiesSection(displayedAntibodies)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(.black.opacity(0.06)) }
        .accessibilityAction(.escape, close)
    }

    private func antibodiesSection(_ results: [ThyroidAntibodyResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Antikroppar")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(results) { result in
                Divider()
                antibodyRow(result)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    private func antibodyRow(_ result: ThyroidAntibodyResult) -> some View {
        let isExpanded = expandedAntibodies.contains(result.id)
        return VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.30)) {
                    if isExpanded {
                        expandedAntibodies.remove(result.id)
                    } else {
                        expandedAntibodies.insert(result.id)
                    }
                }
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    LabeledContent {
                        HStack(spacing: 8) {
                            Text(result.value).monospacedDigit()
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                                .rotationEffect(.degrees(isExpanded ? 180 : 0))
                                .accessibilityHidden(true)
                        }
                    } label: {
                        Text(result.id.title)
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    Text("Provdatum \(result.sampledAt.formatted(.dateTime.day().month(.abbreviated).year()))")
                    Text("Labgräns \(result.referenceLimit)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(isExpanded ? "Dölj förklaring" : "Visa förklaring")

            if isExpanded {
                Text(result.id.explanation)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(organ.overviewTitle)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                Text(isDemo ? "Testvärden · Exempelbetyg" : "Översikt över dina mätvärden")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isDemo {
                let grade = demoGrade
                Text(grade.rawValue)
                    .font(.title2.bold())
                    .foregroundStyle(grade.color)
                    .padding(9)
                    .frame(minWidth: 44, minHeight: 44)
                    .background(grade.color.opacity(0.08), in: Circle())
                    .overlay { Circle().strokeBorder(grade.color, lineWidth: 2) }
                    .accessibilityLabel("Exempelbetyg \(grade.rawValue)")
            }

            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.04), in: Circle())
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stäng \(organ.overviewTitle.lowercased())")
        }
    }

    @ViewBuilder
    private func metricRow(_ metric: OrganMetric) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                metricTitle(metric)
                metricStatus(metric)
                history(metric).frame(width: 100)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 8) {
                metricTitle(metric)
                    .frame(maxWidth: .infinity, alignment: .leading)
                metricStatus(metric)
                    .frame(width: statusWidth, alignment: .leading)
                history(metric)
                    .frame(width: historyWidth)
            }
        }
    }

    private func metricTitle(_ metric: OrganMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(metric.title).font(.subheadline.weight(.semibold))
            Text(metric.subtitle).font(.caption2).foregroundStyle(.secondary)
            if let observation = metric.clinicalObservation {
                Text(observation.reference).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func metricStatus(_ metric: OrganMetric) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle().fill(metric.status.color)
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
                Text(metric.status.title)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(metric.status.color)
            }
            Text(metric.currentValue)
                .font(.caption.weight(.medium).monospacedDigit())
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func history(_ metric: OrganMetric) -> some View {
        if metric.samples.count >= 2 {
            OrganSparkline(samples: metric.samples, color: metric.status.color)
                .frame(height: 28)
        } else {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Ingen kort historik")
        }
    }
}

private struct OrganSparkline: View {
    let samples: [Double]
    let color: Color

    private var trend: String {
        guard let first = samples.first, let last = samples.last else { return "Ingen historik" }
        if last > first { return "Senaste värdet är högre än det första" }
        if last < first { return "Senaste värdet är lägre än det första" }
        return "Första och senaste värdet är lika"
    }

    var body: some View {
        Canvas { context, size in
            guard let minimum = samples.min(), let maximum = samples.max(), samples.count >= 2 else { return }
            let points = samples.enumerated().map { index, value in
                let fraction = maximum == minimum ? 0.5 : (value - minimum) / (maximum - minimum)
                return CGPoint(x: 2 + (size.width - 4) * CGFloat(index) / CGFloat(samples.count - 1),
                               y: 3 + (size.height - 9) * (1 - fraction))
            }
            guard let first = points.first, let last = points.last else { return }
            var line = Path()
            line.addLines(points)
            var area = line
            area.addLine(to: CGPoint(x: last.x, y: size.height))
            area.addLine(to: CGPoint(x: first.x, y: size.height))
            area.closeSubpath()
            context.fill(area, with: .linearGradient(
                Gradient(colors: [color.opacity(0.23), color.opacity(0.02)]),
                startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
            ))
            context.stroke(line, with: .color(color), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            for point in points {
                context.fill(Path(ellipseIn: CGRect(x: point.x - 1.5, y: point.y - 1.5, width: 3, height: 3)), with: .color(color))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Historik, \(samples.count) mätningar")
        .accessibilityValue(trend)
    }
}
