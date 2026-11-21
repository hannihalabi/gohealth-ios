import SwiftUI

@MainActor
private final class PublishedArchiveFrames: ImagingFrameSource {
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
    @State private var source: PublishedArchiveFrames?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        Group {
            if let source {
                RadiologySeriesView(api: source, series: source.series, synthetic: false,
                                    startingIndex: 0, startingDetail: source.detail, loadDetail: nil)
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
            let bytes = try await download(archive)
            try Task.checkCancellation()
            let worker = Task.detached(priority: .utility) { try ClinicalImageArchive(data: bytes) }
            let contents = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            try Task.checkCancellation()
            source = PublishedArchiveFrames(archive: contents, record: record, attachment: archive)
        } catch {
            guard !Task.isCancelled else { return }
            if let failure = error as? ClinicalImageArchive.Failure {
                self.error = failure.localizedDescription
            } else {
                self.error = "Kontrollera anslutningen och försök igen. Bilderna behöver vara publicerade till ditt konto."
            }
        }
    }
}
