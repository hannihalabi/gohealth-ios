import SwiftUI

// MARK: - The assistant character

enum AssistantMood: Equatable {
    case calm, happy, attentive

    var glow: Color {
        switch self {
        case .calm: Color(red: 1.0, green: 0.55, blue: 0.78)
        case .happy: Color(red: 0.50, green: 0.96, blue: 0.90)
        case .attentive: Color(red: 1.0, green: 0.77, blue: 0.42)
        }
    }
}

/// The body of the assistant, the same outline as in the clinician portal.
private struct AssistantShell: Shape {
    func path(in rect: CGRect) -> Path {
        let s = rect.width / 200
        func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: rect.minX + x * s, y: rect.minY + y * s) }
        var path = Path()
        path.move(to: p(100, 42))
        path.addCurve(to: p(170, 108), control1: p(150, 42), control2: p(170, 70))
        path.addCurve(to: p(100, 170), control1: p(170, 148), control2: p(142, 170))
        path.addCurve(to: p(30, 108), control1: p(58, 170), control2: p(30, 148))
        path.addCurve(to: p(100, 42), control1: p(30, 70), control2: p(50, 42))
        path.closeSubpath()
        return path
    }
}

/// A smile whose depth animates: positive smiles, zero is flat.
private struct AssistantMouth: Shape {
    var depth: CGFloat
    var animatableData: CGFloat {
        get { depth }
        set { depth = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: CGPoint(x: rect.midX, y: rect.midY + depth))
        return path
    }
}

/// A happy, squinting eye.
private struct AssistantArcEye: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY), control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.6))
        return path
    }
}

/**
 The living assistant: breathes and floats, blinks at an irregular pace, looks where it is told (a finger on the screen
 or an idle glance), talks while text is shown, smiles when things go well and looks attentive when something needs a
 second look. All motion stops for Reduce Motion.
 */
struct HealthAssistantAvatar: View {
    var mood: AssistantMood
    var talking: Bool
    /// Where the eyes look, each axis -1...1.
    var look: CGSize
    var size: CGFloat = 180
    var poke = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var blink = false
    @State private var squash = false

