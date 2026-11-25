import Charts
import SwiftUI

private enum HealthGrade: String, CaseIterable {
    case a = "A", b = "B", c = "C", d = "D"

    struct Example: Identifiable {
        let title: String
        let detail: String
        var id: String { title }
    }

    var title: String {
        switch self {
        case .a: "Jämn utveckling"
        case .b: "Stabil grund"
        case .c: "Flera förändringar att följa"
        case .d: "Tydliga förändringar över tid"
        }
    }

    var examples: [Example] {
        switch self {
        case .a:
            [
                .init(title: "Sömnen håller en jämn rytm",
                      detail: "Sovtiderna är ungefär desamma de flesta nätter och sömntiden är stabil från vecka till vecka."),
                .init(title: "Rörelsen har blivit en vana",
                      detail: "Aktiviteten är regelbunden över flera månader och vilopulsen ligger nära den egna vanliga nivån.")
            ]
        case .b:
            [
                .init(title: "Mer rörelse, ojämn sömn",
                      detail: "Stegen har blivit fler över året, medan den genomsnittliga sömntiden varierar mellan månaderna."),
                .init(title: "Stabil vilopuls, varierande aktivitet",
                      detail: "Vilopulsen följer det vanliga mönstret. Aktiva veckor varvas med lugnare veckor.")
            ]
        case .c:
            [
                .init(title: "Sömnen har blivit kortare",
                      detail: "Flera nätter i veckan är kortare än vanligt och veckosnittet har sjunkit gradvis."),
                .init(title: "Mindre rörelse under flera veckor",
                      detail: "Vardagsstegen har minskat under en längre period, samtidigt som sömnrytmen har blivit mer ojämn.")
            ]
        case .d:
            [
                .init(title: "Sömn och aktivitet har minskat samtidigt",
                      detail: "Både sömntiden och den vardagliga rörelsen ligger under de egna tidigare nivåerna i flera veckor."),
                .init(title: "Vilopuls och pulsvariation har förändrats",
                      detail: "Vilopulsen ligger högre och pulsvariationen lägre än vanligt under samma period.")
            ]
        }
    }

    var position: Double {
        switch self {
        case .a: 1
        case .b: 0.75
        case .c: 0.5
        case .d: 0.25
        }
    }
}

private enum HealthGradeSource: CaseIterable {
    case sleep, pulse, breathing, activity, bloodTests, imaging, recovery, vaccinations

    var title: String {
        switch self {
        case .sleep: "Sömn"
        case .pulse: "Vilopuls"
        case .breathing: "Andningsfrekvens"
        case .activity: "Fysisk aktivitet"
        case .bloodTests: "Blodprover"
        case .imaging: "Röntgen"
        case .recovery: "Pulsvariation (HRV)"
        case .vaccinations: "Vaccinationer"
        }
    }

    var scanMessage: String {
        switch self {
        case .sleep: "Läser sömnen det senaste året…"
        case .pulse: "Läser pulsmätningarna det senaste året…"
        case .breathing: "Beräknar andningsfrekvensen det senaste året…"
        case .activity: "Går igenom din fysiska aktivitet…"
        case .bloodTests: "Går igenom alla dina blodprover…"
        case .imaging: "Går igenom dina röntgenbilder…"
        case .recovery: "Jämför din pulsvariation över tid…"
        case .vaccinations: "Går igenom din vaccinationshistorik…"
        }
    }

    var symbol: String {
        switch self {
        case .sleep: "moon.stars"
        case .pulse: "heart"
        case .breathing: "lungs"
        case .activity: "figure.walk"
        case .bloodTests: "testtube.2"
        case .imaging: "viewfinder"
        case .recovery: "waveform.path.ecg"
        case .vaccinations: "syringe"
        }
    }

