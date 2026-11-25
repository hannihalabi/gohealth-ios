import HealthKit
import ImageIO
import PhotosUI
import SwiftUI

private enum DashboardTab: CaseIterable {
    case activity, measurements, home, recovery, more
    
    var title: String {
        switch self {
        case .home: "Hem"
        case .activity: "Aktivitet"
        case .measurements: "Mätvärden"
        case .recovery: "Hälsobetyg"
        case .more: "Mer"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .activity: "figure.run"
        case .measurements: "waveform.path.ecg"
        case .recovery: "sparkles"
        case .more: "ellipsis"
        }
    }
}

private enum BodyAppearance {
    case female, male
}

private struct NavigationBarTopEdge: Shape {
    func path(in rect: CGRect) -> Path {
        let center = rect.midX
        let shoulder: CGFloat = min(44, rect.width * 0.12)
        return Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: center - shoulder, y: rect.minY))
            path.addCurve(to: CGPoint(x: center, y: rect.minY - 14),
                          control1: CGPoint(x: center - shoulder * 0.55, y: rect.minY),
                          control2: CGPoint(x: center - shoulder * 0.50, y: rect.minY - 14))
            path.addCurve(to: CGPoint(x: center + shoulder, y: rect.minY),
                          control1: CGPoint(x: center + shoulder * 0.50, y: rect.minY - 14),
                          control2: CGPoint(x: center + shoulder * 0.55, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        }
    }
}

private struct NavigationBarSurface: Shape {
    func path(in rect: CGRect) -> Path {
        var path = NavigationBarTopEdge().path(in: rect)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct SoftHomeGlyph: Shape {
    func path(in rect: CGRect) -> Path {
        let drawing = Path { path in
            path.move(to: CGPoint(x: 3, y: 10.5))
            path.addLine(to: CGPoint(x: 10, y: 4.4))
            path.addQuadCurve(to: CGPoint(x: 14, y: 4.4), control: CGPoint(x: 12, y: 2.7))
            path.addLine(to: CGPoint(x: 21, y: 10.5))
            path.move(to: CGPoint(x: 5, y: 11))
            path.addLine(to: CGPoint(x: 5, y: 18.5))
            path.addQuadCurve(to: CGPoint(x: 7.5, y: 21), control: CGPoint(x: 5, y: 21))
            path.addLine(to: CGPoint(x: 16.5, y: 21))
            path.addQuadCurve(to: CGPoint(x: 19, y: 18.5), control: CGPoint(x: 19, y: 21))
            path.addLine(to: CGPoint(x: 19, y: 11))
            path.move(to: CGPoint(x: 10, y: 21))
            path.addLine(to: CGPoint(x: 10, y: 17))
            path.addQuadCurve(to: CGPoint(x: 14, y: 17), control: CGPoint(x: 12, y: 13.5))
            path.addLine(to: CGPoint(x: 14, y: 21))
        }
        return drawing.applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24)
            .concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

private struct HomeButtonFramePreference: PreferenceKey {
    static let defaultValue = CGRect.zero

    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if !next.isEmpty { value = next }
    }
}

private enum HomePanel {
    case vaccinations, imaging, messages

    var coordinateSpace: String {
        switch self {
        case .vaccinations, .imaging: "homeBodyStage"
        case .messages: "homeMessageStage"
        }
    }
}

private struct HomePanelFramePreference: PreferenceKey {
    static let defaultValue: [HomePanel: CGRect] = [:]

    static func reduce(value: inout [HomePanel: CGRect], nextValue: () -> [HomePanel: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, newest in newest })
    }
}

private struct WelcomeRevealMask: Shape {
    var center: CGPoint
    var radius: CGFloat

    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.addRect(rect)
            if radius > 0 {
                path.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius,
                                           width: radius * 2, height: radius * 2))
            }
        }
    }
}

enum BodyOrgan: CaseIterable, Hashable {
    case heart, liver, lungs, kidneys, thyroid

    var title: String {
        switch self {
        case .heart: "Hjärta"
        case .liver: "Lever"
        case .lungs: "Lungor"
        case .kidneys: "Njurar"
        case .thyroid: "Sköldkörtel"
        }
    }

    // Coordinates relative to the center line and the height of the illustration.
    var markerPosition: CGPoint {
        switch self {
        case .heart: CGPoint(x: 0.052, y: 0.292)
        case .liver: CGPoint(x: -0.059, y: 0.401)
        case .lungs: CGPoint(x: -0.073, y: 0.277)
        case .kidneys: CGPoint(x: 0.061, y: 0.454)
        case .thyroid: CGPoint(x: 0, y: 0.182)
        }
    }
}

private struct OrganGlyph: Shape {
    let organ: BodyOrgan

    func path(in rect: CGRect) -> Path {
        let drawing = Path { path in
            switch organ {
            case .heart:
                path.move(to: CGPoint(x: 9, y: 8))
                path.addCurve(to: CGPoint(x: 4, y: 16), control1: CGPoint(x: 3, y: 7), control2: CGPoint(x: 2, y: 12))
                path.addCurve(to: CGPoint(x: 18, y: 22), control1: CGPoint(x: 7, y: 21), control2: CGPoint(x: 15, y: 23))
                path.addCurve(to: CGPoint(x: 21, y: 14), control1: CGPoint(x: 22, y: 21), control2: CGPoint(x: 23, y: 18))
                path.addCurve(to: CGPoint(x: 15, y: 8), control1: CGPoint(x: 20, y: 11), control2: CGPoint(x: 18, y: 9))
                path.addLine(to: CGPoint(x: 15, y: 5))
                path.addQuadCurve(to: CGPoint(x: 18, y: 4), control: CGPoint(x: 16, y: 4))
                path.addLine(to: CGPoint(x: 18, y: 2))
                path.addQuadCurve(to: CGPoint(x: 11, y: 5), control: CGPoint(x: 12, y: 1))
                path.addLine(to: CGPoint(x: 11, y: 7))
                path.addQuadCurve(to: CGPoint(x: 8, y: 3), control: CGPoint(x: 9, y: 5))
                path.addLine(to: CGPoint(x: 6, y: 4))
                path.closeSubpath()
                path.move(to: CGPoint(x: 9, y: 8))
                path.addQuadCurve(to: CGPoint(x: 15, y: 13), control: CGPoint(x: 13, y: 9))
                path.addQuadCurve(to: CGPoint(x: 17, y: 19), control: CGPoint(x: 16, y: 15))
                path.move(to: CGPoint(x: 13, y: 11))
                path.addQuadCurve(to: CGPoint(x: 9, y: 15), control: CGPoint(x: 12, y: 14))
            case .liver:
                path.move(to: CGPoint(x: 2, y: 9))
                path.addCurve(to: CGPoint(x: 9, y: 5), control1: CGPoint(x: 2, y: 6), control2: CGPoint(x: 5, y: 5))
                path.addCurve(to: CGPoint(x: 22, y: 7), control1: CGPoint(x: 14, y: 5), control2: CGPoint(x: 19, y: 7))
                path.addQuadCurve(to: CGPoint(x: 22, y: 10), control: CGPoint(x: 24, y: 7))
                path.addQuadCurve(to: CGPoint(x: 15, y: 14), control: CGPoint(x: 20, y: 12))
                path.addCurve(to: CGPoint(x: 4, y: 20), control1: CGPoint(x: 10, y: 16), control2: CGPoint(x: 8, y: 20))
                path.addQuadCurve(to: CGPoint(x: 2, y: 17), control: CGPoint(x: 2, y: 20))
                path.closeSubpath()
                path.move(to: CGPoint(x: 12, y: 5.5))
                path.addQuadCurve(to: CGPoint(x: 12, y: 15.5), control: CGPoint(x: 13.5, y: 10))
            case .lungs:
                for side in [CGFloat(-1), 1] {
                    path.move(to: CGPoint(x: 12 + side * 3, y: 8))
                    path.addQuadCurve(to: CGPoint(x: 12 + side * 10, y: 18), control: CGPoint(x: 12 + side * 9, y: 5))
                    path.addQuadCurve(to: CGPoint(x: 12 + side * 2, y: 18), control: CGPoint(x: 12 + side * 10, y: 24))
                    path.closeSubpath()
                    path.move(to: CGPoint(x: 12, y: 8))
                    path.addQuadCurve(to: CGPoint(x: 12 + side * 6, y: 14), control: CGPoint(x: 12 + side, y: 11))
                }
                path.move(to: CGPoint(x: 12, y: 3))
                path.addLine(to: CGPoint(x: 12, y: 8))
            case .kidneys:
                for side in [CGFloat(-1), 1] {
                    path.move(to: CGPoint(x: 12 + side * 6, y: 4))
                    path.addCurve(to: CGPoint(x: 12 + side * 7, y: 18), control1: CGPoint(x: 12 + side * 12, y: 4), control2: CGPoint(x: 12 + side * 12, y: 18))
                    path.addQuadCurve(to: CGPoint(x: 12 + side * 4, y: 11), control: CGPoint(x: 12 + side * 2, y: 18))
                    path.addQuadCurve(to: CGPoint(x: 12 + side * 6, y: 4), control: CGPoint(x: 12 + side, y: 5))
                    path.closeSubpath()
                    path.move(to: CGPoint(x: 12 + side * 4, y: 11))
                    path.addQuadCurve(to: CGPoint(x: 12 + side * 2, y: 21), control: CGPoint(x: 12 + side, y: 13))
                }
            case .thyroid:
                path.move(to: CGPoint(x: 12, y: 11))
                path.addCurve(to: CGPoint(x: 3, y: 10), control1: CGPoint(x: 8, y: 11), control2: CGPoint(x: 4, y: 2))
                path.addCurve(to: CGPoint(x: 12, y: 15), control1: CGPoint(x: 1, y: 20), control2: CGPoint(x: 7, y: 22))
                path.addCurve(to: CGPoint(x: 21, y: 10), control1: CGPoint(x: 17, y: 22), control2: CGPoint(x: 23, y: 20))
                path.addCurve(to: CGPoint(x: 12, y: 11), control1: CGPoint(x: 20, y: 2), control2: CGPoint(x: 16, y: 11))
                path.closeSubpath()
            }
        }
        return drawing
            .applying(CGAffineTransform(scaleX: rect.width / 24, y: rect.height / 24))
            .applying(CGAffineTransform(translationX: rect.minX, y: rect.minY))
    }
}

struct GoHealthLaunchView<Actions: View>: View {
    let title: String
    let detail: String
    let isLoading: Bool
    @ViewBuilder var actions: () -> Actions

