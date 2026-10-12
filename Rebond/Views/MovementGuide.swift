import SwiftUI
import Vision

/// Hollow outline of a person doing the exercise in a loop. The patient steps inside it to be well framed;
/// it turns green and stops once their body lines up with it.
struct MovementGuide: View {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let exercise: CatalogExercise
    /// The patient's detected body, to check the alignment.
    let skeleton: PoseSkeleton?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let limbs: [(Joint, Joint)] = [
        (.neck, .nose),
        (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist),
        (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]
    /// Seconds for one full movement, down and back up.
    private static let cycle = 4.0

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { timeline in
            Canvas { context, size in
                let box = Self.box(in: size)
                let aligned = isAligned(in: size, box: box)
                let progress = aligned || reduceMotion ? 0 : Self.progress(at: timeline.date)
                let outline = Self.silhouette(exercise.guideRest, exercise.guideTarget, progress: progress, in: box)
                let color: Color = aligned ? .green : .white
                context.fill(outline, with: .color(color.opacity(0.12)))
                context.stroke(outline, with: .color(color.opacity(0.9)), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the outline sits: about the size of a person standing 2 to 3 m away.
    private static func box(in size: CGSize) -> CGRect {
        let height = size.height * 0.62
        let width = height * 0.5
        return CGRect(x: (size.width - width) / 2, y: size.height * 0.88 - height, width: width, height: height)
    }

    /// 0 standing, 1 at the bottom, with a pause at each end.
    private static func progress(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        let wave = (1 - cos(phase * 2 * .pi)) / 2
        let held = min(1, max(0, (wave - 0.15) / 0.7))
        return held * held * (3 - 2 * held)
    }

    private static func silhouette(_ rest: GuidePose, _ target: GuidePose, progress: Double, in box: CGRect) -> Path {
        func point(_ joint: Joint) -> CGPoint? {
            guard let a = rest[joint], let b = target[joint] else { return nil }
            return CGPoint(
                x: box.minX + (a.x + (b.x - a.x) * progress) * box.width,
                y: box.minY + (a.y + (b.y - a.y) * progress) * box.height
            )
        }

        var limbs = Path()
        for (a, b) in Self.limbs {
            guard let pointA = point(a), let pointB = point(b) else { continue }
            limbs.move(to: pointA)
            limbs.addLine(to: pointB)
        }
        var outline = limbs.strokedPath(StrokeStyle(lineWidth: box.height * 0.055, lineCap: .round, lineJoin: .round))

        if let leftShoulder = point(.leftShoulder), let rightShoulder = point(.rightShoulder),
           let leftHip = point(.leftHip), let rightHip = point(.rightHip) {
            var torso = Path()
            torso.addLines([leftShoulder, rightShoulder, rightHip, leftHip])
            torso.closeSubpath()
            outline = outline.union(torso.strokedPath(StrokeStyle(lineWidth: box.height * 0.03, lineJoin: .round)).union(torso))
        }
        if let head = point(.nose) {
            let radius = box.height * 0.055
            outline = outline.union(Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)))
        }
        return outline
    }

    /// The patient's shoulders, hips and feet close to the outline's, standing.
    private func isAligned(in size: CGSize, box: CGRect) -> Bool {
        guard let skeleton else { return false }
        func middle(_ a: CGPoint?, _ b: CGPoint?) -> CGPoint? {
            guard let a, let b else { return nil }
            return CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
        }
        func guide(_ a: Joint, _ b: Joint) -> CGPoint? {
            middle(exercise.guideRest[a], exercise.guideRest[b]).map {
                CGPoint(x: box.minX + $0.x * box.width, y: box.minY + $0.y * box.height)
            }
        }
        func body(_ a: Joint, _ b: Joint) -> CGPoint? {
            middle(skeleton.points[a], skeleton.points[b]).map { skeleton.place($0, in: size) }
        }
        let pairs: [(Joint, Joint)] = [(.leftShoulder, .rightShoulder), (.leftHip, .rightHip), (.leftAnkle, .rightAnkle)]
        for (a, b) in pairs {
            guard let expected = guide(a, b), let actual = body(a, b),
                  hypot(expected.x - actual.x, expected.y - actual.y) < box.height * 0.08
            else { return false }
        }
        return true
    }
}
