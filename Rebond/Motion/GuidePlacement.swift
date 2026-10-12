import CoreGraphics
import Foundation

/// How the patient stands compared with the guide outline, to tell them where to move.
/// Positions are fractions of the screen, origin top-left, as seen in the mirrored camera.
nonisolated enum GuidePlacement: Equatable, Sendable {
    case notVisible
    case showFeet
    case stepBack
    case stepCloser
    case moveLeft
    case moveRight
    /// Nearly the right distance and side.
    case almost
    case aligned

    struct Body {
        let shoulders: CGPoint
        let hips: CGPoint
        let ankles: CGPoint?
    }

    /// Body height (shoulders to ankles) around the guide's, as a ratio: beyond, step back or closer.
    private static let sizeTolerance = 0.15
    private static let alignedSizeTolerance = 0.08
    /// Sideways distance between the hips and the guide's, in screen widths.
    private static let sideTolerance = 0.08
    private static let alignedSideTolerance = 0.04

    /// Only distance and side are judged: the height on screen depends on how the phone is set,
    /// so the guide follows the patient's feet instead.
    static func evaluate(_ body: Body?, guide: Body) -> GuidePlacement {
        guard let body else { return .notVisible }
        guard let ankles = body.ankles, let guideAnkles = guide.ankles else { return .showFeet }

        let size = (ankles.y - body.shoulders.y) / (guideAnkles.y - guide.shoulders.y)
        if size > 1 + sizeTolerance { return .stepBack }
        if size < 1 - sizeTolerance { return .stepCloser }

        // The camera is mirrored: moving to your left moves you to the left of the screen.
        let side = body.hips.x - guide.hips.x
        if side > sideTolerance { return .moveLeft }
        if side < -sideTolerance { return .moveRight }

        let lined = abs(size - 1) < alignedSizeTolerance && abs(side) < alignedSideTolerance
        return lined ? .aligned : .almost
    }

    var message: LocalizedStringResource {
        switch self {
        case .notVisible: "Placez-vous dans la silhouette"
        case .showFeet: "Reculez pour que vos pieds soient visibles"
        case .stepBack: "Reculez un peu"
        case .stepCloser: "Approchez-vous un peu"
        case .moveLeft: "Décalez-vous vers la gauche"
        case .moveRight: "Décalez-vous vers la droite"
        case .almost: "Presque, ajustez-vous dans la silhouette"
        case .aligned: "Parfait, restez immobile"
        }
    }
}