    private let accent = Color(red: 0.73, green: 0.20, blue: 0.47)

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 34, weight: .semibold))
                        .foregroundStyle(accent)
                        .frame(width: 84, height: 84)
                        .background(.white, in: RoundedRectangle(cornerRadius: 27))
                        .shadow(color: accent.opacity(0.13), radius: 18, y: 8)
                        .accessibilityHidden(true)
                    Text("GoHealth")
                        .font(.headline)
                        .foregroundStyle(accent)
                    Text(title)
                        .font(.largeTitle.bold())
                        .accessibilityAddTraits(.isHeader)
                    Text(detail)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 330)
                    if isLoading {
                        ProgressView()
                            .tint(accent)
                            .accessibilityLabel("Pågår")
                            .padding(.top, 8)
                    }
                    actions()
                }
                .multilineTextAlignment(.center)
                .padding(28)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
        }
        .background {
            LinearGradient(colors: [.white, accent.opacity(0.10)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
    }
}

struct ContentView: View {
    private enum WelcomePhase {
        case idle, preparing, centered, docked, revealed
    }

    private enum LaunchScreen {
        case restoringAvatar, avatarSetup, appleHealthSetup, profileSetup, doctorSelection, productTour, dashboard

        var onboardingStep: OnboardingStep? {
            switch self {
            case .restoringAvatar, .avatarSetup: .avatar
            case .appleHealthSetup: .appleHealth
            case .profileSetup: .profile
            case .doctorSelection: .doctor
            case .productTour: .tour
            case .dashboard: nil
            }
        }
    }

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var health: HealthStore
    @StateObject private var clinical: ClinicalStore
    @AppStorage private var profilePhotoData: Data?
    @AppStorage private var chosenDoctorID: String
    @State private var showsDoctorProfile = false
    @AppStorage private var healthLinked: Bool
    @AppStorage private var hasCompletedAvatarSetup: Bool
    @AppStorage private var hasCompletedHealthSetup: Bool
    @AppStorage private var hasCompletedProfileSetup: Bool
    @AppStorage private var hasCompletedDoctorSelection: Bool
    @AppStorage private var hasCompletedOnboarding: Bool
    @State private var healthBodyAppearance: BodyAppearance?
    @State private var healthProfile: HealthProfile?
    @State private var profileLoadFailed = false
    @State private var avatar: BodyAvatar?
    @State private var hasLoadedAvatar = false
    @State private var showsAvatarCapture = false
    @State private var showsAvatarRemoval = false
    @State private var avatarStorageError: String?
    @State private var showsHealthLinkConfirmation = false
    @State private var profilePhotoSelection: PhotosPickerItem?
    @State private var showsProfilePhotoError = false
    @State private var showsProfileNameEditor = false
    @State private var showsPasswordEditor = false
    @State private var passwordSaved = false
    @State private var showsProfileNameError = false
    @State private var profileNameDraft = ""
    @State private var selectedTab: DashboardTab = .home
    /// The health grade's scan and assistant fill the screen; the tab bar steps aside meanwhile.
    @State private var gradeImmersive = false
    @State private var selectedOrgan: BodyOrgan?
    @State private var homePanel: HomePanel?
    @State private var homePanelProgress: CGFloat = 0
    @State private var homePanelFrames: [HomePanel: CGRect] = [:]
    @State private var homePanelIsClosing = false
    @State private var homePanelSession = UUID()
    @State private var homeNoticeHeight: CGFloat = 61
    @State private var hiddenHomeNoticeID: UUID?
    @StateObject private var vaccinations: VaccinationStore
    @StateObject private var messages: CareMessageStore
    @State private var welcomePhase: WelcomePhase = .idle
    @State private var homeButtonFrame = CGRect.zero
    @State private var welcomeDestination = CGRect.zero
    @State private var welcomeProgress: CGFloat = 0
    @State private var welcomeMessage = "Öppnar din hälsoöversikt"
    private let accountID: UUID
    private let email: String?
    private let displayName: String?
    private let givenName: String?
    private let updateDisplayName: (String) async -> Bool
    private let signOut: () async -> Void
    private let deleteAccount: () async -> Bool
    private let setPassword: (String) async -> Bool
    @State private var showsAccountDeletion = false
    @State private var isDeletingAccount = false
    @State private var showsAccountDeletionError = false
    private let imagingAccessToken: () async throws -> String
    private let isBeta: Bool
    private let accent = Color(red: 0.73, green: 0.20, blue: 0.47)
    private let pageBackground = Color(red: 0.965, green: 0.970, blue: 0.982)
    private static let bodyStageTopPadding: CGFloat = 14
    private let metricOrder = ["heart-rate", "steps", "sleep", "resting-heart-rate", "hrv", "respiratory-rate", "oxygen", "fev1", "fvc", "fev1-fvc", "pef", "active-energy", "distance", "vo2-max", "weight", "temperature", "flights"]

    private var isWelcoming: Bool { welcomePhase != .idle }

    private var homeGradient: AngularGradient {
        AngularGradient(
            colors: [Color(red: 0.77, green: 0.02, blue: 0.78),
                     Color(red: 0.98, green: 0.02, blue: 0.39),
                     Color(red: 1, green: 0.32, blue: 0.12),
                     Color(red: 1, green: 0.73, blue: 0.08),
                     Color(red: 1, green: 0.40, blue: 0.10),
                     Color(red: 0.77, green: 0.02, blue: 0.78)],
            center: .center, angle: .degrees(-90)
        )
    }

    init(
        accountID: UUID,
        email: String?,
        displayName: String?,
        givenName: String? = nil,
        updateDisplayName: @escaping (String) async -> Bool,
        signOut: @escaping () async -> Void,
        deleteAccount: @escaping () async -> Bool = { false },
        setPassword: @escaping (String) async -> Bool = { _ in false },
        betaPreferences: UserDefaults? = nil,
        imagingAccessToken: @escaping () async throws -> String = { throw URLError(.userAuthenticationRequired) },
        messaging: CareMessaging = .unavailable,
        fetchClinicalRecords: @escaping () async throws -> ClinicalEnvelope = { ClinicalEnvelope(records: []) },
        uploadClinicalVitals: @escaping (ClinicalVitalsBatch) async throws -> Void = { _ in throw URLError(.userAuthenticationRequired) },
        downloadClinicalArchive: @escaping (ClinicalArchiveAttachment) async throws -> Data = { _ in throw URLError(.userAuthenticationRequired) }
    ) {
        self.accountID = accountID
        self.email = email
        self.displayName = displayName
        self.givenName = givenName ?? displayName?.split(whereSeparator: \.isWhitespace).first.map(String.init)
        self.updateDisplayName = updateDisplayName
        self.signOut = signOut
        self.deleteAccount = deleteAccount
        self.setPassword = setPassword
        self.imagingAccessToken = imagingAccessToken
        let isBeta = betaPreferences != nil
        self.isBeta = isBeta
        _health = StateObject(wrappedValue: HealthStore(isBeta: isBeta))
        _clinical = StateObject(wrappedValue: ClinicalStore(accountID: accountID, isBeta: isBeta, fetch: fetchClinicalRecords,
                                                            upload: uploadClinicalVitals, downloadArchive: downloadClinicalArchive))
        _vaccinations = StateObject(wrappedValue: VaccinationStore(accountID: accountID, isBeta: isBeta))
        _messages = StateObject(wrappedValue: CareMessageStore(
            accountID: accountID, betaPreferences: betaPreferences, messaging: messaging
        ))
        _profilePhotoData = AppStorage("profilePhoto.\(accountID.uuidString)", store: betaPreferences)
        _hasCompletedAvatarSetup = AppStorage(wrappedValue: false, "hasCompletedAvatarSetup.\(accountID.uuidString)", store: betaPreferences)
        _hasCompletedHealthSetup = AppStorage(wrappedValue: false, "hasCompletedWelcome.\(accountID.uuidString)", store: betaPreferences)
        _hasCompletedProfileSetup = AppStorage(wrappedValue: false, "hasCompletedProfileSetup.\(accountID.uuidString)", store: betaPreferences)
        _hasCompletedDoctorSelection = AppStorage(wrappedValue: false, "hasCompletedDoctorSelection.\(accountID.uuidString)", store: betaPreferences)
        _hasCompletedOnboarding = AppStorage(wrappedValue: false, "hasCompletedTour.\(accountID.uuidString)", store: betaPreferences)
        _chosenDoctorID = AppStorage(wrappedValue: isBeta ? "sofia" : "", "chosenDoctor.\(accountID.uuidString)", store: betaPreferences)
        _healthLinked = AppStorage(wrappedValue: isBeta, "healthLinked.\(accountID.uuidString)", store: betaPreferences)
    }

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var orderedReadings: [HealthReading] {
        health.readings.sorted {
            (metricOrder.firstIndex(of: $0.id) ?? metricOrder.count) < (metricOrder.firstIndex(of: $1.id) ?? metricOrder.count)
        }
    }

    private var launchScreen: LaunchScreen {
        if !hasCompletedAvatarSetup {
            return isBeta || hasLoadedAvatar ? .avatarSetup : .restoringAvatar
        }
        if !hasCompletedHealthSetup { return .appleHealthSetup }
        if !hasCompletedProfileSetup { return .profileSetup }
        if hasCompletedOnboarding { return .dashboard }
        return isBeta && !hasCompletedDoctorSelection ? .doctorSelection : .productTour
    }

    var body: some View {
        let screen = launchScreen
        ZStack {
            switch screen {
            case .restoringAvatar:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(pageBackground.ignoresSafeArea())
                    .transition(.opacity)
            case .avatarSetup:
                AvatarCaptureFlow(isOnboarding: true, save: saveAvatar)
                    .transition(.opacity)
                    .zIndex(2)
            case .appleHealthSetup:
                firstLaunch
                    .transition(.opacity)
                    .zIndex(1)
            case .profileSetup:
                healthProfileEditor(isOnboarding: true)
                    .transition(.opacity)
                    .zIndex(1)
            case .doctorSelection:
                DoctorSelectionView { doctor in
                    finishDoctorSelection(doctor)
                }
                .transition(.opacity)
                .zIndex(1)
            case .productTour:
                productTour
                    .transition(.opacity)
                    .zIndex(1)
            case .dashboard:
                dashboard
                    .accessibilityHidden(isWelcoming)
                    .transition(.opacity)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let step = screen.onboardingStep {
                let canSkip = screen != .restoringAvatar && (screen != .appleHealthSetup || !healthLinked || isBeta)
                OnboardingProgress(step: step, onSkip: canSkip ? { skipOnboardingScreen(screen) } : nil,
                                   includesDoctorSelection: isBeta)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: launchScreen)
        .disabled(isWelcoming)
        .overlay {
            if isWelcoming {
                GeometryReader { geometry in
                    welcomeOverlay(in: geometry)
                }
                .ignoresSafeArea()
            }
        }
        .onPreferenceChange(HomeButtonFramePreference.self) { homeButtonFrame = $0 }
        .task(id: isWelcoming) {
            if isWelcoming { await runWelcomeTransition() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active && isWelcoming { welcomePhase = .idle }
        }
        .tint(accent)
        .preferredColorScheme(.light)
        .task {
            loadHealthProfile()
            if !isBeta {
                do {
                    restoreAvatar(try BodyAvatarFiles.load(for: accountID))
                } catch let error as CocoaError where error.code == .fileReadNoPermission {
                    // Protected data is available again on the next active scene.
                } catch {
                    avatarStorageError = "Den sparade avataren kunde inte öppnas. Du kan skapa en ny."
                }
            }
            hasLoadedAvatar = true
        }
        .task(id: hasCompletedAvatarSetup) {
            guard hasCompletedAvatarSetup else { return }
            await syncAtLaunch()
        }
        .fullScreenCover(isPresented: $showsAvatarCapture) {
            AvatarCaptureFlow(save: saveAvatar)
                .tint(accent)
        }
        .alert("3D-avatar", isPresented: Binding(
            get: { avatarStorageError != nil },
            set: { if !$0 { avatarStorageError = nil } }
        )) {
            Button("OK", role: .cancel) { avatarStorageError = nil }
        } message: {
            Text(avatarStorageError ?? "")
        }
        .task(id: profilePhotoSelection) {
            await saveProfilePhoto(profilePhotoSelection)
        }
        .alert("Profilbilden kunde inte sparas", isPresented: $showsProfilePhotoError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Försök igen eller välj en annan bild.")
        }
        .alert("Visningsnamn", isPresented: $showsProfileNameEditor) {
            TextField("Ditt namn", text: $profileNameDraft)
                .textContentType(.name)
            Button("Spara") {
                let name = profileNameDraft
                Task { showsProfileNameError = !(await updateDisplayName(name)) }
            }
            .disabled(profileNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text("Namnet används i din GoHealth-profil.")
        }
        .alert("Namnet kunde inte sparas", isPresented: $showsProfileNameError) {
            Button("Försök igen") { showsProfileNameEditor = true }
            Button("Avbryt", role: .cancel) {}
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if !isBeta, avatar == nil { restoreAvatar(try? BodyAvatarFiles.load(for: accountID)) }
                if healthProfile == nil { loadHealthProfile() }
                guard hasCompletedAvatarSetup, hasCompletedHealthSetup else { return }
                Task { await syncHealth() }
            }
        }
        .confirmationDialog("Anslut Apple Hälsa", isPresented: $showsHealthLinkConfirmation, titleVisibility: .visible) {
            Button("Anslut till det här kontot") {
                healthLinked = true
                Task { await syncAtLaunch() }
            }
            Button("Avbryt", role: .cancel) {}
        } message: {
            Text(isBeta
                 ? "I Beta-login simuleras anslutningen till Apple Hälsa med en testprofil."
                 : "GoHealth läser dina hälsomätningar och delar automatiskt appens mätvärden och tillgängliga historik med ditt behöriga vårdteam. Nya mätvärden följer också med. Biologiskt kön används för kroppsfiguren. Anslut bara om uppgifterna på den här iPhonen är dina.")
        }
        .onOpenURL { url in
            if url.scheme == "gohealth" && url.host == "recovery" { selectedTab = .recovery }
        }
    }

    private func skipOnboardingScreen(_ screen: LaunchScreen) {
        guard launchScreen == screen else { return }
        switch screen {
        case .avatarSetup: hasCompletedAvatarSetup = true
        case .appleHealthSetup where !healthLinked || isBeta: hasCompletedHealthSetup = true
        case .profileSetup: hasCompletedProfileSetup = true
        case .doctorSelection: finishDoctorSelection(nil)
        case .productTour: finishOnboarding()
        default: break
        }
    }

    private func restoreAvatar(_ model: BodyAvatar?) {
        guard let model else { return }
        avatar = model
        if !hasCompletedAvatarSetup { hasCompletedAvatarSetup = true }
    }

    private func saveAvatar(_ model: BodyAvatar) throws {
        if !isBeta { try BodyAvatarFiles.save(model, for: accountID) }
        avatar = model
        hasCompletedAvatarSetup = true
    }

    private func loadHealthProfile() {
        guard healthProfile == nil else { return }
        do {
            healthProfile = isBeta
                ? HealthProfile(age: 36, biologicalSex: .male, backgroundCountryCode: "SE")
                : try HealthProfileFiles.load(for: accountID)
            profileLoadFailed = false
        } catch {
            profileLoadFailed = true
        }
    }

    @ViewBuilder
    private func healthProfileEditor(isOnboarding: Bool) -> some View {
        if let healthProfile {
            HealthProfileView(profile: healthProfile, isOnboarding: isOnboarding) { updated in
                if !isBeta { try HealthProfileFiles.save(updated, for: accountID) }
                self.healthProfile = updated
                if isOnboarding { hasCompletedProfileSetup = true }
            }
        } else if profileLoadFailed {
            ContentUnavailableView {
                Label("Hälsoprofilen kunde inte öppnas", systemImage: "person.crop.circle.badge.exclamationmark")
            } actions: {
                Button("Försök igen", action: loadHealthProfile).buttonStyle(.borderedProminent)
                if isOnboarding {
                    Button("Fortsätt till visningen") { hasCompletedProfileSetup = true }
                }
            }
        } else {
            ProgressView("Öppnar hälsoprofilen…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(pageBackground.ignoresSafeArea())
        }
    }

    private var dashboard: some View {
        VStack(spacing: 0) {
            NavigationStack {
                Group {
                    switch selectedTab {
                    case .home: homePage
                    case .activity: activityPage
                    case .measurements: measurementsPage
                    case .recovery:
                        HealthGradePreview(firstName: givenName, immersive: $gradeImmersive) {
                            if let avatar {
                                BodyAvatarDisplay(avatar: avatar, showMarkers: false) { _ in EmptyView() }
                                    .id(avatar.id)
                            } else {
                                bodyDiagram(standardAppearance ?? .male, showsMarkers: false)
                            }
                        } measurements: {
                            HealthSummaryView(
                                health: health, vaccinations: vaccinations, healthLinked: healthLinked,
                                age: healthProfile?.age, isBeta: isBeta, imagingToken: imagingAccessToken,
                                connect: { showsHealthLinkConfirmation = true },
                                refreshHealth: syncHealth,
                                openVaccinations: { showSummarySource(.vaccinations) },
                                openImaging: { showSummarySource(.imaging) }
                            )
                        }
                    case .more: morePage
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            }
            .id(selectedTab)
            .allowsHitTesting(homePanel != .messages)
            .accessibilityHidden(homePanel == .messages)
            .overlay {
                if homePanel == .messages {
                    GeometryReader { geometry in
                        homePanelReveal(.messages, size: geometry.size) {
                            CareMessageCenter(store: messages, close: closeHomePanel)
                        }
                    }
                    .transition(.identity)
                }
            }
            .coordinateSpace(name: HomePanel.messages.coordinateSpace)

            if !gradeImmersive {
                tabBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onChange(of: selectedTab) { _, _ in gradeImmersive = false }
        .task(id: scenePhase) {
            if scenePhase == .active && !isBeta { await messages.refreshWhileActive() }
        }
        .task(id: scenePhase) {
            guard scenePhase == .active, !isBeta else { return }
            await clinical.refresh()
            if healthLinked { clinical.attach(to: health); await clinical.sync() }
        }
        .onReceive(clinical.$records) { vaccinations.setCareTeam($0) }
        .onPreferenceChange(HomePanelFramePreference.self) { frames in
            if homePanel == nil {
                homePanelFrames.merge(frames.filter { !$0.value.isEmpty }, uniquingKeysWith: { _, newest in newest })
            }
        }
    }

    private var firstLaunch: some View {
        GoHealthLaunchView(
            title: healthLinked && !isBeta ? "Hämtar dina hälsodata" : "Din hälsa i GoHealth",
            detail: isBeta
                ? "Testprofilen är fylld med mätvärden och historik så att du kan utforska GoHealth."
                : (healthLinked
                   ? "Läser tillgängliga mätningar och förbereder din kroppsöversikt."
                   : "Anslut Apple Hälsa för att läsa dina mätningar och visa din kroppsöversikt."),
            isLoading: healthLinked && !isBeta
        ) {
            if isBeta {
                Button("Fortsätt med testdata") { hasCompletedHealthSetup = true }
                    .buttonStyle(.borderedProminent)
            } else if !healthLinked {
                Button("Anslut Apple Hälsa") { showsHealthLinkConfirmation = true }
                    .buttonStyle(.borderedProminent)
                Button("Fortsätt utan Apple Hälsa") { hasCompletedHealthSetup = true }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func syncAtLaunch() async {
        guard healthLinked else { return }
        await syncHealth()
        if !isBeta && !Task.isCancelled { hasCompletedHealthSetup = true }
    }

    private func syncHealth() async {
        guard healthLinked, !health.isLoading else { return }
        clinical.attach(to: health)
        await health.connect()
        await clinical.sync()
        refreshBodyAppearance()
    }

    private func refreshBodyAppearance() {
        guard healthLinked else { return }
        healthBodyAppearance = switch health.biologicalSexForBodyFigure() {
        case .female?: .female
        case .male?: .male
        default: nil
        }
    }

    private var connectHealthPrompt: some View {
        ContentUnavailableView {
            Label("Anslut Apple Hälsa", systemImage: "heart.text.square")
        } description: {
            Text("Visa mätningar från den här iPhonen i din profil.")
        } actions: {
            Button("Anslut") { showsHealthLinkConfirmation = true }
                .buttonStyle(.borderedProminent)
        }
    }

    private var tabBar: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(DashboardTab.allCases, id: \.self) { tab in
                    let selected = selectedTab == tab
                    Button {
                        if tab != .home {
                            homePanelSession = UUID()
                            homePanel = nil
                            homePanelProgress = 0
                            homePanelIsClosing = false
                        } else {
                            closeHomePanel()
                        }
                        selectedTab = tab
                        if tab == .home {
                            selectOrgan(nil)
                            refreshBodyAppearance()
                        }
                    } label: {
                        VStack(spacing: 5) {
                            if tab == .home {
                                homeNavigationIcon(selected: selected)
                            } else {
                                Image(systemName: tab.symbol)
                                    .font(.system(size: 21, weight: selected ? .semibold : .regular))
                                    .symbolVariant(selected ? .fill : .none)
                                    .frame(height: 24)
                            }
                            Text(tab.title)
                                .font(.caption2.weight(selected ? .semibold : .medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                        }
                        .foregroundStyle(selected ? accent : Color.secondary)
                        .frame(maxWidth: .infinity, minHeight: 52)
                        .padding(.horizontal, 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(tab.title)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 3)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: selectedTab)
        }
        .background {
            NavigationBarSurface()
                .fill(.white)
                .ignoresSafeArea(edges: .bottom)
        }
        .overlay(alignment: .top) {
            NavigationBarTopEdge()
                .stroke(Color(uiColor: .separator).opacity(0.45), lineWidth: 0.5)
                .frame(height: 1)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func homeNavigationIcon(selected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(.white)
            Circle()
                .strokeBorder(homeGradient, lineWidth: selected ? 2.4 : 2)
                .opacity(selected ? 1 : 0.65)
            SoftHomeGlyph()
                .stroke(style: StrokeStyle(lineWidth: selected ? 1.9 : 1.7, lineCap: .round, lineJoin: .round))
                .frame(width: 21, height: 21)
        }
        .frame(width: 36, height: 36)
        .background {
            GeometryReader { geometry in
                Color.clear.preference(key: HomeButtonFramePreference.self,
                                       value: geometry.frame(in: .global))
            }
        }
        .opacity(isWelcoming && welcomePhase != .revealed ? 0 : 1)
        .offset(y: -5)
        .frame(height: 24)
        .accessibilityHidden(true)
    }

    private var profileHeader: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if let profilePhotoData, let photo = UIImage(data: profilePhotoData) {
                        Image(uiImage: photo).resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.fill")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(accent.opacity(0.08))
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
                .accessibilityHidden(true)

                Text(displayName ?? "GoHealth")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 8) {
                    if isBeta, let doctor = DemoDoctor(rawValue: chosenDoctorID) {
                        DoctorPortrait(doctor: doctor, size: 30)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Vald läkare: \(doctor.name)")
                    }

                    CareMessageIcon(count: messages.current.count, open: openMessageCenter)
                        .background {
                            GeometryReader { geometry in
                                Color.clear.preference(key: HomePanelFramePreference.self, value: [
                                    .messages: geometry.frame(in: .named(HomePanel.messages.coordinateSpace))
                                ])
                            }
                        }
                        .disabled(homePanel != nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 6)
            Divider()
        }
        .background { Color.white.ignoresSafeArea(edges: .top) }
    }

    private var homePage: some View {
        let notice = scenePhase == .active && homePanel == nil && selectedOrgan == nil ? messages.notice : nil
        let visibleNotice = hiddenHomeNoticeID == notice?.id ? nil : notice
        let bodyTopPadding = homeBodyTopPadding(showsNotice: visibleNotice != nil)
        return VStack(spacing: 0) {
            profileHeader

            GeometryReader { geometry in
                ZStack {
                    ScrollView {
                        bodyStage(size: homeBodyStageSize(in: geometry.size, topPadding: bodyTopPadding), usesDemoData: isBeta,
                                  bottomPadding: hasBodyFigure ? 2 : 14) {
                            bodyCard(topPadding: bodyTopPadding)
                        }
                    }
                    .scrollBounceBehavior(.always)
                    .refreshable { await syncHealth() }
                    .allowsHitTesting(homePanel == nil)
                    .accessibilityHidden(homePanel != nil)

                    Group {
                        switch homePanel {
                        case .imaging:
                            homePanelReveal(.imaging, size: geometry.size) {
                                RadiologyView(isBeta: isBeta, token: imagingAccessToken, clinical: clinical, embedded: true, close: closeHomePanel)
                            }
                        case .vaccinations:
                            homePanelReveal(.vaccinations, size: geometry.size) {
                                VaccinationView(store: vaccinations, close: closeHomePanel)
                            }
                        case .messages, nil:
                            EmptyView()
                        }
                    }
                    .zIndex(2)
                    .transition(.identity)
                }
                .coordinateSpace(name: HomePanel.imaging.coordinateSpace)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if let notice = visibleNotice {
                        CareMessageNotice(firstName: givenName, message: notice, isBeta: isBeta,
                                          open: openMessageCenter, dismiss: messages.dismissNotice)
                            .frame(width: max(0, min(224, (geometry.size.width / 2 - 28) * 1.3)))
                            .padding(.trailing, 12)
                            .padding(.top, 7)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { homeNoticeHeight = $0 }
                            .transition(reduceMotion ? .opacity : .offset(y: -4).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: hiddenHomeNoticeID)
            }
        }
        .background(pageBackground)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: notice?.id)
        .task(id: notice?.id) {
            hiddenHomeNoticeID = nil
            guard let notice else { return }
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(10))
                    try Task.checkCancellation()
                    hiddenHomeNoticeID = hiddenHomeNoticeID == notice.id ? nil : notice.id
                }
            } catch {
                // Stop when Home no longer presents this notice.
            }
        }
        .navigationTitle("Hem")
        .toolbar(.hidden, for: .navigationBar)
    }

    private var productTour: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Kom igång").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                    Text("Tryck på ett organ för att se exempel på mätvärden, historik och betyg.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 20)

                bodyStage(size: CGSize(width: geometry.size.width, height: max(360, geometry.size.height - 185)),
                          usesDemoData: true) {
                    Group {
                        if let avatar {
                            BodyAvatarDisplay(avatar: avatar) { organ in
                                organMarker(organ)
                                    .opacity(selectedOrgan == nil ? 1 : 0)
                            }
                        } else {
                            bodyDiagram(standardAppearance ?? .male)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: beginWelcomeTransition) {
                    HStack(spacing: 12) {
                        Text("Kom igång")
                        Image(systemName: "arrow.right")
                            .accessibilityHidden(true)
                    }
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 420, minHeight: 54)
                    .background(LinearGradient(
                        colors: [accent, Color(red: 0.84, green: 0.13, blue: 0.52),
                                 Color(red: 0.97, green: 0.36, blue: 0.25)],
                        startPoint: .leading, endPoint: .trailing
                    ), in: Capsule())
                    .overlay { Capsule().strokeBorder(.white.opacity(0.18), lineWidth: 1) }
                    .shadow(color: accent.opacity(0.16), radius: 10, y: 4)
                }
                .buttonStyle(.plain)
                .accessibilityHint("Öppnar din personliga hälsoöversikt")
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
        .background(pageBackground.ignoresSafeArea())
    }

    private func finishDoctorSelection(_ doctor: DemoDoctor?) {
        chosenDoctorID = doctor?.id ?? ""
        hasCompletedDoctorSelection = true
    }

    private func finishOnboarding() {
        selectedOrgan = nil
        selectedTab = .home
        hasCompletedOnboarding = true
    }

    private func beginWelcomeTransition() {
        guard !isWelcoming, !hasCompletedOnboarding else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            welcomeDestination = .zero
            welcomeProgress = 0
            welcomeMessage = "Öppnar din hälsoöversikt"
            homeButtonFrame = .zero
            welcomePhase = .preparing
            finishOnboarding()
        }
    }

    @MainActor
    private func runWelcomeTransition() async {
        do {
            if reduceMotion {
                // Keep the preparation visible, without travel or expanding motion.
                welcomePhase = .centered
                try await Task.sleep(for: .milliseconds(450))
                welcomeProgress = 0.5
                try await Task.sleep(for: .milliseconds(450))
                welcomeProgress = 1
                welcomeMessage = "Välkommen hem"
                try await Task.sleep(for: .milliseconds(350))
                withAnimation(.easeOut(duration: 0.35)) { welcomePhase = .revealed }
                try await Task.sleep(for: .milliseconds(360))
            } else {
                // Wait briefly for the actual destination to finish its first layout.
                for _ in 0..<30 where homeButtonFrame.isEmpty {
                    try await Task.sleep(for: .milliseconds(16))
                }
                try Task.checkCancellation()
                guard !homeButtonFrame.isEmpty else {
                    welcomePhase = .idle
                    return
                }
                welcomeDestination = homeButtonFrame
                withAnimation(.spring(duration: 0.8, bounce: 0.05)) { welcomePhase = .centered }
                try await Task.sleep(for: .milliseconds(800))
                // This ring tracks the welcome sequence, not a network upload.
                withAnimation(.easeInOut(duration: 2.6)) { welcomeProgress = 1 }
                try await Task.sleep(for: .milliseconds(2600))
                withAnimation(.easeInOut(duration: 0.3)) { welcomeMessage = "Välkommen hem" }
                try await Task.sleep(for: .milliseconds(650))
                withAnimation(.timingCurve(0.55, 0, 0.20, 1, duration: 1.15)) { welcomePhase = .docked }
                try await Task.sleep(for: .milliseconds(1400))
                withAnimation(.easeInOut(duration: 1.15)) { welcomePhase = .revealed }
                try await Task.sleep(for: .milliseconds(1180))
            }
            welcomePhase = .idle
        } catch {
            // Cancellation must always leave the completed dashboard usable.
            welcomePhase = .idle
        }
    }

    private func welcomeOverlay(in geometry: GeometryProxy) -> some View {
        let origin = geometry.frame(in: .global).origin
        let destination = welcomeDestination.offsetBy(dx: -origin.x, dy: -origin.y)
        let target = CGPoint(x: destination.midX, y: destination.midY)
        let docked = welcomePhase == .docked || welcomePhase == .revealed
        let center = docked ? target : CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
        let diameter: CGFloat = docked ? max(36, destination.width) : 88
        let radius = hypot(max(target.x, geometry.size.width - target.x),
                           max(target.y, geometry.size.height - target.y)) + 24
        return ZStack {
            Color.white
                .mask {
                    WelcomeRevealMask(center: target, radius: welcomePhase == .revealed && !reduceMotion ? radius : 0)
                        .fill(.black, style: FillStyle(eoFill: true))
                }
                .opacity(welcomePhase == .revealed && reduceMotion ? 0 : 1)

            ZStack {
                Circle()
                    .strokeBorder(accent.opacity(0.10), lineWidth: 2.5)
                Circle()
                    .trim(from: 0, to: welcomeProgress)
                    .stroke(homeGradient, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 112, height: 112)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            .opacity(welcomePhase == .centered ? 1 : 0)

            VStack(spacing: 9) {
                Text(welcomeMessage)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .contentTransition(.opacity)
                Text("Din hälsa, samlad på ett ställe.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
            .frame(width: geometry.size.width)
            .position(x: geometry.size.width / 2, y: geometry.size.height / 2 + 112)
            .opacity(welcomePhase == .centered ? 1 : 0)

            ZStack {
                Circle().fill(homeGradient).opacity(docked ? 0 : 1)
                Circle().strokeBorder(homeGradient, lineWidth: docked ? 2.4 : 4)
                SoftHomeGlyph()
                    .stroke(accent, style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
                    .frame(width: 21, height: 21)
                    .opacity(docked ? 1 : 0)
            }
            .frame(width: diameter, height: diameter)
            .scaleEffect(welcomePhase == .preparing ? 0.65 : 1)
            .shadow(color: accent.opacity(docked ? 0 : 0.20), radius: 24, y: 8)
            .position(center)
            .opacity(welcomePhase == .preparing || welcomePhase == .revealed ? 0 : 1)
        }
        .frame(width: geometry.size.width, height: geometry.size.height)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(welcomeMessage)
    }

    private var hasBodyFigure: Bool { avatar != nil || standardAppearance != nil }

    private func homeBodyTopPadding(showsNotice: Bool) -> CGFloat {
        guard hasBodyFigure else { return 16 }
        let minimumPadding: CGFloat = avatar == nil ? 12 : 40
        let noticeClearance = showsNotice ? homeNoticeHeight + 4 - Self.bodyStageTopPadding : 0
        return max(minimumPadding, noticeClearance)
    }

    private func homeBodyStageSize(in viewport: CGSize, topPadding: CGFloat) -> CGSize {
        guard hasBodyFigure else { return viewport }
        return CGSize(width: viewport.width,
                      height: max(viewport.height, Self.bodyStageTopPadding + topPadding + 230))
    }

    private func bodyStage<Figure: View>(size: CGSize, usesDemoData: Bool, bottomPadding: CGFloat = 14,
                                        @ViewBuilder figure: () -> Figure) -> some View {
        let width = size.width
        // Keep a full-size touch target for every organ beside the open panel.
        let panelWidth = min(500, max(0, width - 76), width * (dynamicTypeSize.isAccessibilitySize ? 0.94 : 0.82))
        let showsOrgan = selectedOrgan != nil
        return ZStack(alignment: .topTrailing) {
            figure()
                .frame(width: min(540, max(0, width - 40)),
                       height: max(0, size.height - Self.bodyStageTopPadding - bottomPadding))
                .frame(maxWidth: .infinity)
                .offset(x: showsOrgan ? -panelWidth * 0.49 : 0)
                .allowsHitTesting(!showsOrgan)
                .accessibilityHidden(showsOrgan)

            if let organ = selectedOrgan {
                OrganOverview(
                    organ: organ,
                    metrics: usesDemoData && !isBeta ? organ.demoMetrics : organMetrics(organ),
                    isDemo: usesDemoData,
                    healthLinked: healthLinked,
                    isLoading: health.isLoading,
                    close: { selectOrgan(nil) },
                    connectHealth: { showsHealthLinkConfirmation = true }
                )
                .id(organ)
                .frame(width: panelWidth)
                .padding(.trailing, 10)
                .transition(.offset(x: 24).combined(with: .opacity))
                .zIndex(1)
            }
        }
        .padding(.top, Self.bodyStageTopPadding)
        .padding(.bottom, bottomPadding)
        .background {
            if showsOrgan {
                Button {
                    selectOrgan(nil)
                } label: {
                    Color.clear
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Återgå till kroppsöversikten")
            }
        }
        .overlay(alignment: .topLeading) {
            if showsOrgan {
                VStack(spacing: 12) {
                    ForEach(BodyOrgan.allCases, id: \.self) { organ in
                        organMarker(organ)
                    }
                }
                .padding(.top, 100)
                .padding(.leading, 6)
            }
        }
        .clipped()
    }

    private func bodyCard(topPadding: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let avatar {
                BodyAvatarDisplay(avatar: avatar) { organ in
                    organMarker(organ)
                        .opacity(selectedOrgan == nil ? 1 : 0)
                }
                .id(avatar.id)
                .layoutPriority(-1)

                Text("Dra åt sidan för att rotera.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .opacity(selectedOrgan == nil ? 1 : 0)
            } else {
                standardBodyCard
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, topPadding)
        .padding(.bottom, avatar != nil ? 6 : hasBodyFigure ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .bottomLeading) {
            if selectedOrgan == nil {
                homeShortcut(.vaccinations, title: "Vaccination", symbol: "syringe", iconSize: 26,
                             hint: "Öppnar din vaccinationshistorik")
                    .padding(.leading, 10)
                    .padding(.bottom, 36)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if selectedOrgan == nil {
                homeShortcut(.imaging, title: "Röntgen", symbol: "viewfinder", iconSize: 36,
                             hint: "Öppnar dina bildserier och undersökningar")
                    .padding(.trailing, 10)
                    .padding(.bottom, 36)
            }
        }
    }

    private func homeShortcut(_ panel: HomePanel, title: String, symbol: String, iconSize: CGFloat, hint: String) -> some View {
        Button { openHomePanel(panel) } label: {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: iconSize, weight: .regular))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(red: 0.28, green: 0.12, blue: 0.32),
                                 Color(red: 0.53, green: 0.10, blue: 0.32),
                                 Color(red: 0.70, green: 0.28, blue: 0.20)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 44, height: 44)
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: HomePanelFramePreference.self,
                                                   value: [panel: geometry.frame(in: .named(panel.coordinateSpace))])
                        }
                    }
                    .accessibilityHidden(true)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: 100, height: 80)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(hint)
    }

    private func showSummarySource(_ panel: HomePanel) {
        selectedTab = .home
        openHomePanel(panel)
    }

    private func openMessageCenter() {
        messages.dismissNotice()
        openHomePanel(.messages)
    }

    private func openHomePanel(_ panel: HomePanel) {
        guard homePanel == nil else { return }
        homePanelSession = UUID()
        homePanelProgress = 0
        homePanelIsClosing = false
        homePanel = panel
    }

    private func closeHomePanel() {
        guard homePanel != nil, !homePanelIsClosing else { return }
        homePanelIsClosing = true
        let session = homePanelSession
        withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.4, 0, 0.2, 1, duration: 0.55)) {
            homePanelProgress = 0
        } completion: {
            if homePanelSession == session { homePanel = nil }
        }
    }

    private func homePanelReveal<Panel: View>(_ panel: HomePanel, size: CGSize, @ViewBuilder content: () -> Panel) -> some View {
        let iconFrame = homePanelFrames[panel] ?? .zero
        let origin = CGPoint(x: min(size.width, max(0, iconFrame.midX)),
                             y: min(size.height, max(0, iconFrame.midY)))
        let horizontal = max(origin.x, size.width - origin.x)
        let vertical = max(origin.y, size.height - origin.y)
        let diameter = (horizontal * horizontal + vertical * vertical).squareRoot() * 2 + 4
        let anchor = UnitPoint(x: origin.x / max(1, size.width), y: origin.y / max(1, size.height))

        return content()
            .frame(width: size.width, height: size.height)
            .background(pageBackground)
            .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * homePanelProgress, anchor: anchor)
            .opacity(homePanelProgress)
            .mask {
                if reduceMotion {
                    Rectangle()
                } else {
                    Circle()
                        .frame(width: 44 + (diameter - 44) * homePanelProgress,
                               height: 44 + (diameter - 44) * homePanelProgress)
                        .position(origin)
                }
            }
            .task(id: homePanelSession) {
                let session = homePanelSession
                await Task.yield()
                guard !Task.isCancelled, homePanel == panel, homePanelSession == session, !homePanelIsClosing else { return }
                withAnimation(reduceMotion ? .easeOut(duration: 0.2) : .timingCurve(0.2, 0.7, 0.15, 1, duration: 0.85)) {
                    homePanelProgress = 1
                }
            }
    }

    private var standardAppearance: BodyAppearance? {
        if let healthBodyAppearance { return healthBodyAppearance }
        return switch healthProfile?.biologicalSex {
        case .female?: .female
        case .male?: .male
        default: isBeta ? .male : nil
        }
    }

    @ViewBuilder
    private var standardBodyCard: some View {
        if let appearance = standardAppearance {
            bodyDiagram(appearance, alignsToBottom: true)
                .layoutPriority(-1)
        } else if !healthLinked {
            connectHealthPrompt
        } else if health.isLoading {
            ProgressView("Förbereder kroppsöversikten…")
                .frame(maxWidth: .infinity, minHeight: 140)
        } else {
            ContentUnavailableView(
                "Standardfiguren kan inte visas",
                systemImage: "person.crop.circle",
                description: Text("Ange biologiskt kön i din hälsoprofil eller dela uppgiften från Apple Hälsa för att visa standardfiguren.")
            )
        }
    }

    private func bodyDiagram(_ appearance: BodyAppearance, alignsToBottom: Bool = false,
                             showsMarkers: Bool = true) -> some View {
        GeometryReader { geometry in
            let center = geometry.size.width / 2
            // Each figure fits within the central 40% of the image height in width.
            // The extra width in each portrait is blank margin.
            // The lowest 3% of the illustration is blank below both pairs of shoes.
            let visibleFraction = alignsToBottom ? 0.97 : 1.0
            let height = min(geometry.size.height / visibleFraction, geometry.size.width / 0.4)
            let top = alignsToBottom ? geometry.size.height - height * visibleFraction : (geometry.size.height - height) / 2
            ZStack {
                RadialGradient(
                    colors: [accent.opacity(0.09), .white],
                    center: .center,
                    startRadius: 0,
                    endRadius: height * 0.52
                )
                .accessibilityHidden(true)
                .allowsHitTesting(false)

                // The two portraits are side by side in a 3:2 image.
                Image("BodyFigures")
                    .resizable()
                    .frame(width: height * 1.5, height: height)
                    .offset(x: height * (appearance == .female ? 0.375 : -0.375))
                    .frame(width: height * 0.75, height: height)
                    .clipped()
                    .frame(width: geometry.size.width, height: height)
                    .position(x: center, y: top + height / 2)
                    .blendMode(.multiply)
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)

                if showsMarkers {
                    ForEach(BodyOrgan.allCases, id: \.self) { organ in
                        organMarker(organ)
                            .opacity(selectedOrgan == nil ? 1 : 0)
                            .position(
                                x: center + height * organ.markerPosition.x,
                                y: top + height * organ.markerPosition.y
                            )
                    }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .clipped()
        }
    }

    private func organMarker(_ organ: BodyOrgan) -> some View {
        Button {
            selectOrgan(organ)
        } label: {
            OrganGlyph(organ: organ)
                .stroke(organColor(organ), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                .frame(width: 21, height: 21)
                .frame(width: 34, height: 34)
                .background(.white, in: Circle())
                .overlay { Circle().strokeBorder(organColor(organ).opacity(0.35)) }
                .frame(width: 46, height: 46)
                .background(organColor(organ).opacity(0.22), in: Circle())
                .overlay {
                    if selectedOrgan == organ {
                        Circle().strokeBorder(organColor(organ), lineWidth: 2)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(organ.title)
        .accessibilityAddTraits(selectedOrgan == organ ? .isSelected : [])
        .accessibilityHint("Öppnar organets översikt")
    }

    private func organColor(_ organ: BodyOrgan) -> Color {
        switch organ {
        case .heart: accent
        case .liver: Color(red: 0.58, green: 0.35, blue: 0.12)
        case .lungs: Color(red: 0.06, green: 0.49, blue: 0.49)
        case .kidneys: Color(red: 0.24, green: 0.39, blue: 0.72)
        case .thyroid: Color(red: 0.48, green: 0.29, blue: 0.70)
        }
    }

    private func selectOrgan(_ organ: BodyOrgan?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.5)) {
            selectedOrgan = organ
        }
    }

    private func organMetrics(_ organ: BodyOrgan) -> [OrganMetric] {
        var metrics = isBeta ? organ.demoMetrics : organ.demoMetrics.map(\.withoutDemoData)

        for index in metrics.indices {
            switch metrics[index].id {
            case "heart-rate":
                metrics[index].source = "Senaste puls · Apple Hälsa"
                if healthLinked {
                    metrics[index].samples = health.heartRateHistory.prefix(7).reversed().map(\.beatsPerMinute)
                }
            case "resting-heart-rate":
                metrics[index].source = "Senaste mätning · Apple Hälsa"
                if healthLinked {
                    metrics[index].samples = health.restingHeartRateHistory.prefix(7).reversed().map(\.beatsPerMinute)
                }
            case "hrv", "respiratory-rate", "oxygen", "vo2-max", "fev1", "fvc", "fev1-fvc", "pef":
                let id = metrics[index].id
                switch id {
                case "hrv": metrics[index].source = "SDNN · Apple Hälsa"
                case "vo2-max": metrics[index].source = "Kondition · Apple Hälsa"
                case "fev1", "fvc": metrics[index].source = "Spirometri · Apple Hälsa"
                case "fev1-fvc": metrics[index].source = "Beräknad från matchande mätningar"
                case "pef": metrics[index].source = "Utandningsflöde · Apple Hälsa"
                default: metrics[index].source = "Apple Hälsa"
                }
                if healthLinked {
                    let samples = health.metricHistory[id, default: []].prefix(7).reversed().compactMap(\.numericValue)
                    metrics[index].samples = id == "oxygen" ? samples.map { $0 * 100 } : samples
                }
            default:
                break
            }
            if !isBeta {
                let matches = clinical.records.filter { $0.kind == "lab" }.compactMap { record -> (ClinicalRecord, ClinicalObservation)? in
                    guard let observation = record.payload.observations?.first(where: { $0.code == metrics[index].id }) else { return nil }
                    return (record, observation)
                }.sorted { ($0.0.payload.date ?? .distantPast) > ($1.0.payload.date ?? .distantPast) }
                if let latest = matches.first {
                    metrics[index].source = latest.0.payload.source
                    metrics[index].sampledAt = latest.0.payload.date
                    metrics[index].clinicalObservation = latest.1
                    metrics[index].samples = matches.filter { $0.1.unit == latest.1.unit }.reversed().compactMap { $0.1.numericValue }
                }
            }
            if isBeta, health.metricHistory[metrics[index].id] != nil {
                metrics[index].source = "Testdata · Betaprofil"
                metrics[index].demoStatus = nil
            }
        }
        return metrics
    }

    private func saveProfilePhoto(_ selection: PhotosPickerItem?) async {
        guard let selection else { return }
        defer {
            if !Task.isCancelled && profilePhotoSelection == selection {
                profilePhotoSelection = nil
            }
        }

        let data = try? await selection.loadTransferable(type: Data.self)
        guard !Task.isCancelled, profilePhotoSelection == selection else { return }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 256
        ]
        guard let data,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let jpeg = UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.85) else {
            showsProfilePhotoError = true
            return
        }
        profilePhotoData = jpeg
    }

    private var activityPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Aktivitet idag").font(.title3.bold())
                let activity = health.readings(in: "Aktivitet idag")
                if !healthLinked {
                    connectHealthPrompt
                } else if activity.isEmpty && health.workouts.isEmpty {
                    ContentUnavailableView("Ingen aktivitet ännu", systemImage: "figure.walk")
                }
                measurementGrid(activity)
                workoutSection
            }
            .padding(20)
        }
        .background(pageBackground)
        .refreshable { await syncHealth() }
        .navigationTitle("Aktivitet")
    }

    private var measurementsPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Dina mätvärden")
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                if !healthLinked {
                    connectHealthPrompt
                } else if health.readings.isEmpty {
                    if health.isLoading {
                        ProgressView("Hämtar mätvärden…")
                            .frame(maxWidth: .infinity)
                    } else {
                        ContentUnavailableView(
                            "Inga mätningar ännu",
                            systemImage: "heart.text.square",
                            description: Text("Kontrollera GoHealths åtkomst i Apple Hälsa och att dina enheter har synkroniserat.")
                        )
                    }
                } else {
                    measurementGrid(orderedReadings)
                }

                if healthLinked {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(health.message).font(.footnote)
                        Text(isBeta
                             ? "Testvärdena visar hur din översikt och historik fungerar."
                             : "Värdena är inte en medicinsk bedömning. Apple Hälsa kan innehålla data från flera enheter och appar; källan visas under varje mätning.")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .background(pageBackground)
        .refreshable { await syncHealth() }
        .navigationTitle("Mätvärden")
    }

    private var historyPage: some View {
        List(orderedReadings) { reading in
            NavigationLink {
                historyView(for: reading)
            } label: {
                Label {
                    Text(reading.title)
                } icon: {
                    Image(systemName: reading.icon)
                        .foregroundStyle(metricColor(reading))
                }
            }
        }
        .overlay {
            if !healthLinked {
                connectHealthPrompt
            } else if health.readings.isEmpty {
                ContentUnavailableView("Ingen historik ännu", systemImage: "calendar")
            }
        }
        .refreshable { await syncHealth() }
        .navigationTitle("Historik")
    }

    private var morePage: some View {
        ScrollView {
            VStack(spacing: 12) {
                NavigationLink {
                    ClinicalRecordsView(store: clinical)
                } label: {
                    moreTile("Svar från vårdteamet", symbol: "cross.case")
                }
                Button {
                    showsDoctorProfile = true
                } label: {
                    moreTile("Välj läkare", symbol: "stethoscope")
                }
                NavigationLink {
                    RadiologyView(isBeta: isBeta, token: imagingAccessToken, clinical: clinical)
                } label: {
                    moreTile("Röntgen", symbol: "viewfinder")
                }
                NavigationLink {
                    historyPage
                } label: {
                    moreTile("Historik", symbol: "calendar")
                }
                NavigationLink {
                    settingsPage
                } label: {
                    moreTile("Inställningar", symbol: "gearshape")
                }
            }
            .buttonStyle(.plain)
            .padding(20)
        }
        .background(pageBackground)
        .navigationTitle("Mer")
        .sheet(isPresented: $showsDoctorProfile) {
            DoctorProfileSheet(chosenDoctorID: $chosenDoctorID, isBeta: isBeta) {
                showsDoctorProfile = false
            }
            .tint(accent)
        }
    }

    private func moreTile(_ title: String, symbol: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.title3.weight(.semibold))
                .foregroundStyle(accent)
                .frame(width: 44, height: 44)
                .background(accent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            Text(title)
                .font(.headline)
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(16)
        .foregroundStyle(.primary)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .contentShape(Rectangle())
    }

    private var settingsPage: some View {
        List {
            Section("Konto") {
                if let email { Text(email).textSelection(.enabled) }
                if isBeta { Text("Beta-login").foregroundStyle(.secondary) }
                if !isBeta {
                    Button("Sätt eller byt lösenord") { showsPasswordEditor = true }
                        .disabled(isDeletingAccount)
                }
                Button("Logga ut") { Task { await signOut() } }
                    .disabled(isDeletingAccount)
                if !isBeta {
                    Button(role: .destructive) {
                        showsAccountDeletion = true
                    } label: {
                        HStack {
                            Text("Radera konto")
                            if isDeletingAccount { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(isDeletingAccount)
                    .confirmationDialog("Radera ditt GoHealth-konto?", isPresented: $showsAccountDeletion, titleVisibility: .visible) {
                        Button("Radera konto", role: .destructive) {
                            Task {
                                isDeletingAccount = true
                                let deleted = await deleteAccount()
                                isDeletingAccount = false
                                if !deleted { showsAccountDeletionError = true }
                            }
                        }
                        Button("Avbryt", role: .cancel) {}
                    } message: {
                        Text("Din inloggning, profil, avatar och sparade data på den här iPhonen raderas permanent. Det går inte att ångra. Om du är registrerad hos en mottagning sparar vårdgivaren din journal enligt patientdatalagen. Dina data i Apple Hälsa påverkas inte.")
                    }
                }
            }
            .sheet(isPresented: $showsPasswordEditor) {
                PasswordSetupSheet(save: setPassword) { passwordSaved = true }
                    .presentationDetents([.medium])
            }
            .alert("Lösenordet är sparat", isPresented: $passwordSaved) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Nästa gång kan du logga in med din e-postadress och ditt lösenord.")
            }
            .alert("Kontot kunde inte raderas", isPresented: $showsAccountDeletionError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Kontrollera anslutningen och försök igen.")
            }
            Section("Profil") {
                NavigationLink("Hälsoprofil") {
                    healthProfileEditor(isOnboarding: false)
                }
                Button {
                    profileNameDraft = displayName ?? ""
                    showsProfileNameEditor = true
                } label: {
                    LabeledContent("Visningsnamn", value: displayName ?? "Ange namn")
                }
                PhotosPicker(selection: $profilePhotoSelection, matching: .images) {
                    HStack(spacing: 12) {
                        Group {
                            if let profilePhotoData, let photo = UIImage(data: profilePhotoData) {
                                Image(uiImage: photo).resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle").font(.title2)
                            }
                        }
                        .frame(width: 36, height: 36)
                        .clipShape(Circle())
                        .accessibilityHidden(true)
                        Text(profilePhotoData == nil ? "Välj profilbild" : "Byt profilbild")
                    }
                }
                if profilePhotoData != nil {
                    Button("Ta bort profilbild", role: .destructive) {
                        profilePhotoSelection = nil
                        profilePhotoData = nil
                    }
                }
            }
            Section("3D-avatar") {
                Button(avatar == nil ? "Skapa 3D-avatar" : "Skapa en ny 3D-avatar") { showsAvatarCapture = true }
                if avatar != nil {
                    Button("Återställ till originalavatar", role: .destructive) { showsAvatarRemoval = true }
                        .confirmationDialog("Återställa originalavataren?", isPresented: $showsAvatarRemoval, titleVisibility: .visible) {
                            Button("Återställ", role: .destructive) {
                                do {
                                    if !isBeta { try BodyAvatarFiles.remove(for: accountID) }
                                    avatar = nil
                                } catch {
                                    avatarStorageError = "Originalavataren kunde inte återställas. Försök igen."
                                }
                            }
                            Button("Avbryt", role: .cancel) {}
                        } message: {
                            Text("GoHealth visar originalavataren igen. Din sparade 3D-avatar tas bort från den här iPhonen.")
                        }
                }
            }
            Section("Apple Hälsa") {
                if healthLinked {
                    Button {
                        Task { await syncHealth() }
                    } label: {
                        Label("Uppdatera mätningar", systemImage: "arrow.clockwise")
                    }
                    .disabled(health.isLoading)
                    Text(health.message).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button("Anslut Apple Hälsa") { showsHealthLinkConfirmation = true }
                }
            }
            Section("Om GoHealth") {
                NavigationLink("Visa syntetiskt exempel") {
                    RecoveryDemoView(health: health, scope: isBeta ? .beta : .demo)
                        .navigationTitle("Återhämtning · Demo")
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }
        .navigationTitle("Inställningar")
    }

    private func measurementGrid(_ readings: [HealthReading]) -> some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(readings) { reading in
                NavigationLink {
                    historyView(for: reading)
                        .toolbar(.visible, for: .navigationBar)
                } label: {
                    readingCard(reading)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @ViewBuilder
    private var workoutSection: some View {
        if !health.workouts.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text("Senaste träningspassen").font(.title3.bold())
                VStack(spacing: 0) {
                    ForEach(health.workouts) { workout in
                        HStack(alignment: .top, spacing: 14) {
                            Image(systemName: "figure.run")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.orange)
                                .frame(width: 42, height: 42)
                                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 5) {
                                Text(workout.title).font(.subheadline.weight(.semibold))
                                Text(workout.detail).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(16)
                        if workout.id != health.workouts.last?.id {
                            Divider().padding(.leading, 72)
                        }
                    }
                }
                .background(.white, in: RoundedRectangle(cornerRadius: 22))
            }
        }
    }

    @ViewBuilder
    private func historyView(for reading: HealthReading) -> some View {
        if reading.id == "steps" {
            StepHistoryView(health: health)
        } else if reading.id == "heart-rate" || reading.id == "resting-heart-rate" {
            HeartRateHistoryView(health: health, isResting: reading.id == "resting-heart-rate")
        } else {
            MetricHistoryView(health: health, reading: reading)
        }
    }

    private func metricColor(_ reading: HealthReading) -> Color {
        switch reading.id {
        case "heart-rate", "resting-heart-rate": accent
        case "steps", "distance", "flights": .blue
        case "sleep": .indigo
        case "hrv", "respiratory-rate", "oxygen": .teal
        case "active-energy": .orange
        default: .purple
        }
    }

    private func readingCard(_ reading: HealthReading) -> some View {
        let color = metricColor(reading)
        let detail = reading.detail.replacingOccurrences(of: " · Visa historik", with: "")
        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: reading.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 36, height: 36)
                    .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            Text(reading.title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(reading.value)
                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(reading.unit)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            Text(detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 190, alignment: .topLeading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22).strokeBorder(Color.black.opacity(0.035), lineWidth: 1))
        .shadow(color: .black.opacity(0.025), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }
}

private struct TeamRating {
    let countsByStar: [Int]

    var reviewCount: Int { countsByStar.reduce(0, +) }

    var average: Double? {
        guard reviewCount > 0 else { return nil }
        let points = countsByStar.enumerated().reduce(0) { total, entry in
            total + (entry.offset + 1) * entry.element
        }
        return (Double(points) / Double(reviewCount) * 10).rounded() / 10
    }
}

private enum DemoDoctor: String, CaseIterable, Identifiable {
    case sofia, erik, amir, emma

    struct Profile {
        let name: String
        let rating: TeamRating
        let education: String
        let specialty: String
        let graduation: String
        let license: String
        let specialistCertificate: String
        let research: String
        let researchArea: String
        let languages: String
    }

    var id: String { rawValue }
    var name: String { profile.name }

    var portraitAsset: String {
        self == .sofia ? "DemoClinicianPortrait" : "DemoDoctor-\(rawValue)-Portrait"
    }

    var fullBodyAsset: String {
        self == .sofia ? "DemoClinicianFullBody" : "DemoDoctor-\(rawValue)-FullBody"
    }

    var nursePortraitAsset: String {
        self == .sofia ? "DemoTeamRegisteredNurse" : "DemoTeam-\(rawValue)-RegisteredNurse"
    }

    var assistantNursePortraitAsset: String {
        self == .sofia ? "DemoTeamAssistantNurse" : "DemoTeam-\(rawValue)-AssistantNurse"
    }

    // The PNGs share a 1,200 px canvas height. Measure the visible figure
    // so transparent margins do not affect the height or centering on screen.
    var fullBodyFraming: (imageWidth: CGFloat, figure: CGRect) {
        switch self {
        case .sofia: (419, CGRect(x: 32, y: 15, width: 349, height: 1171))
        case .erik: (462, CGRect(x: 24, y: 28, width: 413, height: 1150))
        case .amir: (435, CGRect(x: 20, y: 30, width: 380, height: 1142))
        case .emma: (412, CGRect(x: 21, y: 28, width: 352, height: 1155))
        }
    }

    static let widestFigureRatio: CGFloat = allCases.map {
        let figure = $0.fullBodyFraming.figure
        return figure.width / figure.height
    }.max() ?? 1

    var profile: Profile {
        switch self {
        case .sofia:
            Profile(name: "Dr Sofia Lind", rating: TeamRating(countsByStar: [0, 0, 0, 0, 5]),
                    education: "Karolinska Institutet", specialty: "Infektionsmedicin",
                    graduation: "2020", license: "2023", specialistCertificate: "2026",
                    research: "Avhandling 2026 · 8 publikationer", researchArea: "Antibiotikaresistens",
                    languages: "Svenska och engelska")
        case .erik:
            Profile(name: "Dr Erik Dahl", rating: TeamRating(countsByStar: [0, 0, 0, 4, 16]),
                    education: "Uppsala universitet", specialty: "Kardiologi",
                    graduation: "2011", license: "2013", specialistCertificate: "2020",
                    research: "Avhandling 2022 · 12 publikationer", researchArea: "Hjärtsvikt",
                    languages: "Svenska och engelska")
        case .amir:
            Profile(name: "Dr Amir Nasser", rating: TeamRating(countsByStar: [0, 12, 2, 0, 86]),
                    education: "Göteborgs universitet", specialty: "Allmänmedicin",
                    graduation: "2014", license: "2016", specialistCertificate: "2022",
                    research: "6 publikationer", researchArea: "Prevention i primärvården",
                    languages: "Svenska, engelska och arabiska")
        case .emma:
            Profile(name: "Dr Emma Berg", rating: TeamRating(countsByStar: [0, 0, 0, 2, 18]),
                    education: "Lunds universitet", specialty: "Endokrinologi",
                    graduation: "2013", license: "2015", specialistCertificate: "2022",
                    research: "Avhandling 2023 · 9 publikationer", researchArea: "Typ 2-diabetes",
                    languages: "Svenska och engelska")
        }
    }
}

private struct TeamRatingView: View {
    let rating: TeamRating

    var body: some View {
        if let average = rating.average {
            let formatted = average.formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "sv_SE")))
            VStack(alignment: .leading, spacing: 3) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) {
                        stars(for: average)
                        score(formatted)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        stars(for: average)
                        score(formatted)
                    }
                }
                Text("\(rating.reviewCount) exempelomdömen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Teamets exempelbetyg")
            .accessibilityValue("\(formatted) av 5, \(rating.reviewCount) omdömen")
        }
    }

    private func score(_ formatted: String) -> some View {
        Text(formatted)
            .font(.footnote.weight(.semibold).monospacedDigit())
    }

    private func stars(for average: Double) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<5) { index in
                let fill = min(1, max(0, average - Double(index)))
                Image(systemName: "star")
                    .foregroundStyle(.secondary)
                    .overlay {
                        Image(systemName: "star.fill")
                            .foregroundStyle(Color(red: 0.76, green: 0.44, blue: 0.06))
                            .mask(alignment: .leading) {
                                GeometryReader { geometry in
                                    Rectangle().frame(width: geometry.size.width * fill)
                                }
                            }
                    }
            }
        }
        .font(.caption2)
    }
}

