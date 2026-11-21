import SwiftUI

struct HealthProfile: Codable, Equatable {
    enum BiologicalSex: String, Codable, CaseIterable {
        case female, male, other

        var title: String {
            switch self {
            case .female: "Kvinna"
            case .male: "Man"
            case .other: "Annat"
            }
        }
    }

    var age: Int?
    var biologicalSex: BiologicalSex?
    var ethnicBackground: String?
    var backgroundCountryCode: String?
}

enum HealthProfileFiles {
    private static func folder() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("HealthProfiles", isDirectory: true)
    }

    private static func filename(for accountID: UUID) -> String { "\(accountID.uuidString).json" }

    static func load(for accountID: UUID) throws -> HealthProfile {
        let url = try folder().appendingPathComponent(filename(for: accountID))
        do {
            return try JSONDecoder().decode(HealthProfile.self, from: Data(contentsOf: url))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return HealthProfile()
        }
    }

    static func save(_ profile: HealthProfile, for accountID: UUID) throws {
        var directory = try folder()
        let url = directory.appendingPathComponent(filename(for: accountID))
        if profile == HealthProfile() {
            do {
                try FileManager.default.removeItem(at: url)
            } catch let error as CocoaError where error.code == .fileNoSuchFile {
                return
            }
            return
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var attributes = URLResourceValues()
        attributes.isExcludedFromBackup = true
        try directory.setResourceValues(attributes)
        try JSONEncoder().encode(profile).write(to: url, options: [.atomic, .completeFileProtection])
    }
}

struct HealthProfileView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var ageText: String
    @State private var biologicalSex: HealthProfile.BiologicalSex?
    @State private var legacyBackground: String?
    @State private var countryCode: String?
    @State private var showsCountryPicker = false
    @State private var showsBackgroundInfo = false
    @State private var showsSaveError = false

    let isOnboarding: Bool
    let save: (HealthProfile) throws -> Void

    init(profile: HealthProfile, isOnboarding: Bool, save: @escaping (HealthProfile) throws -> Void) {
        _ageText = State(initialValue: profile.age.map(String.init) ?? "")
        _biologicalSex = State(initialValue: profile.biologicalSex)
        _legacyBackground = State(initialValue: profile.ethnicBackground)
        _countryCode = State(initialValue: profile.backgroundCountryCode)
        self.isOnboarding = isOnboarding
        self.save = save
    }

    private var ageInput: String { ageText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var age: Int? { Int(ageInput).flatMap { (0...130).contains($0) ? $0 : nil } }
    private var ageIsInvalid: Bool { !ageInput.isEmpty && age == nil }
    private var selectedCountry: ProfileCountry? { ProfileCountry.all.first { $0.id == countryCode } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Om dig").font(.headline).accessibilityAddTraits(.isHeader)
                    VStack(spacing: 0) {
                        profileRow("Ålder", icon: "calendar") {
                            TextField("År", text: $ageText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(maxWidth: 90)
                                .accessibilityLabel("Ålder i år")
                        }
                        Divider().padding(.horizontal, 16)
                        sexPicker
                    }
                    .profileCard()

                    if ageIsInvalid {
                        Text("Ange åldern i hela år, mellan 0 och 130.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Geografisk bakgrund").font(.headline).accessibilityAddTraits(.isHeader)
                        Spacer()
                        Text("Frivilligt")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 4)
                            .background(.primary.opacity(0.05), in: Capsule())
                    }
                    VStack(spacing: 0) {
                        countryButton
                        if let legacyBackground {
                            Divider().padding(.horizontal, 16)
                            profileRow("Tidigare anteckning", icon: "note.text") {
                                Text(legacyBackground)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.trailing)
                                Button {
                                    self.legacyBackground = nil
                                } label: {
                                    Image(systemName: "xmark.circle.fill")
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Ta bort tidigare anteckning")
                            }
                        }
                    }
                    .profileCard()
                    backgroundInfo
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .background {
            LinearGradient(colors: [.white, Color(red: 0.98, green: 0.96, blue: 0.97)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
        }
        .navigationTitle(isOnboarding ? "" : "Hälsoprofil")
        .sheet(isPresented: $showsCountryPicker) { ProfileCountryPicker(selection: $countryCode) }
        .alert("Hälsoprofilen kunde inte sparas", isPresented: $showsSaveError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Kontrollera att iPhonen är upplåst och försök igen.")
        }
    }

    private var sexPicker: some View {
        Menu {
            Picker("Biologiskt kön", selection: $biologicalSex) {
                Text("Vill inte ange").tag(nil as HealthProfile.BiologicalSex?)
                ForEach(HealthProfile.BiologicalSex.allCases, id: \.self) { sex in
                    Text(sex.title).tag(Optional(sex))
                }
            }
        } label: {
            profileRow("Biologiskt kön", icon: "person.crop.circle") {
                Text(biologicalSex?.title ?? "Vill inte ange")
                    .font(.subheadline)
                    .multilineTextAlignment(.trailing)
                Image(systemName: "chevron.up.chevron.down").font(.caption2.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
    }

    private var countryButton: some View {
        Button {
            showsCountryPicker = true
        } label: {
            profileRow("Land eller region", icon: "globe.europe.africa") {
                if let selectedCountry {
                    Text(selectedCountry.flag).accessibilityHidden(true)
                    Text(selectedCountry.name)
                        .font(.subheadline)
                        .multilineTextAlignment(.trailing)
                } else {
                    Text("Välj").font(.subheadline)
                }
                Image(systemName: "chevron.right").font(.caption2.weight(.semibold))
            }
        }
        .buttonStyle(.plain)
    }

    private var backgroundInfo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.26)) { showsBackgroundInfo.toggle() }
            } label: {
                Label("Varför frågar vi?", systemImage: "info.circle")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(showsBackgroundInfo ? "Dölj förklaringen" : "Visa förklaringen")

            if showsBackgroundInfo {
                Text("Förekomsten av vissa sjukdomar varierar mellan regioner. Ärftlighet, miljö och tidigare exponeringar kan bidra. Landvalet beskriver din geografiska bakgrund och sparas som en frivillig profiluppgift.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 4)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                do {
                    try save(HealthProfile(age: age, biologicalSex: biologicalSex,
                                           ethnicBackground: legacyBackground, backgroundCountryCode: countryCode))
                    if !isOnboarding { dismiss() }
                } catch {
                    showsSaveError = true
                }
            } label: {
                HStack {
                    Spacer(minLength: 0)
                    Text(isOnboarding ? "Fortsätt till visningen" : "Spara ändringar").fontWeight(.semibold)
                    Spacer(minLength: 0)
                    Image(systemName: isOnboarding ? "arrow.right" : "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .accessibilityHidden(true)
                }
                .padding(.horizontal, 16)
                .frame(minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.roundedRectangle(radius: 16))
            .disabled(ageIsInvalid)

            Label("Sparas på den här iPhonen och kan ändras i Inställningar.", systemImage: "lock")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: 500)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func profileRow<Control: View>(_ title: String, icon: String, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
                .accessibilityHidden(true)
            Text(title).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
            Spacer(minLength: 2)
            HStack(spacing: 6) { control() }.foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .contentShape(Rectangle())
    }
}

private extension View {
    func profileCard() -> some View {
        background(.white, in: RoundedRectangle(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).strokeBorder(.black.opacity(0.06)) }
    }
}

private struct ProfileCountry: Identifiable {
    let id: String
    let name: String

    var flag: String {
        id.unicodeScalars.compactMap { UnicodeScalar($0.value + 0x1F1E6 - 65) }.map(String.init).joined()
    }

    static let locale = Locale(identifier: "sv_SE")
    static let all: [Self] = Locale.Region.isoRegions.compactMap { region in
        let code = region.identifier
        guard code.utf8.count == 2, code.utf8.allSatisfy({ (65...90).contains($0) }),
              let name = locale.localizedString(forRegionCode: code) else { return nil }
        return Self(id: code, name: name)
    }.sorted { $0.name.compare($1.name, locale: locale) == .orderedAscending }
}

private struct ProfileCountryPicker: View {
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @Binding var selection: String?

    private var results: [ProfileCountry] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ProfileCountry.all }
        return ProfileCountry.all.filter {
            $0.name.range(of: query, options: [.caseInsensitive, .diacriticInsensitive], locale: ProfileCountry.locale) != nil
                || $0.id.caseInsensitiveCompare(query) == .orderedSame
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button("Vill inte ange") { select(nil) }
                }
                ForEach(results) { country in
                    Button {
                        select(country.id)
                    } label: {
                        HStack(spacing: 12) {
                            Text(country.flag).accessibilityHidden(true)
                            Text(country.name).foregroundStyle(.primary)
                            Spacer()
                            if selection == country.id {
                                Image(systemName: "checkmark").foregroundStyle(.tint).accessibilityHidden(true)
                            }
                        }
                        .frame(minHeight: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == country.id ? .isSelected : [])
                }
            }
            .overlay {
                if results.isEmpty { ContentUnavailableView.search(text: search) }
            }
            .searchable(text: $search, prompt: "Sök land eller region")
            .navigationTitle("Land eller region")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Stäng") { dismiss() } }
            }
        }
    }

    private func select(_ code: String?) {
        selection = code
        dismiss()
    }
}

