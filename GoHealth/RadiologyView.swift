import SwiftUI
import UniformTypeIdentifiers

struct ImagingCapabilities: Decodable {
    let canImport: Bool
    let patientId: String?
    let mode: String
    let aiEnabled: Bool
}

struct ImagingSeries: Decodable, Identifiable {
    let id: String
    let description: String
    let modality: String
    let frameCount: Int
    let kind: String?
    var isPatientArchive: Bool { kind == "patient-archive" }
    var isPreview: Bool { kind == "preview" || isPatientArchive }
}

struct ImagingStudy: Decodable, Identifiable {
    let id: String
    let description: String
    let studyDate: String
    let modality: String
    let synthetic: Bool
    let series: [ImagingSeries]
}


struct ImagingSeriesDetail: Decodable {
    let id: String
    let description: String
    let modality: String
    let regularSpacing: Bool?
    let aiStatus: String
    let frames: [ImagingFrame]
    let sourceUrl: String?
    let attribution: String?
    let rightsNote: String?
}

struct ImagingImport: Decodable {
    let id: String
    let status: String
    let detail: String
}

private struct ImagingFailure: Decodable { let detail: String }

enum ImagingError: LocalizedError {
    case unavailable, server(String), tooLarge, invalidResponse

    var errorDescription: String? {
        switch self {
        case .unavailable: "Bildtjänsten är inte ansluten för det här kontot ännu."
        case .server(let message): message
        case .tooLarge: "Filerna är för stora. Välj högst 256 MB sammanlagt."
        case .invalidResponse: "Bildtjänsten skickade ett svar som inte kunde läsas."
        }
    }
}

private class ImagingSessionPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class ImagingUploadProgress: ImagingSessionPolicy, @unchecked Sendable {
    let update: @Sendable (Double) -> Void
    init(update: @escaping @Sendable (Double) -> Void) { self.update = update }
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64,
                    totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        if totalBytesExpectedToSend > 0 { update(Double(totalBytesSent) / Double(totalBytesExpectedToSend)) }
    }
}

@MainActor
final class RadiologyAPI: ImagingFrameSource {
    let baseURL: URL
    let isDemo: Bool
    private let offlineDemo: BundledImagingDemo?
    private let token: () async throws -> String
    private let session: URLSession
    private let decoder: JSONDecoder