private struct DoctorPortrait: View {
    let doctor: DemoDoctor?
    let size: CGFloat

    var body: some View {
        Group {
            if let doctor {
                Image(doctor.portraitAsset)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "stethoscope")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.tint)
            }
        }
        .frame(width: size, height: size)
        .background(.tint.opacity(0.09))
        .clipShape(Circle())
        .overlay { Circle().strokeBorder(.tint.opacity(0.15)) }
        .accessibilityHidden(true)
    }
}

private struct DoctorSelectionView: View {
    let confirm: (DemoDoctor) -> Void
    @State private var doctor = DemoDoctor.sofia

    var body: some View {
        DoctorProfile(doctor: doctor, isChoosing: true) { option in
            doctor = option
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button { confirm(doctor) } label: {
                Text("Välj \(doctor.name)")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .frame(maxWidth: 420)
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.bar)
        }
    }
}

private struct DoctorProfileSheet: View {
    @Binding var chosenDoctorID: String
    let isBeta: Bool
    let close: () -> Void

    var body: some View {
        NavigationStack {
            Group {
                if isBeta {
                    if let doctor = DemoDoctor(rawValue: chosenDoctorID) {
                        DoctorProfile(doctor: doctor) { option in
                            chosenDoctorID = option.id
                        }
                    } else {
                        DoctorSelectionView { doctor in
                            chosenDoctorID = doctor.id
                        }
                    }
                } else {
                    ContentUnavailableView("Inga läkare tillgängliga", systemImage: "stethoscope",
                                           description: Text("Läkarvalet finns i betaprofilen medan läkarkatalogen förbereds."))
                }
            }
            .navigationTitle("Läkare")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Stäng", action: close)
                }
            }
        }
    }
}