    private let cyan = Color(red: 0.50, green: 0.96, blue: 0.90)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bob = reduceMotion ? 0 : sin(t * 2 * .pi / 4.2)
            let talk = talking && !reduceMotion ? (sin(t * 2 * .pi * 4.2) + 1) / 2 : 0
            let pulse = reduceMotion ? 0.5 : (sin(t * 2 * .pi / (mood == .attentive ? 1.4 : 3.0)) + 1) / 2
            canvas(bob: bob, talk: talk, pulse: pulse, spin: reduceMotion ? 0 : t / 14)
        }
        .frame(width: 200, height: 200)
        .scaleEffect(x: (squash ? 1.1 : 1) * size / 200, y: (squash ? 0.88 : 1) * size / 200, anchor: .center)
        .frame(width: size, height: size)
        .task { await blinkLoop() }
        .onChange(of: poke) { _, _ in
            guard !reduceMotion else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.4)) { squash = true }
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                withAnimation(.spring(response: 0.42, dampingFraction: 0.45)) { squash = false }
            }
        }
        .accessibilityHidden(true)
    }

    private func canvas(bob: Double, talk: Double, pulse: Double, spin: Double) -> some View {
        let lift = CGFloat(-4.5 * (bob + 1))
        let happy = mood == .happy && !talking
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [mood.glow.opacity(0.55), mood.glow.opacity(0)], center: .center, startRadius: 0, endRadius: 96))
                .frame(width: 192, height: 192)
                .scaleEffect(0.95 + 0.08 * pulse)
                .opacity(0.7 + 0.3 * pulse)
                .position(x: 100, y: 104)

            ForEach(0..<3) { i in
                let angle = spin * 2 * .pi + Double(i) * 2.1
                let radius = 88.0 + Double(i) * 4
                Circle()
                    .fill(Color(red: 1, green: 0.89, blue: 0.95))
                    .frame(width: CGFloat(6 - i), height: CGFloat(6 - i))
                    .opacity(0.35 + 0.65 * ((sin(spin * 40 + Double(i) * 1.7) + 1) / 2))
                    .position(x: 100 + cos(angle) * radius, y: 100 + sin(angle) * radius)
            }

            Ellipse()
                .fill(.black.opacity(0.28 - 0.08 * (bob + 1) / 2))
                .frame(width: 92 * (1 - 0.09 * (bob + 1)), height: 14)
                .position(x: 100, y: 188)

            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: 100, y: 44))
                    path.addCurve(to: CGPoint(x: 108, y: 22), control1: CGPoint(x: 100, y: 34), control2: CGPoint(x: 104, y: 28))
                }
                .stroke(Color(red: 1, green: 0.84, blue: 0.92), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                Circle()
                    .fill(mood.glow)
                    .frame(width: 12, height: 12)
                    .shadow(color: mood.glow, radius: 6 + 4 * pulse)
                    .opacity(0.6 + 0.4 * pulse)
                    .position(x: 109, y: 20)

                AssistantShell()
                    .fill(RadialGradient(stops: [
                        .init(color: Color(red: 1, green: 0.84, blue: 0.92), location: 0),
                        .init(color: Color(red: 0.85, green: 0.34, blue: 0.60), location: 0.45),
                        .init(color: Color(red: 0.43, green: 0.16, blue: 0.33), location: 1)
                    ], center: UnitPoint(x: 0.38, y: 0.30), startRadius: 0, endRadius: 150))
                    .frame(width: 200, height: 200)
                Ellipse()
                    .fill(.white.opacity(0.28))
                    .frame(width: 44, height: 24)
                    .rotationEffect(.degrees(-24))
                    .position(x: 72, y: 66)

                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 0.16, green: 0.08, blue: 0.19), Color(red: 0.07, green: 0.04, blue: 0.08)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 100, height: 58)
                    .position(x: 100, y: 107)

                if mood == .attentive {
                    ForEach([78.0, 122.0], id: \.self) { x in
                        AssistantArcEye()
                            .stroke(cyan.opacity(0.9), style: StrokeStyle(lineWidth: 2.6, lineCap: .round))
                            .frame(width: 16, height: 4)
                            .rotationEffect(.degrees(x < 100 ? 8 : -8))
                            .position(x: x, y: 87)
                    }
                }

                ForEach([78.0, 122.0], id: \.self) { x in
                    if happy {
                        AssistantArcEye()
                            .stroke(cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                            .frame(width: 20, height: 8)
                            .position(x: x, y: 104)
                    } else {
                        ZStack {
                            Ellipse().fill(cyan).frame(width: 20, height: 24)
                            Circle()
                                .fill(Color(red: 0.05, green: 0.18, blue: 0.19))
                                .frame(width: 9.2, height: 9.2)
                                .offset(x: look.width * 5, y: look.height * 4)
                            Circle()
                                .fill(.white)
                                .frame(width: 3.6, height: 3.6)
                                .offset(x: 2 + look.width * 5, y: -4 + look.height * 4)
                        }
                        .scaleEffect(x: 1, y: blink ? 0.08 : 1)
                        .position(x: x, y: 105)
                    }
                }

                if talk > 0.02 {
                    Ellipse()
                        .fill(cyan)
                        .frame(width: 16 + 4 * talk, height: 3 + 9 * talk)
                        .position(x: 100, y: 127)
                } else {
                    AssistantMouth(depth: happy ? 14 : mood == .attentive ? 2 : 7)
                        .stroke(cyan, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                        .frame(width: happy ? 32 : 24, height: 10)
                        .position(x: 100, y: 124)
                        .animation(.easeOut(duration: 0.3), value: happy)
                }

                ForEach([58.0, 142.0], id: \.self) { x in
                    Ellipse()
                        .fill(Color(red: 1, green: 0.55, blue: 0.78).opacity(happy ? 0.75 : 0.35))
                        .frame(width: 16, height: 10)
                        .position(x: x, y: 128)
                }
            }
            .frame(width: 200, height: 200)
            .scaleEffect(x: 1 + 0.012 * (bob + 1) / 2, y: 1 - 0.01 * (bob + 1) / 2, anchor: .bottom)
            .offset(y: lift)
        }
        .frame(width: 200, height: 200)
    }

    private func blinkLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 2200...6000)))
            guard !Task.isCancelled else { return }
            withAnimation(.easeIn(duration: 0.08)) { blink = true }
            try? await Task.sleep(for: .milliseconds(130))
            withAnimation(.easeOut(duration: 0.1)) { blink = false }
            if Int.random(in: 0..<4) == 0 {
                try? await Task.sleep(for: .milliseconds(180))
                withAnimation(.easeIn(duration: 0.08)) { blink = true }
                try? await Task.sleep(for: .milliseconds(110))
                withAnimation(.easeOut(duration: 0.1)) { blink = false }
            }
        }
    }
}

