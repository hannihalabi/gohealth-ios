import SwiftUI

/// Times from the server: UTC with or without fractional seconds.
fileprivate func careDate(_ text: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return fractional.date(from: text) ?? ISO8601DateFormatter().date(from: text)
}

/// "tis 25 nov 09:20–09:40" in Swedish time.
fileprivate func careTimeText(_ start: Date, _ end: Date?) -> String {
    let day = DateFormatter()
    day.locale = Locale(identifier: "sv_SE")
    day.timeZone = TimeZone(identifier: "Europe/Stockholm")
    day.dateFormat = "EEE d MMM HH:mm"
    let clock = DateFormatter()
    clock.locale = day.locale
    clock.timeZone = day.timeZone
    clock.dateFormat = "HH:mm"
    return day.string(from: start) + (end.map { "–" + clock.string(from: $0) } ?? "")
}

/// A request from the care team to book a time, and the time once booked.
struct CareBooking: Decodable, Identifiable, Equatable {
    let id: UUID
    let status: String
    let visitType: String
    let startsAt: Date?
    let endsAt: Date?
    let clinicianName: String?
    let canUnbook: Bool

    var isOpen: Bool { status == "open" }
    var isBooked: Bool { status == "booked" }
    var visitName: String {
        switch visitType {
        case "video": return "Videosamtal"
        case "phone": return "Telefonsamtal"
        default: return "Besök på mottagningen"
        }
    }
    var timeText: String? { startsAt.map { careTimeText($0, endsAt) } }

    enum CodingKeys: String, CodingKey {
        case id, status
        case visitType = "visit_type"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case clinicianName = "clinician_name"
        case canUnbook = "can_unbook"
    }

    init(id: UUID, status: String, visitType: String, startsAt: Date? = nil, endsAt: Date? = nil, clinicianName: String? = nil, canUnbook: Bool = false) {
        self.id = id
        self.status = status
        self.visitType = visitType
        self.startsAt = startsAt
        self.endsAt = endsAt
        self.clinicianName = clinicianName
        self.canUnbook = canUnbook
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        status = try c.decode(String.self, forKey: .status)
        visitType = try c.decode(String.self, forKey: .visitType)
        startsAt = try c.decodeIfPresent(String.self, forKey: .startsAt).flatMap(careDate)
        endsAt = try c.decodeIfPresent(String.self, forKey: .endsAt).flatMap(careDate)
        clinicianName = try c.decodeIfPresent(String.self, forKey: .clinicianName)
        canUnbook = try c.decodeIfPresent(Bool.self, forKey: .canUnbook) ?? false
    }
}

/// One of the clinician's free times.
struct CareSlot: Decodable, Identifiable, Equatable {
    let id: UUID
    let startsAt: Date
    let endsAt: Date

    var timeText: String { careTimeText(startsAt, endsAt) }

    enum CodingKeys: String, CodingKey {
        case id
        case startsAt = "starts_at"
        case endsAt = "ends_at"
    }

    init(id: UUID, startsAt: Date, endsAt: Date) {
        self.id = id
        self.startsAt = startsAt
        self.endsAt = endsAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        guard let start = careDate(try c.decode(String.self, forKey: .startsAt)),
              let end = careDate(try c.decode(String.self, forKey: .endsAt)) else {
            throw DecodingError.dataCorruptedError(forKey: .startsAt, in: c, debugDescription: "Invalid date")
        }
        startsAt = start
        endsAt = end
    }

    static func examples(from now: Date = .now) -> [Self] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Stockholm") ?? .current
        let tomorrow = calendar.startOfDay(for: now.addingTimeInterval(86_400))
        return (0..<3).flatMap { day in
            [9 * 60, 9 * 60 + 20, 9 * 60 + 40, 13 * 60].map { minute in
                let start = tomorrow.addingTimeInterval(Double(day * 86_400 + minute * 60))
                return Self(id: UUID(), startsAt: start, endsAt: start.addingTimeInterval(20 * 60))
            }
        }
    }
}

struct CareSlots: Decodable {
    let slots: [CareSlot]
}

/// One message in the conversation between the patient and the care team.
struct CareMessage: Decodable, Identifiable, Equatable {
    let id: UUID
    let sender: String
    let kind: String
    let authorName: String
    let body: String
    let createdAt: Date
    let readAt: Date?
    let booking: CareBooking?