private struct DoctorProfile: View {
    let doctor: DemoDoctor
    var isChoosing = false
    let select: (DemoDoctor) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let background = Color(red: 0.97, green: 0.96, blue: 0.98)

    var body: some View {
        GeometryReader { geometry in
            ScrollViewReader { scroll in
                ScrollView {
                    VStack(spacing: isChoosing ? 12 : 16) {
                        VStack(spacing: 10) {
                            if isChoosing {
                                Text("Välj din läkare")
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ZStack(alignment: .top) {
                                profileLayout(in: geometry.size)
                                    .id(doctor)
                                    .transition(.opacity)
                            }
                            .animation(reduceMotion ? nil : .easeInOut(duration: 0.24), value: doctor)
                        }
                        .padding(.top, isChoosing ? 8 : 12)
                        .id("selectedDoctor")
                        otherDoctors
                    }
                    .padding(.bottom, 16)
                }
                .onChange(of: doctor) {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) {
                        scroll.scrollTo("selectedDoctor", anchor: .top)
                    }
                }
            }
        }
        .background(background)
    }

    @ViewBuilder
    private func profileLayout(in size: CGSize) -> some View {
        if typeSize.isAccessibilitySize || size.width < 320 || size.height < 340 {
            VStack(spacing: 16) {
                portrait.frame(height: 280)
                detailsWithTeam
            }
            .padding(.horizontal, 16)
        } else {
            let width = min(280, size.width * 0.44)
            let height = min(width * 2.86, max(280, size.height - (isChoosing ? 185 : 150)))
            HStack(alignment: .top, spacing: 2) {
                portrait.frame(width: width, height: height)
                detailsWithTeam.padding(.trailing, 12)
            }
        }
    }

