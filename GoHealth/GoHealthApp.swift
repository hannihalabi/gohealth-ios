import AuthenticationServices
import Supabase
import SwiftUI

@main
struct GoHealthApp: App {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var account = GoHealthAccount()
    @State private var hasShownSignInIntro = false

    var body: some Scene {
        WindowGroup {
            ZStack {
                if Self.runsRecoveryDemo {
                    NavigationStack {
                        RecoveryDemoView(health: HealthStore(), scope: .demo)
                            .navigationTitle("Återhämtning · Demo")
                    }
                } else if let accountID = account.activeAccountID {
                    ContentView(
                        accountID: accountID,
                        email: account.email,
                        displayName: account.displayName,
                        givenName: account.givenName,
                        updateDisplayName: account.updateDisplayName,
                        signOut: account.signOut,
                        betaPreferences: account.betaPreferences,
                        imagingAccessToken: { try await account.imagingAccessToken(for: accountID) },
                        fetchMessages: { try await account.careMessages(for: accountID) },
                        fetchClinicalRecords: { try await account.clinicalRecords(for: accountID) },
                        uploadClinicalVitals: { try await account.uploadVitals($0, for: accountID) },
                        downloadClinicalArchive: { try await account.clinicalArchive($0, for: accountID) }
                    )
                    .id(accountID)
                    .transition(.opacity)
                    .zIndex(1)
                } else {
                    GoHealthSignInView(account: account, hasShownIntro: $hasShownSignInIntro)
                        .transition(.opacity)
                }
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.5), value: account.activeAccountID)
            .preferredColorScheme(.light)
            .task {
                if !Self.runsRecoveryDemo { await account.observeSession() }
            }
            .onOpenURL { url in
                Task { await account.finishEmailSignIn(url) }
            }
        }
    }

    private static var runsRecoveryDemo: Bool {
        #if DEBUG && targetEnvironment(simulator)
        ProcessInfo.processInfo.arguments.contains("--recovery-demo")
        #else
        false
        #endif
    }
}

@MainActor
private final class GoHealthAccount: ObservableObject {
    @Published private(set) var user: User?
    @Published private(set) var isRestoring = true
    @Published private(set) var isBusy = false
    @Published private(set) var errorMessage: String?

    #if DEBUG
    private struct BetaSession {
        let id = UUID()
        let preferences: UserDefaults
        var displayName: String? = "Alex Testsson"
    }

    private static let betaDomain = "se.hemlakare.gohealth.beta"
    @Published private var betaSession: BetaSession?

    func startBetaSession() {
        guard user == nil, betaSession == nil, !isRestoring, !isBusy else { return }
        guard let preferences = UserDefaults(suiteName: Self.betaDomain) else {
            errorMessage = "Testprofilen kunde inte startas. Försök igen."
            return
        }
        preferences.removePersistentDomain(forName: Self.betaDomain)
        let session = BetaSession(preferences: preferences)
        preferences.set(true, forKey: "healthLinked.\(session.id.uuidString)")
        errorMessage = nil
        betaSession = session
    }
    #endif

    var activeAccountID: UUID? {
        #if DEBUG
        if let betaSession { return betaSession.id }
        #endif
        return user?.id
    }

    var betaPreferences: UserDefaults? {
        #if DEBUG
        return betaSession?.preferences
        #else
        return nil
        #endif
    }

    var email: String? { betaPreferences == nil ? user?.email : nil }

    func imagingAccessToken(for expectedAccountID: UUID) async throws -> String {
        guard betaPreferences == nil, user?.id == expectedAccountID else {
            throw URLError(.userAuthenticationRequired)
        }
        let session = try await client.auth.session
        guard user?.id == expectedAccountID, session.user.id == expectedAccountID else {
            throw URLError(.userAuthenticationRequired)
        }
        return session.accessToken
    }

    func clinicalRecords(for accountID: UUID) async throws -> ClinicalEnvelope {
        _ = try await imagingAccessToken(for: accountID)
        let result: ClinicalEnvelope = try await client.rpc("gohealth_patient_data").execute().value
        guard user?.id == accountID else { throw URLError(.userAuthenticationRequired) }
        return result
    }

    func clinicalArchive(_ archive: ClinicalArchiveAttachment, for accountID: UUID) async throws -> Data {
        guard (22...ClinicalImageArchive.maximumArchiveBytes).contains(archive.size) else { throw ImagingError.invalidResponse }
        _ = try await imagingAccessToken(for: accountID)
        let data = try await client.storage.from("clinical-ct-archives")
            .download(path: "\(archive.id.uuidString.lowercased()).zip", cacheNonce: UUID().uuidString)
        try Task.checkCancellation()
        guard user?.id == accountID else { throw URLError(.userAuthenticationRequired) }
        guard data.count == archive.size else { throw ImagingError.invalidResponse }
        return data
    }

