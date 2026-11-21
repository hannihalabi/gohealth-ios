import CoreGraphics
import Foundation
import ImageIO
import Vision
import simd

enum AvatarAngle: String, CaseIterable, Sendable {
    case front, right, back

    var title: String {
        switch self {
        case .front: "Framifrån"
        case .right: "Höger sida"
        case .back: "Bakifrån"
        }
    }

    var instruction: String {
        switch self {
        case .front: "Stå rakt mot kameran. Ha fötterna höftbrett och lämna en liten glipa mellan armar och överkropp."
        case .right: "Vänd ett kvarts varv åt vänster på samma plats. Låt kameran stå kvar och behåll hållningen."
        case .back: "Vänd ryggen mot kameran på samma plats. Håll samma avstånd mellan fötterna och samma glipa vid armarna som framifrån."
        }
    }
}

struct BodyAvatar: Codable, Sendable {
    let id: UUID
    let positions: [SIMD3<Float>]
    let triangles: [UInt32]
    let frontTones: Data
    let heart: SIMD3<Float>
    let liver: SIMD3<Float>
    let calibratedHeightCM: Double?

    static let textureWidth = 384
    static let textureHeight = 512
    static let gray: UInt8 = 184
    static let width: Float = 0.84
    static let heightRangeCM = 90.0...250.0

    var metersPerUnit: Float {
        guard let calibratedHeightCM,
              let minY = positions.lazy.map(\.y).min(),
              let maxY = positions.lazy.map(\.y).max(), maxY - minY > 0.8 else { return 1 }
        return Float(calibratedHeightCM / 100) / (maxY - minY)
    }

    var isValid: Bool {
        (calibratedHeightCM.map(Self.heightRangeCM.contains) ?? true) &&
        positions.count >= 100 && positions.count <= 80_000 &&
        triangles.count >= 300 && triangles.count <= 480_000 &&
        triangles.count.isMultiple(of: 3) &&
        frontTones.count == Self.textureWidth * Self.textureHeight &&
        triangles.allSatisfy { Int($0) < positions.count } &&
        positions.allSatisfy { abs($0.x) < 0.6 && abs($0.y) < 0.6 && abs($0.z) < 0.5 } &&
        [heart, liver].allSatisfy { abs($0.x) < 0.6 && abs($0.y) < 0.6 && abs($0.z) < 0.5 }
    }

    func markerPosition(for organ: BodyOrgan) -> SIMD3<Float> {
        switch organ {
        case .heart: heart
        case .liver: liver
        case .lungs, .kidneys, .thyroid:
            Self.surfaceAnchor(x: Float(organ.markerPosition.x), y: 0.5 - Float(organ.markerPosition.y), in: positions)
        }
    }

    fileprivate static func surfaceAnchor(x: Float, y: Float, in positions: [SIMD3<Float>]) -> SIMD3<Float> {
        let depth = positions.lazy.filter { abs($0.x - x) < 0.022 && abs($0.y - y) < 0.02 }
            .map(\.z).max() ?? 0.08
        return [x, y, depth + 0.014]
    }
}

enum BodyAvatarFiles {
    private static func directory() throws -> URL {
        let directory = try FileManager.default.url(for: .applicationSupportDirectory,
                                                     in: .userDomainMask,
                                                     appropriateFor: nil,
                                                     create: true)
            .appendingPathComponent("BodyAvatars", isDirectory: true)
        return directory
    }

    private static func file(for accountID: UUID) throws -> URL {
        try directory().appendingPathComponent("v1-\(accountID.uuidString).json")
    }

    static func load(for accountID: UUID) throws -> BodyAvatar? {
        let url = try file(for: accountID)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size < 10_000_000 else { throw AvatarScanError.reconstruction }
        let avatar = try JSONDecoder().decode(BodyAvatar.self, from: Data(contentsOf: url))
        guard avatar.isValid else { throw AvatarScanError.reconstruction }
        return avatar
    }