    var fromCareTeam: Bool { sender == "clinician" }
    /// A booking or cancellation, shown as a line in the conversation rather than a bubble.
    var isEvent: Bool { kind == "booked" || kind == "unbooked" }
    /// The clinician's name for messages from the care team, used in the notice.
    var clinicianName: String? { fromCareTeam ? authorName : nil }

    enum CodingKeys: String, CodingKey {
        case id, sender, kind, body, booking
        case authorName = "author_name"
        case createdAt = "created_at"
        case readAt = "read_at"
    }

    init(id: UUID, sender: String, kind: String = "text", authorName: String, body: String, createdAt: Date, readAt: Date?, booking: CareBooking? = nil) {
        self.id = id
        self.sender = sender
        self.kind = kind
        self.authorName = authorName
        self.body = body
        self.createdAt = createdAt
        self.readAt = readAt
        self.booking = booking
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sender = try c.decode(String.self, forKey: .sender)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "text"
        authorName = try c.decode(String.self, forKey: .authorName)
        body = try c.decode(String.self, forKey: .body)
        let created = try c.decode(String.self, forKey: .createdAt)
        guard let createdAt = careDate(created) else {
            throw DecodingError.dataCorruptedError(forKey: .createdAt, in: c, debugDescription: "Invalid date")
        }
        self.createdAt = createdAt
        readAt = try c.decodeIfPresent(String.self, forKey: .readAt).flatMap(careDate)
        booking = try c.decodeIfPresent(CareBooking.self, forKey: .booking)
    }

    func with(readAt: Date? = nil, booking: CareBooking? = nil) -> Self {
        Self(id: id, sender: sender, kind: kind, authorName: authorName, body: body, createdAt: createdAt,
             readAt: readAt ?? self.readAt, booking: booking ?? self.booking)
    }

    static let examples: [Self] = [
        Self(id: UUID(), sender: "clinician", kind: "booking", authorName: "Dr Sofia Lind",
             body: "Vi behöver ta om sköldkörtelprovet. Välj en tid för videosamtal nedan.",
             createdAt: .now.addingTimeInterval(-3_600), readAt: nil,
             booking: CareBooking(id: UUID(), status: "open", visitType: "video", clinicianName: "Dr Sofia Lind")),
        Self(id: UUID(), sender: "patient", authorName: "Du", body: "Tack, då bokar jag en tid.",
             createdAt: .now.addingTimeInterval(-86_400 * 2), readAt: nil),
        Self(id: UUID(), sender: "clinician", authorName: "Dr Sofia Lind", body: "Välkommen till GoHealth!",
             createdAt: .now.addingTimeInterval(-86_400 * 3), readAt: .now.addingTimeInterval(-86_400 * 3))
    ].sorted { $0.createdAt < $1.createdAt }
}

struct CareInbox: Decodable {
    let canReply: Bool
    let messages: [CareMessage]
    /// Booked times still ahead, also when the conversation has been closed.
    let upcoming: [CareBooking]

    enum CodingKeys: String, CodingKey {
        case canReply = "can_reply"
        case messages, upcoming
    }

    init(canReply: Bool, messages: [CareMessage], upcoming: [CareBooking] = []) {
        self.canReply = canReply
        self.messages = messages
        self.upcoming = upcoming
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        canReply = try c.decode(Bool.self, forKey: .canReply)
        messages = try c.decode([CareMessage].self, forKey: .messages)
        upcoming = try c.decodeIfPresent([CareBooking].self, forKey: .upcoming) ?? []
    }
}

/// Server calls for the conversation. The app never reads the table directly.
struct CareMessaging {
    var fetch: () async throws -> CareInbox
    var send: (String) async throws -> CareInbox
    var markRead: () async throws -> CareInbox
    var slots: (UUID) async throws -> [CareSlot]
    var book: (UUID, UUID) async throws -> CareInbox
    var unbook: (UUID) async throws -> CareInbox

    static let unavailable = CareMessaging(
        fetch: { CareInbox(canReply: false, messages: []) },
        send: { _ in throw URLError(.userAuthenticationRequired) },
        markRead: { CareInbox(canReply: false, messages: []) },
        slots: { _ in throw URLError(.userAuthenticationRequired) },
        book: { _, _ in throw URLError(.userAuthenticationRequired) },
        unbook: { _ in throw URLError(.userAuthenticationRequired) }
    )
}

