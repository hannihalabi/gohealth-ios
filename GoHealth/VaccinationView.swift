import SwiftUI

struct VaccinationRecord: Codable, Identifiable {
    let id: UUID
    let vaccine: String
    let date: Date
    let location: String
    var planned: Bool? = nil
    // Published by the care team; shown read-only and never stored in the local file.
    var careTeam: Bool? = nil

    var isPlanned: Bool { planned == true }
    var isCareTeam: Bool { careTeam == true }

    var seriesKey: String {
        let key = vaccine.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "sv_SE"))
        switch key {
        case "covid", "covid 19", "covid-19", "covid19": return "covid-19"
        default: return key
        }
    }

    // A dose is recorded as a calendar day and stays on that day when travelling.
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    static let dateFormat = Date.FormatStyle(locale: Locale(identifier: "sv_SE"), calendar: calendar, timeZone: .gmt)

    static var today: Date {
        var localCalendar = calendar
        localCalendar.timeZone = .current
        let components = localCalendar.dateComponents([.year, .month, .day], from: .now)
        return calendar.date(from: components) ?? calendar.startOfDay(for: .now)
    }

    static let demoRecords: [Self] = [
        ("Influensa", 2026, 10, 21, "Exempelmottagning · Stockholm", false),
        ("TBE", 2026, 5, 14, "Exempelklinik · Uppsala", false),
        ("TBE", 2025, 6, 12, "Exempelklinik · Uppsala", false),
        ("Hepatit A", 2025, 2, 6, "Exempelmottagning · Stockholm", false),
        ("Covid-19", 2021, 5, 19, "Exempelmottagning · Stockholm", false),
        ("Covid-19", 2021, 7, 1, "Exempelmottagning · Stockholm", false),
        ("Covid-19", 2022, 1, 15, "Exempelklinik · Uppsala", false),
        ("Covid-19", 2022, 10, 12, "Exempelklinik · Uppsala", false),
        ("Covid-19", 2026, 12, 3, "Exempelmottagning · Stockholm", true)
    ].compactMap { vaccine, year, month, day, location, planned in
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
        return Self(id: UUID(), vaccine: vaccine, date: date, location: location, planned: planned)
    }
}

struct VaccinationSeries: Identifiable {
    struct Dose: Identifiable {
        let record: VaccinationRecord
        let number: Int
        var id: UUID { record.id }
    }

    let id: String
    let vaccine: String
    let doses: [Dose]

    var taken: [Dose] { doses.filter { !$0.record.isPlanned } }
    var nextPlanned: Dose? { doses.first { $0.record.isPlanned } }

    static func grouped(_ records: [VaccinationRecord]) -> [Self] {
        Dictionary(grouping: records, by: \.seriesKey).map { key, records in
            // An unconfirmed appointment remains planned even after its date passes.
            let ordered = records.sorted { lhs, rhs in
                if lhs.isPlanned != rhs.isPlanned { return !lhs.isPlanned }
                if lhs.date != rhs.date { return lhs.date < rhs.date }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            let doses = ordered.enumerated().map { Dose(record: $0.element, number: $0.offset + 1) }
            let vaccine = key == "covid-19" ? "Covid-19" : ordered.last?.vaccine ?? key
            return Self(id: key, vaccine: vaccine, doses: doses)
        }.sorted { $0.vaccine.localizedCompare($1.vaccine) == .orderedAscending }
    }
}

@MainActor
final class VaccinationStore: ObservableObject {
    @Published private(set) var records: [VaccinationRecord] = []
    private var local: [VaccinationRecord] = []
    private var careTeam: [VaccinationRecord] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var loadFailed = false

    let isBeta: Bool
    private let accountID: UUID

    init(accountID: UUID, isBeta: Bool) {
        self.accountID = accountID
        self.isBeta = isBeta
        if isBeta {
            local = VaccinationRecord.demoRecords
            records = local
            isLoaded = true
        }
    }

    func load() {
        guard !isLoaded else { return }
        do {
            let url = try directory().appendingPathComponent(filename)
            local = try JSONDecoder().decode([VaccinationRecord].self, from: Data(contentsOf: url))
            records = local + careTeam
            isLoaded = true
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            isLoaded = true
        } catch {
            loadFailed = true
        }
        if isLoaded { loadFailed = false }
    }