    static func save(_ avatar: BodyAvatar, for accountID: UUID) throws {
        guard avatar.isValid else { throw AvatarScanError.reconstruction }
        var folder = try directory()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.complete])
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try folder.setResourceValues(values)
        try JSONEncoder().encode(avatar).write(to: file(for: accountID), options: [.atomic, .completeFileProtection])
    }

    static func remove(for accountID: UUID) throws {
        do {
            try FileManager.default.removeItem(at: file(for: accountID))
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return
        }
    }
}

enum AvatarScanError: LocalizedError {
    case image, darkPhoto, onePerson, framing, pose, face, view, captureDistance, stance, inconsistent, reconstruction

    var errorDescription: String? {
        switch self {
        case .image: "Bilden gick inte att läsa. Ta en ny bild i bra ljus."
        case .darkPhoto: "Kamerabilden är nästan svart. Om du använder Device Hub, avsluta speglingen och ta bilden direkt på iPhonen. Kontrollera ljuset och att linsen är fri."
        case .onePerson: "Se till att bara du syns och att det är tydlig kontrast mot bakgrunden."
        case .framing: "Hela kroppen behöver synas, med luft ovanför huvudet och under fötterna."
        case .pose: "Stå upprätt och håll armarna lite ut från kroppen."
        case .face: "Ansiktet syns inte tillräckligt tydligt. Titta rakt in i kameran i jämnt ljus."
        case .view: "Vinkeln stämmer inte. Följ guiden och ta om den här bilden."
        case .captureDistance: "Stå på samma avstånd från telefonen i alla tre bilderna. Ta om bilden från samma plats."
        case .stance: "Avståndet mellan fötterna skiljer sig från den andra bilden. Ställ fötterna likadant som tidigare och ta om bilden."
        case .inconsistent: "Bilderna visar olika poser. Stå likadant i alla tre bilderna och försök igen."
        case .reconstruction: "GoHealth kunde inte skapa en sammanhängande figur från bilderna."
        }
    }
}

struct AvatarCaptureData: Sendable {
    let photo: Data
    let hair: Data?
}

struct AvatarObservation: Sendable {
    let angle: AvatarAngle
    fileprivate let silhouette: AvatarSilhouette
    fileprivate let face: AvatarFace?
    fileprivate let pose: AvatarPose
}

private struct AvatarFace: Sendable {
    let toneMap: Data
    let nose: SIMD2<Float>
    let eyes: [SIMD2<Float>]
    let mouth: SIMD2<Float>
}

// Coordinates are normalized by subject height. The image origin is at the top left.
private struct AvatarSilhouette: Sendable {
    let width: Int
    let height: Int
    let distance: [Float]
    let minY: Int
    let maxY: Int
    let centerX: Float
    var subjectHeight: Float { Float(maxY - minY) }
    var coverage: Float { subjectHeight / Float(height) }

    func smoothedSample(x: Float, y: Float) -> Float {
        let radius: Float = 0.011
        return sample(x: x, y: y) * 0.50
            + (sample(x: x, y: y - radius) + sample(x: x, y: y + radius)) * 0.25
    }

    func imagePoint(x: Float, y: Float) -> SIMD2<Float> {
        [centerX + x * subjectHeight, Float(minY) + (0.5 - y) * subjectHeight]
    }

    func bodyPoint(x: CGFloat, y: CGFloat) -> SIMD2<Float> {
        let pixelX = Float(x) * Float(width - 1)
        let pixelY = (1 - Float(y)) * Float(height - 1)
        return [(pixelX - centerX) / subjectHeight, 0.5 - (pixelY - Float(minY)) / subjectHeight]
    }

