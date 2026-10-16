import SwiftUI
import Vision

/// Draws the detected body over the camera preview. The joints the exercise follows are drawn thick, in the color
/// of the amplitude reached (yellow on the way, then the "Bien", "Très bien", "Parfait" colors); each time the
/// movement reaches a higher tier they swell for a moment, so reaching the target is seen from 2–3 m, not only
/// by a change of color. A dark edge keeps every line readable over a bright room.
struct SkeletonOverlay: View {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let skeleton: PoseSkeleton
    let highlightedJoints: Set<Joint>
    let highlightColor: Color
    /// Body part at fault, drawn in red above everything else.
    var faultyJoints: Set<Joint> = []

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Counts the tiers reached, to make the followed joints swell each time.
    @State private var tierReached = 0
    @State private var tier = 0

    private static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    private enum Layer: Int, CaseIterable { case plain, highlighted, faulty }

    var body: some View {
        KeyframeAnimator(initialValue: 1.0, trigger: tierReached) { swell in
            Canvas { context, size in
                draw(in: &context, size: size, swell: swell)
            }
        } keyframes: { _ in
            SpringKeyframe(reduceMotion ? 1 : 1.7, duration: 0.18)
            SpringKeyframe(1, duration: 0.45)
        }
        .onChange(of: highlightColor, initial: true) {
            let reached = Self.tier(of: highlightColor)
            if reached > tier { tierReached += 1 }
            tier = reached
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// 0 on the way, then 1 "Bien", 2 "Très bien", 3 "Parfait".
    private static func tier(of color: Color) -> Int {
        let tiers: [AmplitudeTier] = [.good, .veryGood, .perfect]
        return (tiers.firstIndex { $0.color == color } ?? -1) + 1
    }

    private func layer(_ joints: Joint...) -> Layer {
        if joints.allSatisfy(faultyJoints.contains) { return .faulty }
        if joints.allSatisfy(highlightedJoints.contains) { return .highlighted }
        return .plain
    }

    private func draw(in context: inout GraphicsContext, size: CGSize, swell: Double) {
        func place(_ point: CGPoint) -> CGPoint {
            skeleton.place(point, in: size)
        }
        func color(_ layer: Layer) -> Color {
            switch layer {
            case .plain: .white.opacity(0.6)
            case .highlighted: highlightColor
            case .faulty: .red
            }
        }
        func width(_ layer: Layer) -> CGFloat {
            switch layer {
            case .plain: 3
            case .highlighted: 8 * swell
            case .faulty: 8
            }
        }
        let joints = skeleton.points.filter { joint, _ in Self.bones.contains { $0.0 == joint || $0.1 == joint } }

        // Plain first, then the followed joints, then the fault on top, each over its dark edge.
        for drawn in Layer.allCases {
            var lines = Path()
            for (a, b) in Self.bones where layer(a, b) == drawn {
                guard let pointA = skeleton.points[a], let pointB = skeleton.points[b] else { continue }
                lines.move(to: place(pointA))
                lines.addLine(to: place(pointB))
            }
            var dots = Path()
            let radius = drawn == .plain ? 5 : width(drawn)
            for (joint, point) in joints where layer(joint) == drawn {
                let center = place(point)
                dots.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            }
            let edge = Color.black.opacity(0.35)
            context.stroke(lines, with: .color(edge), style: StrokeStyle(lineWidth: width(drawn) + 4, lineCap: .round))
            context.stroke(dots, with: .color(edge), lineWidth: 4)
            context.stroke(lines, with: .color(color(drawn)), style: StrokeStyle(lineWidth: width(drawn), lineCap: .round))
            context.fill(dots, with: .color(drawn == .plain ? .white : color(drawn)))
        }
    }
}

extension Correction {
    /// The body part each correction is about, to show it on the skeleton.
    var bodyJoints: Set<VNHumanBodyPoseObservation.JointName> {
        switch self {
        case .keepBackStraight: [.neck, .root, .leftShoulder, .rightShoulder, .leftHip, .rightHip]
        case .goLower: [.root, .leftHip, .rightHip, .leftKnee, .rightKnee]
        case .bendBothKnees: [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case .keepFeetInPlace: [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case .showBothLegs: [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case .kneesOverFeet: [.leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case .raiseHigher, .raiseBothArms: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
        case .keepArmsStraight, .keepArmStraight: [.leftElbow, .rightElbow, .leftWrist, .rightWrist]
        case .turnForearmFurther: [.leftElbow, .rightElbow, .leftWrist, .rightWrist]
        case .keepElbowUp: [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow]
        case .standUpFully: [.root, .leftHip, .rightHip, .leftKnee, .rightKnee]
        case .lungeFurther, .bendFrontKnee: [.root, .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case .useBothLegs: [.neck, .root, .leftHip, .rightHip, .leftKnee, .rightKnee]
        case .raiseLegHigher, .keepLegStraight, .keepStandingLegStraight, .raiseKneeHigher: [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle]
        case .slowDown, .followReference, .useOtherSide, .holdPosition: []
        case .matchLeftArm: [.leftShoulder, .leftElbow, .leftWrist]
        case .matchRightArm: [.rightShoulder, .rightElbow, .rightWrist]
        case .matchLeftLeg: [.leftHip, .leftKnee, .leftAnkle]
        case .matchRightLeg: [.rightHip, .rightKnee, .rightAnkle]
        case .matchTrunk: [.neck, .root, .leftShoulder, .rightShoulder, .leftHip, .rightHip]
        }
    }
}

nonisolated extension PoseSkeleton {
    /// Position on screen of a normalized point, with the same "aspect fill" placement as the camera image.
    func place(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let scale = max(size.width / imageSize.width, size.height / imageSize.height)
        let shown = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let origin = CGPoint(x: (size.width - shown.width) / 2, y: (size.height - shown.height) / 2)
        return CGPoint(x: origin.x + point.x * shown.width, y: origin.y + point.y * shown.height)
    }
}
