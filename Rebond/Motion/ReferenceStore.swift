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

        // 15 images per second, as during the session. Everyone seen is followed from one image to the next:
        // the physiotherapist is often in the picture with the patient.
        let analyzer = PoseAnalyzer(orientation: mirrored ? .upMirrored : .up)
        var people: [PersonTrack] = []
        let generator = imageGenerator(for: asset, maximumSide: 1280)
        let times = stride(from: 0.0, to: duration, by: 1.0 / 15).map { CMTime(seconds: $0, preferredTimescale: 600) }
        var frames: [(time: Double, people: [PoseFrame], size: CGSize)] = []
        for await result in generator.images(for: times) {
            guard let image = try? result.image else { continue }
            frames.append((result.requestedTime.seconds, analyzer.analyzeEveryone(image),
                           CGSize(width: image.width, height: image.height)))
        }
        frames.sort { $0.time < $1.time }
        for frame in frames {
            PersonTrack.follow(frame.people, at: frame.time, imageSize: frame.size, in: &people)
        }
        // The patient is the one doing the movement.
        guard let patient = people.max(by: { ReferenceAnalyzer.motion(of: $0.samples) < ReferenceAnalyzer.motion(of: $1.samples) })
        else { throw ReferenceError.noBody }
        let analysis = try ReferenceAnalyzer.analyze(patient.samples)

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
        let peakIndex = min(peakFrame, max(index - 1, 0))
        let movementName = name.isEmpty ? suggestedName(for: analysis) : name
        let symbol = await MovementSymbolPicker.pick(peakImage: loadImage(frameURL(id, peakIndex)),
                                                     movingJoints: analysis.highlightedJoints, name: movementName)

        try? FileManager.default.removeItem(at: videoURL(id))
        try FileManager.default.copyItem(at: video, to: videoURL(id))

        let movement = ReferenceMovement(
            id: id, name: movementName,
            createdAt: .now,
            axis: analysis.axis, target: analysis.target, template: analysis.template,
            minDuration: analysis.minDuration, repCount: analysis.repCount,
            highlightedJoints: analysis.highlightedJoints,
            recognizedID: analysis.recognizedID,
            symbol: symbol.systemName,
            rest: analysis.rest,
            restPose: analysis.restPose,
            targetPose: analysis.targetPose,
            frameCount: index, peakFrame: peakIndex
        )
        try save(movement)
        return movement
    }

    /// The catalog exercise's name when it was recognized ("Squat"), otherwise from what moves ("Jambes").
    private static func suggestedName(for analysis: ReferenceAnalysis) -> String {
        if let recognized = analysis.recognizedID.flatMap(CatalogExercise.find) {
            return String(localized: recognized.name)
        }
        return ReferenceAnalyzer.suggestedName(moving: analysis.highlightedJoints)
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

    private static func loadImage(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
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
            // Movements learned before Apple Intelligence chose a symbol: the rule from what moves.
            symbol: symbol ?? recognizedID.flatMap(CatalogExercise.find)?.symbol
                ?? MovementSymbolPicker.rule(movingJoints: highlightedJoints).systemName,
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

/// One person followed through a video, by where their body is from one image to the next.
nonisolated struct PersonTrack {
    private(set) var samples: [ReferenceSample] = []
    private var center: CGPoint
    private var lastTime: Double

    /// Gives each body of the image to the person it continues, or starts a new person.
    static func follow(_ bodies: [PoseFrame], at time: Double, imageSize: CGSize, in tracks: inout [PersonTrack]) {
        var taken = Set<Int>()
        for body in bodies {
            guard let skeleton = body.skeleton, !skeleton.points.isEmpty else { continue }
            let points = skeleton.points.values
            let center = CGPoint(x: points.map(\.x).reduce(0, +) / Double(points.count),
                                 y: points.map(\.y).reduce(0, +) / Double(points.count))
            let sample = ReferenceSample(time: time, measure: body.measure, points: skeleton.points, imageSize: imageSize)
            let nearest = tracks.indices
                .filter { !taken.contains($0) && time - tracks[$0].lastTime < 1 }
                .min { hypot(tracks[$0].center.x - center.x, tracks[$0].center.y - center.y)
                    < hypot(tracks[$1].center.x - center.x, tracks[$1].center.y - center.y) }
            if let nearest, hypot(tracks[nearest].center.x - center.x, tracks[nearest].center.y - center.y) < 0.2 {
                tracks[nearest].samples.append(sample)
                tracks[nearest].center = center
                tracks[nearest].lastTime = time
                taken.insert(nearest)
            } else {
                tracks.append(PersonTrack(samples: [sample], center: center, lastTime: time))
                taken.insert(tracks.count - 1)
            }
        }
    }
}