    func sample(x: Float, y: Float) -> Float {
        let point = imagePoint(x: x, y: y)
        guard point.x >= 0, point.y >= 0, point.x < Float(width - 1), point.y < Float(height - 1) else {
            return -0.08
        }
        let column = Int(point.x)
        let row = Int(point.y)
        let a = point.x - Float(column)
        let b = point.y - Float(row)
        let offset = row * width + column
        let top = distance[offset] * (1 - a) + distance[offset + 1] * a
        let bottom = distance[offset + width] * (1 - a) + distance[offset + width + 1] * a
        return (top * (1 - b) + bottom * b) / subjectHeight
    }
}

enum BodyAvatarReconstruction {
    static func analyze(_ capture: AvatarCaptureData, angle: AvatarAngle) throws -> AvatarObservation {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(capture.photo as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 2_048
              ] as CFDictionary) else { throw AvatarScanError.image }

        let lightSample = try grayPixels(image, width: 32, height: 32)
        guard lightSample.count(where: { $0 > 24 }) >= 12 else { throw AvatarScanError.darkPhoto }

        let person = VNGeneratePersonSegmentationRequest()
        person.qualityLevel = .accurate
        person.outputPixelFormat = kCVPixelFormatType_OneComponent8
        let pose = VNDetectHumanBodyPoseRequest()
        let face = VNDetectFaceLandmarksRequest()
        let requests: [VNRequest] = angle == .front ? [person, pose, face] : [person, pose]
        try VNImageRequestHandler(cgImage: image, orientation: .up).perform(requests)
        try Task.checkCancellation()

        guard let poses = pose.results, poses.count == 1,
              let mask = person.results?.first?.pixelBuffer else { throw AvatarScanError.onePerson }
        let joints = try poses[0].recognizedPoints(.all)
        guard let root = joints[.root], root.confidence > 0.25,
              [joints[.leftAnkle], joints[.rightAnkle]].compactMap({ $0 }).contains(where: { $0.confidence > 0.25 })
        else { throw AvatarScanError.pose }

        let silhouette = try makeSilhouette(mask, centerX: root.location.x)
        if angle == .right, let nose = joints[.nose], let neck = joints[.neck],
           nose.confidence > 0.35, neck.confidence > 0.35, nose.location.x + 0.018 < neck.location.x {
            throw AvatarScanError.view
        }
        if let left = joints[.leftShoulder], let right = joints[.rightShoulder],
           left.confidence > 0.35, right.confidence > 0.35 {
            let a = silhouette.bodyPoint(x: left.location.x, y: left.location.y)
            let b = silhouette.bodyPoint(x: right.location.x, y: right.location.y)
            let shoulderWidth = abs(a.x - b.x)
            if angle == .right, shoulderWidth > 0.15 { throw AvatarScanError.view }
            if angle != .right, shoulderWidth < 0.095 { throw AvatarScanError.view }
        }

