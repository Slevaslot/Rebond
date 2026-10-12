import Foundation
import Vision

/// A known exercise and the rules used to analyze it with the camera.
nonisolated struct CatalogExercise: Identifiable, Sendable {
    /// Three joints forming the tracked angle, measured at `vertex`.
    struct Joints: Sendable {
        let first: VNHumanBodyPoseObservation.JointName
        let vertex: VNHumanBodyPoseObservation.JointName
        let last: VNHumanBodyPoseObservation.JointName
    }

    let id: String
    let name: LocalizedStringResource
    /// One entry per side of the body; the most reliable side is used.
    let joints: [Joints]
    /// Angle when standing still (upper threshold), in degrees.
    let restAngle: Double
    /// Angle to reach for a complete repetition (lower threshold), in degrees.
    let targetAngle: Double
    /// Shown when the patient comes back up before reaching `targetAngle`.
    let correction: LocalizedStringResource
}

extension CatalogExercise {
    static let squat = CatalogExercise(
        id: "squat",
        name: "Squat",
        joints: [
            Joints(first: .leftHip, vertex: .leftKnee, last: .leftAnkle),
            Joints(first: .rightHip, vertex: .rightKnee, last: .rightAnkle),
        ],
        restAngle: 160,
        targetAngle: 100,
        correction: "Descendez encore un peu"
    )
}