@MainActor
final class CareMessageStore: ObservableObject {
    @Published private(set) var records: [CareMessage] = []
    @Published private(set) var upcoming: [CareBooking] = []
    @Published private(set) var canReply = false
    @Published private(set) var isLoaded = false
    @Published private(set) var loadFailed = false
    @Published private(set) var isSending = false
    @Published private var dismissed: Set<UUID>
    let isBeta: Bool

    private let preferences: UserDefaults
    private let dismissalKey: String
    private let messaging: CareMessaging
    private var isLoading = false

    /// Unread messages from the care team: the badge count and the source of the notice.
    var current: [CareMessage] { records.filter { $0.fromCareTeam && $0.readAt == nil } }
    var notice: CareMessage? { current.last { !dismissed.contains($0.id) } }

    init(accountID: UUID, betaPreferences: UserDefaults?, messaging: CareMessaging) {
        isBeta = betaPreferences != nil
        preferences = betaPreferences ?? .standard
        dismissalKey = "dismissedCareNotices.\(accountID.uuidString)"
        dismissed = Set((preferences.stringArray(forKey: dismissalKey) ?? []).compactMap(UUID.init(uuidString:)))
        self.messaging = messaging
        if isBeta {
            records = CareMessage.examples
            canReply = true
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
            let inbox = try await messaging.fetch()
            try Task.checkCancellation()
            apply(inbox)
            isLoaded = true
            loadFailed = false
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    /// Opening the conversation marks the care team's messages as read, which clears the badge and the notice.
    func markRead() async {
        guard !current.isEmpty else { return }
        if isBeta {
            records = records.map { $0.fromCareTeam && $0.readAt == nil ? $0.with(readAt: .now) : $0 }
            return
        }
        if let inbox = try? await messaging.markRead() { apply(inbox) }
    }

    func send(_ text: String) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, canReply, !isSending else { return }
        isSending = true
        defer { isSending = false }
        if isBeta {
            records.append(CareMessage(id: UUID(), sender: "patient", authorName: "Du", body: body, createdAt: .now, readAt: nil))
            return
        }
        apply(try await messaging.send(body))
    }

    /// The clinician's free times for a booking request.
    func slots(for booking: CareBooking) async throws -> [CareSlot] {
        if isBeta { return CareSlot.examples() }
        return try await messaging.slots(booking.id)
    }

    func book(_ booking: CareBooking, at slot: CareSlot) async throws {
        if isBeta {
            let booked = CareBooking(id: booking.id, status: "booked", visitType: booking.visitType, startsAt: slot.startsAt,
                                     endsAt: slot.endsAt, clinicianName: booking.clinicianName, canUnbook: true)
            records = records.map { $0.booking?.id == booking.id ? $0.with(booking: booked) : $0 }
            records.append(CareMessage(id: UUID(), sender: "patient", kind: "booked", authorName: "Du",
                                       body: "Bokade \(slot.timeText) · \(booking.visitName)", createdAt: .now, readAt: nil))
            upcoming = [booked]
            return
        }
        apply(try await messaging.book(booking.id, slot.id))
    }

    func unbook(_ booking: CareBooking) async throws {
        if isBeta {
            let reopened = CareBooking(id: booking.id, status: "open", visitType: booking.visitType, clinicianName: booking.clinicianName)
            records = records.map { $0.booking?.id == booking.id ? $0.with(booking: reopened) : $0 }
            records.append(CareMessage(id: UUID(), sender: "patient", kind: "unbooked", authorName: "Du",
                                       body: "Avbokade \(booking.timeText ?? "tiden")", createdAt: .now, readAt: nil))
            upcoming = []
            return
        }
        apply(try await messaging.unbook(booking.id))
    }

    func refreshWhileActive() async {
        while !Task.isCancelled {
            await refresh()
            do {
                try await Task.sleep(for: .seconds(10))
            } catch {
                return
            }
        }
    }

    private func apply(_ inbox: CareInbox) {
        records = inbox.messages
        canReply = inbox.canReply
        upcoming = inbox.upcoming
        let activeDismissals = dismissed.intersection(current.map(\.id))
        if activeDismissals != dismissed {
            dismissed = activeDismissals
            saveDismissals()
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
        .accessibilityLabel("Meddelanden")
        .accessibilityValue(count == 1 ? "1 oläst meddelande" : "\(count) olästa meddelanden")
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
                        CareMessageSenderImage(isBeta: isBeta, portraitSize: 26)
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
            .accessibilityHint("Öppnar meddelandet")

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

/// The conversation with the care team. The patient can reply once a clinician has written.
struct CareMessageCenter: View {
    @ObservedObject var store: CareMessageStore
    let close: () -> Void
    @State private var draft = ""
    @State private var sendFailed = false
    @State private var bookingTarget: CareBooking?
    @State private var unbookTarget: CareBooking?
    @State private var unbookFailed = false
    private let background = Color(red: 0.965, green: 0.970, blue: 0.982)

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                CareMessageSymbol(symbol: "envelope")
                VStack(alignment: .leading, spacing: 3) {
                    Text("Meddelanden")
                        .font(.title3.weight(.semibold))
                        .accessibilityAddTraits(.isHeader)
                    Text(store.isBeta ? "Testdata" : "Från ditt vårdteam")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                CareMessageCloseButton(label: "Stäng meddelanden", close: close)
            }
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
                conversation
                composer
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(background)
        .task {
            await store.refresh()
            await store.markRead()
            // While the conversation is open, replies from the care team appear within a few seconds.
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(3))
                } catch {
                    return
                }
                await store.refresh()
            }
        }
        .onChange(of: store.current.count) { _, count in
            if count > 0 { Task { await store.markRead() } }
        }
        .alert("Meddelandet kunde inte skickas", isPresented: $sendFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Kontrollera anslutningen och försök igen.")
        }
        .sheet(item: $bookingTarget) { booking in
            CareBookingSheet(store: store, booking: booking)
                .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Avboka tiden?",
                            isPresented: Binding(get: { unbookTarget != nil }, set: { if !$0 { unbookTarget = nil } }),
                            titleVisibility: .visible,
                            presenting: unbookTarget) { booking in
            Button("Avboka \(booking.timeText ?? "tiden")", role: .destructive) {
                Task {
                    do {
                        try await store.unbook(booking)
                    } catch {
                        unbookFailed = true
                    }
                }
            }
            Button("Behåll tiden", role: .cancel) {}
        } message: { _ in
            Text("Vårdteamet får veta att du har avbokat.")
        }
        .alert("Tiden kunde inte avbokas", isPresented: $unbookFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Kontrollera anslutningen och försök igen.")
        }
        .accessibilityAction(.escape, close)
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if store.loadFailed {
                    Label("Kunde inte uppdatera meddelandena", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                }
                // Booked times whose conversation the care team has closed.
                let closedBookings = store.upcoming.filter { booking in !store.records.contains { $0.booking?.id == booking.id } }
                if !closedBookings.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(closedBookings) { booking in
                            CareUpcomingCard(booking: booking, unbook: { unbookTarget = booking })
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                }
                if store.records.isEmpty {
                    // A fixed-size empty state: a full-height one would draw over the booked-time card and its button.
                    VStack(spacing: 8) {
                        Image(systemName: "envelope")
                            .font(.system(size: 34, weight: .regular))
                            .foregroundStyle(.secondary)
                        Text("Inga meddelanden")
                            .font(.title3.weight(.semibold))
                        Text("När ditt vårdteam skriver till dig visas det här.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 20)
                    .padding(.top, closedBookings.isEmpty ? 80 : 28)
                    .accessibilityElement(children: .combine)
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach(store.records) { message in
                            Group {
                                if message.isEvent {
                                    CareEventRow(message: message)
                                } else {
                                    CareMessageBubble(message: message, isBeta: store.isBeta,
                                                      book: { bookingTarget = $0 },
                                                      unbook: { unbookTarget = $0 })
                                }
                            }
                            .id(message.id)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }
            .scrollBounceBehavior(.always)
            .refreshable { await store.refresh() }
            .onAppear { proxy.scrollTo(store.records.last?.id, anchor: .bottom) }
            .onChange(of: store.records.last?.id) { _, last in
                withAnimation { proxy.scrollTo(last, anchor: .bottom) }
            }
        }
    }

    @ViewBuilder private var composer: some View {
        if store.canReply {
            let empty = draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Skriv ett svar…", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(.primary.opacity(0.08)) }
                Button {
                    let text = draft
                    Task {
                        do {
                            try await store.send(text)
                            draft = ""
                        } catch {
                            sendFailed = true
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(.tint, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(empty || store.isSending)
                .opacity(empty ? 0.45 : 1)
                .accessibilityLabel("Skicka")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)
        } else {
            Text("Du kan svara när ditt vårdteam har skrivit till dig.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.bottom, 14)
        }
    }
}

private struct CareMessageBubble: View {
    let message: CareMessage
    let isBeta: Bool
    var book: (CareBooking) -> Void = { _ in }
    var unbook: (CareBooking) -> Void = { _ in }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.fromCareTeam {
                CareMessageSenderImage(isBeta: isBeta, portraitSize: 30)
            } else {
                Spacer(minLength: 48)
            }
            VStack(alignment: message.fromCareTeam ? .leading : .trailing, spacing: 4) {
                Text(message.body)
                    .font(.subheadline)
                    .foregroundStyle(message.fromCareTeam ? Color.primary : Color.white)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(message.fromCareTeam ? AnyShapeStyle(.white) : AnyShapeStyle(.tint),
                                in: RoundedRectangle(cornerRadius: 18))
                    .textSelection(.enabled)
                if message.kind == "booking", let booking = message.booking {
                    CareBookingCard(booking: booking, book: { book(booking) }, unbook: { unbook(booking) })
                }
                Text("\(message.fromCareTeam ? message.authorName : "Du") · \(message.createdAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            if message.fromCareTeam { Spacer(minLength: 48) }
        }
        .frame(maxWidth: .infinity, alignment: message.fromCareTeam ? .leading : .trailing)
        .accessibilityElement(children: message.booking == nil ? .combine : .contain)
    }
}

/// "Boka här" under the care team's message, then the booked time.
private struct CareBookingCard: View {
    let booking: CareBooking
    let book: () -> Void
    let unbook: () -> Void

    private var status: String {
        if booking.isBooked, let time = booking.timeText { return "Bokad \(time)" }
        if booking.isOpen { return "Välj en tid som passar dig" }
        return "Inte längre aktuell"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: booking.isBooked ? "calendar.badge.checkmark" : "calendar.badge.clock")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 34, height: 34)
                    .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(booking.visitName)
                        .font(.subheadline.weight(.semibold))
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .strikethrough(booking.status == "withdrawn")
                }
            }
            if booking.isOpen {
                Button(action: book) {
                    Text("Boka här")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else if booking.isBooked, booking.canUnbook {
                Button("Avboka", role: .destructive, action: unbook)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: 290, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.tint.opacity(0.18)) }
        .opacity(booking.status == "withdrawn" ? 0.65 : 1)
    }
}

/// A booked time that stays visible after the care team closed the conversation.
private struct CareUpcomingCard: View {
    let booking: CareBooking
    let unbook: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: 40, height: 40)
                .background(.tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Bokad tid")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(booking.timeText ?? "")
                    .font(.subheadline.weight(.semibold))
                Text([booking.visitName, booking.clinicianName].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if booking.canUnbook {
                Button("Avboka", role: .destructive, action: unbook)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(12)
        .background(.white, in: RoundedRectangle(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(.tint.opacity(0.18)) }
        .accessibilityElement(children: .contain)
    }
}

/// "Du bokade …" or "… är avbokad." as a line in the conversation.
private struct CareEventRow: View {
    let message: CareMessage

    private var text: String {
        guard !message.fromCareTeam, let first = message.body.first else { return message.body }
        return "Du " + first.lowercased() + message.body.dropFirst()
    }

    var body: some View {
        let booked = message.kind == "booked"
        Label(text, systemImage: booked ? "calendar.badge.checkmark" : "calendar.badge.minus")
            .font(.caption.weight(.medium))
            .foregroundStyle(booked ? Color(red: 0.12, green: 0.42, blue: 0.29) : Color(red: 0.6, green: 0.15, blue: 0.24))
            .multilineTextAlignment(.center)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background((booked ? Color.green : Color.red).opacity(0.08), in: Capsule())
            .frame(maxWidth: .infinity)
    }
}

/// The clinician's free times, grouped by day. The patient picks one and confirms.
struct CareBookingSheet: View {
    @ObservedObject var store: CareMessageStore
    let booking: CareBooking
    @Environment(\.dismiss) private var dismiss
    @State private var slots: [CareSlot]?
    @State private var loadFailed = false
    @State private var selected: CareSlot?
    @State private var isBooking = false
    @State private var bookFailed = false

    private struct Day: Identifiable {
        let id: Date
        let slots: [CareSlot]
    }

    private static let zone = TimeZone(identifier: "Europe/Stockholm") ?? .current

    private var days: [Day] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = Self.zone
        let groups = Dictionary(grouping: slots ?? []) { calendar.startOfDay(for: $0.startsAt) }
        return groups.keys.sorted().map { Day(id: $0, slots: groups[$0, default: []].sorted { $0.startsAt < $1.startsAt }) }
    }

    private func title(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.timeZone = Self.zone
        f.dateFormat = "EEEE d MMMM"
        let text = f.string(from: day)
        return text.prefix(1).uppercased() + text.dropFirst()
    }

    private func clock(_ slot: CareSlot) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "sv_SE")
        f.timeZone = Self.zone
        f.dateFormat = "HH:mm"
        return "\(f.string(from: slot.startsAt))–\(f.string(from: slot.endsAt))"
    }

    var body: some View {
        NavigationStack {
            Group {
                if let slots {
                    if slots.isEmpty {
                        ContentUnavailableView("Inga lediga tider",
                                               systemImage: "calendar",
                                               description: Text("Det finns inga lediga tider just nu. Skriv till ditt vårdteam i chatten."))
                    } else {
                        List {
                            ForEach(days) { day in
                                Section(title(day.id)) {
                                    ForEach(day.slots) { slot in
                                        Button {
                                            selected = slot
                                        } label: {
                                            HStack {
                                                Text(clock(slot))
                                                    .monospacedDigit()
                                                Spacer()
                                                if selected == slot {
                                                    Image(systemName: "checkmark.circle.fill")
                                                        .foregroundStyle(.tint)
                                                }
                                            }
                                            .contentShape(Rectangle())
                                        }
                                        .foregroundStyle(.primary)
                                        .accessibilityAddTraits(selected == slot ? .isSelected : [])
                                    }
                                }
                            }
                        }
                        .listStyle(.insetGrouped)
                    }
                } else if loadFailed {
                    ContentUnavailableView {
                        Label("Tiderna kunde inte hämtas", systemImage: "calendar")
                    } actions: {
                        Button("Försök igen") { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle(booking.visitName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Avbryt") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if let selected {
                    Button {
                        Task { await confirm(selected) }
                    } label: {
                        Text(isBooking ? "Bokar…" : "Boka \(selected.timeText)")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isBooking)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.bar)
                }
            }
            .alert("Tiden kunde inte bokas", isPresented: $bookFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Tiden kan ha bokats av någon annan. Välj en annan tid.")
            }
        }
        .task { await load() }
    }

    private func load() async {
        loadFailed = false
        do {
            slots = try await store.slots(for: booking)
        } catch {
            if !Task.isCancelled { loadFailed = true }
        }
    }

    private func confirm(_ slot: CareSlot) async {
        isBooking = true
        defer { isBooking = false }
        do {
            try await store.book(booking, at: slot)
            dismiss()
        } catch {
            bookFailed = true
            selected = nil
            await load()
        }
    }
}

private struct CareMessageSenderImage: View {
    let isBeta: Bool
    var portraitSize: CGFloat = 48

    var body: some View {
        if isBeta {
            Image("DemoClinicianPortrait")
                .resizable()
                .scaledToFill()
                .frame(width: portraitSize, height: portraitSize)
                .clipShape(Circle())
                .overlay { Circle().strokeBorder(.primary.opacity(0.08)) }
                .accessibilityHidden(true)
        } else {
            Image(systemName: "stethoscope")
                .font(.system(size: portraitSize * 0.42, weight: .medium))
                .foregroundStyle(.tint)
                .frame(width: portraitSize, height: portraitSize)
                .background(.tint.opacity(0.09), in: Circle())
                .accessibilityHidden(true)
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
