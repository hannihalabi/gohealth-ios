import AVFoundation
import CoreImage
import PhotosUI
import Vision
import RealityKit
import SwiftUI

private enum AvatarCameraError: LocalizedError {
    case denied, unavailable, interrupted

    var errorDescription: String? {
        switch self {
        case .denied: "Tillåt kamera för GoHealth i Inställningar för att kunna ta bilder."
        case .unavailable: "Kameran är inte tillgänglig. Prova på en iPhone med kamera."
        case .interrupted: "Kameran avbröts. Öppna fotograferingen igen."
        }
    }
}

private struct AvatarLiveGuide: Equatable, Sendable {
    enum Status: Equatable, Sendable {
        case good, lighting, person, distance, frame, angle, checking

        var instruction: String {
            switch self {
            case .good: "Bra utsnitt. Håll samma position."
            case .lighting: "Öka ljuset och undvik motljus."
            case .person: "Stå ensam i bilden så att hela kroppen syns."
            case .distance: "Gå lite närmare. Hela kroppen ska fortfarande synas."
            case .frame: "Håll hela kroppen innanför ramen, med luft vid huvudet och fötterna."
            case .angle: "Vänd dig enligt instruktionen för den här vinkeln."
            case .checking: "Kontrollerar kamerabilden…"
            }
        }
    }

    // Vision uses a bottom-left origin. These symmetric insets also match the
    // top-left origin of the on-screen guide.
    static let frame = CGRect(x: 0.07, y: 0.04, width: 0.86, height: 0.92)
    let status: Status
    let aspect: CGFloat
    let timestamp: TimeInterval

    static func inspect(_ buffer: CVPixelBuffer, angle: AvatarAngle, timestamp: TimeInterval) -> Self {
        let aspect = CGFloat(CVPixelBufferGetWidth(buffer)) / CGFloat(CVPixelBufferGetHeight(buffer))
        func report(_ status: Status) -> Self { Self(status: status, aspect: aspect, timestamp: timestamp) }
        guard hasLight(buffer) else { return report(.lighting) }

        let pose = VNDetectHumanBodyPoseRequest()
        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .fast
        person.outputPixelFormat = kCVPixelFormatType_OneComponent8
        do {
            // The capture connection has already rotated the video buffer to portrait.
            let image = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up)
            try image.perform([pose, person])
            guard let poses = pose.results, poses.count == 1,
                  let mask = person.results?.first?.pixelBuffer,
                  let bounds = silhouetteBounds(mask) else { return report(.person) }

            let joints = try poses[0].recognizedPoints(.all)
            func point(_ name: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
                guard let joint = joints[name], joint.confidence > 0.25 else { return nil }
                return joint.location
            }
            guard bounds.height >= 0.58 else { return report(.distance) }
            guard frame.contains(bounds),
                  point(.root) != nil, point(.neck) != nil,
                  [point(.leftAnkle), point(.rightAnkle)].compactMap({ $0 })
                    .contains(where: { frame.contains($0) }) else { return report(.frame) }
            if let left = point(.leftShoulder), let right = point(.rightShoulder) {
                let width = abs(left.x - right.x) * aspect / bounds.height
                if (angle == .right && width > 0.15) || (angle != .right && width < 0.095) {
                    return report(.angle)
                }
            }
            if angle == .right, let nose = point(.nose), let neck = point(.neck),
               nose.x + 0.018 < neck.x { return report(.angle) }
            if angle != .right {
                let face = VNDetectFaceRectanglesRequest()
                try image.perform([face])
                let seesFace = face.results?.contains { observation in
                    let box = observation.boundingBox
                    return observation.confidence > 0.45 && bounds.intersects(box)
                        && box.midY > bounds.maxY - bounds.height * 0.25
                } ?? false
                if seesFace != (angle == .front) { return report(.angle) }
            }
            return report(.good)
        } catch {
            return report(.checking)
        }
    }

    private static func hasLight(_ buffer: CVPixelBuffer) -> Bool {
        guard CVPixelBufferGetPlaneCount(buffer) > 0,
              CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return false }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddressOfPlane(buffer, 0) else { return false }
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRowOfPlane(buffer, 0)
        let width = CVPixelBufferGetWidthOfPlane(buffer, 0)
        let height = CVPixelBufferGetHeightOfPlane(buffer, 0)
        var lightSamples = 0
        for row in 0..<8 {
            for column in 0..<8 {
                let y = (row * 2 + 1) * height / 16
                let x = (column * 2 + 1) * width / 16
                if pixels[y * stride + x] > 24 { lightSamples += 1 }
            }
        }
        return lightSamples >= 5
    }

    private static func silhouetteBounds(_ buffer: CVPixelBuffer) -> CGRect? {
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = base.assumingMemoryBound(to: UInt8.self)
        var left = width, right = 0, top = height, bottom = 0
        var area = 0
        for y in 0..<height {
            for x in 0..<width where pixels[y * stride + x] >= 128 {
                left = min(left, x)
                right = max(right, x + 1)
                top = min(top, y)
                bottom = max(bottom, y + 1)
                area += 1
            }
        }
        guard area > width * height / 25 else { return nil }
        return CGRect(x: CGFloat(left) / CGFloat(width),
                      y: 1 - CGFloat(bottom) / CGFloat(height),
                      width: CGFloat(right - left) / CGFloat(width),
                      height: CGFloat(bottom - top) / CGFloat(height))
    }
}

