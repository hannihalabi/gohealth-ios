import Foundation
import Combine
import CoreGraphics

@MainActor
protocol ImagingFrameSource: AnyObject {
    func imageData(frame: ImagingFrame, center: Double, width: Double, preview: Bool) async throws -> Data
}

@MainActor
final class RadiologyPlayback: ObservableObject {
    private struct Key: Hashable {
        let frameID: String
        let center: Double
        let width: Double
    }
    private struct Request {
        let frame: ImagingFrame
        let key: Key
    }

    @Published private(set) var image: CGImage?
    @Published private(set) var displayedIndex = 0
    @Published private(set) var isLoading = false
    @Published private(set) var isPreparing = false
    @Published private(set) var preparedCount = 0
    @Published private(set) var error: String?

    private var buffer: ImagingFrameBuffer<Key, PreparedImagingFrame>
    private var requests: [Request] = []
    private var workers: [Key: Task<Void, Never>] = [:]
    private var attempted: Set<Key> = []
    private var failed: Set<Key> = []
    private var prepared: Set<Key> = []
    private var api: (any ImagingFrameSource)?
    private var preview = false
    private var target = 0
    private var generation = UUID()
    private var preloadWholeSeries = true
    private var largestFrameCost = 1

    init(bufferCostLimit: Int = 192 * 1024 * 1024) {
        buffer = ImagingFrameBuffer(costLimit: bufferCostLimit)
    }

    func prepare(api: any ImagingFrameSource, frames: [ImagingFrame], window: ImagingWindow, preview: Bool, index: Int,
                 preloadWholeSeries: Bool = true) {
        stop(clearImage: false)
        self.api = api
        self.preview = preview
        self.preloadWholeSeries = preloadWholeSeries
        requests = frames.map { frame in
            let (center, width) = window.settings(frame)
            return Request(frame: frame, key: Key(frameID: frame.id, center: center, width: width))
        }
        target = min(max(0, index), max(0, requests.count - 1))
        displayedIndex = min(displayedIndex, max(0, frames.count - 1))
        isPreparing = preloadWholeSeries && !requests.isEmpty
        isLoading = !requests.isEmpty
        schedule()
    }

    /// A warm selection is entirely synchronous: no Task, HTTP, decode or debounce.
    func select(_ index: Int) {
        guard requests.indices.contains(index) else { return }
        target = index
        error = nil
        failed.remove(requests[index].key)
        if let ready = buffer.value(for: requests[index].key) {
            image = ready.image
            displayedIndex = index
            isLoading = false
            if workers.isEmpty && buffer.count == requests.count { return }
        } else {
            isLoading = true
            if workers.count >= 4, workers[requests[index].key] == nil,
               let distant = workers.keys.max(by: { distance($0) < distance($1) }) {
                workers.removeValue(forKey: distant)?.cancel()
                attempted.remove(distant)
            }
        }
        schedule()
    }

    func releaseMemory() {
        for task in workers.values { task.cancel() }
        workers.removeAll()
        generation = UUID()
        buffer.removeAll()
        attempted.removeAll()
        prepared.removeAll()
        preparedCount = 0
        preloadWholeSeries = false
        isPreparing = false
        isLoading = false
        // Preserve the visible image; subsequent selections use a small moving buffer.
        if image == nil && !requests.isEmpty {
            isLoading = true
            schedule()
        }
    }

    func stop(clearImage: Bool = true) {
        for task in workers.values { task.cancel() }
        workers.removeAll()
        generation = UUID()
        buffer.removeAll()
        requests.removeAll()
        attempted.removeAll()
        failed.removeAll()
        prepared.removeAll()
        preparedCount = 0
        largestFrameCost = 1
        preloadWholeSeries = true
        isPreparing = false
        isLoading = false
        error = nil
        if clearImage { image = nil }
    }

    private func distance(_ key: Key) -> Int {
        abs((requests.firstIndex(where: { $0.key == key }) ?? 0) - target)
    }

    private func schedule() {
        guard !requests.isEmpty else { return }
        var priority = [target]
        let radius = min(8, max(0, (buffer.costLimit / max(1, largestFrameCost) - 2) / 2))
        if radius > 0 {
            for offset in 1...radius {
                if requests.indices.contains(target + offset) { priority.append(target + offset) }
                if requests.indices.contains(target - offset) { priority.append(target - offset) }
            }
        }
        if preloadWholeSeries { priority.append(contentsOf: requests.indices) }
        let neighborhood = Set(priority.prefix(1 + radius * 2))
        for index in priority where workers.count < 4 {
            let key = requests[index].key
            guard !buffer.contains(key), workers[key] == nil, !failed.contains(key),
                  neighborhood.contains(index) || !attempted.contains(key) else { continue }
            start(index)
        }
        if workers.isEmpty || !preloadWholeSeries { isPreparing = false }
    }

    private func start(_ index: Int) {
        guard let api else { return }
        let request = requests[index]
        let session = generation
        let isPreview = preview
        attempted.insert(request.key)
        workers[request.key] = Task { [weak self] in
            do {
                let data = try await api.imageData(frame: request.frame, center: request.key.center,
                                                   width: request.key.width, preview: isPreview)
                let decoder = Task.detached(priority: .utility) { try ImagingFrameDecoder.decode(data) }
                let ready = try await withTaskCancellationHandler {
                    try await decoder.value
                } onCancel: { decoder.cancel() }
                guard !Task.isCancelled, let self, self.generation == session else { return }
                self.workers.removeValue(forKey: request.key)
                self.largestFrameCost = max(self.largestFrameCost, ready.cost)
                if self.buffer.totalCost + ready.cost > self.buffer.costLimit {
                    self.preloadWholeSeries = false
                }
                self.buffer.insert(ready, for: request.key, cost: ready.cost)
                self.prepared.insert(request.key)
                self.preparedCount = self.prepared.count
                if self.target == index {
                    self.image = ready.image
                    self.displayedIndex = index
                    self.isLoading = false
                    self.error = nil
                }
                self.schedule()
            } catch {
                guard !Task.isCancelled, let self, self.generation == session else { return }
                self.workers.removeValue(forKey: request.key)
                self.failed.insert(request.key)
                if self.target == index {
                    self.isLoading = false
                    self.error = error.localizedDescription
                }
                self.schedule()
            }
        }
    }
}