enum OnboardingStep: Int, CaseIterable {
    case intro = 1, signIn, avatar, appleHealth, profile, doctor, tour

    var title: String {
        switch self {
        case .intro: "Introduktion"
        case .signIn: "Inloggning"
        case .avatar: "3D-avatar"
        case .appleHealth: "Apple Hälsa"
        case .profile: "Profil"
        case .doctor: "Läkarval"
        case .tour: "Kom igång"
        }
    }
}

struct OnboardingProgress: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let step: OnboardingStep
    var onSkip: (() -> Void)? = nil
    var includesDoctorSelection = false

    var body: some View {
        let steps = OnboardingStep.allCases.filter { includesDoctorSelection || $0 != .doctor }
        let stepNumber = (steps.firstIndex(of: step) ?? 0) + 1
        VStack(spacing: 4) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Text("Steg \(stepNumber) av \(steps.count)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)

                if let onSkip {
                    Button(action: onSkip) {
                        Text("Hoppa över")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.tint)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.tint.opacity(0.08), in: Capsule())
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(step == .signIn ? "Startar Beta-login" : "Går vidare i introduktionen")
                }
            }
            .frame(minHeight: 44)
            HStack(spacing: 5) {
                ForEach(steps, id: \.self) { segment in
                    Capsule()
                        .fill(.tint)
                        .opacity(segment == step ? 1 : 0.38)
                        .frame(height: 4)
                        .opacity(segment.rawValue <= step.rawValue ? 1 : 0)
                        .background(.primary.opacity(0.08), in: Capsule())
                }
            }
            .accessibilityHidden(true)
        }
        .frame(maxWidth: 500)
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: step)
    }
}
