import Charts
import SwiftUI

// MARK: - Grades, periods and sources

private enum HealthGrade: String, CaseIterable {
    case a = "A", b = "B", c = "C", d = "D", e = "E"

    struct Example: Identifiable {
        let title: String
        let detail: String
        var id: String { title }
    }

    var title: String {
        switch self {
        case .a: "Toppnivå"
        case .b: "Stabil grund"
        case .c: "Flera förändringar att följa"
        case .d: "Tydliga förändringar över tid"
        case .e: "Stora förändringar över tid"
        }
    }

    var examples: [Example] {
        switch self {
        case .a:
            [
                .init(title: "Blodproverna ligger inom referens",
                      detail: "Blodvärdena är inom referensintervallen. Utan blodprover med bra resultat går det inte att få A."),
                .init(title: "Toppnivå månad efter månad",
                      detail: "Låg och stabil vilopuls, hög pulsvariation, jämn sömn och regelbunden rörelse över hela perioden.")
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
        case .e:
            [
                .init(title: "Flera områden har försämrats",
                      detail: "Sömn, vilopuls och aktivitet ligger tydligt under dina tidigare nivåer under en längre period."),
                .init(title: "Värden att ta upp med vården",
                      detail: "Flera blodvärden ligger utanför referensintervallen. Vårdteamet kan hjälpa dig vidare.")
            ]
        }
    }

    var position: Double {
        switch self {
        case .a: 1
        case .b: 0.8
        case .c: 0.6
        case .d: 0.4
        case .e: 0.2
        }
    }

    /// A is the top tier: the best tenth, and never without blood tests with good results.
    var isTop: Bool { self == .a }
}

private enum HealthGradePeriod: String, CaseIterable, Identifiable {
    case week, month, year

    var id: Self { self }

    var title: String {
        switch self {
        case .week: "1 vecka"
        case .month: "1 månad"
        case .year: "1 år"
        }
    }

    /// "Jag har gått igenom ett år av din hälsa."
    var span: String {
        switch self {
        case .week: "en vecka"
        case .month: "en månad"
        case .year: "ett år"
        }
    }

    var recent: String {
        switch self {
        case .week: "den senaste veckan"
        case .month: "den senaste månaden"
        case .year: "det senaste året"
        }
    }

    var label: String {
        switch self {
        case .week: "Senaste veckan"
        case .month: "Senaste månaden"
        case .year: "Senaste året"
        }
    }

    /// The start of the period in a comparison: "fler steg än för ett år sedan".
    var start: String {
        switch self {
        case .week: "i början av veckan"
        case .month: "i början av månaden"
        case .year: "för ett år sedan"
        }
    }

    var over: String {
        switch self {
        case .week: "under veckan"
        case .month: "under månaden"
        case .year: "över året"
        }
    }

    var trendStart: String {
        switch self {
        case .week: "7 dagar sedan"
        case .month: "30 dagar sedan"
        case .year: "För ett år sedan"
        }
    }

    var days: Int {
        switch self {
        case .week: 7
        case .month: 30
        case .year: 365
        }
    }
}

private enum HealthGradeSource: CaseIterable {
    case sleep, pulse, breathing, activity, bloodTests, imaging, recovery, vaccinations

    /// The order of the scan: the watch first, then the journal, and the blood tests last since they decide whether A is possible.
    static let scanOrder: [HealthGradeSource] = [.sleep, .pulse, .recovery, .breathing, .activity, .imaging, .vaccinations, .bloodTests]

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

    var hudTitle: String {
        switch self {
        case .sleep: "Sömn"
        case .pulse: "Vilopuls"
        case .breathing: "Andning"
        case .activity: "Aktivitet"
        case .bloodTests: "Blodprover"
        case .imaging: "Röntgen"
        case .recovery: "HRV"
        case .vaccinations: "Vaccin"
        }
    }

    /// What the scanner reads, shown while it reads it.
    var measures: String {
        switch self {
        case .sleep: "Hur länge du sover, när du somnar och hur jämn rytmen är."
        case .pulse: "Vilopulsen dag för dag, jämfört med din egen normalnivå."
        case .recovery: "Pulsvariationen, ett mått på hur väl kroppen återhämtar sig."
        case .breathing: "Antal andetag per minut medan du sover."
        case .activity: "Steg, aktiva minuter och hur regelbundet du rör dig."
        case .imaging: "Svaren från dina röntgenundersökningar i journalen."
        case .vaccinations: "Ditt vaccinationsskydd jämfört med rekommendationerna."
        case .bloodTests: "Dina blodvärden mot referensintervallen. Krävs för betyg A."
        }
    }

    var unit: String {
        switch self {
        case .sleep, .breathing: "nätter"
        case .pulse: "pulsmätningar"
        case .recovery: "HRV-mätningar"
        case .activity: "dagar"
        case .imaging: "undersökningar"
        case .vaccinations: "doser"
        case .bloodTests: "analyser"
        }
    }

