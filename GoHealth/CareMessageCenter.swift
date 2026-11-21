import SwiftUI

struct CareMessage: Decodable, Identifiable {
    let id: UUID
    let providerName: String
    let clinicianName: String?
    let bookingURL: URL?
    let createdAt: Date
    let resolvedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case providerName = "provider_name"
        case clinicianName = "clinician_name"
        case bookingURL = "booking_url"
        case createdAt = "created_at"
        case resolvedAt = "resolved_at"
    }

    var secureBookingURL: URL? {
        guard let bookingURL,
              bookingURL.scheme?.lowercased() == "https",
              bookingURL.host?.isEmpty == false,
              bookingURL.user == nil, bookingURL.password == nil else { return nil }
        return bookingURL
    }

    static let examples: [Self] = [
        Self(id: UUID(), providerName: "Exempelmottagning", clinicianName: "Dr Sofia Lind",
             bookingURL: nil, createdAt: .now, resolvedAt: nil),
        Self(id: UUID(), providerName: "Exempelklinik", clinicianName: nil, bookingURL: nil,
             createdAt: .now.addingTimeInterval(-7 * 86_400), resolvedAt: nil),
        Self(id: UUID(), providerName: "Exempelmottagning", clinicianName: "Dr Sofia Lind", bookingURL: nil,
             createdAt: .now.addingTimeInterval(-30 * 86_400),
             resolvedAt: .now.addingTimeInterval(-28 * 86_400))
    ]
}

@MainActor
final class CareMessageStore: ObservableObject {
    @Published private(set) var records: [CareMessage] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var loadFailed = false
    @Published private var dismissed: Set<UUID>
    let isBeta: Bool

    private let preferences: UserDefaults
    private let dismissalKey: String
    private let fetch: () async throws -> [CareMessage]
    private var isLoading = false

    var current: [CareMessage] { records.filter { $0.resolvedAt == nil } }
    var previous: [CareMessage] { records.filter { $0.resolvedAt != nil } }
    var notice: CareMessage? { current.first { !dismissed.contains($0.id) } }

    init(accountID: UUID, betaPreferences: UserDefaults?, fetch: @escaping () async throws -> [CareMessage]) {
        isBeta = betaPreferences != nil
        preferences = betaPreferences ?? .standard
        dismissalKey = "dismissedCareNotices.\(accountID.uuidString)"
        dismissed = Set((preferences.stringArray(forKey: dismissalKey) ?? []).compactMap(UUID.init(uuidString:)))
        self.fetch = fetch
        if isBeta {
            records = CareMessage.examples
            isLoaded = true
        }
    }

    func dismissNotice() {
        dismissed.formUnion(current.map(\.id))
        saveDismissals()
    }

    func refresh() async {
        guard !isBeta, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await fetch()
            try Task.checkCancellation()
            records = fetched
            let activeDismissals = dismissed.intersection(current.map(\.id))
            if activeDismissals != dismissed {
                dismissed = activeDismissals
                saveDismissals()
            }
            isLoaded = true
            loadFailed = false
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    func refreshWhileActive() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(15))
            } catch {
                return
            }
        }
    }

    private func saveDismissals() {
        preferences.set(dismissed.map(\.uuidString), forKey: dismissalKey)
    }
}

struct CareMessageIcon: View {
    let count: Int
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            Image(systemName: "envelope")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 44, height: 44)
                .background(.tint.opacity(0.07), in: Circle().inset(by: 3))
                .overlay(alignment: .topTrailing) {
                    if count > 0 {
                        Text(count > 99 ? "99+" : String(count))
                            .font(.caption2.weight(.bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 17, minHeight: 17)
                            .background(.tint, in: Capsule())
                            .overlay { Capsule().strokeBorder(.white, lineWidth: 1.5) }
                            .offset(x: 4, y: -2)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Meddelandecenter")
        .accessibilityValue(count == 1 ? "1 aktuellt ärende" : "\(count) aktuella ärenden")
    }
}

struct CareMessageNotice: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var edgeHighlighted = false

    let firstName: String?
    let message: CareMessage
    let isBeta: Bool
    let open: () -> Void
    let dismiss: () -> Void

    private var greeting: String {
        let salutation = firstName.map { "Hej \($0)" } ?? "Hej"
        let sender = message.clinicianName ?? "din läkare"
        return "\(salutation), \(sender) önskar kontakta dig."
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Button(action: open) {
                HStack(spacing: 6) {
                    if isBeta, message.clinicianName != nil {
                        CareMessageSenderImage(message: message, isBeta: isBeta, portraitSize: 26)
                    }
                    Text(greeting)
                        .font(.caption.weight(.medium))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .padding(.leading, 9)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .accessibilityHint("Öppnar Meddelandecenter")

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 38, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Stäng meddelandenotisen")
        }
        .buttonStyle(.plain)
        .background(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 13)
                .fill(.white)
                .background(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(.white)
                        .frame(width: 10, height: 10)
                        .rotationEffect(.degrees(45))
                        .offset(x: -25, y: -4)
                }
                .shadow(color: .black.opacity(0.09), radius: 7, y: 3)
                .allowsHitTesting(false)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 13)
                .strokeBorder(.tint, lineWidth: 1.5)
                .opacity(edgeHighlighted && !reduceMotion ? 0.5 : 0.12)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .task(id: reduceMotion ? nil : message.id) {
            edgeHighlighted = false
            guard !reduceMotion else { return }
            do {
                while true {
                    try Task.checkCancellation()
                    withAnimation(.easeInOut(duration: 0.45)) { edgeHighlighted = true }
                    try await Task.sleep(for: .milliseconds(450))
                    withAnimation(.easeInOut(duration: 0.65)) { edgeHighlighted = false }
                    try await Task.sleep(for: .milliseconds(650))
                }
            } catch {
                // The notice was closed or replaced.
            }
        }
    }
}

