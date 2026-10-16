import CoreGraphics
import Foundation
import Vision

/// The joints Vision saw on each analyzed frame of a video, compact enough to keep as a test fixture: a filmed
/// movement or a session replays through the real code without a camera (Vision doesn't run in the simulator).
nonisolated struct PoseRecording: Codable, Sendable {
    struct Frame: Codable, Sendable {
        /// Seconds from the start of the video.
        let t: Double
        /// Raw joint name → [x, y], normalized, origin top-left (as `PoseSkeleton`).
        let p: [String: [Double]]
    }

    /// Width and height of the analyzed images.
    let size: [Double]
    let frames: [Frame]

    init(size: CGSize, frames: [Frame]) {
        self.size = [size.width, size.height]
        self.frames = frames
    }

    init(samples: [ReferenceSample]) {
        let size = samples.first?.imageSize ?? CGSize(width: 9, height: 16)
        self.init(size: size, frames: samples.map { sample in
            Frame(t: (sample.time * 1000).rounded() / 1000, p: Dictionary(uniqueKeysWithValues: sample.points.map {
                ($0.key.rawValue.rawValue, [($0.value.x * 10_000).rounded() / 10_000, ($0.value.y * 10_000).rounded() / 10_000])
            }))
        })
    }

    var imageSize: CGSize { CGSize(width: size[0], height: size[1]) }

    /// Each frame as the analysis of a video sees it.
    var samples: [ReferenceSample] {
        frames.map { frame in
            let points = Dictionary(uniqueKeysWithValues: frame.p.compactMap { name, xy -> (VNHumanBodyPoseObservation.JointName, CGPoint)? in
                guard xy.count == 2 else { return nil }
                return (VNHumanBodyPoseObservation.JointName(rawValue: VNRecognizedPointKey(rawValue: name)), CGPoint(x: xy[0], y: xy[1]))
            })
            return ReferenceSample(time: frame.t, measure: PoseAnalyzer.measure(from: points, imageSize: imageSize),
                                   points: points, imageSize: imageSize)
        }
    }
}