        var faceDetail: AvatarFace?
        if angle == .front {
            guard let detected = face.results?.first,
                  detected.boundingBox.width * CGFloat(image.width) >= 42,
                  detected.boundingBox.height * CGFloat(image.height) >= 50,
                  let landmarks = detected.landmarks,
                  let nose = center(landmarks.nose),
                  let leftEye = center(landmarks.leftEye),
                  let rightEye = center(landmarks.rightEye),
                  let lips = center(landmarks.outerLips)
            else { throw AvatarScanError.face }
            let box = detected.boundingBox
            func project(_ point: CGPoint) -> SIMD2<Float> {
                silhouette.bodyPoint(x: box.minX + point.x * box.width, y: box.minY + point.y * box.height)
            }
            let hair = capture.hair.flatMap { CGImageSourceCreateWithData($0 as CFData, nil) }
                .flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
            faceDetail = AvatarFace(toneMap: try makeTones(image: image, hair: hair, face: box, silhouette: silhouette),
                                    nose: project(nose), eyes: [project(leftEye), project(rightEye)], mouth: project(lips))
        }
        func point(_ name: VNHumanBodyPoseObservation.JointName) -> SIMD2<Float>? {
            guard let joint = joints[name], joint.confidence > 0.25 else { return nil }
            return silhouette.bodyPoint(x: joint.location.x, y: joint.location.y)
        }
        func meanY(_ names: VNHumanBodyPoseObservation.JointName...) -> Float? {
            let points = names.compactMap(point)
            guard !points.isEmpty else { return nil }
            return points.reduce(0) { $0 + $1.y } / Float(points.count)
        }
        let levels: [AvatarPose.Level: Float?] = [
            .ankles: meanY(.leftAnkle, .rightAnkle),
            .knees: meanY(.leftKnee, .rightKnee),
            .root: point(.root)?.y,
            .shoulders: meanY(.leftShoulder, .rightShoulder),
            .neck: point(.neck)?.y
        ]
        var stance: Float?
        if let left = point(.leftAnkle), let right = point(.rightAnkle) {
            stance = abs(left.x - right.x)
        }
        let arm = [VNHumanBodyPoseObservation.JointName.rightShoulder, .rightElbow, .rightWrist].compactMap(point)
        let poseDetail = AvatarPose(levels: levels.compactMapValues { $0 }, stance: stance, arm: arm)
        return AvatarObservation(angle: angle, silhouette: silhouette, face: faceDetail, pose: poseDetail)
    }

    private static func center(_ region: VNFaceLandmarkRegion2D?) -> CGPoint? {
        guard let points = region?.normalizedPoints, !points.isEmpty else { return nil }
        let sum = points.reduce(CGPoint.zero) { CGPoint(x: $0.x + $1.x, y: $0.y + $1.y) }
        return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
    }

    private static func makeSilhouette(_ buffer: CVPixelBuffer, centerX: CGFloat) throws -> AvatarSilhouette {
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw AvatarScanError.image }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        let bytes = base.assumingMemoryBound(to: UInt8.self)
        var mask = [Bool](repeating: false, count: width * height)
        var minY = height, maxY = 0, minX = width, maxX = 0
        var area = 0
        for y in 0..<height {
            for x in 0..<width where bytes[y * stride + x] >= 128 {
                mask[y * width + x] = true
                minY = min(minY, y)
                maxY = max(maxY, y)
                minX = min(minX, x)
                maxX = max(maxX, x)
                area += 1
            }
        }
        guard area > width * height / 25, maxY - minY > height / 2,
              minY > 1, maxY < height - 2, minX > 1, maxX < width - 2 else {
            throw AvatarScanError.framing
        }
        let inside = chamfer(mask.map { $0 ? 1_000 as Float : 0 }, width: width, height: height)
        let outside = chamfer(mask.map { $0 ? 0 : 1_000 as Float }, width: width, height: height)
        let signed = zip(inside, outside).map { $0 - $1 }
        return AvatarSilhouette(width: width, height: height, distance: signed,
                                minY: minY, maxY: maxY, centerX: Float(centerX) * Float(width - 1))
    }

    private static func chamfer(_ input: [Float], width: Int, height: Int) -> [Float] {
        var result = input
        let diagonal: Float = 1.4142136
        for y in 0..<height {
            for x in 0..<width {
                let i = y * width + x
                if x > 0 { result[i] = min(result[i], result[i - 1] + 1) }
                if y > 0 {
                    result[i] = min(result[i], result[i - width] + 1)
                    if x > 0 { result[i] = min(result[i], result[i - width - 1] + diagonal) }
                    if x + 1 < width { result[i] = min(result[i], result[i - width + 1] + diagonal) }
                }
            }
        }
        for y in (0..<height).reversed() {
            for x in (0..<width).reversed() {
                let i = y * width + x
                if x + 1 < width { result[i] = min(result[i], result[i + 1] + 1) }
                if y + 1 < height {
                    result[i] = min(result[i], result[i + width] + 1)
                    if x > 0 { result[i] = min(result[i], result[i + width - 1] + diagonal) }
                    if x + 1 < width { result[i] = min(result[i], result[i + width + 1] + diagonal) }
                }
            }
        }
        return result
    }

    private static func grayPixels(_ image: CGImage, width: Int, height: Int) throws -> [UInt8] {
        var pixels = [UInt8](repeating: 0, count: width * height)
        let rendered = pixels.withUnsafeMutableBytes { buffer in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width,
                                          space: CGColorSpaceCreateDeviceGray(),
                                          bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { throw AvatarScanError.image }
        return pixels
    }

    private static func makeTones(image: CGImage, hair: CGImage?, face: CGRect,
                                  silhouette: AvatarSilhouette) throws -> Data {
        let inputWidth = silhouette.width * 2, inputHeight = silhouette.height * 2
        let pixels = try grayPixels(image, width: inputWidth, height: inputHeight)
        let hairPixels = try hair.map { try grayPixels($0, width: inputWidth, height: inputHeight) }
        let width = BodyAvatar.textureWidth, height = BodyAvatar.textureHeight
        var tones = [UInt8](repeating: BodyAvatar.gray, count: width * height)
        let center = silhouette.bodyPoint(x: face.midX, y: face.midY)
        let lower = silhouette.bodyPoint(x: face.minX, y: face.minY)
        let radius = SIMD2<Float>(max((center.x - lower.x) * 1.17, 0.02),
                                   max((center.y - lower.y) * 1.40, 0.025))
        for row in 1..<(height / 5) {
            for column in 1..<width {
                let x = (Float(column) / Float(width - 1) - 0.5) * BodyAvatar.width
                let y = 0.5 - Float(row) / Float(height - 1)
                guard y > 0.30, silhouette.sample(x: x, y: y) > 0.005 else { continue }
                let p = silhouette.imagePoint(x: x, y: y)
                let sx = Int(p.x * 2), sy = Int(p.y * 2)
                guard (0..<inputWidth).contains(sx), (0..<inputHeight).contains(sy) else { continue }
                let pixel = sy * inputWidth + sx
                let ellipse = simd_length((SIMD2<Float>(x, y) - center) / radius)
                let faceWeight = max(0, min(1, (1 - ellipse) * 4))
                let hairWeight = Float(hairPixels?[pixel] ?? 0) / 255
                let weight = max(faceWeight, hairWeight * 0.8)
                let lightness = 129 + Float(pixels[pixel]) * 0.39 - hairWeight * 14
                tones[row * width + column] = UInt8(max(0, min(255, Float(BodyAvatar.gray) * (1 - weight) + lightness * weight)))
            }
        }
        return Data(tones)
    }

    static func validate(_ observation: AvatarObservation, against accepted: [AvatarAngle: AvatarObservation]) throws {
        for other in accepted.values where other.angle != observation.angle {
            let ratio = observation.silhouette.coverage / other.silhouette.coverage
            guard (0.87...1.15).contains(ratio) else { throw AvatarScanError.captureDistance }
            guard observation.angle != .right, other.angle != .right else { continue }
            if let first = observation.pose.stance, let second = other.pose.stance,
               abs(first - second) > 0.055 {
                throw AvatarScanError.stance
            }
        }
    }

    static func reconstruct(_ observations: [AvatarAngle: AvatarObservation], heightCM: Double) throws -> BodyAvatar {
        guard BodyAvatar.heightRangeCM.contains(heightCM),
              let front = observations[.front], let back = observations[.back],
              let right = observations[.right], let face = front.face
        else { throw AvatarScanError.reconstruction }
        for observation in [front, back, right] {
            try validate(observation, against: observations)
        }

        let rearAlignment = front.pose.alignment(to: back.pose)
        let sideAlignment = front.pose.alignment(to: right.pose)
        let grid = AvatarVolume()
        var field = [Float](repeating: -0.04, count: grid.count)
        var common = 0
        var union = 0

        for j in 1..<(grid.ny - 1) {
            try Task.checkCancellation()
            let y = grid.point(grid.index(0, j, 0)).y
            guard abs(y) < 0.505 else { continue }
            let rearY = rearAlignment.map(y)
            let sideY = sideAlignment.map(y)
            let frontal = AvatarSpan.trace { x in
                let a = front.silhouette.smoothedSample(x: x, y: y)
                let b = back.silhouette.smoothedSample(x: -x, y: rearY)
                if a > 0 || b > 0 { union += 1 }
                if a > 0 && b > 0 { common += 1 }
                return (a + b) / 2
            }
            let profiles = AvatarSpan.trace { right.silhouette.smoothedSample(x: $0, y: sideY) }
            guard let profile = profiles.max(by: { $0.radius < $1.radius }) else { continue }
            let hipY = front.pose.levels[.root] ?? 0
            let shoulderY = front.pose.levels[.shoulders] ?? 0.30
            let sections = frontal.map { span -> AvatarSection in
                let isArm = y > hipY - 0.08 && y < shoulderY && abs(span.center) > 0.10
                let isLeg = y < hipY - 0.035 && frontal.count > 1
                let radius: Float
                if isArm {
                    radius = min(profile.radius, span.radius * 1.35)
                } else if isLeg {
                    radius = min(profile.radius, span.radius * 1.55)
                } else {
                    radius = profile.radius
                }
                let sideJoint = isArm ? right.pose.armDepth(at: sideY) : nil
                let center = sideJoint.map { min(profile.upper - radius, max(profile.lower + radius, $0)) }
                    ?? profile.center
                return AvatarSection(span: span, centerZ: center, radiusZ: radius)
            }

            for k in 1..<(grid.nz - 1) {
                for i in 1..<(grid.nx - 1) {
                    let index = grid.index(i, j, k)
                    let p = grid.point(index)
                    var z = p.z
                    if z > profile.center, y > 0.30 {
                        z -= faceRelief(SIMD2<Float>(p.x, y), face: face)
                    }
                    for section in sections {
                        field[index] = max(field[index], section.sample(x: p.x, z: z))
                    }
                }
            }
        }
        guard union > 0, Float(common) / Float(union) > 0.60 else { throw AvatarScanError.inconsistent }

        // Blend adjacent levels so that a change in silhouette topology at the
        // armpits or hips does not create a hard horizontal ridge.
        let unsmoothed = field
        let rowSize = grid.nx * grid.nz
        for j in 2..<(grid.ny - 2) {
            try Task.checkCancellation()
            for index in (j * rowSize)..<((j + 1) * rowSize) {
                field[index] = (unsmoothed[index] * 6
                    + (unsmoothed[index - rowSize] + unsmoothed[index + rowSize]) * 4
                    + unsmoothed[index - 2 * rowSize] + unsmoothed[index + 2 * rowSize]) / 16
            }
        }
        let solid = try grid.largestComponent(of: &field)
        guard solid > 1_000 else { throw AvatarScanError.inconsistent }
        let mesh = try grid.surface(field)
        let avatar = BodyAvatar(id: UUID(), positions: mesh.positions, triangles: mesh.triangles, frontTones: face.toneMap,
                                heart: BodyAvatar.surfaceAnchor(x: 0.050, y: 0.19, in: mesh.positions),
                                liver: BodyAvatar.surfaceAnchor(x: -0.055, y: 0.085, in: mesh.positions), calibratedHeightCM: heightCM)
        guard avatar.isValid else { throw AvatarScanError.reconstruction }
        return avatar
    }

    private static func faceRelief(_ point: SIMD2<Float>, face: AvatarFace) -> Float {
        func bump(_ center: SIMD2<Float>, width: Float, height: Float) -> Float {
            let delta = (point - center) / SIMD2<Float>(width, height)
            return exp(-simd_length_squared(delta) * 2)
        }
        let nose = bump(face.nose, width: 0.018, height: 0.026)
        let eyes = face.eyes.reduce(Float(0)) { $0 + bump($1, width: 0.014, height: 0.011) }
        let mouth = bump(face.mouth, width: 0.022, height: 0.008)
        return nose * 0.006 - eyes * 0.004 + mouth * 0.002
    }
}