struct CareMessageCenter: View {
    private enum Segment: String, CaseIterable {
        case current = "Aktuella"
        case previous = "Tidigare"
    }

    @ObservedObject var store: CareMessageStore
    let close: () -> Void
    @State private var segment = Segment.current
    private let background = Color(red: 0.965, green: 0.970, blue: 0.982)

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                CareMessageSymbol(symbol: "envelope")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Meddelandecenter")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    if store.isBeta {
                        Text("Testdata").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                CareMessageCloseButton(label: "Stäng Meddelandecenter", close: close)
            }
            .padding(.horizontal, 20)

            Picker("Ärenden", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)

            if !store.isLoaded {
                if store.loadFailed {
                    ContentUnavailableView {
                        Label("Meddelandena kunde inte hämtas", systemImage: "envelope")
                    } actions: {
                        Button("Försök igen") { Task { await store.refresh() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                messageList
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(background)
        .task { await store.refresh() }
        .accessibilityAction(.escape, close)
    }

    private var messageList: some View {
        let records = segment == .current ? store.current : store.previous
        return ScrollView {
            if store.loadFailed {
                Label("Kunde inte uppdatera ärendena", systemImage: "arrow.clockwise")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
            }
            if records.isEmpty {
                ContentUnavailableView(segment == .current ? "Inga aktuella ärenden" : "Inga tidigare ärenden",
                                       systemImage: segment == .current ? "envelope" : "clock")
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(records) { message in
                        HStack(alignment: .top, spacing: 12) {
                            CareMessageSenderImage(message: message, isBeta: store.isBeta)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(message.clinicianName ?? message.providerName)
                                    .font(.subheadline.weight(.semibold))
                                if message.clinicianName != nil {
                                    Text(message.providerName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let resolvedAt = message.resolvedAt {
                                    Text("Avslutat \(resolvedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(message.clinicianName == nil
                                         ? "Din läkare vill komma i kontakt med dig."
                                         : "Vill komma i kontakt med dig.")
                                        .font(.subheadline)
                                    Text(message.createdAt, format: .dateTime.day().month(.abbreviated).year())
                                        .font(.caption).foregroundStyle(.secondary)
                                    CareBookingLink(message: message, isBeta: store.isBeta)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(14)
                        .background(.white, in: RoundedRectangle(cornerRadius: 19))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .scrollBounceBehavior(.always)
        .refreshable { await store.refresh() }
    }
}

private struct CareMessageSenderImage: View {
    let message: CareMessage
    let isBeta: Bool
    var portraitSize: CGFloat = 48

    var body: some View {
        if isBeta, message.clinicianName != nil {
            Image("DemoClinicianPortrait")
                .resizable()
                .scaledToFill()
                .frame(width: portraitSize, height: portraitSize)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.primary.opacity(0.08)) }
                .accessibilityHidden(true)
        } else {
            CareMessageSymbol(symbol: message.resolvedAt == nil ? "envelope.fill" : "checkmark")
        }
    }
}

private struct CareMessageSymbol: View {
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(.tint)
            .frame(width: 40, height: 40)
            .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
            .accessibilityHidden(true)
    }
}

private struct CareMessageCloseButton: View {
    let label: String
    let close: () -> Void

    var body: some View {
        Button(action: close) {
            Image(systemName: "xmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .background(.primary.opacity(0.045), in: Circle().inset(by: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct CareBookingLink: View {
    let message: CareMessage
    let isBeta: Bool
    @State private var showsDemo = false

    var body: some View {
        Group {
            if isBeta {
                Button { showsDemo = true } label: { label }
                    .alert("Testbokning", isPresented: $showsDemo) {
                        Button("Stäng", role: .cancel) {}
                    } message: {
                        Text("Här öppnas vårdgivarens bokningssida för ett riktigt ärende.")
                    }
            } else if let url = message.secureBookingURL {
                Link(destination: url) { label }
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }

    private var label: some View {
        Label("Boka din tid här", systemImage: "arrow.up.right")
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
    }
}