    var tint: Color {
        switch self {
        case .sleep, .recovery: Color(red: 0.43, green: 0.29, blue: 0.69)
        case .pulse, .bloodTests: Color(red: 0.65, green: 0.16, blue: 0.39)
        case .breathing, .imaging: Color(red: 0.18, green: 0.40, blue: 0.61)
        case .activity, .vaccinations: Color(red: 0.16, green: 0.43, blue: 0.38)
        }
    }

    var resultTint: Color {
        switch self {
        case .sleep, .recovery: Color(red: 0.85, green: 0.75, blue: 1.0)
        case .pulse, .bloodTests: Color(red: 1.0, green: 0.72, blue: 0.87)
        case .breathing, .imaging: Color(red: 0.72, green: 0.83, blue: 1.0)
        case .activity, .vaccinations: Color(red: 0.68, green: 0.91, blue: 0.85)
        }
    }
}

private struct HealthGradeReport {
    struct Metric: Identifiable {
        let source: HealthGradeSource
        let value: String
        let context: String
        var trend: [Double] = []
        var id: HealthGradeSource { source }
    }

    let grade: HealthGrade
    let title: String
    let summary: String
    let metrics: [Metric]

    static let example = HealthGradeReport(
        grade: .b,
        title: HealthGrade.b.title,
        summary: "I exemplet har aktiviteten ökat över året. Sömnen varierar mer mellan månaderna.",
        metrics: [
            .init(source: .sleep, value: "7,0 tim", context: "Per natt i snitt",
                  trend: [7.3, 7.2, 7.1, 7.4, 7.0, 6.8, 6.9, 6.7, 7.0, 7.1, 6.8, 6.7]),
            .init(source: .pulse, value: "61 slag/min", context: "Vilopuls i snitt",
                  trend: [65, 64, 63, 63, 62, 61, 60, 58, 60, 59, 58, 59]),
            .init(source: .breathing, value: "15,2 andetag/min", context: "Andningsfrekvens i snitt",
                  trend: [15.3, 15.6, 15.4, 15.1, 15.2, 14.9, 15.1, 15.2, 15.2, 14.8, 15.0, 15.3]),
            .init(source: .activity, value: "8 240 steg", context: "Per dag i snitt",
                  trend: [6800, 7300, 7400, 7510, 8210, 8310, 8020, 8960, 8810, 9080, 9200, 9280]),
            .init(source: .recovery, value: "52 ms", context: "Pulsvariation i snitt",
                  trend: [45, 46, 49, 46, 52, 53, 49, 54, 55, 56, 58, 61]),
            .init(source: .bloodTests, value: "4 provtagningar", context: "I provhistoriken"),
            .init(source: .imaging, value: "3 undersökningar", context: "I röntgenhistoriken"),
            .init(source: .vaccinations, value: "6 doser", context: "I vaccinationshistoriken")
        ]
    )
}

struct HealthGradePreview<Avatar: View, Measurements: View>: View {
    var firstName: String? = nil
    @ViewBuilder var avatar: () -> Avatar
    @ViewBuilder var measurements: () -> Measurements

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var resultFocused: Bool
    @State private var run = 0
    @State private var stepIndex = 0
    @State private var stepStartedAt: Date?
    @State private var scanComplete = false
    @State private var report: HealthGradeReport?
    @State private var exploredGrade: HealthGrade?
    @State private var revealCards = false
    /// The assistant presents the findings once after each scan, before the full results.
    @State private var presented = false