private struct AvatarPose: Sendable {
    enum Level: CaseIterable, Sendable {
        case ankles, knees, root, shoulders, neck
    }

    let levels: [Level: Float]
    let stance: Float?
    let arm: [SIMD2<Float>]

    // Each landmark is normalized by the visible subject height. Pin both ends
    // to preserve the top of the head and the soles when aligning the views.
    func alignment(to other: Self) -> AvatarAlignment {
        var pairs: [SIMD2<Float>] = [[-0.5, -0.5]]
        var previous = SIMD2<Float>(-0.5, -0.5)
        for level in Level.allCases {
            guard let a = levels[level], let b = other.levels[level],
                  a > previous.x + 0.02, b > previous.y + 0.02,
                  a < 0.47, b < 0.47, abs(a - b) < 0.08 else { continue }
            previous = [a, b]
            pairs.append(previous)
        }
        pairs.append([0.5, 0.5])
        return AvatarAlignment(pairs: pairs)
    }

    func armDepth(at y: Float) -> Float? {
        for (upper, lower) in zip(arm, arm.dropFirst()) where y <= upper.y && y >= lower.y && upper.y > lower.y {
            let weight = (upper.y - y) / (upper.y - lower.y)
            return upper.x + weight * (lower.x - upper.x)
        }
        return nil
    }
}