    init?(isBeta: Bool, token: @escaping () async throws -> String) {
        #if DEBUG
        if isBeta {
            guard let demo = try? BundledImagingDemo() else { return nil }
            offlineDemo = demo
            baseURL = demo.root
            isDemo = true
        } else {
            offlineDemo = nil
            guard let value = Bundle.main.object(forInfoDictionaryKey: "GoHealthImagingAPIURL") as? String,
                  let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
            baseURL = url
            isDemo = false
        }
        #else
        offlineDemo = nil
        guard !isBeta,
              let value = Bundle.main.object(forInfoDictionaryKey: "GoHealthImagingAPIURL") as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        baseURL = url
        isDemo = false
        #endif
        self.token = token
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 300
        configuration.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: configuration, delegate: ImagingSessionPolicy(), delegateQueue: nil)
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
    }

    private func request(_ path: String, query: [URLQueryItem] = [], method: String = "GET") async throws -> URLRequest {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if isDemo { request.setValue("1", forHTTPHeaderField: "X-GoHealth-Demo") }
        else { request.setValue("Bearer \(try await token())", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func checked(_ data: Data, _ response: URLResponse) throws -> Data {
        guard let response = response as? HTTPURLResponse else { throw ImagingError.invalidResponse }
        guard (200..<300).contains(response.statusCode) else {
            throw ImagingError.server((try? decoder.decode(ImagingFailure.self, from: data))?.detail
                                      ?? "Bildtjänsten kunde inte slutföra begäran (\(response.statusCode)).")
        }
        return data
    }

    func get<T: Decodable>(_ path: String, as type: T.Type = T.self) async throws -> T {
        if let offlineDemo {
            return try decoder.decode(type, from: offlineDemo.responseData(for: path))
        }
        let request = try await request(path)
        let (data, response) = try await session.data(for: request)
        return try decoder.decode(type, from: checked(data, response))
    }

    func imageData(frame: ImagingFrame, center: Double, width: Double, preview: Bool) async throws -> Data {
        if let offlineDemo {
            guard preview else { throw BundledImagingDemo.Failure.unknownResource }
            let reader = Task.detached(priority: .utility) {
                try Task.checkCancellation()
                return try offlineDemo.frameData(id: frame.id)
            }
            return try await withTaskCancellationHandler {
                try await reader.value
            } onCancel: { reader.cancel() }
        }
        let query = preview ? [] : [URLQueryItem(name: "center", value: String(center)), URLQueryItem(name: "width", value: String(width))]
        let request = try await request("v1/frames/\(frame.id)/\(preview ? "preview" : "rendered")", query: query)
        let (data, response) = try await session.data(for: request)
        return try checked(data, response)
    }

    func upload(_ urls: [URL], patientID: String, progress: @escaping @Sendable (Double) -> Void) async throws -> ImagingImport {
        guard offlineDemo == nil else {
            throw ImagingError.server("Betaprofilen visar förinstallerade testbilder. Import kräver en ansluten bildtjänst.")
        }
        let boundary = "GoHealth-\(UUID().uuidString)"
        let bodyURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".multipart")
        FileManager.default.createFile(atPath: bodyURL.path, contents: nil, attributes: [.protectionKey: FileProtectionType.complete])
        defer { try? FileManager.default.removeItem(at: bodyURL) }
        let output = try FileHandle(forWritingTo: bodyURL)
        defer { try? output.close() }
        var total = 0
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let input = try FileHandle(forReadingFrom: url)
            defer { try? input.close() }
            let extensionName = url.pathExtension.lowercased() == "zip" ? "zip" : "dcm"
            let header = "--\(boundary)\r\nContent-Disposition: form-data; name=\"files\"; filename=\"\(UUID().uuidString).\(extensionName)\"\r\nContent-Type: application/octet-stream\r\n\r\n"
            try output.write(contentsOf: Data(header.utf8))
            while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                total += chunk.count
                if total > 255 * 1024 * 1024 { throw ImagingError.tooLarge }
                try output.write(contentsOf: chunk)
            }
            try output.write(contentsOf: Data("\r\n".utf8))
        }
        try output.write(contentsOf: Data("--\(boundary)--\r\n".utf8))
        try output.synchronize()
        let query = [URLQueryItem(name: "patient_id", value: patientID), URLQueryItem(name: "identity_confirmed", value: "true")]
        var request = try await request("v1/imports", query: query, method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue(UUID().uuidString, forHTTPHeaderField: "Idempotency-Key")
        let delegate = ImagingUploadProgress(update: progress)
        let (data, response) = try await session.upload(for: request, fromFile: bodyURL, delegate: delegate)
        return try decoder.decode(ImagingImport.self, from: checked(data, response))
    }
}

@MainActor
final class RadiologyStore: ObservableObject {
    let api: RadiologyAPI?
    private let isBeta: Bool
    @Published var studies: [ImagingStudy] = []
    @Published var capabilities: ImagingCapabilities?
    @Published var isLoading = false
    @Published var isImporting = false
    @Published var uploadProgress: Double = 0
    @Published var importStatus: String?
    @Published var error: String?

    init(isBeta: Bool, token: @escaping () async throws -> String) {
        self.isBeta = isBeta
        api = RadiologyAPI(isBeta: isBeta, token: token)
    }

