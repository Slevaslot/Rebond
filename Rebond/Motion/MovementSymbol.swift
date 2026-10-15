import CoreGraphics
import Foundation
import FoundationModels
import Vision

/// The workout symbols a filmed movement can get, the same `figure.*` symbols as Apple's Fitness app.
@Generable
nonisolated enum MovementSymbol: String, CaseIterable, Sendable {
    /// Knees bending while standing: squat, half squat.
    case squat
    /// A lunge or a step forward or to the side.
    case lunge
    /// Standing up from a chair and sitting back down.
    case sitToStand
    /// Arms raised sideways or forward.
    case armsRaise
    /// A shoulder rotation, the forearm turning.
    case shoulderRotation
    /// One leg raised, knee bent or straight.
    case legRaise
    /// A stretch or a slow mobility movement.
    case stretch
    /// The trunk bending or turning, the legs still.
    case trunk
    /// A position held still, plank or sheathing.
    case hold
    /// Balance on one leg.
    case balance
    /// Arms and legs moving together.
    case fullBody

    var systemName: String {
        switch self {
        case .squat: "figure.cross.training"
        case .lunge: "figure.strengthtraining.functional"
        case .sitToStand: "chair.fill"
        case .armsRaise: "figure.arms.open"
        case .shoulderRotation: "figure.taichi"
        case .legRaise: "figure.kickboxing"
        case .stretch: "figure.cooldown"
        case .trunk: "figure.flexibility"
        case .hold: "figure.core.training"
        case .balance: "figure.mind.and.body"
        case .fullBody: "figure.mixed.cardio"
        }
    }
}

/// Picks the symbol of a filmed movement: Apple Intelligence looks at the image at the end of the movement
/// and at what moves; without it, a rule from the moving joints. On the device only.
nonisolated enum MovementSymbolPicker {
    static func pick(peakImage: CGImage?, movingJoints: [String], name: String) async -> MovementSymbol {
        let fallback = rule(movingJoints: movingJoints)
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return fallback }
        let session = LanguageModelSession(instructions: """
            Tu choisis l'icône d'un exercice de rééducation filmé chez le kinésithérapeute. \
            squat : flexion des genoux debout ; lunge : fente avant ou latérale ; sitToStand : assis-debout ; \
            armsRaise : élévation des bras ; shoulderRotation : rotation de l'épaule ; legRaise : jambe levée ; \
            stretch : étirement ; trunk : buste qui se penche ou tourne ; hold : position tenue ; \
            balance : équilibre sur une jambe ; fullBody : bras et jambes ensemble.
            """)
        let description = "Exercice « \(name) ». Parties du corps qui bougent : \(bodyParts(movingJoints))."
        do {
            if let peakImage, model.capabilities.contains(.vision) {
                return try await session.respond(generating: MovementSymbol.self) {
                    "\(description) Voici l'image au bout du mouvement."
                    Attachment(peakImage)
                }.content
            }
            return try await session.respond(to: description, generating: MovementSymbol.self).content
        } catch {
            return fallback
        }
    }

    /// From the joints that move: legs, arms, both, or the trunk.
    static func rule(movingJoints: [String]) -> MovementSymbol {
        typealias Joint = VNHumanBodyPoseObservation.JointName
        let names = Set(movingJoints)
        func moves(_ list: [Joint]) -> Bool { list.contains { names.contains($0.rawValue.rawValue) } }
        let arms = moves([.leftElbow, .rightElbow, .leftWrist, .rightWrist])
        let legs = moves([.leftKnee, .rightKnee, .leftAnkle, .rightAnkle])
        switch (arms, legs) {
        case (true, true): return .fullBody
        case (true, false): return .armsRaise
        case (false, true): return .squat
        case (false, false): return .trunk
        }
    }

    private static func bodyParts(_ joints: [String]) -> String {
        switch rule(movingJoints: joints) {
        case .fullBody: "bras et jambes"
        case .armsRaise: "bras"
        case .squat: "jambes"
        default: "buste"
        }
    }
}
