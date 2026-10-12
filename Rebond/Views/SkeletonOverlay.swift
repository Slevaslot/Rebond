import SwiftUI
import Vision

/// Draws the detected body over the camera preview.
struct SkeletonOverlay: View {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let skeleton: PoseSkeleton
    let highlightedJoints: Set<Joint>
    let highlightColor: Color

    private static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftShoulder, .leftHip), (.rightShoulder, .rightHip),
        (.leftHip, .rightHip),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            // Same "aspect fill" placement as the camera preview.
            let scale = max(size.width / skeleton.imageSize.width, size.height / skeleton.imageSize.height)
            let shown = CGSize(width: skeleton.imageSize.width * scale, height: skeleton.imageSize.height * scale)
            let origin = CGPoint(x: (size.width - shown.width) / 2, y: (size.height - shown.height) / 2)
            func place(_ point: CGPoint) -> CGPoint {
                CGPoint(x: origin.x + point.x * shown.width, y: origin.y + point.y * shown.height)
            }

            for (a, b) in Self.bones {
                guard let pointA = skeleton.points[a], let pointB = skeleton.points[b] else { continue }
                var path = Path()
                path.move(to: place(pointA))
                path.addLine(to: place(pointB))
                let isHighlighted = highlightedJoints.contains(a) && highlightedJoints.contains(b)
                context.stroke(
                    path,
                    with: .color(isHighlighted ? highlightColor : .white.opacity(0.6)),
                    style: StrokeStyle(lineWidth: isHighlighted ? 7 : 3, lineCap: .round)
                )
            }

            for (joint, point) in skeleton.points where Self.bones.contains(where: { $0.0 == joint || $0.1 == joint }) {
                let isHighlighted = highlightedJoints.contains(joint)
                let radius: CGFloat = isHighlighted ? 8 : 5
                let center = place(point)
                let dot = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                context.fill(dot, with: .color(isHighlighted ? highlightColor : .white))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