private struct AvatarAlignment {
    let pairs: [SIMD2<Float>]

    func map(_ y: Float) -> Float {
        for (lower, upper) in zip(pairs, pairs.dropFirst()) where y >= lower.x && y <= upper.x {
            let weight = (y - lower.x) / (upper.x - lower.x)
            return lower.y + weight * (upper.y - lower.y)
        }
        return y
    }
}

private struct AvatarSpan {
    let lower: Float
    let upper: Float
    var center: Float { (lower + upper) / 2 }
    var radius: Float { (upper - lower) / 2 }

    static func trace(_ sample: (Float) -> Float) -> [Self] {
        let halfWidth = BodyAvatar.width / 2
        let count = 120
        let step = BodyAvatar.width / Float(count)
        var previous = sample(-halfWidth)
        var start: Float? = previous > 0 ? -halfWidth : nil
        var spans: [Self] = []

        for index in 1...count {
            let x = Float(index) * step - halfWidth
            let current = sample(x)
            if (current > 0) != (previous > 0) {
                let crossing = x - step * current / (current - previous)
                if current > 0 {
                    start = crossing
                } else if let lower = start {
                    if crossing - lower > 0.008 { spans.append(Self(lower: lower, upper: crossing)) }
                    start = nil
                }
            }
            previous = current
        }
        if let lower = start, halfWidth - lower > 0.008 {
            spans.append(Self(lower: lower, upper: halfWidth))
        }
        return spans
    }
}