    func load() async {
        guard let api else {
            error = isBeta ? BundledImagingDemo.Failure.missing.localizedDescription : ImagingError.unavailable.localizedDescription
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            capabilities = try await api.get("v1/capabilities")
            studies = try await api.get("v1/studies")
            error = nil
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    func importFiles(_ urls: [URL]) async {
        guard let api, let patient = capabilities?.patientId, capabilities?.canImport == true, !isImporting else { return }
        isImporting = true
        uploadProgress = 0
        importStatus = "Förbereder uppladdning…"
        error = nil
        defer { isImporting = false }
        do {
            var job = try await api.upload(urls, patientID: patient) { [weak self] progress in
                Task { @MainActor in self?.uploadProgress = progress }
            }
            uploadProgress = 1
            importStatus = job.detail
            for _ in 0..<600 {
                try Task.checkCancellation()
                job = try await api.get("v1/imports/\(job.id)")
                importStatus = job.detail
                if job.status == "available" { await load(); return }
                if job.status == "failed" { throw ImagingError.server(job.detail) }
                try await Task.sleep(for: .seconds(1))
            }
            importStatus = "Importen fortsätter på servern. Uppdatera listan senare."
        } catch is CancellationError {
            importStatus = "Visningen avbröts. En mottagen import fortsätter på servern."
        } catch { self.error = error.localizedDescription }
    }
}

private enum RadiologyColors {
    static let background = Color.black
    static let accent = Color(red: 1, green: 0.67, blue: 0.83)
}

struct RadiologyView: View {
    private struct Selection: Identifiable {
        let series: ImagingSeries
        let synthetic: Bool
        var index = 0
        var detail: ImagingSeriesDetail? = nil

        var id: String { series.id }
    }

    @StateObject private var model: RadiologyStore
    @ObservedObject private var clinical: ClinicalStore
    @State private var selection: Selection?
    @State private var archiveSelection: ClinicalRecord?
    @State private var showsImporter = false
    @State private var showsConfirmation = false
    @State private var pendingFiles: [URL] = []
    @State private var uploadTask: Task<Void, Never>?
    private let embedded: Bool
    private let close: (() -> Void)?
    private let isBeta: Bool

    init(isBeta: Bool, token: @escaping () async throws -> String, clinical: ClinicalStore,
         embedded: Bool = false, close: (() -> Void)? = nil) {
        self.embedded = embedded
        self.close = close
        self.isBeta = isBeta
        self.clinical = clinical
        _model = StateObject(wrappedValue: RadiologyStore(isBeta: isBeta, token: token))
    }

    private var featured: (study: ImagingStudy, series: ImagingSeries)? {
        for study in model.studies {
            if let series = study.series.first(where: { $0.frameCount > 0 }) {
                return (study, series)
            }
        }
        return nil
    }

    private var library: some View {
        let featured = featured
        return ScrollView {
            VStack(spacing: 20) {
                if let featured, let api = model.api {
                    RadiologyPreview(api: api, study: featured.study, series: featured.series,
                                     isActive: selection == nil) { index, detail in
                        selection = Selection(series: featured.series, synthetic: featured.study.synthetic,
                                              index: index, detail: detail)
                    }
                    .id(featured.series.id)
                }

                VStack(alignment: .leading, spacing: 16) {
                    ForEach(clinical.imageRecords) { record in
                        if let archive = record.imageArchive {
                            Button { archiveSelection = record } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "viewfinder").foregroundStyle(RadiologyColors.accent)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(record.payload.title).font(.headline).foregroundStyle(.primary)
                                        Text("\(archive.imageCount) bilder · \(record.payload.modality ?? "Bilddiagnostik")")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                        if let date = record.payload.date {
                                            Text(date, format: .dateTime.day().month().year())
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right").foregroundStyle(.secondary)
                                }
                                .padding(14)
                                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                                .contentShape(Rectangle())
                            }.buttonStyle(.plain)
                        }
                    }
                    if !isBeta, let error = clinical.error {
                        Text(error).foregroundStyle(.secondary)
                        Button("Försök igen") { Task { await clinical.refresh() } }
                    }
                    if let error = model.error, model.api != nil || isBeta {
                        Text(error).foregroundStyle(.secondary)
                        Button("Försök igen") { Task { await model.load() } }
                    } else if model.studies.isEmpty && clinical.imageRecords.isEmpty && clinical.error == nil {
                        if model.isLoading || clinical.isLoading {
                            ProgressView("Hämtar undersökningar…")
                                .frame(maxWidth: .infinity)
                        } else {
                            ContentUnavailableView("Inga undersökningar ännu", systemImage: "viewfinder",
                                                   description: Text("Bilder som vårdteamet publicerar visas här."))
                        }
                    }
                    remainingStudies(excluding: featured?.series.id)
                    if model.capabilities?.canImport == true { importControls }
                }
                .frame(maxWidth: 640, alignment: .leading)
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 22)
            .frame(maxWidth: .infinity)
        }
        .refreshable {
            await clinical.refresh()
            if model.api != nil || isBeta { await model.load() }
        }
    }