    func uploadVitals(_ batch: ClinicalVitalsBatch, for accountID: UUID) async throws {
        try Task.checkCancellation()
        _ = try await imagingAccessToken(for: accountID)
        try await client.rpc(batch.expandedHistory ? "gohealth_ingest_vitals_v2" : "gohealth_ingest_vitals", params: batch).execute()
        guard user?.id == accountID else { throw URLError(.userAuthenticationRequired) }
    }

    func careMessages(for accountID: UUID) async throws -> [CareMessage] {
        guard betaPreferences == nil, user?.id == accountID else {
            throw URLError(.userAuthenticationRequired)
        }
        var messages: [CareMessage] = []
        let pageSize = 100
        while true {
            try Task.checkCancellation()
            let page: [CareMessage] = try await client
                .from("care_messages")
                .select("id,provider_name,booking_url,created_at,resolved_at")
                .eq("patient_id", value: accountID)
                .order("created_at", ascending: false)
                .order("id", ascending: false)
                .range(from: messages.count, to: messages.count + pageSize - 1)
                .execute()
                .value
            guard user?.id == accountID else { throw URLError(.userAuthenticationRequired) }
            messages.append(contentsOf: page)
            if page.count < pageSize { return messages }
        }
    }

    private static let callbackURL = URL(string: "gohealth://auth/callback")!
    private static let backendURL: URL = {
        if let value = Bundle.main.object(forInfoDictionaryKey: "GoHealthSupabaseURL") as? String,
           let url = URL(string: value), url.scheme == "https", url.host != nil {
            return url
        }
        return URL(string: "https://example.invalid")!
    }()
    private let client = SupabaseClient(
        supabaseURL: backendURL,
        supabaseKey: Bundle.main.object(forInfoDictionaryKey: "GoHealthSupabasePublishableKey") as? String ?? "",
        options: .init(
            auth: .init(redirectToURL: callbackURL, flowType: .pkce),
            global: .init(session: URLSession(configuration: .ephemeral))
        )
    )

    var displayName: String? {
        #if DEBUG
        if let betaSession { return betaSession.displayName }
        #endif
        guard let user else { return nil }
        let metadata = user.userMetadata
        let profile = user.identities?.first { $0.provider == "google" }?.identityData ?? metadata
        let candidates = [
            metadata["display_name"]?.stringValue,
            profile["full_name"]?.stringValue,
            profile["name"]?.stringValue,
            profile["given_name"]?.stringValue
        ]
        return candidates.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    var givenName: String? {
        guard betaPreferences == nil, let user else { return nil }
        let metadata = user.userMetadata
        if let customName = metadata["display_name"]?.stringValue,
           let firstName = customName.split(whereSeparator: \.isWhitespace).first {
            return String(firstName)
        }
        let googleProfile = user.identities?.first { $0.provider == "google" }?.identityData
        let name = (googleProfile?["given_name"]?.stringValue ?? metadata["given_name"]?.stringValue)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.flatMap { $0.isEmpty ? nil : $0 }
    }

    func updateDisplayName(_ name: String) async -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        #if DEBUG
        if betaSession != nil {
            betaSession?.displayName = trimmedName
            return true
        }
        #endif
        return await run(failure: "Namnet kunde inte sparas.") {
            try await client.auth.update(user: UserAttributes(data: ["display_name": .string(trimmedName)]))
        }
    }

    func observeSession() async {
        for await (_, session) in client.auth.authStateChanges {
            user = session?.user
            isRestoring = false
        }
    }

    func sendEmailLink(to email: String) async -> Bool {
        guard Self.backendURL.host != "example.invalid",
              let key = Bundle.main.object(forInfoDictionaryKey: "GoHealthSupabasePublishableKey") as? String,
              !key.isEmpty else {
            errorMessage = "Ange Supabase-adress och publik klientnyckel i Xcodes bygginställningar."
            return false
        }
        return await run(failure: "Länken kunde inte skickas. Kontrollera e-postadressen och försök igen om en stund.") {
            try await client.auth.signInWithOTP(email: email)
        }
    }

    func signInWithGoogle() async {
        _ = await run(failure: "Google-inloggningen kunde inte slutföras. Försök igen eller använd e-post.") {
            try await client.auth.signInWithOAuth(provider: .google, queryParams: [("prompt", "select_account")]) { session in
                session.prefersEphemeralWebBrowserSession = true
            }
        }
    }

