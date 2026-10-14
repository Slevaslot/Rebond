import Foundation
import Vision

/// A known exercise and the rules used to analyze it with the camera.
nonisolated struct CatalogExercise: Identifiable, Sendable {
    /// How the camera measures the movement.
    enum Analysis: Sendable {
        /// Hips going down and back up, in torso lengths measured standing.
        case squat(targetDepth: Double)
        /// Both arms raised sideways, in degrees between the arm and the body.
        case armRaise(targetAngle: Double)
        /// One arm raised, either side (or both), in degrees between the arm and the body.
        case oneArmRaise(targetAngle: Double)
        /// Standing up from a chair, in torso lengths of hips rise above the seat.
        case sitToStand(targetRise: Double)
        /// One leg raised in front, in torso lengths of the knee coming up toward the hip.
        case legRaise(targetLift: Double)
        /// One knee raised, bent, either side: the same lift as the leg raise.
        case kneeRaise(targetLift: Double)
        /// Lunge with one foot in front of the other, in torso lengths of hips drop.
        case forwardLunge(targetDrop: Double)
        /// Lunge to one side, either side, in torso lengths of hips shifting sideways.
        case sideLunge(targetShift: Double)
    }

    /// How the guide pictogram moves its arms.
    enum ArmStyle: Sendable {
        /// Arms straight when standing, hands joined in front of the chest at the bottom (squat).
        case handsToChest
        /// Straight arms following the wrists of the guide poses.
        case straight
    }

    let id: String
    let name: LocalizedStringResource
    /// SF Symbol shown in the program and the history.
    let symbol: String
    let analysis: Analysis
    /// Joints highlighted on the on-screen skeleton.
    let highlightedJoints: Set<VNHumanBodyPoseObservation.JointName>
    /// Spoken when the target is reached, to start the way back.
    let returnCue: LocalizedStringResource
    /// What "amplitude" means for this exercise, for the patient and the report.
    let amplitudeMeaning: LocalizedStringResource
    /// Guide outline shown before the set, seen from the front: the resting pose and the target pose.
    /// Points in a unit box, origin top-left, as the patient sees themselves in the mirrored camera.
    let guideRest: GuidePose
    let guideTarget: GuidePose
    let armStyle: ArmStyle

    func makeCounter() -> any MovementCounter {
        switch analysis {
        case .squat(let targetDepth): RepCounter(targetDepth: targetDepth)
        case .armRaise(let targetAngle): ArmRaiseCounter(targetAngle: targetAngle)
        case .oneArmRaise(let targetAngle): ArmRaiseCounter(targetAngle: targetAngle, arms: .either)
        case .sitToStand(let targetRise): SitToStandCounter(targetRise: targetRise)
        case .legRaise(let targetLift): LegRaiseCounter(targetLift: targetLift)
        case .kneeRaise(let targetLift): LegRaiseCounter(targetLift: targetLift, style: .bentKnee)
        case .forwardLunge(let targetDrop): LungeCounter(direction: .forward, target: targetDrop)
        case .sideLunge(let targetShift): LungeCounter(direction: .side, target: targetShift)
        }
    }
}

typealias GuidePose = [VNHumanBodyPoseObservation.JointName: CGPoint]

nonisolated extension VNHumanBodyPoseObservation.JointName {
    /// In a guide's resting pose: the middle of the seat of the chair the exercise starts from, drawn with the figure.
    /// A guide pose has no other use for the root joint (the torso is drawn from the hips).
    static let guideChairSeat = Self.root
}