    func save(_ record: VaccinationRecord) throws {
        try replaceRecords(local.filter { $0.id != record.id } + [record])
    }

    func remove(_ record: VaccinationRecord) throws {
        try replaceRecords(local.filter { $0.id != record.id })
    }

    // Vaccinations published by the care team in the clinician portal.
    func setCareTeam(_ clinical: [ClinicalRecord]) {
        careTeam = clinical.compactMap { item in
            guard item.kind == "vaccination", let vaccine = item.payload.vaccine,
                  !vaccine.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            // The dose is the calendar day entered by the clinician, kept as written.
            let parts = item.payload.sampledAt.prefix(10).split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3,
                  let date = VaccinationRecord.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
            else { return nil }
            let place = [item.payload.location, item.payload.source].compactMap { $0 }.first { !$0.isEmpty } ?? "Vårdteamet"
            return VaccinationRecord(id: item.id, vaccine: vaccine, date: date, location: place, careTeam: true)
        }
        records = local + careTeam
    }

    private var filename: String { "\(accountID.uuidString).json" }

    private func directory() throws -> URL {
        try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                    appropriateFor: nil, create: true)
            .appendingPathComponent("Vaccinations", isDirectory: true)
    }

    private func replaceRecords(_ updated: [VaccinationRecord]) throws {
        guard isLoaded else { throw CocoaError(.fileReadUnknown) }
        if !isBeta {
            var folder = try directory()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                    attributes: [.protectionKey: FileProtectionType.complete])
            var attributes = URLResourceValues()
            attributes.isExcludedFromBackup = true
            try folder.setResourceValues(attributes)
            try JSONEncoder().encode(updated).write(to: folder.appendingPathComponent(filename),
                                                     options: [.atomic, .completeFileProtection])
        }
        local = updated
        records = local + careTeam
    }
}

struct VaccinationView: View {
    private enum Section: String, CaseIterable {
        case travel = "Reseguide"
        case history = "Mina vaccinationer"
    }

    private enum Layout: String, CaseIterable {
        case series = "Per vaccin"
        case timeline = "Tidslinje"
    }

    private struct YearGroup: Identifiable {
        let id: Int
        let doses: [VaccinationSeries.Dose]
    }

    private struct EditSelection: Identifiable {
        let id = UUID()
        let record: VaccinationRecord?
        var vaccine = ""
    }

    @ObservedObject var store: VaccinationStore
    let close: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var editing: EditSelection?
    @State private var section = Section.travel
    @State private var travelRegion: TravelVaccinationRegion?
    @State private var layout = Layout.series
    @State private var expandedSeries: Set<String> = []
    private let background = Color(red: 0.965, green: 0.970, blue: 0.982)

    private func years(for series: [VaccinationSeries]) -> [YearGroup] {
        let grouped = Dictionary(grouping: series.flatMap(\.doses)) { VaccinationRecord.calendar.component(.year, from: $0.record.date) }
        return grouped.map { year, doses in
            YearGroup(id: year, doses: doses.sorted { $0.record.date > $1.record.date })
        }.sorted { $0.id > $1.id }
    }