    private var detailsWithTeam: some View {
        VStack(alignment: .leading, spacing: isChoosing ? 8 : 10) {
            details
            HStack(spacing: -10) {
                teamPortrait(doctor.nursePortraitAsset, role: "Sjuksköterska")
                    .zIndex(2)
                teamPortrait(doctor.assistantNursePortraitAsset, role: "Undersköterska")
                    .zIndex(1)
                teamPortrait("DemoTeamAdministrator", role: "Administratör")
            }
            .padding(.leading, 4)
            .accessibilityElement(children: .combine)
        }
    }

    private func teamPortrait(_ asset: String, role: String) -> some View {
        Image(asset)
            .resizable()
            .scaledToFill()
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            .overlay { Circle().strokeBorder(.white, lineWidth: 2) }
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
            .accessibilityLabel(Text(role))
    }

    private var portrait: some View {
        GeometryReader { geometry in
            let framing = doctor.fullBodyFraming
            let figureHeight = max(0, min(geometry.size.height - 12,
                                          (geometry.size.width - 8) / DemoDoctor.widestFigureRatio))
            let scale = figureHeight / framing.figure.height
            Image(doctor.fullBodyAsset)
                .resizable()
                .frame(width: framing.imageWidth * scale, height: 1200 * scale)
                .position(x: geometry.size.width / 2 + (framing.imageWidth / 2 - framing.figure.midX) * scale,
                          y: 6 + (600 - framing.figure.minY) * scale)
        }
        .clipped()
        .accessibilityHidden(true)
    }

