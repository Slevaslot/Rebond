import Foundation
import Vision

/// A known exercise and the rules used to analyze it with the camera.
nonisolated struct CatalogExercise: Identifiable, Sendable {
    /// Three joints forming the tracked angle, measured at `vertex`.
    struct Joints: Sendable {
        let first: VNHumanBodyPose3DObservation.JointName
        let vertex: VNHumanBodyPose3DObservation.JointName
        let last: VNHumanBodyPose3DObservation.JointName
    }

    let id: String
    let name: LocalizedStringResource
    /// Measured in 3D, so the angle is right whether the patient faces the camera or stands sideways.
    /// One entry per side of the body.
    let joints: [Joints]
    /// Joints highlighted on the on-screen skeleton.
    let highlightedJoints: Set<VNHumanBodyPoseObservation.JointName>
    /// Angle to reach for a complete repetition, in degrees.
    /// The resting angle is measured on the patient before the first repetition.
    let targetAngle: Double
}

extension CatalogExercise {
    static let squat = CatalogExercise(
        id: "squat",
        name: "Squat",
        joints: [
            Joints(first: .leftHip, vertex: .leftKnee, last: .leftAnkle),
            Joints(first: .rightHip, vertex: .rightKnee, last: .rightAnkle),
        ],
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        targetAngle: 110
    )
}