nonisolated extension CatalogExercise {
    /// Legs and torso standing, shared by the exercises done standing.
    private static let standingBody: GuidePose = [
        .nose: CGPoint(x: 0.5, y: 0.08),
        .neck: CGPoint(x: 0.5, y: 0.18),
        .leftShoulder: CGPoint(x: 0.36, y: 0.2), .rightShoulder: CGPoint(x: 0.64, y: 0.2),
        .leftHip: CGPoint(x: 0.42, y: 0.5), .rightHip: CGPoint(x: 0.58, y: 0.5),
        .leftKnee: CGPoint(x: 0.41, y: 0.73), .rightKnee: CGPoint(x: 0.59, y: 0.73),
        .leftAnkle: CGPoint(x: 0.41, y: 0.95), .rightAnkle: CGPoint(x: 0.59, y: 0.95),
    ]

    static let squat = CatalogExercise(
        id: "squat",
        name: "Squat",
        symbol: "figure.strengthtraining.functional",
        // Partial squat: Rebond is for rehabilitation, often for older patients (half squats reach 0.6–0.85).
        analysis: .squat(targetDepth: 0.6),
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        returnCue: "Remontez",
        amplitudeMeaning: "Profondeur de la descente, en % de la profondeur visée",
        guideRest: standingBody.merging([
            // Straight arms, held out from the body.
            .leftElbow: CGPoint(x: 0.255, y: 0.38), .rightElbow: CGPoint(x: 0.745, y: 0.38),
            .leftWrist: CGPoint(x: 0.15, y: 0.5), .rightWrist: CGPoint(x: 0.85, y: 0.5),
        ]) { $1 },
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
        ],
        armStyle: .handsToChest
    )

    /// Shoulder rehabilitation: both arms raised sideways to shoulder height, then lowered slowly.
    static let lateralRaise = CatalogExercise(
        id: "lateral-raise",
        name: "Élévation latérale des bras",
        symbol: "figure.arms.open",
        // Shoulder height is 90°: slightly below, as rehabilitation programs usually ask.
        analysis: .armRaise(targetAngle: 80),
        highlightedJoints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist],
        returnCue: "Redescendez doucement",
        amplitudeMeaning: "Hauteur des bras, en % de la hauteur visée",
        guideRest: standingBody.merging([
            .leftWrist: CGPoint(x: 0.3, y: 0.5), .rightWrist: CGPoint(x: 0.7, y: 0.5),
        ]) { $1 },
        guideTarget: standingBody.merging([
            .leftWrist: CGPoint(x: 0.0, y: 0.26), .rightWrist: CGPoint(x: 1.0, y: 0.26),
        ]) { $1 },
        armStyle: .straight
    )

    /// Shoulder rehabilitation: one arm raised sideways a little above shoulder height, either side.
    static let shoulderAbduction = CatalogExercise(
        id: "shoulder-abduction",
        name: "Élévation latérale d'un bras",
        symbol: "figure.arms.open",
        // Above shoulder height but well short of the full 180°: a partial range, as for the squat.
        // UI-PRMD shoulder abductions (one arm, front view): 99% of correct ones counted, 53% of incorrect ones
        // (range too small, torso leaning to the side).
        analysis: .oneArmRaise(targetAngle: 110),
        highlightedJoints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist],
        returnCue: "Redescendez doucement",
        amplitudeMeaning: "Hauteur du bras, en % de la hauteur visée",
        guideRest: standingBody.merging([
            .leftWrist: CGPoint(x: 0.3, y: 0.5), .rightWrist: CGPoint(x: 0.7, y: 0.5),
        ]) { $1 },
        // One arm at 110° from the body, the other one down.
        guideTarget: standingBody.merging([
            .leftWrist: CGPoint(x: 0.02, y: 0.13), .rightWrist: CGPoint(x: 0.7, y: 0.5),
        ]) { $1 },
        armStyle: .straight
    )

    /// Scaption: the arms rise in front of the body, about 30° forward of the side ("in the plane of the shoulder
    /// blade"), thumbs up. Seen from the front it reads as a side raise: the same angle is measured, one arm or both.
    static let scaption = CatalogExercise(
        id: "scaption",
        name: "Élévation des bras en diagonale",
        symbol: "figure.arms.open",
        // Shoulder height, as rehabilitation programs usually ask. UI-PRMD scaptions (one arm, front view):
        // 100% of correct ones counted, 41% of incorrect ones (range too small, torso leaning to the side).
        analysis: .oneArmRaise(targetAngle: 90),
        highlightedJoints: [.leftShoulder, .leftElbow, .leftWrist, .rightShoulder, .rightElbow, .rightWrist],
        returnCue: "Redescendez doucement",
        amplitudeMeaning: "Hauteur des bras, en % de la hauteur visée",
        guideRest: standingBody.merging([
            .leftWrist: CGPoint(x: 0.3, y: 0.5), .rightWrist: CGPoint(x: 0.7, y: 0.5),
        ]) { $1 },
        // Arms in a "Y", a little above the target: the diagonal reads at a glance, unlike level arms
        // that would look like the lateral raise.
        guideTarget: standingBody.merging([
            .leftWrist: CGPoint(x: 0.07, y: 0.08), .rightWrist: CGPoint(x: 0.93, y: 0.08),
        ]) { $1 },
        armStyle: .straight
    )

    /// Standing up from a chair without the hands, then sitting back down slowly. Starts seated.
    static let sitToStand = CatalogExercise(
        id: "sit-to-stand",
        name: "Assis-debout",
        symbol: "figure.stand",
        // Getting up from a chair raises the hips by about 0.8–0.9 torso lengths: 0.6 is standing up,
        // even from a high seat. UI-PRMD sit-to-stands (front view): 100% of correct ones counted,
        // 51% of incorrect ones (torso leaning to one side, chest thrown forward).
        analysis: .sitToStand(targetRise: 0.6),
        highlightedJoints: [.leftShoulder, .rightShoulder, .leftHip, .rightHip, .leftKnee, .rightKnee],
        returnCue: "Rasseyez-vous doucement",
        amplitudeMeaning: "Hauteur à laquelle vous vous levez, en % de la hauteur visée",
        // Seated, seen from the front: thighs pointing at the camera, so the knees are just below the hips;
        // hands resting on the thighs.
        guideRest: [
            .nose: CGPoint(x: 0.5, y: 0.3),
            .neck: CGPoint(x: 0.5, y: 0.4),
            .leftShoulder: CGPoint(x: 0.36, y: 0.42), .rightShoulder: CGPoint(x: 0.64, y: 0.42),
            .leftWrist: CGPoint(x: 0.33, y: 0.72), .rightWrist: CGPoint(x: 0.67, y: 0.72),
            .leftHip: CGPoint(x: 0.42, y: 0.72), .rightHip: CGPoint(x: 0.58, y: 0.72),
            .leftKnee: CGPoint(x: 0.36, y: 0.77), .rightKnee: CGPoint(x: 0.64, y: 0.77),
            .leftAnkle: CGPoint(x: 0.38, y: 0.95), .rightAnkle: CGPoint(x: 0.62, y: 0.95),
            .guideChairSeat: CGPoint(x: 0.5, y: 0.76),
        ],
        // Standing, arms crossed on the chest as the exercise is usually done.
        guideTarget: standingBody.merging([
            .leftWrist: CGPoint(x: 0.33, y: 0.5), .rightWrist: CGPoint(x: 0.67, y: 0.5),
        ]) { $1 },
        armStyle: .handsToChest
    )

    /// Standing on one leg, the other raised in front with the knee straight, either side.
    static let legRaise = CatalogExercise(
        id: "leg-raise",
        name: "Élévation de la jambe tendue",
        symbol: "figure.walk",
        // Seen from hip height, 0.3 is the thigh at about 55°. UI-PRMD straight leg raises (front view, phone at
        // 2–3 m): 100% of correct ones counted, 68% of incorrect ones (standing leg bending, torso leaning).
        analysis: .legRaise(targetLift: 0.3),
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        returnCue: "Reposez la jambe doucement",
        amplitudeMeaning: "Hauteur de la jambe, en % de la hauteur visée",
        guideRest: standingBody.merging([
            .leftWrist: CGPoint(x: 0.28, y: 0.5), .rightWrist: CGPoint(x: 0.72, y: 0.5),
        ]) { $1 },
        // The raised leg comes toward the camera: it looks shorter, the foot off the floor.
        guideTarget: standingBody.merging([
            .leftWrist: CGPoint(x: 0.24, y: 0.47), .rightWrist: CGPoint(x: 0.72, y: 0.5),
            .leftKnee: CGPoint(x: 0.39, y: 0.63), .leftAnkle: CGPoint(x: 0.35, y: 0.77),
        ]) { $1 },
        armStyle: .straight
    )

    /// Hurdle step: one knee raised, bent, as when stepping over an obstacle, then the foot set back down;
    /// one leg then the other. Works the hip and the balance on the standing leg.
    static let hurdleStep = CatalogExercise(
        id: "hurdle-step",
        name: "Montée de genou",
        symbol: "figure.step.training",
        // 0.45 is the thigh at about 60° seen from hip height, short of level: a partial range for older patients.
        // UI-PRMD hurdle steps (front view, phone at 2–3 m): 94% of correct ones counted, 41% of incorrect ones
        // (knee not high enough, standing leg bending, torso leaning).
        analysis: .kneeRaise(targetLift: 0.45),
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        returnCue: "Reposez le pied doucement",
        amplitudeMeaning: "Hauteur du genou, en % de la hauteur visée",
        guideRest: standingBody.merging([
            .leftWrist: CGPoint(x: 0.28, y: 0.5), .rightWrist: CGPoint(x: 0.72, y: 0.5),
        ]) { $1 },
        // The thigh comes toward the camera and the shin hangs: the knee nearly at hip height, the foot under it.
        guideTarget: standingBody.merging([
            .leftWrist: CGPoint(x: 0.24, y: 0.47), .rightWrist: CGPoint(x: 0.72, y: 0.5),
            .leftKnee: CGPoint(x: 0.38, y: 0.56), .leftAnkle: CGPoint(x: 0.4, y: 0.74),
        ]) { $1 },
        armStyle: .straight
    )

    /// Forward lunge, one foot in front of the other: the hips go straight down, the back knee toward the floor,
    /// then back up. Seen from the front, the knees overlap: the hips are followed, as for the squat.
    static let forwardLunge = CatalogExercise(
        id: "forward-lunge",
        name: "Fente avant",
        symbol: "figure.strengthtraining.functional",
        // A shallow lunge: UI-PRMD inline lunges go down 0.43–0.98 torso lengths. At 0.45 (front view, phone at
        // 2–3 m): 97% of correct ones counted, 54% of incorrect ones (torso leaning forward or to the side).
        analysis: .forwardLunge(targetDrop: 0.45),
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        returnCue: "Remontez",
        amplitudeMeaning: "Profondeur de la descente, en % de la profondeur visée",
        guideRest: standingBody.merging([
            .leftWrist: CGPoint(x: 0.3, y: 0.5), .rightWrist: CGPoint(x: 0.7, y: 0.5),
        ]) { $1 },
        // Down, the torso straight: the front knee bends over the foot, the back knee comes down lower.
        guideTarget: [
            .nose: CGPoint(x: 0.5, y: 0.26),
            .neck: CGPoint(x: 0.5, y: 0.36),
            .leftShoulder: CGPoint(x: 0.36, y: 0.38), .rightShoulder: CGPoint(x: 0.64, y: 0.38),
            .leftWrist: CGPoint(x: 0.3, y: 0.68), .rightWrist: CGPoint(x: 0.7, y: 0.68),
            .leftHip: CGPoint(x: 0.42, y: 0.68), .rightHip: CGPoint(x: 0.58, y: 0.68),
            .leftKnee: CGPoint(x: 0.4, y: 0.78), .rightKnee: CGPoint(x: 0.6, y: 0.86),
            .leftAnkle: CGPoint(x: 0.41, y: 0.95), .rightAnkle: CGPoint(x: 0.59, y: 0.95),
        ],
        armStyle: .straight
    )

    /// Side lunge, either side: one leg steps out and bends, the other stays straight; the hips go over the bent
    /// leg, then come back to the middle.
    static let sideLunge = CatalogExercise(
        id: "side-lunge",
        name: "Fente latérale",
        symbol: "figure.strengthtraining.functional",
        // UI-PRMD side lunges shift the hips 0.38–0.77 torso lengths. At 0.4 (front view, phone at 2–3 m):
        // 98% of correct ones counted, 43% of incorrect ones (torso leaning to the side, knee not bent).
        analysis: .sideLunge(targetShift: 0.4),
        highlightedJoints: [.leftHip, .leftKnee, .leftAnkle, .rightHip, .rightKnee, .rightAnkle],
        returnCue: "Revenez au centre",
        amplitudeMeaning: "Écart sur le côté, en % de l'écart visé",
        guideRest: standingBody.merging([
            .leftWrist: CGPoint(x: 0.3, y: 0.5), .rightWrist: CGPoint(x: 0.7, y: 0.5),
            .leftAnkle: CGPoint(x: 0.36, y: 0.95), .rightAnkle: CGPoint(x: 0.64, y: 0.95),
        ]) { $1 },
        // Hips over the bent left leg, the right leg straight and slanted, hands joined in front of the chest.
        guideTarget: [
            .nose: CGPoint(x: 0.4, y: 0.24),
            .neck: CGPoint(x: 0.4, y: 0.34),
            .leftShoulder: CGPoint(x: 0.26, y: 0.36), .rightShoulder: CGPoint(x: 0.54, y: 0.36),
            .leftWrist: CGPoint(x: 0.2, y: 0.62), .rightWrist: CGPoint(x: 0.6, y: 0.62),
            .leftHip: CGPoint(x: 0.32, y: 0.64), .rightHip: CGPoint(x: 0.48, y: 0.64),
            .leftKnee: CGPoint(x: 0.2, y: 0.78), .rightKnee: CGPoint(x: 0.66, y: 0.8),
            .leftAnkle: CGPoint(x: 0.18, y: 0.95), .rightAnkle: CGPoint(x: 0.84, y: 0.95),
        ],
        armStyle: .handsToChest
    )

    /// Exercises the camera knows how to follow.
    static let all: [CatalogExercise] = [
        .squat, .lateralRaise, .shoulderAbduction, .scaption, .sitToStand, .legRaise, .hurdleStep,
        .forwardLunge, .sideLunge,
    ]

    static func find(_ id: String) -> CatalogExercise? {
        all.first { $0.id == id }
    }
}

nonisolated extension CatalogExercise {
    /// Raised arms or leg and standing up fill the amplitude gauge upward; a squat or a forward lunge fills it
    /// downward.
    var fillsGaugeUpward: Bool {
        switch analysis {
        case .squat, .forwardLunge: false
        default: true
        }
    }
}
