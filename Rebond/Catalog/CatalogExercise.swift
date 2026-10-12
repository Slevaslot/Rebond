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
}

nonisolated extension CatalogExercise {
    static let squat = CatalogExercise(
        id: "squat",
        name: "Squat",
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        targetDepth: 0.85
    )

    /// Exercises the camera knows how to follow.
    static let all: [CatalogExercise] = [.squat]

    static func find(_ id: String) -> CatalogExercise? {
        all.first { $0.id == id }
    }
}