private final class AvatarCamera: NSObject, AVCapturePhotoCaptureDelegate,
                                  AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "se.hemlakare.gohealth.avatar-camera", qos: .userInitiated)
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let guideQueue = DispatchQueue(label: "se.hemlakare.gohealth.avatar-guide", qos: .userInitiated)
    // Only accessed on guideQueue. Camera session and photo capture use queue.
    private var guide: (angle: AvatarAngle, report: @Sendable (AvatarLiveGuide) -> Void)?
    private var lastGuideTime: TimeInterval = 0
    private var configured = false
    private var pending: (id: Int64, result: CheckedContinuation<AvatarCaptureData, Error>)?

    func start(guideFor angle: AvatarAngle,
               report: @escaping @Sendable (AvatarLiveGuide) -> Void) async throws {
        guard await AVCaptureDevice.requestAccess(for: .video) else { throw AvatarCameraError.denied }
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    if !self.configured { try self.configure() }
                    self.guideQueue.async {
                        self.lastGuideTime = 0
                        self.guide = (angle, report)
                    }
                    if !self.session.isRunning { self.session.startRunning() }
                    guard self.session.isRunning else { throw AvatarCameraError.interrupted }
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func configure() throws {
        guard let device = AVCaptureDevice.default(.builtInDualCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        else { throw AvatarCameraError.unavailable }
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .photo
        guard session.canAddInput(input) else { throw AvatarCameraError.unavailable }
        session.addInput(input)
        guard session.canAddOutput(output) else {
            session.removeInput(input)
            throw AvatarCameraError.unavailable
        }
        session.addOutput(output)
        guard session.canAddOutput(video) else {
            session.removeOutput(output)
            session.removeInput(input)
            throw AvatarCameraError.unavailable
        }
        video.alwaysDiscardsLateVideoFrames = true
        video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        session.addOutput(video)
        if let connection = video.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        video.setSampleBufferDelegate(self, queue: guideQueue)
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
        if output.isDepthDataDeliverySupported, output.availableSemanticSegmentationMatteTypes.contains(.hair) {
            output.isDepthDataDeliveryEnabled = true
            output.enabledSemanticSegmentationMatteTypes = output.availableSemanticSegmentationMatteTypes.filter { $0 == .hair }
        }
        configured = true
    }

    func stop() {
        queue.async {
            self.guideQueue.async { self.guide = nil }
            if self.session.isRunning { self.session.stopRunning() }
            self.pending?.result.resume(throwing: CancellationError())
            self.pending = nil
        }
    }

    func takePhoto(includeHair: Bool) async throws -> AvatarCaptureData {
        try Task.checkCancellation()
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                guard self.session.isRunning, self.pending == nil else {
                    continuation.resume(throwing: AvatarCameraError.interrupted)
                    return
                }
                let settings = AVCapturePhotoSettings()
                if includeHair, self.output.isDepthDataDeliveryEnabled {
                    settings.isDepthDataDeliveryEnabled = true
                    settings.embedsDepthDataInPhoto = false
                    settings.enabledSemanticSegmentationMatteTypes = self.output.enabledSemanticSegmentationMatteTypes
                    settings.embedsSemanticSegmentationMattesInPhoto = false
                }
                self.pending = (settings.uniqueID, continuation)
                self.output.capturePhoto(with: settings, delegate: self)
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let guide, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastGuideTime >= 0.25 else { return }
        lastGuideTime = now
        guide.report(AvatarLiveGuide.inspect(buffer, angle: guide.angle, timestamp: now))
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let id = photo.resolvedSettings.uniqueID
        let result: Result<AvatarCaptureData, Error>
        if let error {
            result = .failure(error)
        } else if let bytes = photo.fileDataRepresentation() {
            let orientationValue = (photo.metadata[kCGImagePropertyOrientation as String] as? UInt32) ?? 1
            let orientation = CGImagePropertyOrientation(rawValue: orientationValue) ?? .up
            let hair = photo.semanticSegmentationMatte(for: .hair)?.applyingExifOrientation(orientation)
            let hairBytes = hair.flatMap { matte -> Data? in
                let image = CIImage(cvPixelBuffer: matte.mattingImage)
                guard let bitmap = CIContext().createCGImage(image, from: image.extent) else { return nil }
                return UIImage(cgImage: bitmap).pngData()
            }
            result = .success(AvatarCaptureData(photo: bytes, hair: hairBytes))
        } else {
            result = .failure(AvatarScanError.image)
        }
        queue.async { self.finish(id: id, result: result) }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor settings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error {
            let id = settings.uniqueID
            queue.async { self.finish(id: id, result: .failure(error)) }
        }
    }

    private func finish(id: Int64, result: Result<AvatarCaptureData, Error>) {
        guard let pending, pending.id == id else { return }
        self.pending = nil
        pending.result.resume(with: result)
    }
}

private struct AvatarCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var video: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    func makeUIView(context: Context) -> Preview {
        let view = Preview()
        view.video.session = session
        view.video.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ view: Preview, context: Context) {
        if let connection = view.video.connection, connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
    }
}