private struct AvatarSection {
    let span: AvatarSpan
    let centerZ: Float
    let radiusZ: Float

    func sample(x: Float, z: Float) -> Float {
        let dx = (x - span.center) / span.radius
        let dz = (z - centerZ) / radiusZ
        return (1 - sqrt(dx * dx + dz * dz)) * min(span.radius, radiusZ)
    }
}

private struct AvatarVolume {
    let nx = 73, ny = 99, nz = 57
    var count: Int { nx * ny * nz }

    func index(_ x: Int, _ y: Int, _ z: Int) -> Int { x + nx * (z + nz * y) }

    func point(_ index: Int) -> SIMD3<Float> {
        let x = index % nx, z = index / nx % nz, y = index / (nx * nz)
        return [(Float(x) / Float(nx - 1) - 0.5) * BodyAvatar.width,
                (Float(y) / Float(ny - 1) - 0.5) * 1.06,
                (Float(z) / Float(nz - 1) - 0.5) * 0.64]
    }

    // Keep one connected figure when a small background fragment survives segmentation.
    func largestComponent(of field: inout [Float]) throws -> Int {
        var seen = [Bool](repeating: false, count: count)
        var largest: [Int] = []
        let offsets = [-1, 1, -nx, nx, -nx * nz, nx * nz]
        for i in 0..<count where field[i] > 0 && !seen[i] {
            try Task.checkCancellation()
            var component = [i]
            var head = 0
            seen[i] = true
            while head < component.count {
                let index = component[head]
                head += 1
                for offset in offsets {
                    let next = index + offset
                    if !seen[next], field[next] > 0 {
                        seen[next] = true
                        component.append(next)
                    }
                }
            }
            if component.count > largest.count { largest = component }
        }
        for i in 0..<count where field[i] > 0 { seen[i] = false }
        for i in largest { seen[i] = true }
        for i in 0..<count where field[i] > 0 && !seen[i] { field[i] = -0.01 }
        return largest.count
    }