    private var otherDoctors: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Andra läkare")
                .font(.subheadline.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                     count: typeSize.isAccessibilitySize ? 1 : 3), spacing: 8) {
                ForEach(DemoDoctor.allCases.filter { $0 != doctor }) { option in
                    Button { select(option) } label: {
                        VStack(spacing: 5) {
                            DoctorPortrait(doctor: option, size: 46)
                            Text(option.name)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.primary)
                            Text(option.profile.specialty)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity, minHeight: isChoosing ? 80 : 88)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 6)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(.black.opacity(0.05))
                                .allowsHitTesting(false)
                        }
                        .contentShape(RoundedRectangle(cornerRadius: 16))
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(isChoosing ? "Visar läkarens profil" : "Visar profilen och väljer läkaren")
                }
            }
        }
        .padding(.horizontal, 12)
    }

    private var details: some View {
        let profile = doctor.profile
        return VStack(alignment: .leading, spacing: isChoosing ? 6 : 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Team")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                Text(profile.name)
                    .font(.title3.bold())
                    .accessibilityAddTraits(.isHeader)
                TeamRatingView(rating: profile.rating)
            }

            Divider()
            VStack(alignment: .leading, spacing: isChoosing ? 6 : 8) {
                detail("Utbildning", profile.education, symbol: "graduationcap")
                detail("Specialistkompetens", profile.specialty, symbol: "stethoscope")
            }

            Divider()
            VStack(alignment: .leading, spacing: 5) {
                sectionHeading("Yrkesväg")
                milestone(profile.graduation, "Läkarexamen")
                milestone(profile.license, "Läkarlegitimation")
                milestone(profile.specialistCertificate, "Specialistbevis")
            }

            Divider()
            VStack(alignment: .leading, spacing: isChoosing ? 6 : 8) {
                detail("Forskning", profile.research, symbol: "doc.text")
                detail("Forskningsområde", profile.researchArea, symbol: "cross.case")
                detail("Språk", profile.languages, symbol: "globe")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, isChoosing ? 10 : 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 22))
        .overlay {
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(.black.opacity(0.05))
                .allowsHitTesting(false)
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .accessibilityAddTraits(.isHeader)
    }

    private func detail(_ title: String, _ value: String, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol)
                .font(.footnote)
                .foregroundStyle(.tint)
                .frame(width: 16)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                sectionHeading(title)
                Text(value)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func milestone(_ year: String, _ title: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(year)
                .font(.footnote.weight(.semibold).monospacedDigit())
                .foregroundStyle(.tint)
            Text(title)
                .font(.footnote)
        }
        .accessibilityElement(children: .combine)
    }
}