    func finishEmailSignIn(_ url: URL) async {
        guard betaPreferences == nil, user == nil, url.scheme == Self.callbackURL.scheme,
              url.host == Self.callbackURL.host, url.path == Self.callbackURL.path else { return }
        _ = await run(failure: "Länken kunde inte öppnas. Be om en ny länk och öppna den på samma iPhone.") {
            try await client.auth.session(from: url)
        }
    }

    func signOut() async {
        #if DEBUG
        if let betaSession {
            self.betaSession = nil
            betaSession.preferences.removePersistentDomain(forName: Self.betaDomain)
            return
        }
        #endif
        _ = await run(failure: "Utloggningen kunde inte slutföras.") {
            try await client.auth.signOut(scope: .local)
        }
    }

    private func run(failure: String, operation: () async throws -> Void) async -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await operation()
            return true
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return false
        } catch {
            errorMessage = failure
            return false
        }
    }
}

private struct GoHealthSignInView: View {
    private enum Phase {
        case scanning, movingAvatar, signIn
    }

    @ObservedObject var account: GoHealthAccount
    @Binding var hasShownIntro: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale
    @FocusState private var emailFocused: Bool
    @State private var email = ""
    @State private var linkSent = false
    @State private var phase: Phase
    @State private var scanStart: Date?
    @State private var scanComplete = false
    private let accent = Color(red: 0.73, green: 0.20, blue: 0.47)
    private let scanDuration = 5.0