    func surface(_ field: [Float]) throws -> (positions: [SIMD3<Float>], triangles: [UInt32]) {
        var vertices: [SIMD3<Float>] = []
        var triangles: [UInt32] = []
        var edges: [UInt64: UInt32] = [:]
        let tetrahedra = [[0, 1, 3, 7], [0, 3, 2, 7], [0, 2, 6, 7],
                          [0, 6, 4, 7], [0, 4, 5, 7], [0, 5, 1, 7]]

        func crossing(_ a: Int, _ b: Int) -> UInt32 {
            let key = UInt64(min(a, b)) << 32 | UInt64(max(a, b))
            if let existing = edges[key] { return existing }
            let t = min(0.9999, max(0.0001, field[a] / (field[a] - field[b])))
            let vertex = point(a) + (point(b) - point(a)) * t
            let i = UInt32(vertices.count)
            vertices.append(vertex)
            edges[key] = i
            return i
        }

        func triangle(_ a: UInt32, _ b: UInt32, _ c: UInt32, toward: SIMD3<Float>) {
            let origin = vertices[Int(a)]
            let normal = simd_cross(vertices[Int(b)] - origin, vertices[Int(c)] - origin)
            if simd_dot(normal, toward) >= 0 {
                triangles.append(contentsOf: [a, b, c])
            } else {
                triangles.append(contentsOf: [a, c, b])
            }
        }

        for y in 0..<(ny - 1) {
            try Task.checkCancellation()
            for z in 0..<(nz - 1) {
                for x in 0..<(nx - 1) {
                    let base = index(x, y, z)
                    let layer = nx * nz
                    let corners = [base, base + 1, base + nx, base + nx + 1,
                                   base + layer, base + layer + 1, base + layer + nx, base + layer + nx + 1]
                    let count = corners.reduce(0) { $0 + (field[$1] > 0 ? 1 : 0) }
                    guard count > 0, count < 8 else { continue }
                    for tetrahedron in tetrahedra {
                        let corners = tetrahedron.map { corners[$0] }
                        let inside = corners.filter { field[$0] > 0 }
                        let outside = corners.filter { field[$0] <= 0 }
                        guard let firstInside = inside.first, let firstOutside = outside.first else { continue }
                        let outward = point(firstOutside) - point(firstInside)
                        switch inside.count {
                        case 1:
                            triangle(crossing(firstInside, outside[0]), crossing(firstInside, outside[1]),
                                     crossing(firstInside, outside[2]), toward: outward)
                        case 2:
                            let a = crossing(inside[0], outside[0]), b = crossing(inside[0], outside[1])
                            let c = crossing(inside[1], outside[0]), d = crossing(inside[1], outside[1])
                            triangle(a, b, c, toward: outward)
                            triangle(b, d, c, toward: outward)
                        case 3:
                            triangle(crossing(inside[0], firstOutside), crossing(inside[1], firstOutside),
                                     crossing(inside[2], firstOutside), toward: outward)
                        default: break
                        }
                    }
                }
            }
        }
        return (vertices, triangles)
    }
}