#if DEBUG
private struct GoHealthDashboardPreview: View {
    var startsAtDoctorSelection = false
    private static let accountID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
    private static let onboardingAccountID = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
    private static let preferences: UserDefaults? = {
        guard let preferences = UserDefaults(suiteName: "GoHealth.XcodePreview") else { return nil }
        for account in [accountID, onboardingAccountID] {
            for key in ["hasCompletedAvatarSetup", "hasCompletedWelcome", "hasCompletedProfileSetup", "healthLinked"] {
                preferences.set(true, forKey: "\(key).\(account.uuidString)")
            }
        }
        preferences.set(true, forKey: "hasCompletedTour.\(accountID.uuidString)")
        preferences.removeObject(forKey: "hasCompletedDoctorSelection.\(onboardingAccountID.uuidString)")
        preferences.removeObject(forKey: "hasCompletedTour.\(onboardingAccountID.uuidString)")
        return preferences
    }()

    var body: some View {
        if let preferences = Self.preferences {
            ContentView(accountID: startsAtDoctorSelection ? Self.onboardingAccountID : Self.accountID,
                        email: nil, displayName: "Alex Testsson",
                        updateDisplayName: { _ in true }, signOut: {}, betaPreferences: preferences)
        } else {
            Text("Testprofilen kunde inte öppnas.")
        }
    }
}