// MARK: - Findings

struct HealthRevealFinding: Identifiable, Equatable {
    enum Tone: Equatable {
        case good, watch, steady

        var label: String {
            switch self {
            case .good: "Positivt"
            case .watch: "Håll koll"
            case .steady: "Stabilt"
            }
        }
        var symbol: String {
            switch self {
            case .good: "arrow.up.heart.fill"
            case .watch: "eye.fill"
            case .steady: "equal.circle.fill"
            }
        }
        var color: Color {
            switch self {
            case .good: Color(red: 0.50, green: 0.96, blue: 0.80)
            case .watch: Color(red: 1.0, green: 0.78, blue: 0.45)
            case .steady: Color(red: 0.78, green: 0.80, blue: 1.0)
            }
        }
    }

    let id: String
    let symbol: String
    let title: String
    /// One sentence the assistant says about the finding.
    let speech: String
    let value: String
    let context: String
    /// The change in percent over the year, shown counting up; nil when there is no trend.
    let change: Int?
    let trend: [Double]
    let tone: Tone
    let tint: Color
}

/// A sparkline that draws itself.
private struct Sparkline: Shape {
    let values: [Double]
    func path(in rect: CGRect) -> Path {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return Path() }
        let span = max(high - low, 0.0001)
        let points = values.enumerated().map { index, value in
            CGPoint(x: rect.minX + rect.width * CGFloat(index) / CGFloat(values.count - 1),
                    y: rect.maxY - rect.height * CGFloat((value - low) / span))
        }
        var path = Path()
        path.move(to: points[0])
        for i in 1..<points.count {
            let previous = points[i - 1], point = points[i]
            let mid = CGPoint(x: (previous.x + point.x) / 2, y: (previous.y + point.y) / 2)
            path.addQuadCurve(to: mid, control: previous)
            if i == points.count - 1 { path.addQuadCurve(to: point, control: point) }
        }
        return path
    }
}
// MARK: - Shared look

enum GradePalette {
    static let ink = Color(red: 0.19, green: 0.11, blue: 0.22)
    static let plum = Color(red: 0.34, green: 0.12, blue: 0.29)
    static let rose = Color(red: 0.73, green: 0.20, blue: 0.47)
    static let softPink = Color(red: 1.0, green: 0.68, blue: 0.82)
    static let lavender = Color(red: 0.90, green: 0.82, blue: 1.0)
    static let gold = Color(red: 1.0, green: 0.80, blue: 0.47)
    static let goldLight = Color(red: 1.0, green: 0.93, blue: 0.76)
    static let goldDeep = Color(red: 0.78, green: 0.53, blue: 0.20)
    /// The colour of the top grade.
    static var goldGradient: LinearGradient {
        LinearGradient(colors: [goldLight, gold, goldDeep], startPoint: .topLeading, endPoint: .bottomTrailing)
    }
}

/// The main button of the health grade: a wide capsule with a light sweep and an arrow, for dark or light backgrounds.
struct HealthPrimaryButtonLabel: View {
    let title: String
    var symbol = "arrow.right"
    var onDark = true

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Text(title)
                .font(.system(.headline, design: .rounded, weight: .bold))
                .foregroundStyle(onDark ? GradePalette.ink : .white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .padding(.horizontal, 58)
                .contentTransition(.opacity)
            HStack {
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(onDark ? Color.white : GradePalette.plum)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 42, height: 42)
                    .background {
                        if onDark {
                            Circle().fill(LinearGradient(colors: [GradePalette.rose, GradePalette.plum],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                        } else {
                            Circle().fill(.white)
                        }
                    }
                    .shadow(color: GradePalette.plum.opacity(0.3), radius: 6, y: 2)
            }
            .padding(.trailing, 8)
        }
        .frame(maxWidth: .infinity, minHeight: 58)
        .background(background, in: Capsule())
        .overlay { shimmer.clipShape(Capsule()).allowsHitTesting(false) }
        .overlay { Capsule().strokeBorder(.white.opacity(onDark ? 0.8 : 0.25), lineWidth: 1) }
        .shadow(color: onDark ? GradePalette.softPink.opacity(0.5) : GradePalette.rose.opacity(0.35), radius: 18, y: 8)
        .contentShape(Capsule())
    }