    func dataPoints(_ period: HealthGradePeriod) -> Int {
        switch self {
        case .sleep, .breathing, .activity: period.days
        case .pulse: period.days * 168
        case .recovery: period.days * 6
        case .imaging: 3
        case .vaccinations: 6
        case .bloodTests: 38
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

    /// Where the scanner marks the source on the figure: sideways from the centre line and down from the top,
    /// both as a share of the stage height, since the figure is scaled to the height of the stage.
    var anchor: (x: CGFloat, y: CGFloat) {
        switch self {
        case .sleep: (0.02, 0.055)
        case .breathing: (-0.035, 0.25)
        case .pulse: (0.03, 0.28)
        case .vaccinations: (-0.125, 0.31)
        case .bloodTests: (0.125, 0.37)
        case .recovery: (-0.13, 0.49)
        case .imaging: (0.035, 0.72)
        case .activity: (-0.04, 0.84)
        }
    }

    var labelOnLeft: Bool {
        switch self {
        case .breathing, .vaccinations, .recovery, .activity: true
        default: false
        }
    }

    var labelY: CGFloat {
        switch self {
        case .sleep: 0.06
        case .breathing: 0.19
        case .pulse: 0.25
        case .vaccinations: 0.34
        case .bloodTests: 0.42
        case .recovery: 0.50
        case .imaging: 0.67
        case .activity: 0.80
        }
    }
}

private struct HealthGradeReport {
    struct Metric: Identifiable {
        let source: HealthGradeSource
        let value: String
        /// The value on the scanner's label.
        let short: String
        let context: String
        var trend: [Double] = []
        var id: HealthGradeSource { source }
    }

    struct Requirement: Identifiable {
        let title: String
        let met: Bool
        var id: String { title }
    }

    let period: HealthGradePeriod
    let grade: HealthGrade
    let summary: String
    let metrics: [Metric]
    /// What it takes to reach A. Example criteria until the real ones are set.
    let requirements: [Requirement]

    var title: String { grade.title }
    var dataPoints: Int { HealthGradeSource.scanOrder.reduce(0) { $0 + $1.dataPoints(period) } }

    func short(_ source: HealthGradeSource) -> String {
        metrics.first { $0.source == source }?.short ?? ""
    }

    static func example(_ period: HealthGradePeriod) -> HealthGradeReport {
        let sleep: [Double], pulse: [Double], breathing: [Double], activity: [Double], recovery: [Double]
        let values: (sleep: String, pulse: String, breathing: String, steps: String, hrv: String)
        let summary: String
        switch period {
        case .week:
            sleep = [7.1, 6.6, 7.2, 6.8, 6.5, 7.4, 6.9]
            pulse = [59, 60, 59, 60, 59, 59, 60]
            breathing = [15.2, 15.0, 15.3, 15.1, 15.2, 15.1, 15.2]
            activity = [8100, 9400, 7800, 10200, 9100, 11800, 9600]
            recovery = [56, 58, 55, 59, 60, 58, 62]
            values = ("6,9", "59", "15,2", "9 430", "58")
            summary = "I exemplet har du rört dig mer under veckan. Sömn och vilopuls har legat jämnt."
        case .month:
            sleep = [7.2, 7.0, 7.1, 6.9, 6.8, 7.0, 6.9, 6.7, 6.9, 6.8]
            pulse = [62, 61, 61, 60, 61, 60, 59, 60, 59, 59]
            breathing = [15.1, 15.3, 15.0, 15.2, 15.1, 15.0, 15.2, 15.3, 15.1, 15.2]
            activity = [8600, 8900, 8200, 9100, 8800, 9300, 9000, 9400, 9200, 9500]
            recovery = [55, 56, 54, 57, 58, 57, 59, 60, 59, 61]
            values = ("6,9", "60", "15,2", "9 000", "58")
            summary = "I exemplet har rörelsen och återhämtningen ökat under månaden. Sömnen har blivit något kortare."
        case .year:
            sleep = [7.3, 7.2, 7.1, 7.4, 7.0, 6.8, 6.9, 6.7, 7.0, 7.1, 6.8, 6.7]
            pulse = [65, 64, 63, 63, 62, 61, 60, 58, 60, 59, 58, 59]
            breathing = [15.3, 15.6, 15.4, 15.1, 15.2, 14.9, 15.1, 15.2, 15.2, 14.8, 15.0, 15.3]
            activity = [6800, 7300, 7400, 7510, 8210, 8310, 8020, 8960, 8810, 9080, 9200, 9280]
            recovery = [45, 46, 49, 46, 52, 53, 49, 54, 55, 56, 58, 61]
            values = ("7,0", "61", "15,2", "8 240", "52")
            summary = "I exemplet har aktiviteten ökat över året. Sömnen varierar mer mellan månaderna."
        }
        return HealthGradeReport(
            period: period,
            grade: .b,
            summary: summary,
            metrics: [
                .init(source: .sleep, value: "\(values.sleep) tim", short: "\(values.sleep) tim",
                      context: "Per natt i snitt", trend: sleep),
                .init(source: .pulse, value: "\(values.pulse) slag/min", short: "\(values.pulse) slag/min",
                      context: "Vilopuls i snitt", trend: pulse),
                .init(source: .breathing, value: "\(values.breathing) andetag/min", short: "\(values.breathing)/min",
                      context: "Andningsfrekvens i snitt", trend: breathing),
                .init(source: .activity, value: "\(values.steps) steg", short: "\(values.steps) steg",
                      context: "Per dag i snitt", trend: activity),
                .init(source: .recovery, value: "\(values.hrv) ms", short: "\(values.hrv) ms",
                      context: "Pulsvariation i snitt", trend: recovery),
                .init(source: .bloodTests, value: "4 provtagningar", short: "Inom ref.", context: "I provhistoriken"),
                .init(source: .imaging, value: "3 undersökningar", short: "3 svar", context: "I röntgenhistoriken"),
                .init(source: .vaccinations, value: "6 doser", short: "6 doser", context: "I vaccinationshistoriken")
            ],
            requirements: [
                .init(title: "Blodprover inom referensintervallen", met: true),
                .init(title: "Stabil eller sjunkande vilopuls", met: true),
                .init(title: "Regelbunden rörelse", met: true),
                .init(title: "Jämn sömnrytm", met: false)
            ]
        )
    }
}

private func grouped(_ number: Int) -> String {
    number.formatted(.number.locale(Locale(identifier: "sv_SE")))
}

// MARK: - The view

/**
 Hälsobetyg: choose a period and start the scan; the tab bar steps aside and a scanner passes over the figure,
 marking each source on the body as it reads it. When the blood tests are read, A unlocks. The assistant then presents
 the grade full screen, and the results stay on the page afterwards.
 */
struct HealthGradePreview<Avatar: View, Measurements: View>: View {
    var firstName: String? = nil
    /// True while the scan and the assistant fill the screen; the tab bar hides meanwhile.
    var immersive: Binding<Bool> = .constant(false)
    @ViewBuilder var avatar: () -> Avatar
    @ViewBuilder var measurements: () -> Measurements

    private enum Phase { case intro, scanning, reveal, results }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @AccessibilityFocusState private var resultFocused: Bool
    @Namespace private var periodSelection
    @State private var phase = Phase.intro
    @State private var period = HealthGradePeriod.year
    @State private var run = 0
    /// -1 while the scanner prepares, then the index of the source being read.
    @State private var stepIndex = -1
    @State private var stepStartedAt: Date?
    @State private var scanComplete = false
    @State private var topUnlocked = false
    @State private var pending: HealthGradeReport?
    @State private var report: HealthGradeReport?
    @State private var exploredGrade: HealthGrade?
    @State private var revealCards = false

    private let steps = HealthGradeSource.scanOrder
    private let preparation = 2.6
    private let stepDuration = 2.8
    private let ink = GradePalette.ink
    private let plum = GradePalette.plum
    private let rose = GradePalette.rose
    private let softPink = GradePalette.softPink
    private let lavender = GradePalette.lavender
    private let gold = GradePalette.gold

    var body: some View {
        ZStack {
            switch phase {
            case .intro, .scanning:
                scanner
                    .transition(.opacity)
            case .reveal:
                if let report {
                    reveal(report)
                        .transition(.opacity.combined(with: .scale(scale: 1.04)))
                }
            case .results:
                if let report {
                    resultsPage(report)
                        .transition(.opacity)
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .statusBarHidden(phase == .reveal)
        .sensoryFeedback(.selection, trigger: stepIndex) { previous, current in current > previous && current >= 0 }
        .sensoryFeedback(.success, trigger: topUnlocked) { _, unlocked in unlocked }
        .task(id: run) { await playScan() }
        .onChange(of: phase) { _, current in
            let full = current == .scanning || current == .reveal
            guard immersive.wrappedValue != full else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88)) {
                immersive.wrappedValue = full
            }
        }
        .onDisappear { immersive.wrappedValue = false }
    }

    // MARK: Start and scan

    private var currentTint: Color {
        stepIndex >= 0 && stepIndex < steps.count && !scanComplete ? steps[stepIndex].tint : rose
    }

    private var scanner: some View {
        let scanning = phase == .scanning
        return VStack(spacing: 14) {
            if scanning {
                scanTopBar
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                introHeader
                    .transition(.opacity)
            }

            stage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if scanning {
                scanPanel
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                introControls
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, scanning ? 4 : 14)
        .padding(.bottom, scanning ? 8 : 14)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background { scannerBackdrop }
    }

    private var scannerBackdrop: some View {
        ZStack {
            Color(red: 0.975, green: 0.963, blue: 0.977)
            RadialGradient(colors: [rose.opacity(0.10), .clear], center: .top, startRadius: 0, endRadius: 440)
            RadialGradient(colors: [Color(red: 0.56, green: 0.34, blue: 0.82).opacity(0.08), .clear],
                           center: .bottomTrailing, startRadius: 0, endRadius: 400)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private var introHeader: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Hälsobetyg")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Skanna din hälsa och få ett betyg från A till E.")
                    .font(.subheadline)
                    .foregroundStyle(plum.opacity(0.8))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            testBadge
                .padding(.top, 6)
        }
        .foregroundStyle(ink)
    }

    private var introControls: some View {
        VStack(spacing: 12) {
            periodPicker
            gradeScaleCard
            Button(action: startScan) {
                HealthPrimaryButtonLabel(title: "Starta scanning", symbol: "viewfinder", onDark: false)
            }
            .buttonStyle(HealthPressStyle())
            .accessibilityHint("Går igenom \(period.recent)")
        }
    }

    private var periodPicker: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Period att analysera")
                .font(.caption.weight(.bold))
                .foregroundStyle(plum.opacity(0.7))
            HStack(spacing: 4) {
                ForEach(HealthGradePeriod.allCases) { option in
                    periodButton(option)
                }
            }
            .padding(4)
            .background(.white, in: Capsule())
            .overlay { Capsule().strokeBorder(plum.opacity(0.08)) }
            .shadow(color: plum.opacity(0.06), radius: 10, y: 4)
        }
    }

    private func periodButton(_ option: HealthGradePeriod) -> some View {
        let selected = option == period
        return Button {
            withAnimation(reduceMotion ? nil : .spring(response: 0.35, dampingFraction: 0.8)) { period = option }
        } label: {
            Text(option.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? Color.white : plum)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background {
                    if selected {
                        Capsule()
                            .fill(LinearGradient(colors: [rose, plum], startPoint: .topLeading, endPoint: .bottomTrailing))
                            .matchedGeometryEffect(id: "period", in: periodSelection)
                            .shadow(color: rose.opacity(0.35), radius: 8, y: 3)
                    }
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var gradeScaleCard: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 6) {
                ForEach(HealthGrade.allCases, id: \.self) { grade in
                    scaleChip(grade)
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "crown.fill")
                    .font(.caption)
                    .foregroundStyle(GradePalette.goldDeep)
                    .padding(.top, 1)
                Text(verbatim: "A ges till topp 10 % och kräver blodprover med bra resultat.")
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).strokeBorder(plum.opacity(0.08)) }
        .shadow(color: plum.opacity(0.06), radius: 14, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Betygsskala från A till E. A ges till topp 10 procent och kräver blodprover med bra resultat.")
    }

    private func scaleChip(_ grade: HealthGrade) -> some View {
        let shape = RoundedRectangle(cornerRadius: 13)
        return Text(grade.rawValue)
            .font(.system(size: 20, weight: .bold, design: .rounded))
            .foregroundStyle(grade.isTop ? ink : plum.opacity(0.4 + 0.6 * grade.position))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background {
                if grade.isTop {
                    shape.fill(GradePalette.goldGradient)
                } else {
                    shape.fill(plum.opacity(0.05))
                }
            }
            .overlay(alignment: .topTrailing) {
                if grade.isTop {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(ink.opacity(0.6))
                        .padding(5)
                }
            }
            .shadow(color: grade.isTop ? gold.opacity(0.55) : .clear, radius: 8, y: 3)
    }

    private var scanTopBar: some View {
        HStack {
            Button(action: cancelScan) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(plum)
                    .frame(width: 40, height: 40)
                    .background(.white, in: Circle())
                    .overlay { Circle().strokeBorder(plum.opacity(0.08)) }
            }
            .buttonStyle(HealthPressStyle())
            .accessibilityLabel("Avbryt scanningen")
            .frame(width: 96, alignment: .leading)

            Spacer(minLength: 4)
            VStack(spacing: 1) {
                Text(scanComplete ? "Scanning klar" : "Skannar")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(ink)
                    .contentTransition(.opacity)
                Text("\(period.label) · Testdata")
                    .font(.caption)
                    .foregroundStyle(plum.opacity(0.7))
            }
            Spacer(minLength: 4)

            Button("Hoppa över", action: finishScan)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(plum)
                .frame(width: 96, alignment: .trailing)
                .frame(minHeight: 44)
                .buttonStyle(.plain)
        }
    }

    private var stage: some View {
        let shape = RoundedRectangle(cornerRadius: 32)
        return GeometryReader { proxy in
            let size = proxy.size
            avatar()
                .frame(width: size.width, height: size.height)
                .background(.white)
                .overlay { scanGuides(currentTint) }
                .overlay {
                    if !reduceMotion && !scanComplete {
                        TimelineView(.animation) { context in
                            beam(size: size, now: context.date)
                        }
                        .transaction { $0.animation = nil }
                    }
                }
                .overlay {
                    if scanComplete {
                        RadialGradient(colors: [rose.opacity(0.14), .clear],
                                       center: .center, startRadius: 0, endRadius: size.height * 0.58)
                            .transition(.opacity)
                    }
                }
                .overlay {
                    if phase == .scanning {
                        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
                            hud(size: size, now: context.date)
                        }
                        .transition(.opacity)
                    }
                }
        }
        .clipShape(shape)
        .overlay { shape.strokeBorder(currentTint.opacity(0.22)) }
        .shadow(color: plum.opacity(0.08), radius: 24, y: 10)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func smooth(_ value: Double) -> Double { value * value * (3 - 2 * value) }

    /// 0...1 through the current step (or the preparation).
    private func stepProgress(_ now: Date) -> Double {
        if scanComplete || reduceMotion { return 1 }
        let duration = stepIndex < 0 ? preparation : stepDuration
        return min(1, max(0, now.timeIntervalSince(stepStartedAt ?? now) / duration))
    }

    private func beam(size: CGSize, now: Date) -> some View {
        let position: Double
        let upward: Bool
        if phase == .intro {
            // Idle: a slow pass up and down.
            let cycle = now.timeIntervalSinceReferenceDate / 3.8
            let fraction = cycle - floor(cycle)
            upward = Int(floor(cycle)).isMultiple(of: 2) == false
            position = upward ? 1 - smooth(fraction) : smooth(fraction)
        } else {
            let duration = stepIndex < 0 ? preparation : stepDuration
            let elapsed = now.timeIntervalSince(stepStartedAt ?? now)
            let progress = min(1, max(0, elapsed / (duration - 0.18)))
            upward = !(stepIndex + 1).isMultiple(of: 2)
            position = upward ? 1 - smooth(progress) : smooth(progress)
        }
        return scanBeam(tint: currentTint, upward: upward)
            .frame(width: size.width, height: 122)
            .position(x: size.width / 2, y: 16 + (size.height - 32) * position)
            .opacity(phase == .intro ? 0.7 : 1)
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

    // MARK: Markers on the body

    private let labelWidth: CGFloat = 94
    private let labelInset: CGFloat = 10

    private func anchorPoint(_ source: HealthGradeSource, in size: CGSize) -> CGPoint {
        CGPoint(x: size.width / 2 + source.anchor.x * size.height, y: source.anchor.y * size.height)
    }

    private func labelCenter(_ source: HealthGradeSource, in size: CGSize) -> CGPoint {
        let x = source.labelOnLeft ? labelInset + labelWidth / 2 : size.width - labelInset - labelWidth / 2
        return CGPoint(x: x, y: source.labelY * size.height)
    }

    /// 0 hidden, 1 fully shown: a marker appears as its source is read and stays.
    private func visibility(_ index: Int, progress: Double) -> Double {
        if scanComplete || index < stepIndex { return 1 }
        if index == stepIndex { return reduceMotion ? 1 : min(1, progress / 0.12) }
        return 0
    }

    private func hud(size: CGSize, now: Date) -> some View {
        let progress = stepProgress(now)
        let active = scanComplete ? -1 : stepIndex
        let ping = now.timeIntervalSinceReferenceDate * 0.9
        let pingPhase = ping - floor(ping)
        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for (index, source) in steps.enumerated() {
                    let shown = visibility(index, progress: progress)
                    guard shown > 0 else { continue }
                    let anchor = anchorPoint(source, in: size)
                    let center = labelCenter(source, in: size)
                    let edge = CGPoint(x: center.x + (source.labelOnLeft ? labelWidth / 2 : -labelWidth / 2), y: center.y)
                    var layer = context
                    layer.opacity = shown
                    var line = Path()
                    line.move(to: edge)
                    line.addLine(to: CGPoint(x: edge.x + (source.labelOnLeft ? 10 : -10), y: edge.y))
                    line.addLine(to: anchor)
                    layer.stroke(line, with: .color(source.tint.opacity(0.6)),
                                 style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3]))
                    layer.fill(Path(ellipseIn: CGRect(x: anchor.x - 3.5, y: anchor.y - 3.5, width: 7, height: 7)),
                               with: .color(source.tint))
                    layer.stroke(Path(ellipseIn: CGRect(x: anchor.x - 7, y: anchor.y - 7, width: 14, height: 14)),
                                 with: .color(source.tint.opacity(0.35)), lineWidth: 1)
                    if index == active && !reduceMotion {
                        let radius = 7 + 18 * pingPhase
                        var pingLayer = context
                        pingLayer.opacity = 1 - pingPhase
                        pingLayer.stroke(Path(ellipseIn: CGRect(x: anchor.x - radius, y: anchor.y - radius,
                                                                width: radius * 2, height: radius * 2)),
                                         with: .color(source.tint), lineWidth: 1.5)
                    }
                }
            }
            ForEach(Array(steps.enumerated()), id: \.element) { index, source in
                let shown = visibility(index, progress: progress)
                if shown > 0 {
                    hudLabel(source, reading: index == active && progress < 0.72)
                        .scaleEffect(0.85 + 0.15 * shown, anchor: source.labelOnLeft ? .leading : .trailing)
                        .opacity(shown)
                        .position(labelCenter(source, in: size))
                }
            }
        }
        .frame(width: size.width, height: size.height)
    }

    private func hudLabel(_ source: HealthGradeSource, reading: Bool) -> some View {
        let alignment: HorizontalAlignment = source.labelOnLeft ? .leading : .trailing
        let shape = RoundedRectangle(cornerRadius: 11)
        return VStack(alignment: alignment, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: reading ? source.symbol : "checkmark.circle.fill")
                    .font(.system(size: 9, weight: .bold))
                Text(source.hudTitle.uppercased())
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.4)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(source.tint)
            Text(reading ? "Analyserar…" : pending?.short(source) ?? "")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: labelWidth, alignment: source.labelOnLeft ? .leading : .trailing)
        .background(.white.opacity(0.93), in: shape)
        .overlay { shape.strokeBorder(source == .bloodTests && topUnlocked ? gold : source.tint.opacity(0.3),
                                      lineWidth: source == .bloodTests && topUnlocked ? 1.5 : 1) }
        .shadow(color: source.tint.opacity(0.18), radius: 8, y: 3)
    }

    // MARK: The scan panel

    private var scanPanel: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let progress = stepProgress(context.date)
            VStack(alignment: .leading, spacing: 14) {
                possibleGrades
                Rectangle()
                    .fill(plum.opacity(0.07))
                    .frame(height: 1)
                currentStep(progress: progress)
                segments(progress: progress)
            }
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).strokeBorder(plum.opacity(0.08)) }
        .shadow(color: plum.opacity(0.08), radius: 20, y: 8)
        .accessibilityElement(children: .combine)
    }

    private var possibleGrades: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Möjliga betyg")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(plum.opacity(0.65))
                Text(topUnlocked ? "A är möjligt" : "A kräver blodprover")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(topUnlocked ? GradePalette.goldDeep : ink.opacity(0.7))
                    .contentTransition(.opacity)
            }
            Spacer(minLength: 6)
            HStack(spacing: 5) {
                ForEach(HealthGrade.allCases, id: \.self) { grade in
                    miniChip(grade)
                }
            }
        }
    }

    private func miniChip(_ grade: HealthGrade) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9)
        let golden = grade.isTop && topUnlocked
        return Text(grade.rawValue)
            .font(.system(size: 15, weight: .bold, design: .rounded))
            .foregroundStyle(golden ? ink : plum.opacity(grade.isTop ? 0.35 : 0.4 + 0.6 * grade.position))
            .frame(width: 30, height: 32)
            .background {
                if golden {
                    shape.fill(GradePalette.goldGradient)
                } else {
                    shape.fill(plum.opacity(0.06))
                }
            }
            .overlay(alignment: .topTrailing) {
                if grade.isTop {
                    Image(systemName: topUnlocked ? "crown.fill" : "lock.fill")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(topUnlocked ? ink.opacity(0.7) : plum.opacity(0.55))
                        .contentTransition(.symbolEffect(.replace))
                        .padding(3)
                }
            }
            .scaleEffect(golden ? 1.08 : 1)
            .shadow(color: golden ? gold.opacity(0.7) : .clear, radius: 8, y: 2)
    }

    private func currentStep(progress: Double) -> some View {
        let preparing = stepIndex < 0
        let source = preparing || scanComplete ? nil : steps[stepIndex]
        let title = scanComplete ? "Räknar fram ditt betyg" : source?.title ?? "Förbereder scanningen"
        let detail = scanComplete
            ? "Väger samman \(steps.count) källor till ett betyg från A till E."
            : source?.measures ?? "Hämtar \(period.recent) från Apple Hälsa och din journal."
        let count: String
        if scanComplete {
            count = "\(grouped(pending?.dataPoints ?? 0)) datapunkter analyserade"
        } else if let source {
            let total = source.dataPoints(period)
            // Large counts tick up while they are read; a handful of journal entries is shown as it is.
            let shown = total < 50 ? total : Int((Double(total) * min(1, progress / 0.8)).rounded())
            count = "\(grouped(shown)) \(source.unit)"
        } else {
            count = "Ansluter källor…"
        }
        let symbol = scanComplete ? "checkmark" : source?.symbol ?? "sparkles"

        return HStack(spacing: 14) {
            ZStack {
                Circle().fill(currentTint.opacity(0.10))
                Circle().stroke(currentTint.opacity(0.15), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(AngularGradient(colors: [currentTint, rose, currentTint], center: .center),
                            style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(currentTint)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 54, height: 54)

            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(ink)
                    Spacer(minLength: 6)
                    if !preparing {
                        Text("\(scanComplete ? steps.count : stepIndex + 1)/\(steps.count)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(plum.opacity(0.6))
                            .monospacedDigit()
                    }
                }
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(ink.opacity(0.68))
                    .lineLimit(2, reservesSpace: true)
                Text(count)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(currentTint)
                    .monospacedDigit()
            }
        }
    }

    private func segments(progress: Double) -> some View {
        HStack(spacing: 4) {
            ForEach(steps.indices, id: \.self) { index in
                let fill = scanComplete || index < stepIndex ? 1 : index == stepIndex ? progress : 0
                Capsule()
                    .fill(plum.opacity(0.08))
                    .overlay(alignment: .leading) {
                        GeometryReader { proxy in
                            Capsule()
                                .fill(LinearGradient(colors: [steps[index].tint, rose], startPoint: .leading, endPoint: .trailing))
                                .frame(width: proxy.size.width * fill)
                        }
                    }
                    .frame(height: 5)
                    .clipShape(Capsule())
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: The assistant

    private func reveal(_ report: HealthGradeReport) -> some View {
        HealthGradeReveal(firstName: firstName, grade: report.grade.rawValue, gradeTitle: report.title,
                          gradePosition: report.grade.position, positiveGrade: report.grade == .a || report.grade == .b,
                          findings: report.revealFindings, isExample: true,
                          periodTitle: report.period.title, periodSpan: report.period.span,
                          trendStart: report.period.trendStart,
                          sources: steps.map(\.symbol), dataPoints: report.dataPoints) {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.45)) { phase = .results }
        }
    }

    // MARK: Results

    private func resultsPage(_ report: HealthGradeReport) -> some View {
        ScrollView {
            results(report)
                .frame(maxWidth: 560)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 22)
                .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.top)
        .background { resultsBackdrop }
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
            if !report.grade.isTop {
                topTierCard(report)
            }
            gradeGuide(assigned: report.grade)

            VStack(alignment: .leading, spacing: 4) {
                Text("Resultat")
                    .font(.title2.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Exempeltrender från \(report.period.recent)")
                    .font(.footnote)
                    .foregroundStyle(lavender)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(Array(report.metrics.enumerated()), id: \.element.id) { index, metric in
                    metricCard(metric, period: report.period)
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
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) { phase = .reveal }
            } label: {
                Label("Låt assistenten berätta igen", systemImage: "sparkles")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button(action: newScan) {
                Label("Gör en ny mätning", systemImage: "viewfinder")
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
        .ignoresSafeArea()
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
        let ring: [Color] = grade.isTop ? [GradePalette.goldLight, gold, GradePalette.goldDeep, GradePalette.goldLight]
                                        : [.white, lavender, softPink, .white]
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [softPink.opacity(0.25), softPink.opacity(0.05)],
                                     center: .topLeading, startRadius: 0, endRadius: 145))
                .padding(9)
            Circle().strokeBorder(.white.opacity(0.18), lineWidth: 5)
            Circle()
                .trim(from: 0, to: revealCards || reduceMotion ? grade.position : 0)
                .stroke(AngularGradient(colors: ring, center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(2.5)
                .shadow(color: (grade.isTop ? gold : softPink).opacity(0.48), radius: 8)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.75), value: revealCards)
            Text(grade.rawValue)
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .foregroundStyle(grade.isTop ? AnyShapeStyle(GradePalette.goldGradient) : AnyShapeStyle(.white))
        }
        .frame(width: 104, height: 104)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Exempelbetyg \(grade.rawValue) på skalan A till E")
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

    private func topTierCard(_ report: HealthGradeReport) -> some View {
        let shape = RoundedRectangle(cornerRadius: 24)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Text("A")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
                    .frame(width: 44, height: 44)
                    .background(GradePalette.goldGradient, in: RoundedRectangle(cornerRadius: 13))
                    .shadow(color: gold.opacity(0.5), radius: 10, y: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Vägen till A")
                        .font(.headline)
                        .accessibilityAddTraits(.isHeader)
                    Text(verbatim: "Topp 10 % av GoHealths användare")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(gold)
                }
            }
            ForEach(report.requirements) { item in
                HStack(spacing: 10) {
                    Image(systemName: item.met ? "checkmark.circle.fill" : "circle.dashed")
                        .foregroundStyle(item.met ? Color(red: 0.5, green: 0.96, blue: 0.8) : lavender.opacity(0.7))
                    Text(item.title)
                        .font(.subheadline)
                    Spacer(minLength: 4)
                    Text(item.met ? "Klart" : "Kvar")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.met ? lavender : gold)
                }
                .accessibilityElement(children: .combine)
            }
            Text("Exempel på kriterier. A kräver alltid blodprover med bra resultat.")
                .font(.caption)
                .foregroundStyle(lavender.opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            shape.fill(LinearGradient(colors: [gold.opacity(0.16), .white.opacity(0.04)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { shape.strokeBorder(gold.opacity(0.35)) }
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

            HStack(spacing: 7) {
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
                    .foregroundStyle(selection.isTop ? gold : softPink)
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
        let border: Color = grade.isTop ? gold.opacity(selected ? 1 : 0.6)
            : selected && !assigned ? lavender : .white.opacity(0.19)

        return Button {
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                exploredGrade = grade
            }
        } label: {
            HStack(spacing: 3) {
                Text(grade.rawValue)
                    .font(.headline)
                if assigned {
                    Image(systemName: "checkmark")
                        .font(.caption2.bold())
                        .accessibilityHidden(true)
                } else if grade.isTop {
                    Image(systemName: "crown.fill")
                        .font(.system(size: 9, weight: .bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundStyle(assigned ? ink : grade.isTop ? gold : .white)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(assigned ? softPink : .white.opacity(selected ? 0.13 : 0.06), in: shape)
            .overlay { shape.strokeBorder(border, lineWidth: selected && !assigned ? 1.5 : 1) }
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

    private func metricCard(_ metric: HealthGradeReport.Metric, period: HealthGradePeriod) -> some View {
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
                Chart(Array(metric.trend.enumerated()), id: \.offset) { index, value in
                    LineMark(x: .value("Tid", index), y: .value("Värde", value))
                        .interpolationMethod(.monotone)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .foregroundStyle(accent)
                    AreaMark(x: .value("Tid", index), yStart: .value("Bas", low - margin),
                             yEnd: .value("Värde", value))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(LinearGradient(colors: [accent.opacity(0.25), .clear],
                                                        startPoint: .top, endPoint: .bottom))
                }
                .chartYScale(domain: (low - margin)...(high + margin))
                .chartXAxis(.hidden)
                .chartYAxis(.hidden)
                .frame(height: 29)
                .accessibilityLabel("Utveckling \(period.recent) med testdata")
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(resultSurface(cornerRadius: 19))
    }

    // MARK: Flow

    private func startScan() {
        pending = .example(period)
        report = nil
        stepIndex = -1
        stepStartedAt = .now
        scanComplete = false
        topUnlocked = false
        withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.88)) { phase = .scanning }
        run += 1
    }

    private func cancelScan() {
        run += 1
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.88)) {
            phase = .intro
            stepIndex = -1
            scanComplete = false
            topUnlocked = false
        }
    }

    private func newScan() {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.4)) {
            report = nil
            revealCards = false
            exploredGrade = nil
            stepIndex = -1
            scanComplete = false
            topUnlocked = false
            phase = .intro
        }
    }

    private func playScan() async {
        guard phase == .scanning, report == nil else { return }
        do {
            stepStartedAt = .now
            try await Task.sleep(for: .seconds(preparation))
            for index in steps.indices {
                try Task.checkCancellation()
                guard phase == .scanning else { return }
                stepStartedAt = .now
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { stepIndex = index }
                if steps[index] == .bloodTests {
                    try await Task.sleep(for: .seconds(stepDuration * 0.75))
                    try Task.checkCancellation()
                    withAnimation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.6)) { topUnlocked = true }
                    // Let the unlocked A sink in.
                    try await Task.sleep(for: .seconds(stepDuration * 0.25 + 1.0))
                } else {
                    try await Task.sleep(for: .seconds(stepDuration))
                }
            }
            try Task.checkCancellation()
            guard phase == .scanning else { return }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.3)) { scanComplete = true }
            try await Task.sleep(for: .seconds(1.8))
            try Task.checkCancellation()
            finishScan()
        } catch {
            // Cancelled: the scan was skipped, stopped or the tab was left.
        }
    }

    private func finishScan() {
        guard phase == .scanning else { return }
        report = pending ?? .example(period)
        topUnlocked = true
        run += 1
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.6)) { phase = .reveal }
    }
}