    private let steps = HealthGradeSource.allCases
    private let stepDuration = 2.65
    private let ink = Color(red: 0.19, green: 0.11, blue: 0.22)
    private let plum = Color(red: 0.34, green: 0.12, blue: 0.29)
    private let rose = Color(red: 0.73, green: 0.20, blue: 0.47)
    private let softPink = Color(red: 1.0, green: 0.68, blue: 0.82)
    private let lavender = Color(red: 0.90, green: 0.82, blue: 1.0)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let report, presented {
                        results(report)
                            .transition(.opacity)
                    } else if report == nil {
                        scanning(height: min(650, max(265, geometry.size.height - 244)))
                            .transition(.opacity)
                    }
                }
                .frame(maxWidth: 560)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
            }
            .defaultScrollAnchor(.top)
            .id(run)
        }
        .background {
            if report != nil {
                resultsBackdrop
            }
        }
        .overlay {
            if let report, !presented {
                HealthGradeReveal(firstName: firstName, grade: report.grade.rawValue, gradeTitle: report.title,
                                  gradePosition: report.grade.position, positiveGrade: report.grade == .a || report.grade == .b,
                                  findings: report.revealFindings, isExample: true) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { presented = true }
                }
                .transition(.opacity.combined(with: .scale(scale: 1.04)))
            }
        }
        .background(Color(red: 0.975, green: 0.963, blue: 0.977).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.selection, trigger: stepIndex) { previous, current in
            current > previous
        }
        .task(id: run) { await playScan() }
    }

    private func scanning(height: CGFloat) -> some View {
        let step = steps[stepIndex]

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Hälsobetyg")
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Label("Simulerad genomgång", systemImage: "viewfinder")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(plum)
                }
                Spacer(minLength: 8)
                testBadge
                    .padding(.top, 4)
            }
            .foregroundStyle(ink)

            avatarStage(height: height, tint: step.tint)

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(scanComplete ? "Genomgång klar" : "Steg \(stepIndex + 1) av \(steps.count)",
                          systemImage: scanComplete ? "checkmark.circle.fill" : step.symbol)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(plum)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Spacer(minLength: 8)
                    Button("Visa resultat direkt", action: finishScan)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(plum)
                        .multilineTextAlignment(.trailing)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                        .buttonStyle(.plain)
                }
                Text(scanComplete ? "Tar fram ditt exempelresultat…" : step.scanMessage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .contentTransition(.opacity)
                scanProgress
            }
            .padding(.horizontal, 14)
            .padding(.top, 2)
            .padding(.bottom, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.white, in: RoundedRectangle(cornerRadius: 24))
            .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(plum.opacity(0.08)) }
            .shadow(color: plum.opacity(0.07), radius: 18, y: 8)
        }
    }

    private func avatarStage(height: CGFloat, tint: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 32)

        return avatar()
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(.white)
            .overlay {
                scanGuides(tint)
                if !reduceMotion {
                    TimelineView(.animation) { context in
                        GeometryReader { proxy in
                            let elapsed = context.date.timeIntervalSince(stepStartedAt ?? context.date)
                            let progress = min(1, max(0, elapsed / (stepDuration - 0.18)))
                            // Ease into the changes in direction so the beam traces one continuous pass.
                            let eased = progress * progress * (3 - 2 * progress)
                            let upward = !stepIndex.isMultiple(of: 2)
                            let position = upward ? 1 - eased : eased
                            let beamY = 16 + (proxy.size.height - 32) * position
                            if !scanComplete {
                                scanBeam(tint: tint, upward: upward)
                                    .frame(width: proxy.size.width, height: 122)
                                    .position(x: proxy.size.width / 2, y: beamY)
                            }
                        }
                    }
                    .transaction { $0.animation = nil }
                }
                if scanComplete {
                    RadialGradient(colors: [rose.opacity(0.14), .clear],
                                   center: .center, startRadius: 0, endRadius: height * 0.58)
                        .transition(.opacity)
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(tint.opacity(0.20)) }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func scanGuides(_ tint: Color) -> some View {
        Canvas { context, size in
            let inset: CGFloat = 17
            let length: CGFloat = 17
            var brackets = Path()
            for x in [inset, size.width - inset] {
                for y in [inset, size.height - inset] {
                    let dx = x == inset ? length : -length
                    let dy = y == inset ? length : -length
                    brackets.move(to: CGPoint(x: x, y: y + dy))
                    brackets.addLine(to: CGPoint(x: x, y: y))
                    brackets.addLine(to: CGPoint(x: x + dx, y: y))
                }
            }
            context.stroke(brackets, with: .color(tint.opacity(0.54)),
                           style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round))

            var ruler = Path()
            for tick in 1..<24 {
                let y = inset + (size.height - inset * 2) * CGFloat(tick) / 24
                let width: CGFloat = tick.isMultiple(of: 4) ? 7 : 3
                ruler.move(to: CGPoint(x: inset, y: y))
                ruler.addLine(to: CGPoint(x: inset + width, y: y))
                ruler.move(to: CGPoint(x: size.width - inset - width, y: y))
                ruler.addLine(to: CGPoint(x: size.width - inset, y: y))
            }
            context.stroke(ruler, with: .color(tint.opacity(0.25)), lineWidth: 1)
        }
    }

    private func scanBeam(tint: Color, upward: Bool) -> some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0.02),
            .init(color: tint.opacity(0.07), location: 0.28),
            .init(color: tint.opacity(0.30), location: 0.49),
            .init(color: rose.opacity(0.26), location: 0.52),
            .init(color: .clear, location: 0.75)
        ], startPoint: upward ? .bottom : .top, endPoint: upward ? .top : .bottom)
            .overlay {
                Rectangle()
                    .fill(LinearGradient(colors: [.clear, tint, rose, tint, .clear],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(height: 2)
                    .shadow(color: tint.opacity(0.85), radius: 9)
                    .overlay {
                        Rectangle()
                            .fill(LinearGradient(colors: [.clear, softPink, .clear],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(height: 1)
                    }
            }
            .overlay {
                HStack {
                    Circle().fill(tint).frame(width: 6, height: 6)
                    Spacer()
                    Circle().fill(tint).frame(width: 6, height: 6)
                }
                .padding(.horizontal, 14)
                .shadow(color: tint.opacity(0.85), radius: 6)
            }
    }

    private var scanProgress: some View {
        HStack(spacing: 5) {
            ForEach(Array(steps.enumerated()), id: \.element) { index, source in
                let completed = scanComplete || index < stepIndex
                let active = !scanComplete && index == stepIndex
                let shape = RoundedRectangle(cornerRadius: 10)

                Image(systemName: source.symbol)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(active ? .white : completed ? source.tint : plum.opacity(0.33))
                    .frame(maxWidth: .infinity)
                    .frame(height: 33)
                    .background {
                        if active {
                            shape.fill(LinearGradient(colors: [source.tint, rose],
                                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                        } else {
                            shape.fill(completed ? source.tint.opacity(0.12) : plum.opacity(0.04))
                        }
                    }
                    .overlay { shape.strokeBorder(active ? .white.opacity(0.36) : source.tint.opacity(0.08)) }
                    .overlay(alignment: .topTrailing) {
                        if completed {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white, source.tint)
                                .background(.white, in: Circle())
                                .offset(x: 2, y: -3)
                                .transition(.opacity)
                        }
                    }
                    .shadow(color: active ? source.tint.opacity(0.40) : .clear, radius: 7, y: 2)
            }
        }
        .accessibilityHidden(true)
    }

    private func results(_ report: HealthGradeReport) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .firstTextBaseline) {
                Text("Hälsobetyg")
                    .font(.largeTitle.bold())
                    .tracking(-0.7)
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                testBadge
            }

            gradeCard(report)
            gradeGuide(assigned: report.grade)

            VStack(alignment: .leading, spacing: 4) {
                Text("Resultat")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Exempeltrender från de senaste 12 månaderna")
                    .font(.footnote)
                    .foregroundStyle(lavender)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(Array(report.metrics.enumerated()), id: \.element.id) { index, metric in
                    metricCard(metric)
                        .opacity(revealCards || reduceMotion ? 1 : 0)
                        .offset(y: revealCards || reduceMotion ? 0 : 10)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.35).delay(Double(index) * 0.065),
                                   value: revealCards)
                }
            }

            NavigationLink {
                measurements()
                    .navigationTitle("Mina hälsodata")
                    .toolbar(.visible, for: .navigationBar)
            } label: {
                Label("Visa mina mätningar", systemImage: "waveform.path.ecg")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(ink)
                    .background(softPink, in: Capsule())
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { presented = false }
            } label: {
                Label("Låt assistenten berätta igen", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                stepIndex = 0
                stepStartedAt = nil
                scanComplete = false
                revealCards = false
                exploredGrade = nil
                presented = false
                self.report = nil
                run += 1
            } label: {
                Label("Gör om testscanningen", systemImage: "arrow.clockwise")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .task {
            await Task.yield()
            guard !Task.isCancelled else { return }
            revealCards = true
            resultFocused = true
        }
    }

    private var resultsBackdrop: some View {
        ZStack {
            LinearGradient(stops: [
                .init(color: Color(red: 0.17, green: 0.08, blue: 0.22), location: 0),
                .init(color: Color(red: 0.32, green: 0.13, blue: 0.37), location: 0.51),
                .init(color: Color(red: 0.25, green: 0.10, blue: 0.32), location: 1)
            ], startPoint: .topLeading, endPoint: .bottomTrailing)

            RadialGradient(colors: [rose.opacity(0.56), .clear],
                           center: UnitPoint(x: 0.96, y: 0.15), startRadius: 0, endRadius: 360)
            RadialGradient(colors: [Color(red: 0.56, green: 0.34, blue: 0.82).opacity(0.28), .clear],
                           center: .bottomLeading, startRadius: 0, endRadius: 410)
        }
        .ignoresSafeArea(edges: [.horizontal, .bottom])
        .accessibilityHidden(true)
    }

    private func gradeCard(_ report: HealthGradeReport) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) {
                    gradeSeal(report.grade)
                    gradeSummary(report.title)
                        .fixedSize(horizontal: true, vertical: false)
                }
                VStack(alignment: .leading, spacing: 12) {
                    gradeSeal(report.grade)
                    gradeSummary(report.title)
                }
            }

            Text(report.summary)
                .font(.subheadline)
                .foregroundStyle(lavender)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 26)
            shape.fill(LinearGradient(colors: [.white.opacity(0.13), rose.opacity(0.14)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { shape.strokeBorder(.white.opacity(0.19)) }
        }
    }

    private func gradeSeal(_ grade: HealthGrade) -> some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [softPink.opacity(0.25), softPink.opacity(0.05)],
                                     center: .topLeading, startRadius: 0, endRadius: 145))
                .padding(9)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: revealCards || reduceMotion ? grade.position : 0)
                .stroke(AngularGradient(colors: [.white, lavender, softPink, .white], center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2.5)
                .shadow(color: softPink.opacity(0.48), radius: 8)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.75), value: revealCards)
            Text(grade.rawValue)
                .font(.system(size: 58, weight: .bold, design: .rounded))
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exempelbetyg \(grade.rawValue) på skalan A till D")
        .accessibilityFocused($resultFocused)
    }

    private func gradeSummary(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Ditt betyg")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(lavender)
            Text(title).font(.title2.bold())
        }
    }

    private func gradeGuide(assigned: HealthGrade) -> some View {
        let selection = exploredGrade ?? assigned

        return VStack(alignment: .leading, spacing: 12) {
            Text("Betygsskalan")
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Text("Välj ett betyg för att se exempel.")
                .font(.footnote)
                .foregroundStyle(lavender)

            HStack(spacing: 8) {
                ForEach(HealthGrade.allCases, id: \.self) { grade in
                    gradeButton(grade, assigned: grade == assigned, selected: grade == selection)
                }
            }

            Rectangle()
                .fill(.white.opacity(0.16))
                .frame(height: 1)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 11) {
                Text("Exempel för betyg \(selection.rawValue)")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(softPink)
                Text(selection.title)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                ForEach(selection.examples) { example in
                    HStack(alignment: .top, spacing: 9) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 5))
                            .foregroundStyle(lavender)
                            .padding(.top, 6)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(example.title)
                                .font(.subheadline.weight(.semibold))
                            Text(example.detail)
                                .font(.footnote)
                                .foregroundStyle(lavender)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .id(selection)
            .transition(.opacity)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(resultSurface(cornerRadius: 24))
    }

    private func gradeButton(_ grade: HealthGrade, assigned: Bool, selected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13)

        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                exploredGrade = grade
            }
        } label: {
            HStack(spacing: 4) {
                Text(grade.rawValue)
                    .font(.headline)
                if assigned {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(assigned ? ink : .white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(assigned ? softPink : .white.opacity(selected ? 0.13 : 0.06), in: shape)
            .overlay {
                shape.strokeBorder(selected && !assigned ? lavender : .white.opacity(0.19),
                                   lineWidth: selected && !assigned ? 1.5 : 1)
            }
            .shadow(color: assigned ? softPink.opacity(0.28) : .clear, radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Betyg \(grade.rawValue)")
        .accessibilityValue(assigned ? "Ditt betyg" : "")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityHint("Visar exempel för det här betyget")
    }

    private func resultSurface(cornerRadius: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius)
        return shape.fill(.white.opacity(0.07))
            .overlay { shape.strokeBorder(.white.opacity(0.15)) }
    }

    private var testBadge: some View {
        Text("Testdata")
            .font(.caption.weight(.bold))
            .foregroundStyle(plum)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(Color(red: 0.98, green: 0.89, blue: 0.94), in: Capsule())
    }

    private func metricCard(_ metric: HealthGradeReport.Metric) -> some View {
        let accent = metric.source.resultTint

        return VStack(alignment: .leading, spacing: 7) {
            Image(systemName: metric.source.symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(accent)
                .frame(width: 37, height: 37)
                .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Text(metric.source.title)
                .font(.subheadline.weight(.semibold))
            Text(metric.value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .fixedSize(horizontal: false, vertical: true)
            Text(metric.context)
                .font(.caption)
                .foregroundStyle(lavender)
            if let low = metric.trend.min(), let high = metric.trend.max() {
                let margin = max((high - low) * 0.24, 0.1)
                Chart(Array(metric.trend.enumerated()), id: \.offset) { month, value in
                    LineMark(x: .value("Månad", month), y: .value("Värde", value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(accent)
                    AreaMark(x: .value("Månad", month), yStart: .value("Bas", low - margin),
                             yEnd: .value("Värde", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                }
                .chartYScale(domain: (low - margin)...(high + margin))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 29)
                .accessibilityLabel("Utveckling under tolv månader med testdata")
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(resultSurface(cornerRadius: 19))
    }

    private func playScan() async {
        guard report == nil else { return }
        do {
            for index in steps.indices {
                try Task.checkCancellation()
                guard report == nil else { return }
                stepStartedAt = .now
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                    stepIndex = index
                }
                try await Task.sleep(for: .seconds(stepDuration))
            }
            try Task.checkCancellation()
            guard report == nil else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.26)) {
                scanComplete = true
            }
            try await Task.sleep(for: .milliseconds(700))
            try Task.checkCancellation()
            finishScan()
        } catch {
            // Leaving the tab cancels the current preview.
        }
    }

    private func finishScan() {
        guard report == nil else { return }
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.42)) {
            report = .example
        }
    }
}

// MARK: - Findings for the assistant

private extension HealthGradeReport {
    /// What the assistant tells: each trend compared between the first and the last three months, good news first.
    var revealFindings: [HealthRevealFinding] {
        func mean(_ values: ArraySlice<Double>) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }
        var found: [HealthRevealFinding] = []
        for metric in metrics where metric.trend.count >= 6 {
            let first = mean(metric.trend.prefix(3)), last = mean(metric.trend.suffix(3))
            let percent = first == 0 ? 0 : Int(((last - first) / first * 100).rounded())
            let source = metric.source
            func make(_ title: String, _ speech: String, _ tone: HealthRevealFinding.Tone) -> HealthRevealFinding {
                HealthRevealFinding(id: "\(source)", symbol: source.symbol, title: title, speech: speech, value: metric.value,
                                    context: metric.context, change: percent, trend: metric.trend, tone: tone,
                                    tint: source.resultTint)
            }
            switch source {
            case .activity:
                if percent >= 5 {
                    found.append(make("Du rör dig mer", "Du rör dig mer! Du tar \(percent) procent fler steg per dag än för ett år sedan.", .good))
                } else if percent <= -5 {
                    found.append(make("Mindre rörelse", "Du tar \(abs(percent)) procent färre steg per dag än för ett år sedan.", .watch))
                } else {
                    found.append(make("Jämn aktivitet", "Din aktivitet har varit jämn över året.", .steady))
                }
            case .pulse:
                let beats = Int((last - first).rounded())
                if beats <= -2 {
                    found.append(make("Lugnare hjärta", "Din vilopuls har sjunkit med \(abs(beats)) slag per minut över året. Det brukar hänga ihop med bättre kondition.", .good))
                } else if beats >= 2 {
                    found.append(make("Vilopulsen har stigit", "Din vilopuls ligger \(beats) slag per minut högre än för ett år sedan.", .watch))
                } else {
                    found.append(make("Stabil vilopuls", "Din vilopuls är stabil.", .steady))
                }
            case .recovery:
                if percent >= 5 {
                    found.append(make("Bättre återhämtning", "Din pulsvariation har ökat med \(percent) procent. Det tyder på bra återhämtning.", .good))
                } else if percent <= -5 {
                    found.append(make("Sämre återhämtning", "Din pulsvariation har minskat med \(abs(percent)) procent.", .watch))
                } else {
                    found.append(make("Jämn återhämtning", "Din pulsvariation är jämn över året.", .steady))
                }
            case .sleep:
                let minutes = Int(((last - first) * 60).rounded())
                if minutes <= -15 {
                    found.append(make("Sömnen har blivit kortare", "Du sover i snitt \(abs(minutes)) minuter mindre per natt än för ett år sedan. Det är värt att hålla koll på.", .watch))
                } else if minutes >= 15 {
                    found.append(make("Du sover längre", "Du sover i snitt \(minutes) minuter längre per natt än för ett år sedan.", .good))
                } else {
                    found.append(make("Jämn sömn", "Din sömn är jämn över året.", .steady))
                }
            case .breathing:
                if abs(percent) < 5 {
                    found.append(make("Stabil andning", "Din andningsfrekvens är stabil, runt \(metric.value).", .steady))
                } else {
                    found.append(make("Andningen har ändrats", "Din andningsfrekvens har ändrats med \(percent) procent över året.", .watch))
                }
            default:
                break
            }
        }
        let records = metrics.filter { $0.trend.isEmpty }
        if let lastRecord = records.last {
            let list = records.map { $0.value }
            let text = records.count > 1 ? list.dropLast().joined(separator: ", ") + " och " + lastRecord.value : lastRecord.value
            found.append(HealthRevealFinding(id: "records", symbol: "doc.text.magnifyingglass", title: "Din journal är med",
                                             speech: "Jag har också vägt in din journal: \(text).", value: "\(records.count) källor",
                                             context: "Blodprover, röntgen och vaccinationer", change: nil, trend: [], tone: .steady,
                                             tint: Color(red: 0.72, green: 0.83, blue: 1.0)))
        }
        let order: [HealthRevealFinding.Tone] = [.good, .watch, .steady]
        return found.sorted { (order.firstIndex(of: $0.tone) ?? 0) < (order.firstIndex(of: $1.tone) ?? 0) }
    }
}