    private var background: LinearGradient {
        onDark
            ? LinearGradient(colors: [.white, Color(red: 1, green: 0.88, blue: 0.94), GradePalette.softPink],
                             startPoint: .leading, endPoint: .trailing)
            : LinearGradient(colors: [GradePalette.rose, GradePalette.plum], startPoint: .leading, endPoint: .trailing)
    }

    @ViewBuilder private var shimmer: some View {
        if !reduceMotion {
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let cycle = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3.4) / 3.4
                GeometryReader { proxy in
                    let sweep = min(1, cycle / 0.35)
                    LinearGradient(colors: [.clear, .white.opacity(onDark ? 0.8 : 0.35), .clear],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: proxy.size.width * 0.28, height: proxy.size.height * 2)
                        .rotationEffect(.degrees(18))
                        .offset(x: -proxy.size.width * 0.35 + proxy.size.width * 1.45 * sweep, y: -proxy.size.height * 0.5)
                        .opacity(cycle < 0.35 ? 1 : 0)
                }
            }
        }
    }
}

/// Gives a button a soft press.
struct HealthPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - The reveal

/**
 After the scan, the assistant presents what it found, full screen: a greeting with the sources it read, the grade
 landing on the A–E scale with a burst of light and a haptic, then each finding on its own card with a self-drawing
 trend, and a closing summary. Tap the assistant to see the line again.
 */
struct HealthGradeReveal: View {
    let firstName: String?
    let grade: String
    let gradeTitle: String
    let gradePosition: Double
    let positiveGrade: Bool
    let findings: [HealthRevealFinding]
    let isExample: Bool
    /// "1 år"
    let periodTitle: String
    /// "ett år"
    let periodSpan: String
    /// Under the start of each trend: "För ett år sedan".
    let trendStart: String
    let sources: [String]
    let dataPoints: Int
    let finish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var step = 0
    @State private var shown = 0
    @State private var typing = false
    @State private var look = CGSize.zero
    @State private var touching = false
    @State private var poke = 0
    @State private var gradeLanded = false
    @State private var burst: Date?
    @State private var cardProgress: CGFloat = 0
    @State private var changeShown = 0
    @State private var sourcesShown = false
    @State private var playToken = 0

    private static let scale = ["A", "B", "C", "D", "E"]
    private let ink = GradePalette.ink
    private let softPink = GradePalette.softPink
    private let lavender = GradePalette.lavender
    private let gold = GradePalette.gold

    /// 0 greeting, 1 grade, 2... findings, last: closing.
    private var lastStep: Int { findings.count + 2 }
    private var finding: HealthRevealFinding? {
        step >= 2 && step - 2 < findings.count ? findings[step - 2] : nil
    }
    private var isTop: Bool { grade == "A" }
    private var line: String {
        let name = firstName.map { " \($0)" } ?? ""
        switch step {
        case 0:
            return "Hej\(name)! Jag har gått igenom \(periodSpan) av din hälsa: sömn, puls, andning, aktivitet, blodprover och journalen."
                + (isExample ? " Det här är exempeldata." : "")
        case 1:
            return "Ditt hälsobetyg blev \(grade). \(gradeTitle)."
        case lastStep:
            return "Det var mina viktigaste fynd. Nu visar jag alla resultat och kurvor."
        default:
            return finding?.speech ?? ""
        }
    }
    private var mood: AssistantMood {
        if let finding { return finding.tone == .watch ? .attentive : .happy }
        if step == 1 { return gradeLanded ? (positiveGrade ? .happy : .attentive) : .calm }
        return step == lastStep ? .happy : .calm
    }
    private var nextTitle: String {
        switch step {
        case 0: "Visa mitt betyg"
        case 1: "Se vad som påverkar"
        case lastStep: "Visa alla resultat"
        case lastStep - 1: "Sammanfattning"
        default: "Nästa fynd"
        }
    }

