import AuthenticationServices
import CryptoKit
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
                        deleteAccount: account.deleteAccount,
                        setPassword: account.setPassword,
                        betaPreferences: account.betaPreferences,
                        imagingAccessToken: { try await account.imagingAccessToken(for: accountID) },
                        messaging: CareMessaging(
                            fetch: { try await account.careInbox(for: accountID) },
                            send: { try await account.sendCareMessage($0, for: accountID) },
                            markRead: { try await account.markCareMessagesRead(for: accountID) },
                            slots: { try await account.careBookingSlots($0, for: accountID) },
                            book: { try await account.bookCareTime($0, slot: $1, for: accountID) },
                            unbook: { try await account.unbookCareTime($0, for: accountID) }
                        ),
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
        try await client.rpc("gohealth_sync_health_v3", params: batch).execute()
        guard user?.id == accountID else { throw URLError(.userAuthenticationRequired) }
    }

    /// The conversation with the care team, through the server functions (never the table directly).
    func careInbox(for accountID: UUID) async throws -> CareInbox {
        try ensureCareAccount(accountID)
        let inbox: CareInbox = try await client.rpc("gohealth_messages").execute().value
        try ensureCareAccount(accountID)
        return inbox
    }

    func sendCareMessage(_ body: String, for accountID: UUID) async throws -> CareInbox {
        try ensureCareAccount(accountID)
        let inbox: CareInbox = try await client.rpc("gohealth_send_message", params: ["p_body": body]).execute().value
        try ensureCareAccount(accountID)
        return inbox
    }

    func markCareMessagesRead(for accountID: UUID) async throws -> CareInbox {
        try ensureCareAccount(accountID)
        let inbox: CareInbox = try await client.rpc("gohealth_mark_messages_read").execute().value
        try ensureCareAccount(accountID)
        return inbox
    }

    /// The clinician's free times for a booking request in the conversation.
    func careBookingSlots(_ booking: UUID, for accountID: UUID) async throws -> [CareSlot] {
        try ensureCareAccount(accountID)
        let result: CareSlots = try await client.rpc("gohealth_booking_slots", params: ["p_booking": booking.uuidString]).execute().value
        try ensureCareAccount(accountID)
        return result.slots
    }

    func bookCareTime(_ booking: UUID, slot: UUID, for accountID: UUID) async throws -> CareInbox {
        try ensureCareAccount(accountID)
        let inbox: CareInbox = try await client.rpc("gohealth_book_time",
                                                    params: ["p_booking": booking.uuidString, "p_slot": slot.uuidString]).execute().value
        try ensureCareAccount(accountID)
        return inbox
    }

    func unbookCareTime(_ booking: UUID, for accountID: UUID) async throws -> CareInbox {
        try ensureCareAccount(accountID)
        let inbox: CareInbox = try await client.rpc("gohealth_unbook_time", params: ["p_booking": booking.uuidString]).execute().value
        try ensureCareAccount(accountID)
        return inbox
    }

    private func ensureCareAccount(_ accountID: UUID) throws {
        try Task.checkCancellation()
        guard betaPreferences == nil, user?.id == accountID else {
            throw URLError(.userAuthenticationRequired)
        }
    }

    private static let callbackURL = URL(string: "gohealth://auth/callback")!
    private let client = SupabaseClient(
        supabaseURL: URL(string: "https://eobycmemrstuivpchqcu.supabase.co")!,
        supabaseKey: "sb_publishable_99qA4y2mnlVBwLXKb5NTHQ_rMozPk-1",
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
        await run(failure: "Länken kunde inte skickas. Kontrollera e-postadressen och försök igen om en stund.") {
            try await client.auth.signInWithOTP(email: email)
        }
    }

    func clearError() { errorMessage = nil }

    /// Signs in with the code from the e-mail. Works in any mail app, with no link to open.
    func verifyEmailCode(email: String, code: String) async -> Bool {
        await run(failure: "Koden stämmer inte eller har gått ut. Be om en ny kod.") {
            try await client.auth.verifyOTP(email: email, token: code, type: .email)
        }
    }

    /// Password sign-in is only for accounts that already exist: it never creates one.
    func signIn(email: String, password: String) async -> Bool {
        await run(failure: "E-postadressen eller lösenordet stämmer inte. Har du inget lösenord än, använd e-postlänken.") {
            try await client.auth.signIn(email: email, password: password)
        }
    }

    /// Sets a password on the signed-in account, so it can be used for sign-in next time.
    func setPassword(_ password: String) async -> Bool {
        guard password.count >= 10 else { return false }
        #if DEBUG
        if betaSession != nil { return true }
        #endif
        return await run(failure: "Lösenordet kunde inte sparas.") {
            try await client.auth.update(user: UserAttributes(password: password))
        }
    }

    func signInWithGoogle() async {
        _ = await run(failure: "Google-inloggningen kunde inte slutföras. Försök igen eller använd e-post.") {
            try await client.auth.signInWithOAuth(provider: .google, queryParams: [("prompt", "select_account")]) { session in
                session.prefersEphemeralWebBrowserSession = true
            }
        }
    }

    // Sign in with Apple (guideline 4.8): the raw nonce goes to Supabase, its SHA-256 hash to Apple.
    private var appleNonce: String?

    func prepareAppleRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        appleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce = SHA256.hash(data: Data(nonce.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    func finishAppleSignIn(_ result: Result<ASAuthorization, Error>) async {
        let nonce = appleNonce
        appleNonce = nil
        let failure = "Apple-inloggningen kunde inte slutföras. Försök igen eller använd e-post."
        switch result {
        case .failure(let error as ASAuthorizationError) where error.code == .canceled:
            return
        case .failure:
            errorMessage = failure
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let tokenData = credential.identityToken,
                  let idToken = String(data: tokenData, encoding: .utf8),
                  let nonce else {
                errorMessage = failure
                return
            }
            // Apple only shares the name on the very first sign-in, so keep it right away.
            let name = [credential.fullName?.givenName, credential.fullName?.familyName]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            _ = await run(failure: failure) {
                let session = try await client.auth.signInWithIdToken(
                    credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
                )
                if !name.isEmpty, session.user.userMetadata["display_name"]?.stringValue == nil {
                    try await client.auth.update(user: UserAttributes(data: ["display_name": .string(name)]))
                }
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var generator = SystemRandomNumberGenerator()
        return String((0..<length).map { _ in charset.randomElement(using: &generator)! })
    }

    // App Store 5.1.1(v): the patient deletes the account from the app. The server keeps the
    // care provider's clinical record (patientdatalagen) but detaches it from the deleted login.
    func deleteAccount() async -> Bool {
        guard betaPreferences == nil, let id = user?.id else { return false }
        let deleted = await run(failure: "Kontot kunde inte raderas. Kontrollera anslutningen och försök igen.") {
            try await client.rpc("gohealth_delete_account").execute()
        }
        guard deleted else { return false }
        Self.removeLocalData(for: id)
        try? await client.auth.signOut(scope: .local)
        user = nil
        return true
    }

    // Every per-account preference key and file on this iPhone carries the account ID.
    private static func removeLocalData(for id: UUID) {
        let marker = id.uuidString
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.contains(marker) {
            defaults.removeObject(forKey: key)
        }
        let manager = FileManager.default
        guard let support = manager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let files = manager.enumerator(at: support, includingPropertiesForKeys: nil) else { return }
        for case let file as URL in files where file.lastPathComponent.contains(marker) {
            try? manager.removeItem(at: file)
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
    @State private var code = ""
    @FocusState private var codeFocused: Bool
    @State private var usesPassword = false
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
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

                Text(usesPassword ? "Logga in med ditt lösenord." : "Logga in eller skapa ett konto.")
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

            if usesPassword {
                HStack(spacing: 10) {
                    Image(systemName: "lock")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    SecureField("Lösenord", text: $password)
                        .textContentType(.password)
                        .focused($passwordFocused)
                        .submitLabel(.go)
                        .onSubmit(submitPassword)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
                .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
                .overlay {
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(passwordFocused ? accent.opacity(0.55) : Color.primary.opacity(0.12))
                        .allowsHitTesting(false)
                }
                .disabled(account.isBusy)

                Button(action: submitPassword) {
                    Text("Logga in")
                }
                .buttonStyle(GoHealthSignInButtonStyle(accent: accent, prominent: true))
                .disabled(account.isBusy || !email.contains("@") || password.isEmpty)

                Button {
                    usesPassword = false
                    password = ""
                    account.clearError()
                } label: {
                    Text("Använd e-postlänk i stället")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
                    Task { linkSent = await account.sendEmailLink(to: address) }
                } label: {
                    Text("Fortsätt med e-post")
                }
                .buttonStyle(GoHealthSignInButtonStyle(accent: accent, prominent: true))
                .disabled(account.isBusy || !email.contains("@"))

                if linkSent {
                    Label("Vi har skickat ett mejl. Skriv in koden från mejlet här, eller tryck på länken i det.", systemImage: "envelope")
                        .font(.footnote).foregroundStyle(.secondary)

                    HStack(spacing: 10) {
                        Image(systemName: "number")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        TextField("Kod från mejlet", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($codeFocused)
                            .onChange(of: code) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(10))
                                if digits != value { code = digits }
                                // The e-mail code has 8 digits; the button also works for shorter codes.
                                if digits.count == 8 && !account.isBusy { submitCode() }
                            }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(minHeight: 48)
                    .background(.white.opacity(0.62), in: RoundedRectangle(cornerRadius: 12))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(codeFocused ? accent.opacity(0.55) : Color.primary.opacity(0.12))
                            .allowsHitTesting(false)
                    }
                    .disabled(account.isBusy)

                    Button(action: submitCode) {
                        Text("Bekräfta kod")
                    }
                    .buttonStyle(GoHealthSignInButtonStyle(accent: accent, prominent: true))
                    .disabled(account.isBusy || code.count < 6)
                } else {
                    Text("Har du redan ett konto loggas du in, annars skapas ett nytt.")
                        .font(.footnote).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }

                Button {
                    usesPassword = true
                    linkSent = false
                    account.clearError()
                } label: {
                    Text("Logga in med lösenord")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            #if !DEBUG
            // Release only: the Sign in with Apple entitlement is in GoHealth-Release.entitlements,
            // because free personal development teams cannot sign it into Debug builds.
            SignInWithAppleButton(.continue) { request in
                linkSent = false
                account.prepareAppleRequest(request)
            } onCompletion: { result in
                Task { await account.finishAppleSignIn(result) }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(minHeight: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .disabled(account.isBusy)
            #endif

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

    private func submitCode() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), code.count >= 6, !account.isBusy else { return }
        let entered = code
        Task {
            if await account.verifyEmailCode(email: address, code: entered) { code = "" }
        }
    }

    private func submitPassword() {
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@"), !password.isEmpty, !account.isBusy else { return }
        Task {
            if await account.signIn(email: address, password: password) { password = "" }
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
