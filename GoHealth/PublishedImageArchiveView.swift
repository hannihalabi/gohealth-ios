import SwiftUI

@MainActor
final class PublishedArchiveFrames: ImagingFrameSource {
    let series: ImagingSeries
    let detail: ImagingSeriesDetail
    private let archive: ClinicalImageArchive

    init(archive: ClinicalImageArchive, record: ClinicalRecord, attachment: ClinicalArchiveAttachment) {
        self.archive = archive
        let modality = record.payload.modality ?? "Bilddiagnostik"
        series = ImagingSeries(id: attachment.id.uuidString, description: record.payload.title,
                               modality: modality, frameCount: archive.imageCount, kind: "patient-archive")
        let frames = (0..<archive.imageCount).map { index in
            ImagingFrame(id: String(index), index: index, positionMm: nil, rows: 0, columns: 0,
                         spacing: [], windowCenter: 0, windowWidth: 1)
        }
        detail = ImagingSeriesDetail(id: series.id, description: series.description, modality: modality,
                                     regularSpacing: nil, aiStatus: "", frames: frames,
                                     sourceUrl: nil, attribution: nil, rightsNote: nil)
    }

    /// Downloads and unpacks a published archive.
    static func load(record: ClinicalRecord, attachment: ClinicalArchiveAttachment,
                     download: (ClinicalArchiveAttachment) async throws -> Data) async throws -> PublishedArchiveFrames {
        let bytes = try await download(attachment)
        try Task.checkCancellation()
        let worker = Task.detached(priority: .utility) { try ClinicalImageArchive(data: bytes) }
        let contents = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
        try Task.checkCancellation()
        return PublishedArchiveFrames(archive: contents, record: record, attachment: attachment)
    }

    static func message(for error: Error) -> String {
        if let failure = error as? ClinicalImageArchive.Failure { return failure.localizedDescription }
        return "Kontrollera anslutningen och försök igen. Bilderna behöver vara publicerade till ditt konto."
    }

    func imageData(frame: ImagingFrame, center: Double, width: Double, preview: Bool) async throws -> Data {
        let archive = archive
        let index = frame.index
        let worker = Task.detached(priority: .utility) { try archive.imageData(at: index) }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }
}

struct PublishedImageArchiveView: View {
    let record: ClinicalRecord
    let archive: ClinicalArchiveAttachment
    let download: (ClinicalArchiveAttachment) async throws -> Data
    let startingIndex: Int
    @State private var source: PublishedArchiveFrames?
    @State private var error: String?
    @State private var attempt = 0

    init(record: ClinicalRecord, archive: ClinicalArchiveAttachment, download: @escaping (ClinicalArchiveAttachment) async throws -> Data,
         preloaded: PublishedArchiveFrames? = nil, startingIndex: Int = 0) {
        self.record = record
        self.archive = archive
        self.download = download
        self.startingIndex = startingIndex
        _source = State(initialValue: preloaded)
    }

    var body: some View {
        Group {
            if let source {
                RadiologySeriesView(api: source, series: source.series, synthetic: false,
                                    startingIndex: startingIndex, startingDetail: source.detail, loadDetail: nil)
            } else if let error {
                ContentUnavailableView {
                    Label("Bilderna kunde inte öppnas", systemImage: "exclamationmark.circle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Försök igen") { self.error = nil; attempt += 1 }
                }
            } else {
                ProgressView("Hämtar bilder…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(record.payload.title)
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) { await load() }
    }

    private func load() async {
        guard source == nil else { return }
        do {
            source = try await PublishedArchiveFrames.load(record: record, attachment: archive, download: download)
        } catch {
            guard !Task.isCancelled else { return }
            self.error = PublishedArchiveFrames.message(for: error)
        }
    }
}