    var body: some View {
        ZStack {
            HealthRevealBackdrop(mood: mood)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                Spacer(minLength: 4)

                HealthAssistantAvatar(mood: mood, talking: typing, look: look, size: step == 0 ? 150 : 124, poke: poke)
                    .onTapGesture {
                        poke += 1
                        replay()
                    }
                    .accessibilityElement()
                    .accessibilityLabel("Assistenten")
                    .accessibilityHint("Visar meningen igen")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction { poke += 1; replay() }

                bubble
                    .padding(.horizontal, 22)
                    .padding(.top, 2)

                stage
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 200)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)

                Spacer(minLength: 10)

                controls
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }
            .frame(maxWidth: 560)

            if let burst, !reduceMotion {
                GradeBurst(start: burst, colors: isTop ? [gold, GradePalette.goldLight, .white, softPink]
                                                       : [softPink, lavender, .white, Color(red: 0.5, green: 0.96, blue: 0.9)])
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
            }
        }
        .foregroundStyle(.white)
        .contentShape(Rectangle())
        .simultaneousGesture(DragGesture(minimumDistance: 0, coordinateSpace: .global)
            .onChanged { value in
                touching = true
                let screen = UIScreen.main.bounds
                let avatarCenter = CGPoint(x: screen.midX, y: screen.height * 0.24)
                let dx = value.location.x - avatarCenter.x, dy = value.location.y - avatarCenter.y
                let d = max(hypot(dx, dy), 1)
                let reach = min(1, d / 220)
                withAnimation(.easeOut(duration: 0.12)) {
                    look = CGSize(width: dx / d * reach, height: dy / d * reach)
                }
            }
            .onEnded { _ in touching = false })
        .sensoryFeedback(.success, trigger: gradeLanded) { _, landed in landed }
        .sensoryFeedback(.impact(weight: .light), trigger: step)
        .task { await glanceLoop() }
        .task(id: "\(step)-\(playToken)") { await play() }
    }

    private var header: some View {
        VStack(spacing: 12) {
            HStack(spacing: 4) {
                ForEach(0...lastStep, id: \.self) { index in
                    Capsule()
                        .fill(.white.opacity(0.18))
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(.white)
                                .scaleEffect(x: index <= step ? 1 : 0, y: 1, anchor: .leading)
                        }
                        .frame(height: 3)
                        .clipShape(Capsule())
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: step)
            .accessibilityElement()
            .accessibilityLabel("Steg \(step + 1) av \(lastStep + 1)")

            HStack(alignment: .center, spacing: 8) {
                Text("Hälsobetyg")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if isExample {
                    Text("Testdata")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(ink)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 9)
                        .background(Color(red: 0.98, green: 0.89, blue: 0.94), in: Capsule())
                }
                Spacer()
                Button("Hoppa över", action: finish)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(lavender)
                    .frame(minHeight: 44)
            }
        }
    }

    private var bubble: some View {
        let text = String(line.prefix(shown))
        return Text(text.isEmpty ? " " : text)
            .font(.system(.title3, design: .rounded, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .top)
            .overlay(alignment: .top) {
                // Reserves the full line's height so the layout does not jump while typing.
                Text(line).font(.system(.title3, design: .rounded, weight: .semibold)).lineSpacing(2)
                    .multilineTextAlignment(.center).hidden()
            }
            .contentShape(Rectangle())
            .onTapGesture { shown = line.count; typing = false }
            .accessibilityLabel(line)
    }

    @ViewBuilder private var stage: some View {
        switch step {
        case 0:
            sourcesCard
                .transition(.scale(scale: 0.92).combined(with: .opacity))
        case 1:
            VStack(spacing: 16) {
                gradeSeal
                gradeScale
            }
            .transition(.scale(scale: 0.6).combined(with: .opacity))
        case lastStep:
            summaryGrid
                .transition(.move(edge: .bottom).combined(with: .opacity))
        default:
            if let finding {
                findingCard(finding)
                    .id(finding.id)
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .leading).combined(with: .opacity)))
            }
        }
    }

    private var sourcesCard: some View {
        let tints: [Color] = [Color(red: 0.85, green: 0.34, blue: 0.60), Color(red: 0.43, green: 0.29, blue: 0.69),
                              Color(red: 0.18, green: 0.40, blue: 0.61), Color(red: 0.16, green: 0.43, blue: 0.38)]
        let shape = RoundedRectangle(cornerRadius: 26)
        return VStack(spacing: 16) {
            HStack(spacing: -9) {
                ForEach(Array(sources.enumerated()), id: \.offset) { index, symbol in
                    Image(systemName: symbol)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 42, height: 42)
                        .background {
                            Circle().fill(LinearGradient(colors: [tints[index % tints.count], tints[(index + 1) % tints.count]],
                                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                        }
                        .overlay { Circle().strokeBorder(Color(red: 0.22, green: 0.09, blue: 0.26), lineWidth: 2.5) }
                        .zIndex(Double(sources.count - index))
                        .scaleEffect(sourcesShown || reduceMotion ? 1 : 0.3)
                        .opacity(sourcesShown || reduceMotion ? 1 : 0)
                        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.62).delay(Double(index) * 0.07),
                                   value: sourcesShown)
                }
            }
            HStack(spacing: 0) {
                stat("\(sources.count)", "källor")
                statDivider
                stat(dataPoints.formatted(.number.locale(Locale(identifier: "sv_SE"))), "datapunkter")
                statDivider
                stat(periodTitle, "period")
            }
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .background {
            shape.fill(LinearGradient(colors: [.white.opacity(0.13), softPink.opacity(0.08)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { shape.strokeBorder(.white.opacity(0.18)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(sources.count) källor, \(dataPoints) datapunkter, period \(periodTitle)")
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.system(.title3, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(lavender)
        }
        .frame(maxWidth: .infinity)
    }

    private var statDivider: some View {
        Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 30)
    }

    private var gradeSeal: some View {
        let ring: [Color] = isTop ? [GradePalette.goldLight, gold, GradePalette.goldDeep, GradePalette.goldLight]
                                  : [.white, lavender, softPink, .white]
        return ZStack {
            Circle()
                .fill(RadialGradient(colors: [(isTop ? gold : softPink).opacity(0.35), softPink.opacity(0.03)],
                                     center: .topLeading, startRadius: 0, endRadius: 150))
                .padding(11)
            Circle().strokeBorder(.white.opacity(0.16), lineWidth: 7)
            Circle()
                .trim(from: 0, to: gradeLanded ? gradePosition : 0)
                .stroke(AngularGradient(colors: ring, center: .center),
                        style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(3.5)
                .shadow(color: (isTop ? gold : softPink).opacity(0.7), radius: 12)
            VStack(spacing: 0) {
                Text(gradeLanded ? grade : " ")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .foregroundStyle(isTop ? AnyShapeStyle(GradePalette.goldGradient) : AnyShapeStyle(.white))
                    .scaleEffect(gradeLanded ? 1 : 0.3)
                    .opacity(gradeLanded ? 1 : 0)
                Text(gradeTitle)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(lavender)
                    .opacity(gradeLanded ? 1 : 0)
            }
        }
        .frame(width: 176, height: 176)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Hälsobetyg \(grade), \(gradeTitle)")
    }

    private var gradeScale: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(Self.scale, id: \.self) { letter in
                    let mine = letter == grade
                    let top = letter == "A"
                    let shape = RoundedRectangle(cornerRadius: 12)
                    Text(letter)
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(mine ? ink : top ? gold : .white.opacity(0.6))
                        .frame(width: 46, height: 40)
                        .background {
                            if mine {
                                shape.fill(top ? AnyShapeStyle(GradePalette.goldGradient)
                                               : AnyShapeStyle(LinearGradient(colors: [.white, softPink],
                                                                              startPoint: .topLeading, endPoint: .bottomTrailing)))
                            } else {
                                shape.fill(.white.opacity(0.07))
                            }
                        }
                        .overlay { shape.strokeBorder(top ? gold.opacity(0.7) : .white.opacity(mine ? 0 : 0.14)) }
                        .overlay(alignment: .topTrailing) {
                            if top {
                                Image(systemName: "crown.fill")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(mine ? ink.opacity(0.7) : gold)
                                    .padding(4)
                            }
                        }
                        .scaleEffect(mine && gradeLanded ? 1.12 : 1)
                        .shadow(color: mine && gradeLanded ? (top ? gold : softPink).opacity(0.6) : .clear, radius: 10)
                }
            }
            Text(verbatim: "A = topp 10 % · kräver blodprover med bra resultat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(gold.opacity(0.9))
                .multilineTextAlignment(.center)
        }
        .opacity(gradeLanded || reduceMotion ? 1 : 0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Skala från A till E. A ges till topp 10 procent och kräver blodprover med bra resultat.")
    }

    private func findingCard(_ finding: HealthRevealFinding) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: finding.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(finding.tint)
                    .frame(width: 42, height: 42)
                    .background(finding.tint.opacity(0.15), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 2) {
                    Text(finding.title).font(.headline)
                    Text(finding.context).font(.caption).foregroundStyle(lavender)
                }
                Spacer(minLength: 4)
                Label(finding.tone.label, systemImage: finding.tone.symbol)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(ink)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 8)
                    .background(finding.tone.color, in: Capsule())
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(finding.value)
                    .font(.system(.title, design: .rounded, weight: .bold))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                if let change = finding.change {
                    Text(verbatim: "\(changeShown > 0 ? "+" : "")\(changeShown) %")
                        .font(.system(.headline, design: .rounded, weight: .bold))
                        .foregroundStyle(finding.tone.color)
                        .contentTransition(.numericText(value: Double(changeShown)))
                        .accessibilityLabel("\(change) procent")
                }
            }
            if finding.trend.count > 1 {
                ZStack(alignment: .bottomLeading) {
                    Sparkline(values: finding.trend)
                        .trim(from: 0, to: cardProgress)
                        .stroke(finding.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                        .shadow(color: finding.tint.opacity(0.7), radius: 6)
                    HStack {
                        Text(trendStart)
                        Spacer()
                        Text("Nu")
                    }
                    .font(.caption2)
                    .foregroundStyle(lavender.opacity(0.8))
                    .offset(y: 18)
                }
                .frame(height: 64)
                .padding(.bottom, 18)
                .accessibilityHidden(true)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: 26)
            shape.fill(LinearGradient(colors: [.white.opacity(0.14), finding.tint.opacity(0.10)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { shape.strokeBorder(.white.opacity(0.2)) }
                .shadow(color: finding.tint.opacity(0.25), radius: 24, y: 12)
        }
        .accessibilityElement(children: .combine)
    }

    private var summaryGrid: some View {
        VStack(spacing: 8) {
            ForEach(findings) { finding in
                HStack(spacing: 10) {
                    Image(systemName: finding.symbol)
                        .foregroundStyle(finding.tint)
                        .frame(width: 26)
                    Text(finding.title).font(.subheadline.weight(.semibold))
                    Spacer()
                    Image(systemName: finding.tone.symbol)
                        .foregroundStyle(finding.tone.color)
                        .accessibilityLabel(finding.tone.label)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            if step > 0 {
                Button(action: back) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .bold))
                        .frame(width: 58, height: 58)
                        .background(.white.opacity(0.12), in: Circle())
                        .overlay { Circle().strokeBorder(.white.opacity(0.22)) }
                }
                .buttonStyle(HealthPressStyle())
                .accessibilityLabel("Tillbaka")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
            Button(action: next) {
                HealthPrimaryButtonLabel(title: nextTitle, symbol: step == lastStep ? "checkmark" : "arrow.right")
            }
            .buttonStyle(HealthPressStyle())
        }
    }

    // MARK: Playback

    private func play() async {
        shown = 0
        cardProgress = 0
        changeShown = 0
        if step != 1 { gradeLanded = false }
        if step == 0 && !sourcesShown { sourcesShown = true }
        await typeLine()
        guard !Task.isCancelled else { return }
        if step == 1 {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(response: 0.55, dampingFraction: 0.62)) { gradeLanded = true }
            burst = .now
        }
        if let finding {
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 1.1)) { cardProgress = 1 }
            if let change = finding.change {
                let frames = reduceMotion ? 1 : 18
                for frame in 1...frames {
                    try? await Task.sleep(for: .milliseconds(40))
                    guard !Task.isCancelled else { return }
                    withAnimation(.snappy) { changeShown = Int((Double(change) * Double(frame) / Double(frames)).rounded()) }
                }
            }
        }
    }

    private func typeLine() async {
        let full = line
        if reduceMotion {
            shown = full.count
            return
        }
        typing = true
        defer { typing = false }
        for count in stride(from: 0, through: full.count, by: 2) {
            guard !Task.isCancelled, shown < full.count else { break }
            shown = count
            try? await Task.sleep(for: .milliseconds(22))
        }
        shown = full.count
    }

    private func replay() { playToken += 1 }

    private func next() {
        if step >= lastStep { finish(); return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) { step += 1 }
    }

    private func back() {
        guard step > 0 else { return }
        withAnimation(reduceMotion ? nil : .spring(response: 0.5, dampingFraction: 0.85)) { step -= 1 }
    }

    /// When no finger is on the screen the eyes wander a little, like someone thinking.
    private func glanceLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(Int.random(in: 1500...2600)))
            guard !Task.isCancelled, !touching else { continue }
            let angle = Double.random(in: 0..<(2 * .pi))
            let reach = Double.random(in: 0.2...0.9)
            withAnimation(.easeInOut(duration: 0.35)) {
                look = CGSize(width: cos(angle) * reach, height: sin(angle) * reach * 0.8)
            }
        }
    }
}