// MARK: - Findings for the assistant

private extension HealthGradeReport {
    /// What the assistant tells: each trend compared between the start and the end of the period, good news first.
    var revealFindings: [HealthRevealFinding] {
        func mean(_ values: ArraySlice<Double>) -> Double { values.reduce(0, +) / Double(max(values.count, 1)) }
        let start = period.start, over = period.over
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
                    found.append(make("Du rör dig mer", "Du rör dig mer! Du tar \(percent) procent fler steg per dag än \(start).", .good))
                } else if percent <= -5 {
                    found.append(make("Mindre rörelse", "Du tar \(abs(percent)) procent färre steg per dag än \(start).", .watch))
                } else {
                    found.append(make("Jämn aktivitet", "Din aktivitet har varit jämn \(over).", .steady))
                }
            case .pulse:
                let beats = Int((last - first).rounded())
                if beats <= -2 {
                    found.append(make("Lugnare hjärta", "Din vilopuls har sjunkit med \(abs(beats)) slag per minut \(over). Det brukar hänga ihop med bättre kondition.", .good))
                } else if beats >= 2 {
                    found.append(make("Vilopulsen har stigit", "Din vilopuls ligger \(beats) slag per minut högre än \(start).", .watch))
                } else {
                    found.append(make("Stabil vilopuls", "Din vilopuls är stabil \(over).", .steady))
                }
            case .recovery:
                if percent >= 5 {
                    found.append(make("Bättre återhämtning", "Din pulsvariation har ökat med \(percent) procent. Det tyder på bra återhämtning.", .good))
                } else if percent <= -5 {
                    found.append(make("Sämre återhämtning", "Din pulsvariation har minskat med \(abs(percent)) procent.", .watch))
                } else {
                    found.append(make("Jämn återhämtning", "Din pulsvariation är jämn \(over).", .steady))
                }
            case .sleep:
                let minutes = Int(((last - first) * 60).rounded())
                if minutes <= -15 {
                    found.append(make("Sömnen har blivit kortare", "Du sover i snitt \(abs(minutes)) minuter mindre per natt än \(start). Det är värt att hålla koll på.", .watch))
                } else if minutes >= 15 {
                    found.append(make("Du sover längre", "Du sover i snitt \(minutes) minuter längre per natt än \(start).", .good))
                } else {
                    found.append(make("Jämn sömn", "Din sömn är jämn \(over).", .steady))
                }
            case .breathing:
                if abs(percent) < 5 {
                    found.append(make("Stabil andning", "Din andningsfrekvens är stabil, runt \(metric.value).", .steady))
                } else {
                    found.append(make("Andningen har ändrats", "Din andningsfrekvens har ändrats med \(percent) procent \(over).", .watch))
                }
            default:
                break
            }
        }
        if let blood = metrics.first(where: { $0.source == .bloodTests }) {
            found.append(HealthRevealFinding(id: "bloodTests", symbol: HealthGradeSource.bloodTests.symbol,
                                             title: "Blodproverna är inom referens",
                                             speech: "Dina blodprover ligger inom referensintervallen. Det är ett krav för att kunna få betyg A.",
                                             value: blood.value, context: blood.context, change: nil, trend: [], tone: .good,
                                             tint: HealthGradeSource.bloodTests.resultTint))
        }
        let records = metrics.filter { $0.trend.isEmpty && $0.source != .bloodTests }
        if let lastRecord = records.last {
            let list = records.map { $0.value }
            let text = records.count > 1 ? list.dropLast().joined(separator: ", ") + " och " + lastRecord.value : lastRecord.value
            found.append(HealthRevealFinding(id: "records", symbol: "doc.text.magnifyingglass", title: "Din journal är med",
                                             speech: "Jag har också vägt in din journal: \(text).", value: "\(records.count) källor",
                                             context: "Röntgen och vaccinationer", change: nil, trend: [], tone: .steady,
                                             tint: Color(red: 0.72, green: 0.83, blue: 1.0)))
        }
        let order: [HealthRevealFinding.Tone] = [.good, .watch, .steady]
        return found.sorted { (order.firstIndex(of: $0.tone) ?? 0) < (order.firstIndex(of: $1.tone) ?? 0) }
    }
}
