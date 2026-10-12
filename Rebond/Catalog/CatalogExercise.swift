import Foundation
import Vision

/// A known exercise and the rules used to analyze it with the camera.
nonisolated struct CatalogExercise: Identifiable, Sendable {
    let id: String
    let name: LocalizedStringResource
    /// Joints highlighted on the on-screen skeleton.
    let highlightedJoints: Set<VNHumanBodyPoseObservation.JointName>
    /// How far the hips must go down for a complete repetition, in torso lengths
    /// (neck to hips distance, measured standing).
    let targetDepth: Double
    /// Guide outline shown before the set, seen from the front: the resting pose and the target pose.
    /// Points in a unit box, origin top-left, as the patient sees themselves in the mirrored camera.
    let guideRest: GuidePose
    let guideTarget: GuidePose
}

typealias GuidePose = [VNHumanBodyPoseObservation.JointName: CGPoint]

nonisolated extension CatalogExercise {
    static let squat = CatalogExercise(
        id: "squat",
        name: "Squat",
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        targetDepth: 0.85,
        guideRest: [
            .nose: CGPoint(x: 0.5, y: 0.08),
            .neck: CGPoint(x: 0.5, y: 0.18),
            .leftShoulder: CGPoint(x: 0.36, y: 0.2), .rightShoulder: CGPoint(x: 0.64, y: 0.2),
            // Straight arms, held out from the body.
            .leftElbow: CGPoint(x: 0.255, y: 0.38), .rightElbow: CGPoint(x: 0.745, y: 0.38),
            .leftWrist: CGPoint(x: 0.15, y: 0.5), .rightWrist: CGPoint(x: 0.85, y: 0.5),
            .leftHip: CGPoint(x: 0.42, y: 0.5), .rightHip: CGPoint(x: 0.58, y: 0.5),
            .leftKnee: CGPoint(x: 0.41, y: 0.73), .rightKnee: CGPoint(x: 0.59, y: 0.73),
            .leftAnkle: CGPoint(x: 0.41, y: 0.95), .rightAnkle: CGPoint(x: 0.59, y: 0.95),
        ],
        // Bottom of the squat seen from the front: hips down, knees over the feet.
        guideTarget: [
            .nose: CGPoint(x: 0.5, y: 0.3),
            .neck: CGPoint(x: 0.5, y: 0.4),
            .leftShoulder: CGPoint(x: 0.36, y: 0.42), .rightShoulder: CGPoint(x: 0.64, y: 0.42),
            // Same arms as standing, moved down with the shoulders: they keep their length.
            .leftElbow: CGPoint(x: 0.255, y: 0.6), .rightElbow: CGPoint(x: 0.745, y: 0.6),
            .leftWrist: CGPoint(x: 0.15, y: 0.72), .rightWrist: CGPoint(x: 0.85, y: 0.72),
            .leftHip: CGPoint(x: 0.41, y: 0.69), .rightHip: CGPoint(x: 0.59, y: 0.69),
            .leftKnee: CGPoint(x: 0.34, y: 0.75), .rightKnee: CGPoint(x: 0.66, y: 0.75),
            .leftAnkle: CGPoint(x: 0.39, y: 0.95), .rightAnkle: CGPoint(x: 0.61, y: 0.95),
        ]
    )

    /// Exercises the camera knows how to follow.
    static let all: [CatalogExercise] = [.squat]

    static func find(_ id: String) -> CatalogExercise? {
        all.first { $0.id == id }
    }
}