#Preview("GoHealth · Testdata") {
    GoHealthDashboardPreview()
}

#Preview("GoHealth · Onboarding läkarval") {
    GoHealthDashboardPreview(startsAtDoctorSelection: true)
}

private struct DoctorProfilePreview: View {
    @State private var doctorID = DemoDoctor.sofia.id
    @State private var showsDoctorProfile = true

    var body: some View {
        Button("Öppna läkarprofilen") { showsDoctorProfile = true }
            .sheet(isPresented: $showsDoctorProfile) {
                DoctorProfileSheet(chosenDoctorID: $doctorID, isBeta: true) {
                    showsDoctorProfile = false
                }
            }
    }
}

#Preview("GoHealth · Läkarprofil") {
    DoctorProfilePreview()
        .tint(Color(red: 0.73, green: 0.20, blue: 0.47))
        .preferredColorScheme(.light)
}
#endif

struct StepHistoryView: View {
    @ObservedObject var health: HealthStore

    var body: some View {
        List {
            Section {
                Text("Alla tillgängliga dagar från Apple Hälsa, med senaste dagen först. Dagar utan läsbara mätningar visas inte som noll steg.")
                    .font(.footnote).foregroundStyle(.secondary)
                if let first = health.stepHistory.last, let last = health.stepHistory.first {
                    Text("\(first.date.formatted(date: .abbreviated, time: .omitted)) – \(last.date.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error = health.stepHistoryError {
                Text(error).foregroundStyle(.secondary)
            } else if health.stepHistory.isEmpty {
                ContentUnavailableView("Ingen läsbar steghistorik", systemImage: "figure.walk", description: Text("Kontrollera att GoHealth får läsa steg i Apple Hälsa och att din enhet har synkroniserat sina mätningar."))
            }
            Section("Steg per dag") {
                ForEach(health.stepHistory) { day in
                    HStack {
                        Text(day.date, format: .dateTime.day().month(.wide).year())
                        Spacer()
                        Text("\(Int(day.count.rounded()).formatted()) steg").fontWeight(.semibold)
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle("Steghistorik")
        .refreshable { await health.refresh() }
        .overlay { if health.isLoading { ProgressView("Hämtar historik…") } }
    }
}

struct HeartRateHistoryView: View {
    @ObservedObject var health: HealthStore
    var isResting = false

    private var history: [HeartRateReading] {
        isResting ? health.restingHeartRateHistory : health.heartRateHistory
    }
    private var historyError: String? {
        isResting ? health.restingHeartRateHistoryError : health.heartRateHistoryError
    }

    var body: some View {
        List {
            Section {
                Text(health.isBeta
                     ? "Betaprofilens testmätningar, med senaste mätningen först."
                     : (isResting ? "Alla tillgängliga vilopulsmätningar från alla läsbara källor i Apple Hälsa, med senaste mätningen först." : "Alla tillgängliga pulsmätningar från alla läsbara källor i Apple Hälsa, med senaste mätningen först."))
                    .font(.footnote).foregroundStyle(.secondary)
                Text("\(history.count.formatted()) mätningar")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = historyError {
                Text(error).foregroundStyle(.secondary)
            } else if history.isEmpty && !health.isLoading {
                ContentUnavailableView(isResting ? "Ingen läsbar vilopulshistorik" : "Ingen läsbar pulshistorik", systemImage: "heart.fill", description: Text(isResting ? "Kontrollera att GoHealth får läsa vilopuls i Apple Hälsa och att dina enheter och appar har synkroniserat sina mätningar." : "Kontrollera att GoHealth får läsa puls i Apple Hälsa och att dina enheter och appar har synkroniserat sina mätningar."))
            }
            Section(isResting ? "Vilopulsmätningar" : "Pulsmätningar") {
                ForEach(history) { reading in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(reading.date, format: .dateTime.day().month(.wide).year().hour().minute().second())
                            Text(reading.source).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(Int(reading.beatsPerMinute.rounded()).formatted()) slag/min")
                            .fontWeight(.semibold)
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(isResting ? "Vilopulshistorik" : "Pulshistorik")
        .refreshable { await health.refresh() }
        .overlay { if health.isLoading { ProgressView("Hämtar historik…") } }
    }
}

struct MetricHistoryView: View {
    @ObservedObject var health: HealthStore
    let reading: HealthReading

    private var history: [MetricHistoryEntry] { health.metricHistory[reading.id] ?? [] }
    private var daily: Bool { ["distance", "active-energy", "flights", "sleep"].contains(reading.id) }

    var body: some View {
        List {
            Section {
                Text(health.isBeta
                     ? "Betaprofilens testvärden från de senaste 30 dagarna, med senaste värdet först."
                     : "Hela den tillgängliga historiken från Apple Hälsa, med senaste värdet först. Saknade mätningar visas inte som noll.")
                    .font(.footnote).foregroundStyle(.secondary)
                if reading.id == "sleep" {
                    Text("Sovtid per kalenderdag. Sömn över midnatt delas mellan dagarna. Överlappande sömn räknas en gång; vaken tid och tid i sängen ingår inte.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Text("\(history.count.formatted()) \(daily ? "dagar" : "mätningar")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let error = health.metricHistoryErrors[reading.id] {
                Text(error).foregroundStyle(.secondary)
            } else if history.isEmpty && !health.isLoading {
                ContentUnavailableView("Ingen läsbar historik", systemImage: reading.icon, description: Text("Kontrollera åtkomsten för \(reading.title.lowercased()) i Apple Hälsa och synkronisera dina enheter."))
            }
            Section(daily ? "Per dag" : "Mätningar") {
                ForEach(history) { entry in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.date.formatted(date: .abbreviated, time: daily ? .omitted : .shortened))
                            Text(entry.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(entry.value) \(reading.unit)").fontWeight(.semibold)
                    }.accessibilityElement(children: .combine)
                }
            }
        }
        .navigationTitle(reading.id == "sleep" ? "Sömnhistorik" : reading.title)
        .refreshable { await health.refresh() }
        .overlay { if health.isLoading { ProgressView("Hämtar historik…") } }
    }
}

/// Lets a signed-in user set a password, so the account can also be opened with e-mail and password.
private struct PasswordSetupSheet: View {
    let save: (String) async -> Bool
    let saved: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var repeated = ""
    @State private var failed = false
    @State private var isSaving = false

    private var mismatch: Bool { !repeated.isEmpty && password != repeated }
    private var valid: Bool { password.count >= 10 && password == repeated }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Nytt lösenord", text: $password)
                        .textContentType(.newPassword)
                    SecureField("Upprepa lösenordet", text: $repeated)
                        .textContentType(.newPassword)
                } footer: {
                    if mismatch {
                        Text("Lösenorden är inte lika.").foregroundStyle(.red)
                    } else {
                        Text("Minst 10 tecken. Du kan fortfarande logga in med e-postlänk.")
                    }
                }
                if failed {
                    Text("Lösenordet kunde inte sparas. Försök igen.").font(.footnote).foregroundStyle(.red)
                }
            }
            .navigationTitle("Lösenord")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Sparar…" : "Spara") {
                        isSaving = true
                        failed = false
                        Task {
                            let ok = await save(password)
                            isSaving = false
                            if ok { dismiss(); saved() } else { failed = true }
                        }
                    }
                    .disabled(!valid || isSaving)
                }
            }
        }
    }
}