struct AvatarCaptureFlow: View {
    private enum Step: Equatable {
        case introduction, capture(AvatarAngle), review, reveal
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isSceneCaptured) private var isSceneCaptured
    @State private var step: Step = .introduction
    @State private var heightText = ""
    @FocusState private var isHeightFocused: Bool
    @State private var camera = AvatarCamera()
    @State private var ready = false
    @State private var cameraRequested = false
    @State private var liveGuide: AvatarLiveGuide?
    @State private var guideToken: UUID?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var observations: [AvatarAngle: AvatarObservation] = [:]
    @State private var result: BodyAvatar?
    @State private var work: Task<Void, Never>?
    @State private var countdown: Int?
    @State private var message: String?
    @State private var cameraError: String?
    @State private var revealProgress: CGFloat = 0
    @State private var isReconstructing = false

    var isOnboarding = false
    let save: (BodyAvatar) throws -> Void

    var body: some View {
        NavigationStack {
            Group {
                switch step {
                case .introduction: introduction
                case .capture(let angle): capture(angle)
                case .review: review
                case .reveal: reveal
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Din 3D-avatar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if !isOnboarding {
                        Button("Stäng", role: .cancel) { dismiss() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(work != nil)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background {
                work?.cancel()
                countdown = nil
                camera.stop()
                ready = false
            }
        }
        .onDisappear {
            work?.cancel()
            camera.stop()
        }
    }

    private var measuredHeightCM: Double? {
        let input = heightText.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
        guard let height = Double(input), BodyAvatar.heightRangeCM.contains(height) else { return nil }
        return height
    }

    private var introduction: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Image(systemName: "person.crop.rectangle")
                    .font(.system(size: 46, weight: .light))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("Se din kroppsform i 3D")
                    .font(.largeTitle.bold())
                    .accessibilityAddTraits(.isHeader)
                Text("Testversion").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                Text("Ta eller välj tre helkroppsbilder. GoHealth uppskattar din kroppsform, ditt ansikte och hårets kontur och visar resultatet som en grå, roterbar figur.")
                Label("Placera iPhone stående på ett stadigt underlag, ungefär i midjehöjd. Använd jämnt ljus och enfärgad bakgrund.", systemImage: "camera.aperture")
                Label("Använd kroppsnära kläder och stå utan skor. Markera var du står så att du kan vända på samma plats.", systemImage: "figure.stand")
                VStack(alignment: .leading, spacing: 8) {
                    Text("Din uppmätta längd").font(.headline)
                    HStack {
                        TextField("Längd i centimeter", text: $heightText)
                            .textFieldStyle(.roundedBorder)
                            .keyboardType(.decimalPad)
                            .focused($isHeightFocused)
                        Text("cm").foregroundStyle(.secondary)
                    }
                    Text("Mät utan skor. Längden ger din avatar rätt skala.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if !heightText.isEmpty, measuredHeightCM == nil, !isHeightFocused {
                        Text("Ange en längd mellan 90 och 250 cm.")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                Label("Bilderna bearbetas på din iPhone. Appen sparar den härledda avataren lokalt.", systemImage: "lock")
                let hasAllPhotos = observations.count == AvatarAngle.allCases.count
                Button(hasAllPhotos ? "Tillbaka till granskning" : "Fortsätt till bilderna") {
                    isHeightFocused = false
                    step = hasAllPhotos ? .review : .capture(.front)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(measuredHeightCM == nil)
            }
            .padding(24)
        }
    }

    private func capture(_ angle: AvatarAngle) -> some View {
        GeometryReader { geometry in
            let isPortrait = geometry.size.height > geometry.size.width
            let cameraAngle: AvatarAngle? = cameraRequested && scenePhase == .active && isPortrait ? angle : nil
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Bild \((AvatarAngle.allCases.firstIndex(of: angle) ?? 0) + 1) av 3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(angle.title).font(.title2.bold())
                    Text(angle.instruction).font(.subheadline)
                    Text("Hela kroppen ska synas. Lämna lite luft ovanför huvudet och under fötterna.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    if cameraRequested {
                        guidedPreview
                            .frame(height: min(390, max(230, geometry.size.height * 0.53)))
                            .clipShape(RoundedRectangle(cornerRadius: 18))

                        if isPortrait, let guide = liveGuide {
                            Label(guide.status.instruction,
                                  systemImage: guide.status == .good ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .font(.subheadline)
                                .foregroundStyle(guide.status == .good ? Color.green : Color.red)
                        }
                        if !isPortrait {
                            Text("Håll telefonen stående när du tar bilden.").font(.footnote)
                        }
                        if isSceneCaptured {
                            Label("Om kamerabilden är svart, avsluta speglingen och fortsätt direkt på iPhonen.", systemImage: "iphone")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text("Starta timern och ställ dig i ramen. Bilden tas om ramen är grön när tiden är ute.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Button {
                            captureWithTimer(angle)
                        } label: {
                            Label("Ta bild om 5 sekunder", systemImage: "timer").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(!ready || work != nil || !isPortrait)
                    } else {
                        Button {
                            message = nil
                            cameraRequested = true
                        } label: {
                            Label("Öppna kameran", systemImage: "camera").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(work != nil)
                    }
                    PhotosPicker(selection: $pickedPhoto, matching: .images, preferredItemEncoding: .current) {
                        Label("Välj från Bilder", systemImage: "photo.on.rectangle").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(work != nil)
                    if !cameraRequested, work != nil { ProgressView("Kontrollerar bilden…") }
                    if let message { Text(message).font(.subheadline).foregroundStyle(.red) }
                    if observations.count == AvatarAngle.allCases.count {
                        Button("Tillbaka till granskning") { step = .review }
                            .disabled(work != nil)
                    }
                }
                .padding(20)
            }
            .task(id: cameraAngle) { await startGuide(for: cameraAngle) }
        }
        .onChange(of: pickedPhoto) { _, item in
            guard let item else { return }
            pickedPhoto = nil
            message = nil
            cameraRequested = false
            guideToken = nil
            liveGuide = nil
            importPhoto(item, angle: angle)
        }
        .onDisappear {
            guideToken = nil
            ready = false
            liveGuide = nil
            camera.stop()
        }
    }

    private var guidedPreview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18).fill(.black)
            AvatarCameraPreview(session: camera.session).accessibilityHidden(true)
            if ready {
                GeometryReader { geometry in
                    let aspect = liveGuide?.aspect ?? 0.75
                    let width = min(geometry.size.width, geometry.size.height * aspect)
                    let height = width / aspect
                    let color: Color = liveGuide.map { $0.status == .good ? .green : .red } ?? .white
                    RoundedRectangle(cornerRadius: 20)
                        .strokeBorder(color, lineWidth: 3)
                        .frame(width: width * AvatarLiveGuide.frame.width,
                               height: height * AvatarLiveGuide.frame.height)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                .accessibilityHidden(true)
            }
            if let countdown {
                Text("\(countdown)")
                    .font(.system(size: 72, weight: .bold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white)
                    .shadow(radius: 8)
                    .accessibilityLabel("Bilden tas om \(countdown) sekunder")
            } else if work != nil {
                ProgressView().tint(.white).controlSize(.large)
            } else if !ready {
                Text(cameraError ?? "Öppnar kameran…")
                    .font(.subheadline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(24)
            }
        }
    }

    private func startGuide(for angle: AvatarAngle?) async {
        guideToken = nil
        liveGuide = nil
        ready = false
        cameraError = nil
        guard let angle else {
            camera.stop()
            return
        }
        let token = UUID()
        guideToken = token
        do {
            try await camera.start(guideFor: angle) { guide in
                Task { @MainActor in
                    guard guideToken == token, step == .capture(angle) else { return }
                    liveGuide = guide
                }
            }
            try Task.checkCancellation()
            guard guideToken == token else { return }
            ready = true
        } catch is CancellationError {
            return
        } catch {
            guard guideToken == token else { return }
            cameraError = error.localizedDescription
            cameraRequested = false
            message = cameraError
        }
    }

    private func captureWithTimer(_ angle: AvatarAngle) {
        message = nil
        work = Task {
            defer { work = nil; countdown = nil }
            do {
                for remaining in (1...5).reversed() {
                    countdown = remaining
                    try await Task.sleep(for: .seconds(1))
                }
                countdown = nil
                guard ready, let guide = liveGuide, guide.status == .good,
                      ProcessInfo.processInfo.systemUptime - guide.timestamp < 1.5 else {
                    message = "Ramen behöver vara grön när tiden går ut. Följ instruktionen vid ramen och försök igen."
                    return
                }
                let picture = try await camera.takePhoto(includeHair: angle == .front)
                try await accept(picture, angle: angle)
            } catch is CancellationError {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func importPhoto(_ item: PhotosPickerItem, angle: AvatarAngle) {
        guard work == nil else { return }
        work = Task {
            defer { work = nil }
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else {
                    throw AvatarScanError.image
                }
                try Task.checkCancellation()
                try await accept(AvatarCaptureData(photo: data, hair: nil), angle: angle)
            } catch is CancellationError {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private func accept(_ picture: AvatarCaptureData, angle: AvatarAngle) async throws {
        let analysis = Task.detached(priority: .userInitiated) {
            try BodyAvatarReconstruction.analyze(picture, angle: angle)
        }
        let observation = try await withTaskCancellationHandler {
            try await analysis.value
        } onCancel: {
            analysis.cancel()
        }
        try Task.checkCancellation()
        guard step == .capture(angle) else { return }
        try BodyAvatarReconstruction.validate(observation, against: observations)
        observations[angle] = observation
        guideToken = nil
        liveGuide = nil
        ready = false
        if let next = AvatarAngle.allCases.first(where: { observations[$0] == nil }) {
            step = .capture(next)
        } else {
            step = .review
        }
    }

    private var review: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Dina tre vinklar är klara").font(.title2.bold())
                Text("GoHealth passar ihop kroppens konturer och ledpunkter från de tre vinklarna.")
                    .foregroundStyle(.secondary)
                if let measuredHeightCM {
                    HStack {
                        Label("\(measuredHeightCM.formatted(.number.precision(.fractionLength(0...2)))) cm", systemImage: "ruler")
                        Spacer()
                        Button("Ändra längd") { step = .introduction }
                    }
                    .disabled(isReconstructing)
                }
                ForEach(AvatarAngle.allCases, id: \.self) { angle in
                    HStack {
                        Label(angle.title, systemImage: "checkmark.circle.fill")
                        Spacer()
                        Button("Ta om") {
                            message = nil
                            step = .capture(angle)
                        }
                        .accessibilityLabel("Ta om bilden \(angle.title.lowercased())")
                    }
                    .disabled(isReconstructing)
                }
                if let message { Text(message).font(.subheadline).foregroundStyle(.red) }
                if isReconstructing {
                    ProgressView("Återskapar din 3D-form…")
                } else {
                    Button("Skapa 3D-avatar", action: reconstruct)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                }
            }
            .padding(24)
        }
    }

    private func reconstruct() {
        guard let heightCM = measuredHeightCM else { return }
        message = nil
        isReconstructing = true
        let inputs = observations
        work = Task {
            defer { isReconstructing = false; work = nil }
            let reconstruction = Task.detached(priority: .userInitiated) {
                try BodyAvatarReconstruction.reconstruct(inputs, heightCM: heightCM)
            }
            do {
                let avatar = try await withTaskCancellationHandler {
                    try await reconstruction.value
                } onCancel: {
                    reconstruction.cancel()
                }
                try Task.checkCancellation()
                observations.removeAll()
                result = avatar
                revealProgress = reduceMotion ? 1 : 0
                step = .reveal
            } catch is CancellationError {
                return
            } catch {
                message = error.localizedDescription
            }
        }
    }

    private var reveal: some View {
        VStack(spacing: 12) {
            if let result {
                GeometryReader { geometry in
                    let y = geometry.size.height * revealProgress
                    ZStack(alignment: .top) {
                        BodyAvatarDisplay(avatar: result, showMarkers: false) { _ in EmptyView() }
                            .mask(alignment: .top) { Rectangle().frame(height: y).frame(maxHeight: .infinity, alignment: .top) }
                        Rectangle()
                            .fill(.tint)
                            .frame(height: 2)
                            .offset(y: y)
                            .opacity(revealProgress >= 1 ? 0 : 1)
                            .accessibilityHidden(true)
                    }
                    .clipped()
                }
                .task {
                    guard !reduceMotion else { return }
                    withAnimation(.easeInOut(duration: 1.8)) { revealProgress = 1 }
                }
                Text("Dra åt sidan för att rotera kroppen.").font(.footnote).foregroundStyle(.secondary)
                if let message { Text(message).font(.footnote).foregroundStyle(.red) }
                Button(isOnboarding ? "Spara och fortsätt" : "Använd på Hem") {
                    do {
                        try save(result)
                        if !isOnboarding { dismiss() }
                    } catch {
                        message = "Avataren kunde inte sparas på telefonen. Försök igen."
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
        .padding(20)
    }
}

struct BodyAvatarDisplay<Marker: View>: View {
    let avatar: BodyAvatar
    var showMarkers = true
    @ViewBuilder var marker: (BodyOrgan) -> Marker

    @State private var angle: Float = 0
    @State private var dragStart: Float?
    @State private var points: [BodyOrgan: CGPoint] = [:]
    @State private var renderFailed = false

    var body: some View {
        ZStack {
            AvatarRealityScene(avatar: avatar, angle: angle, points: $points, renderFailed: $renderFailed)
                .accessibilityHidden(true)
                .gesture(DragGesture(minimumDistance: 10, coordinateSpace: .local)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        let start = dragStart ?? angle
                        dragStart = start
                        angle = (start + Float(value.translation.width) * 0.018).truncatingRemainder(dividingBy: 2 * .pi)
                    }
                    .onEnded { _ in dragStart = nil })
            if renderFailed {
                ContentUnavailableView("3D-vyn är inte tillgänglig", systemImage: "person.crop.circle")
            } else {
                Rectangle()
                    .fill(.clear)
                    .allowsHitTesting(false)
                    .accessibilityElement()
                    .accessibilityLabel("Roterbar kroppsfigur")
                    .accessibilityAdjustableAction { direction in
                        angle += direction == .increment ? .pi / 4 : -.pi / 4
                    }
                if showMarkers {
                    ForEach(BodyOrgan.allCases, id: \.self) { organ in
                        if let point = points[organ] {
                            marker(organ).position(point)
                        }
                    }
                }
            }
        }
        .background(.white)
        .clipped()
    }
}

private struct AvatarRealityScene: UIViewRepresentable {
    let avatar: BodyAvatar
    let angle: Float
    @Binding var points: [BodyOrgan: CGPoint]
    @Binding var renderFailed: Bool

    final class SceneView: ARView {
        var onLayout: (() -> Void)?
        override func layoutSubviews() {
            super.layoutSubviews()
            onLayout?()
        }
    }

    final class Coordinator {
        let figure = Entity()
        var markerLocations: [BodyOrgan: SIMD3<Float>] = [:]
        var publish: (([BodyOrgan: CGPoint]) -> Void)?

        func project(in view: ARView) {
            let front = figure.orientation.act(SIMD3<Float>(0, 0, 1)).z
            let locations = front > 0.22 ? markerLocations.compactMapValues {
                view.project(figure.convert(position: $0, to: nil))
            } : [:]
            publish?(locations)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SceneView {
        let view = SceneView(frame: .zero, cameraMode: .nonAR, automaticallyConfigureSession: false)
        view.environment.background = .color(.white)
        let anchor = AnchorEntity(world: .zero)
        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = 36
        if #available(iOS 18.0, *) { camera.camera.fieldOfViewOrientation = .vertical }
        let scale = avatar.metersPerUnit
        let heights = avatar.positions.lazy.map(\.y)
        let bottom = (heights.min() ?? -0.5) * scale
        let top = (heights.max() ?? 0.5) * scale
        let center = SIMD3<Float>(0, (top + bottom) / 2, 0)
        let halfHeight = (top - bottom) / 2
        // Bound the figure at every rotation about its vertical axis.
        let radius = (avatar.positions.lazy.map { simd_length(SIMD2($0.x, $0.z)) }.max() ?? 0) * scale
        let verticalTangent = tan(camera.camera.fieldOfViewInDegrees * .pi / 360)
        anchor.addChild(camera)
        let key = DirectionalLight()
        key.light.intensity = 2_400
        key.look(at: .zero, from: [-1, 1.5, 2], relativeTo: anchor)
        anchor.addChild(key)
        let fill = DirectionalLight()
        fill.light.intensity = 1_000
        fill.look(at: .zero, from: [1, 0.5, -2], relativeTo: anchor)
        anchor.addChild(fill)

        let coordinator = context.coordinator
        coordinator.figure.scale = SIMD3(repeating: scale)
        do {
            coordinator.figure.addChild(try makeModel())
            coordinator.markerLocations = Dictionary(uniqueKeysWithValues: BodyOrgan.allCases.map { organ in
                (organ, avatar.markerPosition(for: organ))
            })
        } catch {
            DispatchQueue.main.async { renderFailed = true }
        }
        anchor.addChild(coordinator.figure)
        view.scene.addAnchor(anchor)
        view.onLayout = { [weak view, weak coordinator, weak camera] in
            guard let view, let coordinator, let camera,
                  view.bounds.width > 0, view.bounds.height > 0 else { return }
            let aspect = Float(view.bounds.width / view.bounds.height)
            let horizontalTangent = verticalTangent * aspect
            let distance = radius + 1.06 * max(halfHeight / verticalTangent, radius / horizontalTangent)
            camera.position = center + [0, 0, distance]
            coordinator.project(in: view)
        }
        view.onLayout?()
        return view
    }

    func updateUIView(_ view: SceneView, context: Context) {
        let coordinator = context.coordinator
        coordinator.publish = { locations in
            DispatchQueue.main.async {
                if points != locations { points = locations }
            }
        }
        coordinator.figure.orientation = simd_quatf(angle: angle, axis: [0, 1, 0])
        coordinator.project(in: view)
    }

    private func makeModel() throws -> ModelEntity {
        var normals = [SIMD3<Float>](repeating: .zero, count: avatar.positions.count)
        for i in stride(from: 0, to: avatar.triangles.count, by: 3) {
            let a = Int(avatar.triangles[i]), b = Int(avatar.triangles[i + 1]), c = Int(avatar.triangles[i + 2])
            let normal = simd_cross(avatar.positions[b] - avatar.positions[a], avatar.positions[c] - avatar.positions[a])
            normals[a] += normal
            normals[b] += normal
            normals[c] += normal
        }
        normals = normals.map { simd_length_squared($0) > 1e-18 ? simd_normalize($0) : [0, 1, 0] }
        let uv = zip(avatar.positions, normals).map { point, normal -> SIMD2<Float> in
            if point.y > 0.30, normal.z > 0.35 {
                return [point.x / BodyAvatar.width + 0.5, point.y + 0.5]
            }
            return [0, 0]
        }
        var descriptor = MeshDescriptor(name: "GoHealth")
        descriptor.positions = MeshBuffers.Positions(avatar.positions)
        descriptor.normals = MeshBuffers.Normals(normals)
        descriptor.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        descriptor.primitives = .triangles(avatar.triangles)
        let mesh = try MeshResource.generate(from: [descriptor])

        var material = SimpleMaterial(color: UIColor(white: CGFloat(BodyAvatar.gray) / 255, alpha: 1), roughness: 0.85, isMetallic: false)
        let rgba = Data(avatar.frontTones.flatMap { [$0, $0, $0, 255] })
        if let provider = CGDataProvider(data: rgba as CFData),
           let image = CGImage(width: BodyAvatar.textureWidth, height: BodyAvatar.textureHeight,
                               bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: BodyAvatar.textureWidth * 4,
                               space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
                               provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent),
           let texture = try? TextureResource.generate(from: image, options: .init(semantic: .color)) {
            material.color = .init(tint: .white, texture: .init(texture))
        }
        return ModelEntity(mesh: mesh, materials: [material])
    }
}