/// The aurora behind the reveal, tinted by the assistant's mood.
private struct HealthRevealBackdrop: View {
    let mood: AssistantMood
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            GeometryReader { proxy in
                let w = proxy.size.width, h = proxy.size.height
                ZStack {
                    LinearGradient(stops: [
                        .init(color: Color(red: 0.16, green: 0.07, blue: 0.20), location: 0),
                        .init(color: Color(red: 0.29, green: 0.11, blue: 0.33), location: 0.55),
                        .init(color: Color(red: 0.10, green: 0.05, blue: 0.14), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    blob(Color(red: 0.85, green: 0.34, blue: 0.60), x: 0.15 + 0.08 * sin(t / 7), y: 0.12 + 0.05 * cos(t / 9), r: w * 0.9, w: w, h: h)
                    blob(Color(red: 0.36, green: 0.24, blue: 0.77), x: 0.92 + 0.06 * cos(t / 8), y: 0.42 + 0.06 * sin(t / 11), r: w * 0.85, w: w, h: h)
                    blob(mood.glow, x: 0.45 + 0.1 * sin(t / 10), y: 0.95 + 0.04 * cos(t / 6), r: w * 0.8, w: w, h: h)
                        .opacity(0.55)
                        .animation(.easeInOut(duration: 1.2), value: mood)
                }
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    private func blob(_ color: Color, x: Double, y: Double, r: CGFloat, w: CGFloat, h: CGFloat) -> some View {
        Circle()
            .fill(RadialGradient(colors: [color.opacity(0.55), color.opacity(0)], center: .center, startRadius: 0, endRadius: r / 2))
            .frame(width: r, height: r)
            .position(x: w * x, y: h * y)
            .blendMode(.plusLighter)
    }
}

/// A burst of light particles when the grade lands.
private struct GradeBurst: View {
    let start: Date
    let colors: [Color]

    private struct Particle {
        let angle: Double, speed: Double, size: Double, spin: Double, color: Int
    }
    private let particles: [Particle] = (0..<70).map { i in
        var generator = SeededGenerator(seed: UInt64(i) &* 2_654_435_761 &+ 97)
        return Particle(angle: Double.random(in: 0..<(2 * .pi), using: &generator),
                        speed: Double.random(in: 140...420, using: &generator),
                        size: Double.random(in: 3...8, using: &generator),
                        spin: Double.random(in: -6...6, using: &generator),
                        color: Int.random(in: 0..<4, using: &generator))
    }

    var body: some View {
        TimelineView(.animation) { context in
            let age = context.date.timeIntervalSince(start)
            Canvas { canvas, size in
                guard age < 1.8 else { return }
                let origin = CGPoint(x: size.width / 2, y: size.height * 0.62)
                for particle in particles {
                    let distance = particle.speed * age * (1 - age / 3.2)
                    let x = origin.x + cos(particle.angle) * distance
                    let y = origin.y + sin(particle.angle) * distance + 90 * age * age
                    let alpha = max(0, 1 - age / 1.8)
                    let rect = CGRect(x: x - particle.size / 2, y: y - particle.size / 2, width: particle.size, height: particle.size * 0.6)
                    var context = canvas
                    context.opacity = alpha
                    context.translateBy(x: rect.midX, y: rect.midY)
                    context.rotate(by: .radians(particle.spin * age))
                    context.fill(Path(roundedRect: CGRect(x: -rect.width / 2, y: -rect.height / 2, width: rect.width, height: rect.height), cornerRadius: 1.5),
                                 with: .color(colors[particle.color % colors.count]))
                }
            }
        }
    }
}

/// Deterministic random numbers, so the burst looks the same each time.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0x9E3779B97F4A7C15 : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}