    init(account: GoHealthAccount, hasShownIntro: Binding<Bool>) {
        self.account = account
        _hasShownIntro = hasShownIntro
        _phase = State(initialValue: hasShownIntro.wrappedValue ? .signIn : .scanning)
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    avatarStage(in: geometry.size)

                    if phase == .signIn {
                        Spacer(minLength: 4)

                        VStack(spacing: 12) {
                            portalDivider

                            if account.isRestoring {
                                ProgressView("Förbereder din profil…")
                            } else {
                                signInForm
                            }
                        }
                        .frame(maxWidth: 400)
                        .padding(.bottom, 12)
                        .transition(.opacity.combined(with: .offset(y: 18)))
                    }
                }
                .padding(.horizontal, 24)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .scrollDismissesKeyboard(.interactively)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            OnboardingProgress(step: phase == .signIn ? .signIn : .intro, onSkip: onboardingSkip)
        }
        .background {
            LinearGradient(colors: [.white, Color(red: 0.973, green: 0.952, blue: 0.965)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .tint(accent)
        .task(id: reduceMotion) {
            guard phase != .signIn else { return }
            if reduceMotion {
                finishIntro()
                return
            }
            await playIntro()
        }
    }

    private var onboardingSkip: (() -> Void)? {
        if phase != .signIn { return finishIntro }
        #if DEBUG
        if !account.isRestoring && !account.isBusy { return account.startBetaSession }
        #endif
        return nil
    }

    private var signInForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 5) {
                Text("Välkommen till GoHealth")
                    .font(.system(.title2, design: .serif).weight(.semibold))
                    .accessibilityAddTraits(.isHeader)

                Text("Logga in eller skapa ett konto.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 4)

            HStack(spacing: 10) {
                Image(systemName: "envelope")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("E-postadress", text: $email)
                    .multilineTextAlignment(.leading)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($emailFocused)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(minHeight: 48)
            .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
            .overlay {
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(emailFocused ? accent.opacity(0.55) : Color.primary.opacity(0.12))
                    .allowsHitTesting(false)
            }
            .disabled(account.isBusy)

            Button {
                let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
                Task { linkSent = await account.sendEmailLink(to: address) }
            } label: {
                Text("Skicka inloggningslänk")
            }
            .buttonStyle(GoHealthSignInButtonStyle(accent: accent, prominent: true))
            .disabled(account.isBusy || !email.contains("@"))

            if linkSent {
                Label("Öppna länken i mejlet på den här iPhonen för att fortsätta.", systemImage: "envelope")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                linkSent = false
                Task { await account.signInWithGoogle() }
            } label: {
                Text("Fortsätt med Google")
            }
            .buttonStyle(GoHealthSignInButtonStyle(accent: accent, prominent: false))
            .disabled(account.isBusy)

            #if DEBUG
            Button(action: account.startBetaSession) {
                Text("Beta-login")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(account.isBusy)
            .accessibilityHint("Startar en ny lokal testprofil")
            #endif

            if account.isBusy { ProgressView().frame(maxWidth: .infinity) }
            if let message = account.errorMessage {
                Text(message).font(.footnote).foregroundStyle(.red)
            }
        }
    }

    private var portalDivider: some View {
        Rectangle()
            .fill(LinearGradient(colors: [.clear, accent.opacity(0.24), .clear],
                                 startPoint: .leading, endPoint: .trailing))
            .frame(height: 1 / displayScale)
            .accessibilityHidden(true)
    }

    private func avatarStage(in size: CGSize) -> some View {
        let isFullscreen = phase == .scanning
        return TimelineView(.animation(paused: !isFullscreen || scanComplete)) { context in
            let progress = scanProgress(at: context.date)
            VStack(spacing: isFullscreen ? 18 : 8) {
                if isFullscreen {
                    VStack(spacing: 10) {
                        Text("Se din hälsa i 3D")
                            .font(.largeTitle.bold())
                            .accessibilityAddTraits(.isHeader)
                        Text("Din kropp och dina mätningar, samlade på ett ställe.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .transition(.opacity)
                }

                avatarPreview(progress: progress)
                    .frame(maxWidth: 320)
                    .frame(height: min(size.height * (isFullscreen ? 0.60 : 0.59), 500))

                if isFullscreen {
                    VStack(spacing: 8) {
                        Text("Förhandsvisning av kroppsöversikten")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                        ProgressView(value: progress)
                            .frame(maxWidth: 200)
                            .accessibilityHidden(true)
                    }
                    .transition(.opacity)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.vertical, isFullscreen ? 24 : 4)
            .frame(maxWidth: .infinity, minHeight: isFullscreen ? size.height : 0)
        }
    }

    private func playIntro() async {
        scanStart = .now
        do {
            try await Task.sleep(for: .seconds(scanDuration))
            guard phase == .scanning else { return }
            scanComplete = true
            try await Task.sleep(for: .milliseconds(500))
            guard phase == .scanning else { return }
            withAnimation(.easeInOut(duration: 0.8)) { phase = .movingAvatar }
            try await Task.sleep(for: .milliseconds(800))
        } catch {
            return
        }
        if phase == .movingAvatar { finishIntro() }
    }

    private func finishIntro() {
        hasShownIntro = true
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.45)) { phase = .signIn }
    }

    private func scanProgress(at time: Date) -> CGFloat {
        if phase != .scanning || reduceMotion || scanComplete { return 1 }
        guard let scanStart else { return 0 }
        return CGFloat(min(1, max(0, time.timeIntervalSince(scanStart) / scanDuration)))
    }

    private func avatarPreview(progress: CGFloat) -> some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let scanY = height * progress
            ZStack(alignment: .top) {
                RadialGradient(colors: [accent.opacity(0.08), .clear], center: .center,
                               startRadius: 0, endRadius: height * 0.55)

                // The preview uses the right half of the bundled pair of figures.
                Image("BodyFigures")
                    .resizable()
                    .frame(width: height * 1.5, height: height)
                    .offset(x: -height * 0.375)
                    .frame(width: height * 0.75, height: height)
                    .clipped()
                    .frame(width: geometry.size.width, height: height)
                    .blendMode(.multiply)
                    .mask(alignment: .top) { Rectangle().frame(height: scanY) }

                if progress < 1 {
                    Rectangle()
                        .fill(LinearGradient(colors: [.clear, accent, .clear],
                                             startPoint: .leading, endPoint: .trailing))
                        .frame(height: 2)
                        .shadow(color: accent.opacity(0.6), radius: 4)
                        .offset(y: scanY)
                }
            }
            .frame(width: geometry.size.width, height: height)
            .clipped()
        }
        .accessibilityHidden(true)
    }
}

private struct GoHealthSignInButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    let accent: Color
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let filled = prominent && isEnabled
        let shape = RoundedRectangle(cornerRadius: 12)
        configuration.label
            .font(.subheadline.weight(.semibold))
            .multilineTextAlignment(.center)
            .foregroundStyle(filled ? Color.white : (isEnabled ? Color.primary : Color.secondary))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 46)
            .background {
                if filled {
                    shape.fill(LinearGradient(colors: [accent, Color(red: 0.54, green: 0.12, blue: 0.33)],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                } else {
                    shape.fill(prominent ? accent.opacity(0.08) : Color.white.opacity(0.38))
                }
            }
            .overlay { shape.strokeBorder(filled ? Color.clear : Color.primary.opacity(0.10)) }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.78 : 1)
    }
}
