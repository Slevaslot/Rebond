import AVFoundation
import CoreGraphics
import ImageIO
import Synchronization
import UniformTypeIdentifiers
import Vision

/// The filmed movements, on the device only: each in its own folder, with its video, the images of its clearest
/// repetition and what Rebond learned from it. Nothing leaves the iPhone.
nonisolated enum ReferenceStore {
    /// A program's exercise refers to a filmed movement by this prefix and the movement's identifier.
    static let catalogPrefix = "ref:"

    static var directory: URL { URL.applicationSupportDirectory.appending(path: "References", directoryHint: .isDirectory) }

    static func folder(_ id: UUID) -> URL { directory.appending(path: id.uuidString, directoryHint: .isDirectory) }
    static func videoURL(_ id: UUID) -> URL { folder(id).appending(path: "video.mov") }
    static func frameURL(_ id: UUID, _ index: Int) -> URL { folder(id).appending(path: String(format: "frame-%03d.jpg", index)) }
    private static func movementURL(_ id: UUID) -> URL { folder(id).appending(path: "movement.json") }

    private static let cache = Mutex<[UUID: ReferenceMovement]>([:])

    static func id(fromCatalogID catalogID: String) -> UUID? {
        guard catalogID.hasPrefix(catalogPrefix) else { return nil }
        return UUID(uuidString: String(catalogID.dropFirst(catalogPrefix.count)))
    }

    static func load(_ id: UUID) -> ReferenceMovement? {
        if let cached = cache.withLock({ $0[id] }) { return cached }
        guard let data = try? Data(contentsOf: movementURL(id)),
              let movement = try? JSONDecoder().decode(ReferenceMovement.self, from: data)
        else { return nil }
        cache.withLock { $0[id] = movement }
        return movement
    }

    static func save(_ movement: ReferenceMovement) throws {
        try FileManager.default.createDirectory(at: folder(movement.id), withIntermediateDirectories: true)
        try JSONEncoder().encode(movement).write(to: movementURL(movement.id))
        cache.withLock { $0[movement.id] = movement }
    }

    /// Every filmed movement, the latest first.
    static func all() -> [ReferenceMovement] {
        let folders = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return folders.compactMap { UUID(uuidString: $0.lastPathComponent).flatMap(load) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func rename(_ id: UUID, to name: String) {
        guard var movement = load(id) else { return }
        movement.name = name
        try? save(movement)
    }

    static func delete(_ id: UUID) {
        try? FileManager.default.removeItem(at: folder(id))
        cache.withLock { $0[id] = nil }
    }

    // MARK: Learning from a video

    /// Analyzes a filmed movement and keeps it, with its video.
    /// - Parameter mirrored: The video wasn't filmed like a mirror (imported from Photos): it is turned over,
    ///   to look like the camera of the session.
    static func learn(from video: URL, name: String, mirrored: Bool) async throws -> ReferenceMovement {
        let id = UUID()
        let asset = AVURLAsset(url: video)
        let duration = min(try await asset.load(.duration).seconds, 90)

        // 15 images per second, as during the session.
        let analyzer = PoseAnalyzer(orientation: mirrored ? .upMirrored : .up)
        var samples: [ReferenceSample] = []
        let generator = imageGenerator(for: asset, maximumSide: 1280)
        let times = stride(from: 0.0, to: duration, by: 1.0 / 15).map { CMTime(seconds: $0, preferredTimescale: 600) }
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            let frame = analyzer.analyze(image)
            samples.append(ReferenceSample(
                time: result.requestedTime.seconds,
                measure: frame.measure,
                points: frame.skeleton?.points ?? [:],
                imageSize: frame.skeleton?.imageSize ?? CGSize(width: image.width, height: image.height)
            ))
        }
        samples.sort { $0.time < $1.time }
        let analysis = try ReferenceAnalyzer.analyze(samples)

        try FileManager.default.createDirectory(at: folder(id), withIntermediateDirectories: true)
        // The images of the clearest repetition, shown during the session as the patient moves.
        let frameTimes = stride(from: analysis.bestStart, through: analysis.bestEnd, by: 1.0 / 15).map { $0 }
        let small = imageGenerator(for: asset, maximumSide: 640)
        var index = 0
        for await result in small.images(for: frameTimes.map { CMTime(seconds: $0, preferredTimescale: 600) }) {
            guard let image = try? result.image else { continue }
            writeJPEG(mirrored ? flipped(image) : image, to: frameURL(id, index))
            index += 1
        }
        let peakFrame = frameTimes.firstIndex { $0 >= analysis.bestPeak } ?? frameTimes.count / 2

        try? FileManager.default.removeItem(at: videoURL(id))
        try FileManager.default.copyItem(at: video, to: videoURL(id))

        let movement = ReferenceMovement(
            id: id, name: name, createdAt: .now,
            axis: analysis.axis, target: analysis.target, template: analysis.template,
            minDuration: analysis.minDuration, repCount: analysis.repCount,
            highlightedJoints: analysis.highlightedJoints,
            restPose: analysis.restPose,
            targetPose: analysis.targetPose,
            frameCount: index, peakFrame: min(peakFrame, max(index - 1, 0))
        )
        try save(movement)
        return movement
    }

    private static func imageGenerator(for asset: AVAsset, maximumSide: Double) -> AVAssetImageGenerator {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maximumSide, height: maximumSide)
        let tolerance = CMTime(seconds: 1.0 / 30, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance
        return generator
    }

    private static func flipped(_ image: CGImage) -> CGImage {
        guard let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return image }
        context.translateBy(x: CGFloat(image.width), y: 0)
        context.scaleBy(x: -1, y: 1)
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage() ?? image
    }

    private static func writeJPEG(_ image: CGImage, to url: URL) {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        CGImageDestinationFinalize(destination)
    }
}

nonisolated extension ReferenceMovement {
    /// The filmed movement as an exercise of the catalog: the session, the counter and the guide use it like
    /// any other.
    var catalogExercise: CatalogExercise {
        func pose(_ points: [String: CGPoint]) -> GuidePose {
            Dictionary(uniqueKeysWithValues: points.map {
                (VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: $0.key)), $0.value)
            })
        }
        return CatalogExercise(
            id: catalogID,
            name: LocalizedStringResource(stringLiteral: name),
            symbol: Self.symbol,
            analysis: .recorded(self),
            highlightedJoints: Set(highlightedJoints.map { VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: $0)) }),
            returnCue: "Revenez doucement",
            amplitudeMeaning: "Ressemblance avec le mouvement filmé chez votre kiné",
            guideRest: pose(restPose),
            guideTarget: pose(targetPose),
            armStyle: .straight
        )
    }
}