    var body: some View {
        VStack(spacing: 0) {
            sectionControls
                .environment(\.colorScheme, section == .travel ? .dark : colorScheme)
                .background(section == .travel ? TravelVaccinationView.mapSky : background)

            if section == .travel {
                TravelVaccinationView(region: $travelRegion, pageBackground: background)
            } else {
                history
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if section == .history && store.isLoaded {
                Button {
                    editing = EditSelection(record: nil)
                } label: {
                    Label("Lägg till dos", systemImage: "plus")
                        .fontWeight(.semibold)
                        .frame(maxWidth: 440, minHeight: 34)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.roundedRectangle(radius: 16))
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(.regularMaterial)
            }
        }
        .background(background)
        .task(id: section) {
            if section == .history { store.load() }
        }
        .onChange(of: section) { _, current in
            if current != .travel { travelRegion = nil }
        }
        .sheet(item: $editing) { selection in
            VaccinationEditor(record: selection.record, vaccine: selection.vaccine, save: store.save, remove: store.remove)
        }
        .accessibilityAction(.escape) {
            if travelRegion != nil { travelRegion = nil }
            else { close() }
        }
    }

    private var sectionControls: some View {
        VStack(spacing: 0) {
            header
            Picker("Vaccination", selection: $section) {
                ForEach(Section.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)
            .padding(.horizontal, 20)
            .padding(.bottom, 6)
        }
    }

    private var header: some View {
        let iconTint = section == .travel ? AnyShapeStyle(Color(red: 1, green: 0.67, blue: 0.83)) : AnyShapeStyle(.tint)
        return HStack(spacing: 12) {
            Image(systemName: "syringe")
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(iconTint)
                .frame(width: 44, height: 44)
                .background(iconTint.opacity(section == .travel ? 0.12 : 0.09), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Vaccination").font(.title3.weight(.semibold)).accessibilityAddTraits(.isHeader)
                if section == .history && store.isBeta {
                    Text("Testdata").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(section == .travel ? 0.12 : 1), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stäng Vaccination")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var history: some View {
        if store.loadFailed {
            ContentUnavailableView {
                Label("Vaccinationerna kunde inte läsas", systemImage: "syringe")
            } actions: {
                Button("Försök igen", action: store.load).buttonStyle(.bordered)
            }
        } else if !store.isLoaded {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if store.records.isEmpty {
            ContentUnavailableView("Inga vaccinationer än", systemImage: "syringe")
        } else {
            overview
        }
    }

    private var overview: some View {
        let series = VaccinationSeries.grouped(store.records)
        return VStack(spacing: 0) {
            Picker("Visa vaccinationer", selection: $layout) {
                ForEach(Layout.allCases, id: \.self) { option in
                    Text(option.rawValue).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 500)
            .padding(.horizontal, 20)
            .padding(.bottom, 4)
            if layout == .series {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(series) { seriesCard($0) }
                    }
                    .frame(maxWidth: 500)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity)
                }
            } else {
                timeline(years(for: series))
            }
        }
    }

    private func seriesCard(_ series: VaccinationSeries) -> some View {
        DisclosureGroup(isExpanded: Binding(
            get: { expandedSeries.contains(series.id) },
            set: { if $0 { expandedSeries.insert(series.id) } else { expandedSeries.remove(series.id) } }
        )) {
            VStack(spacing: 0) {
                Divider().padding(.top, 8)
                ForEach(series.doses.reversed()) { dose in
                    doseRow(dose, showsVaccine: false)
                }
                Button {
                    editing = EditSelection(record: nil, vaccine: series.vaccine)
                } label: {
                    Label("Ny dos", systemImage: "plus").font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
                .accessibilityLabel("Ny dos för \(series.vaccine)")
            }
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                Text(series.vaccine).font(.headline).foregroundStyle(.primary)
                Text(series.taken.count == 1 ? "1 registrerad dos" : "\(series.taken.count) registrerade doser")
                    .font(.caption).foregroundStyle(.secondary)
                if let planned = series.nextPlanned {
                    Label {
                        Text("Planerad dos \(planned.number) · \(formattedDate(planned.record.date))")
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
                } else if let last = series.taken.last {
                    Text("Senast \(formattedDate(last.record.date))").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 3)
        }
        .padding(16)
        .background(.white, in: RoundedRectangle(cornerRadius: 20))
    }

    private func timeline(_ years: [YearGroup]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                ForEach(years) { year in
                    VStack(alignment: .leading, spacing: 10) {
                        Text(String(year.id))
                            .font(.headline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        VStack(spacing: 0) {
                            ForEach(year.doses) { dose in
                                doseRow(dose, showsVaccine: true, hasNext: dose.id != year.doses.last?.id)
                            }
                        }
                        .background(.white, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
            }
            .frame(maxWidth: 500)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity)
        }
    }

    private func formattedDate(_ date: Date) -> String {
        date.formatted(VaccinationRecord.dateFormat.day().month(.abbreviated).year())
    }

    private func doseRow(_ dose: VaccinationSeries.Dose, showsVaccine: Bool, hasNext: Bool = false) -> some View {
        let record = dose.record
        let doseTitle = record.isPlanned ? "Planerad dos \(dose.number)" : "Dos \(dose.number)"
        return Button {
            if !record.isCareTeam { editing = EditSelection(record: record) }
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(record.date, format: VaccinationRecord.dateFormat.day(.twoDigits))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(record.date, format: VaccinationRecord.dateFormat.month(.abbreviated))
                        .font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    if !showsVaccine {
                        Text(record.date, format: VaccinationRecord.dateFormat.year())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 33, alignment: .leading)

                Image(systemName: record.isPlanned ? "calendar" : "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tint)
                    .frame(width: 26, height: 26)
                    .background(.tint.opacity(0.10), in: Circle())
                    .overlay(alignment: .bottom) {
                        if hasNext {
                            Rectangle().fill(.tint.opacity(0.18))
                                .frame(width: 1, height: 20)
                                .offset(y: 20)
                        }
                    }
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(showsVaccine ? "\(record.vaccine) · \(doseTitle)" : doseTitle)
                        .font(.subheadline.weight(.semibold))
                    if !record.location.isEmpty {
                        Label(record.location, systemImage: "mappin")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(record.vaccine), \(doseTitle), \(formattedDate(record.date)), \(record.location)")
        .accessibilityHint("Öppnar dosen för redigering")
    }
}

#if DEBUG
#Preview("GoHealth · Vaccination") {
    VaccinationView(store: VaccinationStore(accountID: UUID(), isBeta: true), close: {})
        .tint(Color(red: 0.71, green: 0.17, blue: 0.46))
}
#endif

private struct VaccinationEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State private var vaccine: String
    @State private var date: Date
    @State private var location: String
    @State private var planned: Bool
    @State private var confirmsRemoval = false
    @State private var saveFailed = false

    let record: VaccinationRecord?
    let save: (VaccinationRecord) throws -> Void
    let remove: (VaccinationRecord) throws -> Void

    init(record: VaccinationRecord?, vaccine: String, save: @escaping (VaccinationRecord) throws -> Void,
         remove: @escaping (VaccinationRecord) throws -> Void) {
        self.record = record
        self.save = save
        self.remove = remove
        _vaccine = State(initialValue: record?.vaccine ?? vaccine)
        _date = State(initialValue: record?.date ?? VaccinationRecord.today)
        _location = State(initialValue: record?.location ?? "")
        _planned = State(initialValue: record?.isPlanned ?? false)
    }

    private var vaccineName: String { vaccine.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var locationName: String { location.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var doseDate: Date { VaccinationRecord.calendar.startOfDay(for: date) }
    private var futureTakenDate: Bool { !planned && doseDate > VaccinationRecord.today }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Vaccin", text: $vaccine)
                Picker("Status", selection: $planned) {
                    Text("Tagen").tag(false)
                    Text("Planerad").tag(true)
                }
                .pickerStyle(.segmented)
                DatePicker("Datum", selection: $date, displayedComponents: .date)
                    .environment(\.timeZone, .gmt)
                    .environment(\.calendar, VaccinationRecord.calendar)
                if futureTakenDate {
                    Text("Ange dagens datum eller ett tidigare datum för en tagen dos.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                TextField(planned ? "Mottagning eller plats (valfritt)" : "Mottagning eller plats", text: $location)
                if record != nil {
                    Button("Ta bort dos", role: .destructive) { confirmsRemoval = true }
                }
            }
            .navigationTitle(record == nil ? "Ny dos" : "Redigera dos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Avbryt") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Spara") {
                        commit {
                            try save(VaccinationRecord(id: record?.id ?? UUID(), vaccine: vaccineName,
                                                       date: doseDate, location: locationName, planned: planned))
                        }
                    }
                    .disabled(vaccineName.isEmpty || futureTakenDate || (!planned && locationName.isEmpty))
                }
            }
            .confirmationDialog("Ta bort dosen?", isPresented: $confirmsRemoval, titleVisibility: .visible) {
                if let record {
                    Button("Ta bort", role: .destructive) { commit { try remove(record) } }
                }
                Button("Avbryt", role: .cancel) { }
            }
            .alert("Ändringen kunde inte sparas", isPresented: $saveFailed) {
                Button("OK", role: .cancel) { }
            }
        }
    }

    private func commit(_ change: () throws -> Void) {
        do {
            try change()
            dismiss()
        } catch {
            saveFailed = true
        }
    }
}