    private func remainingStudies(excluding featuredID: String?) -> some View {
        ForEach(model.studies) { study in
            let otherSeries = study.series.filter { $0.id != featuredID }
            if !otherSeries.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(study.synthetic ? "Exempelundersökning" : study.description)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .accessibilityAddTraits(.isHeader)
                    ForEach(otherSeries) { series in
                        Button {
                            selection = Selection(series: series, synthetic: study.synthetic)
                        } label: {
                            HStack {
                                seriesSummary(series, study: study)
                                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var importControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { showsImporter = true } label: {
                Label("Importera DICOM eller ZIP", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.bordered)
            .disabled(model.isImporting)
            if model.isImporting {
                ProgressView(value: model.uploadProgress) {
                    Text(model.uploadProgress < 1 ? "Laddar upp \(Int(model.uploadProgress * 100)) %" : "Kontrollerar bildserien…")
                }
            }
            if let status = model.importStatus { Text(status).font(.footnote).foregroundStyle(.secondary) }
            Text("Bekräfta rätt profil före import. Testmiljön tar endast emot avidentifierade testfiler.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func seriesSummary(_ series: ImagingSeries, study: ImagingStudy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(study.synthetic ? "DT · Testserie" : series.description)
                .font(.headline)
            Text("\(series.frameCount) bilder · \(series.modality)")
                .font(.subheadline).foregroundStyle(.secondary)
            if series.isPreview {
                Text("Testbilder · Visningskopior")
                    .font(.caption.weight(.medium)).foregroundStyle(.secondary)
            }
            if !study.studyDate.isEmpty { Text(study.studyDate).font(.caption).foregroundStyle(.secondary) }
        }
        .foregroundStyle(.primary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .padding(.vertical, 5)
    }

    private var embeddedHeader: some View {
        HStack(spacing: 12) {
            Image(systemName: "viewfinder")
                .font(.title3.weight(.medium))
                .foregroundStyle(RadiologyColors.accent)
                .frame(width: 44, height: 44)
                .background(RadiologyColors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .accessibilityHidden(true)
            Text("Röntgen")
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { close?() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.12), in: Circle())
                    .contentShape(Circle())
            }
            .accessibilityLabel("Stäng Röntgen")
            .accessibilityHint("Återgår till avataren på Hem")
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    var body: some View {
        Group {
            if embedded {
                VStack(spacing: 0) {
                    embeddedHeader
                    library
                }
            } else {
                library
                    .navigationTitle("Röntgen")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(RadiologyColors.background, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RadiologyColors.background)
        .environment(\.colorScheme, .dark)
        .tint(RadiologyColors.accent)
        .fullScreenCover(item: $selection) { selected in
            if let api = model.api {
                NavigationStack {
                    RadiologySeriesView(api: api, series: selected.series, synthetic: selected.synthetic,
                                        startingIndex: selected.index, startingDetail: selected.detail,
                                        loadDetail: { try await api.get("v1/series/\(selected.series.id)") })
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Stäng") { selection = nil }
                            }
                        }
                }
            }
        }
        .fullScreenCover(item: $archiveSelection) { record in
            if let archive = record.imageArchive {
                NavigationStack {
                    PublishedImageArchiveView(record: record, archive: archive, download: clinical.downloadArchive)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Stäng") { archiveSelection = nil }
                            }
                        }
                }
            }
        }
        .task { if model.api != nil || isBeta { await model.load() } }
        .task { await clinical.refresh() }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.zip, .data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): pendingFiles = urls; showsConfirmation = !urls.isEmpty
            case .failure(let error): model.error = error.localizedDescription
            }
        }
        .confirmationDialog("Importera till den här profilen?", isPresented: $showsConfirmation, titleVisibility: .visible) {
            Button("Bekräfta och importera") {
                let files = pendingFiles
                uploadTask = Task { await model.importFiles(files) }
                pendingFiles = []
            }
            Button("Avbryt", role: .cancel) { pendingFiles = [] }
        } message: {
            Text("Kontrollera att filerna hör till rätt person och att du har rätt att importera dem.")
        }
        .onDisappear {
            if selection == nil { uploadTask?.cancel() }
        }
    }
}

private struct RadiologyPreview: View {
    let api: RadiologyAPI
    let study: ImagingStudy
    let series: ImagingSeries
    let isActive: Bool
    let open: (Int, ImagingSeriesDetail?) -> Void

    @StateObject private var playback = RadiologyPlayback(bufferCostLimit: 24 * 1024 * 1024)
    @State private var detail: ImagingSeriesDetail?
    @State private var index = 0.0
    @State private var error: String?
    @State private var reload = 0

    private var frameCount: Int { detail?.frames.count ?? series.frameCount }

    private var displayedFrame: ImagingFrame? {
        guard let frames = detail?.frames, frames.indices.contains(playback.displayedIndex) else { return nil }
        return frames[playback.displayedIndex]
    }

    private var frameSelection: Binding<Double> {
        Binding(get: { index }, set: { value in
            index = value
            playback.select(Int(value))
        })
    }

    var body: some View {
        VStack(spacing: 0) {
            imageCanvas
                .aspectRatio(1.12, contentMode: .fit)
                .frame(maxWidth: 760)
                .frame(maxWidth: .infinity)

            controls
                .frame(maxWidth: 640)
                .padding(.horizontal, 20)
                .padding(.top, 14)
        }
        .task(id: isActive ? reload : nil) {
            guard isActive else {
                playback.stop()
                return
            }
            await preparePreview()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            playback.releaseMemory()
        }
        .onDisappear { playback.stop() }
    }

    private var imageCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                RadiologyColors.background
                if let image = playback.image {
                    Image(decorative: image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(displayedFrame.map { CGFloat($0.displayAspectRatio) }, contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        // Give the bundled test images a slightly closer preview. The viewer shows the full frame.
                        .scaleEffect(series.id == BundledImagingDemo.seriesID ? 1.08 : 1)
                } else if error == nil && playback.error == nil {
                    ProgressView().tint(.white)
                } else {
                    Label("Förhandsvisningen kunde inte visas", systemImage: "photo")
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                        .padding(16)
                }
            }
            .transaction { $0.animation = nil }
            .clipped()
            .accessibilityHidden(playback.image != nil)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !study.synthetic && !series.isPreview {
                Text(series.description.isEmpty ? series.modality : series.description)
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                if !study.studyDate.isEmpty {
                    Text(study.studyDate).font(.caption).foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                if playback.image != nil {
                    Text("Bild \(playback.displayedIndex + 1) av \(frameCount)")
                } else {
                    Text("\(frameCount) bilder")
                }
                if playback.isLoading && playback.image != nil {
                    ProgressView().controlSize(.small).accessibilityLabel("Hämtar bild")
                }
                Spacer()
                if series.isPreview {
                    Text("Visningskopior").accessibilityLabel("Testbilder, visningskopior")
                }
                else if study.synthetic { Text("Syntetiska bilder") }
            }
            .font(.caption.weight(.medium).monospacedDigit())
            .foregroundStyle(.secondary)

            if frameCount > 1 {
                Slider(value: frameSelection, in: 0...Double(frameCount - 1), step: 1)
                    .accessibilityLabel("Bläddra mellan snitt")
                    .accessibilityValue("Bild \(Int(index) + 1) av \(frameCount)")
                    .disabled(detail == nil)
            }

            if let message = error ?? playback.error {
                Text(message).font(.footnote).foregroundStyle(.secondary)
                Button("Försök igen") {
                    if playback.error != nil { playback.select(Int(index)) }
                    else { reload += 1 }
                }
                .font(.footnote.weight(.semibold))
            }

            Button {
                open(playback.image == nil ? Int(index) : playback.displayedIndex, detail)
            } label: {
                Label("Öppna bildvisaren", systemImage: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity, minHeight: 28)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 5)
        }
    }

    private func preparePreview() async {
        error = nil
        do {
            let loaded: ImagingSeriesDetail
            if let detail {
                loaded = detail
            } else {
                loaded = try await api.get("v1/series/\(series.id)")
                try Task.checkCancellation()
                guard !loaded.frames.isEmpty else {
                    error = "Bildserien innehåller inga bilder."
                    return
                }
                index = Double(loaded.frames.count / 2)
                detail = loaded
            }
            try Task.checkCancellation()
            playback.prepare(api: api, frames: loaded.frames, window: .standard, preview: series.isPreview,
                             index: Int(index), preloadWholeSeries: false)
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}


struct RadiologySeriesView: View {
    let api: any ImagingFrameSource
    let series: ImagingSeries
    let synthetic: Bool
    let startingIndex: Int
    let startingDetail: ImagingSeriesDetail?
    let loadDetail: (() async throws -> ImagingSeriesDetail)?
    @State private var detail: ImagingSeriesDetail?
    @State private var index: Double = 0
    @State private var window: ImagingWindow = .standard
    @StateObject private var playback = RadiologyPlayback()
    @State private var error: String?
    @State private var zoom: CGFloat = 1
    @State private var zoomStart: CGFloat = 1
    @State private var pan = CGSize.zero
    @State private var panStart: CGSize?
    @State private var dragStartIndex: Double?

    private var frame: ImagingFrame? {
        guard let frames = detail?.frames, !frames.isEmpty else { return nil }
        return frames[min(max(0, playback.displayedIndex), frames.count - 1)]
    }

    private var frameSelection: Binding<Double> {
        Binding(get: { index }, set: { value in
            index = value
            playback.select(Int(value))
        })
    }

    private var imageCanvas: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black
                if let image = playback.image {
                    Image(decorative: image, scale: 1, orientation: .up).resizable()
                        .aspectRatio(series.isPatientArchive ? nil : frame.map { CGFloat($0.displayAspectRatio) }, contentMode: .fit)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .scaleEffect(zoom).offset(pan)
                }
                if playback.isLoading && playback.image == nil { ProgressView().tint(.white) }
            }
            .transaction { $0.animation = nil }
            .clipped()
            .contentShape(Rectangle())
            .gesture(MagnifyGesture().onChanged { zoom = min(5, max(1, zoomStart * $0.magnification)) }
                .onEnded { _ in zoomStart = zoom; if zoom == 1 { pan = .zero } })
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
                if zoom > 1 {
                    let start = panStart ?? pan
                    panStart = start
                    pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                } else if !playback.isPreparing, let count = detail?.frames.count, count > 1 {
                    let start = dragStartIndex ?? index
                    dragStartIndex = start
                    frameSelection.wrappedValue = min(Double(count - 1), max(0, start - (value.translation.height / 10).rounded()))
                }
            }.onEnded { _ in panStart = nil; dragStartIndex = nil })
            .onTapGesture(count: 2) { zoom = 1; zoomStart = 1; pan = .zero }
            .accessibilityLabel("Bild \(playback.displayedIndex + 1) av \(detail?.frames.count ?? 0)")
            .accessibilityAdjustableAction { direction in
                guard !playback.isPreparing, let count = detail?.frames.count, count > 0 else { return }
                frameSelection.wrappedValue = min(Double(count - 1), max(0, index + (direction == .increment ? 1 : -1)))
            }
        }
        .frame(minHeight: 180)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var sequenceControls: some View {
        if let frames = detail?.frames, !frames.isEmpty {
            HStack {
                let visibleIndex = playback.image == nil ? Int(index) : playback.displayedIndex
                Text("Bild \(visibleIndex + 1) av \(frames.count)")
                Spacer()
                if playback.image != nil, let position = frame?.positionMm { Text("\(position, specifier: "%.1f") mm") }
            }.font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            if frames.count > 1 {
                Slider(value: frameSelection, in: 0...Double(frames.count - 1), step: 1)
                    .accessibilityLabel("Bläddra mellan snitt")
                    .disabled(playback.isPreparing)
            }
            if playback.isPreparing {
                ProgressView(value: Double(playback.preparedCount), total: Double(frames.count)) {
                    Text("Förbereder snabb bläddring… \(playback.preparedCount)/\(frames.count)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else if playback.isLoading && playback.image != nil {
                Text("Hämtar bild \(Int(index) + 1)…")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if series.modality == "CT" && !series.isPreview {
                Picker("Bildfönster", selection: $window) {
                    ForEach(ImagingWindow.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }.pickerStyle(.segmented)
            }
            if !series.isPreview && detail?.regularSpacing == false {
                Text("Bildserien har ojämnt snittavstånd eller överlappande snitt.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    @ViewBuilder
    private var sourceAttribution: some View {
        if series.isPreview {
            if let attribution = detail?.attribution {
                Text(attribution).font(.caption2).foregroundStyle(.secondary)
            }
            if let source = detail?.sourceUrl, let url = URL(string: source), url.scheme == "https", url.host == "radiopaedia.org" {
                Link("Källa: Radiopaedia", destination: url).font(.caption)
            }
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if series.isPatientArchive {
                Text("Bilder från vårdteamet · Visningskopior")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else if series.isPreview {
                Text("JPEG-testserie · Visningskopior")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            } else if synthetic {
                Text("Syntetisk DT-fantom · Testdata")
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            }
            imageCanvas
            sequenceControls
            if let error { Text(error).font(.footnote).foregroundStyle(.secondary) }
            if let error = playback.error {
                Button("Försök igen: \(error)") { playback.select(Int(index)) }
                    .font(.footnote)
            }
            Text("Dra upp eller ned för att bläddra. Nyp för att zooma. Dubbeltryck för att återställa.")
                .font(.caption).foregroundStyle(.secondary)
            Label("Ingen AI-analys utförd", systemImage: "sparkles")
                .font(.caption).foregroundStyle(.secondary)
            sourceAttribution
            Text("Bildvisaren är inte validerad för diagnostiska beslut.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .navigationTitle(series.isPatientArchive ? series.description : series.isPreview ? "DT · Testbilder" : synthetic ? "DT · Testserie" : series.modality)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            do {
                let loaded: ImagingSeriesDetail
                if let startingDetail { loaded = startingDetail }
                else if let loadDetail { loaded = try await loadDetail() }
                else { throw ImagingError.invalidResponse }
                try Task.checkCancellation()
                detail = loaded
                index = Double(min(max(0, startingIndex), max(0, loaded.frames.count - 1)))
                playback.prepare(api: api, frames: loaded.frames, window: window, preview: series.isPreview,
                                 index: Int(index), preloadWholeSeries: !series.isPatientArchive)
            }
            catch is CancellationError {} catch { self.error = error.localizedDescription }
        }
        .onChange(of: window) { _, _ in
            guard let detail else { return }
            playback.prepare(api: api, frames: detail.frames, window: window, preview: series.isPreview, index: Int(index))
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)) { _ in
            playback.releaseMemory()
        }
        .onDisappear { playback.stop() }
    }
}

#if DEBUG
#Preview("GoHealth · Röntgen") {
    RadiologyView(isBeta: true, token: { throw ImagingError.unavailable },
                  clinical: ClinicalStore(accountID: UUID(), isBeta: true,
                                          fetch: { ClinicalEnvelope(records: []) }, upload: { _ in },
                                          downloadArchive: { _ in throw ImagingError.unavailable }),
                  embedded: true, close: {})
}
#endif
