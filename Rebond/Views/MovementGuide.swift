import SwiftUI
import Vision

/// Simple outline of a person doing the exercise in a loop. The patient steps inside it to be well framed:
/// it turns yellow when they are close, then green and still once their body lines up with it.
struct MovementGuide: View {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let exercise: CatalogExercise
    /// The patient's detected body, to check the placement.
    let skeleton: PoseSkeleton?
    let onPlacement: (GuidePlacement) -> Void

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
        GeometryReader { geometry in
            let size = geometry.size
            let box = box(in: size)
            let placement = placement(in: size, box: box)

            TimelineView(.animation(paused: reduceMotion || placement == .aligned)) { timeline in
                Canvas { context, _ in
                    let progress = placement == .aligned || reduceMotion ? 0 : Self.progress(at: timeline.date)
                    let figure = Self.outline(exercise.guideRest, exercise.guideTarget, progress: progress, in: box)
                    let color: Color = switch placement {
                    case .aligned: .green
                    case .almost: .yellow
                    default: .white
                    }
                    // A dark edge under the line keeps it visible on a bright room.
                    context.stroke(figure, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 11, lineJoin: .round))
                    context.stroke(figure, with: .color(color), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
                }
            }
            .onChange(of: placement, initial: true) { onPlacement(placement) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the figure sits: the size of a person standing about 3 m away (at 2 to 3 m, shoulders to
    /// ankles fill about 56% of the screen height on real videos). Once the feet are seen, the figure stands
    /// on them: their height on screen depends on how the phone is set, not on where the patient stands.
    private func box(in size: CGSize) -> CGRect {
        let height = size.height * 0.6
        let width = height * 0.65
        var top = size.height * 0.28
        if let feet = bodyPoint(.leftAnkle, .rightAnkle, in: size),
           let guideFeet = exercise.guideRest[.leftAnkle]?.y {
            top = min(max(feet.y - guideFeet * height, size.height * 0.05), size.height * 0.3)
        }
        return CGRect(x: (size.width - width) / 2, y: top, width: width, height: height)
    }

    /// Middle of two joints of the patient on screen, or the visible one (seen from the side, one is hidden).
    private func bodyPoint(_ a: Joint, _ b: Joint, in size: CGSize) -> CGPoint? {
        guard let skeleton else { return nil }
        let points = [skeleton.points[a], skeleton.points[b]].compactMap { $0 }
        guard !points.isEmpty else { return nil }
        let middle = CGPoint(x: points.map(\.x).reduce(0, +) / Double(points.count), y: points.map(\.y).reduce(0, +) / Double(points.count))
        return skeleton.place(middle, in: size)
    }

    /// 0 standing, 1 at the bottom, with a pause at each end.
    private static func progress(at date: Date) -> Double {
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: cycle) / cycle
        let wave = (1 - cos(phase * 2 * .pi)) / 2
        let held = min(1, max(0, (wave - 0.15) / 0.7))
        return held * held * (3 - 2 * held)
    }

    /// A simple pictogram: round head, a torso as wide as the legs, limbs of even thickness, in one contour.
    private static func outline(_ rest: GuidePose, _ target: GuidePose, progress: Double, in box: CGRect) -> Path {
        func pose(_ joint: Joint) -> CGPoint? {
            guard let a = rest[joint], let b = target[joint] else { return nil }
            return CGPoint(x: a.x + (b.x - a.x) * progress, y: a.y + (b.y - a.y) * progress)
        }
        // The torso is as wide as the legs: each arm moves in by the gap between its shoulder and hip.
        func inward(_ shoulder: Joint, _ hip: Joint) -> Double {
            guard let shoulder = pose(shoulder), let hip = pose(hip) else { return 0 }
            return hip.x - shoulder.x
        }
        let leftShift = inward(.leftShoulder, .leftHip), rightShift = inward(.rightShoulder, .rightHip)
        let leftArm: Set<Joint> = [.leftShoulder, .leftElbow, .leftWrist]
        let rightArm: Set<Joint> = [.rightShoulder, .rightElbow, .rightWrist]
        func point(_ joint: Joint) -> CGPoint? {
            guard var p = pose(joint) else { return nil }
            if leftArm.contains(joint) { p.x += leftShift }
            if rightArm.contains(joint) { p.x += rightShift }
            return CGPoint(x: box.minX + p.x * box.width, y: box.minY + p.y * box.height)
        }
        let thickness = box.height * 0.08

        // Arms a little thinner than legs.
        var arms = Path(), legs = Path()
        for (a, b) in limbs {
            guard var pointA = point(a), let pointB = point(b) else { continue }
            // Arms come out of the side of the torso, a little below its top: no shoulder bump.
            if a == .leftShoulder || a == .rightShoulder {
                pointA.y += box.height * 0.06
            }
            let isArm = leftArm.contains(a) || rightArm.contains(a)
            if isArm {
                arms.move(to: pointA)
                arms.addLine(to: pointB)
            } else {
                legs.move(to: pointA)
                legs.addLine(to: pointB)
            }
        }
        var outline = legs.strokedPath(StrokeStyle(lineWidth: thickness, lineCap: .round, lineJoin: .round))
            .union(arms.strokedPath(StrokeStyle(lineWidth: thickness * 0.8, lineCap: .round, lineJoin: .round)))

        if let leftShoulder = point(.leftShoulder), let rightShoulder = point(.rightShoulder),
           let leftHip = point(.leftHip), let rightHip = point(.rightHip) {
            // Sloped shoulders: the top narrows toward the neck, the sides meet the arms smoothly.
            let inset = (rightShoulder.x - leftShoulder.x) * 0.2
            let slope = box.height * 0.06
            var torso = Path()
            torso.addLines([
                CGPoint(x: leftShoulder.x + inset, y: leftShoulder.y),
                CGPoint(x: rightShoulder.x - inset, y: rightShoulder.y),
                CGPoint(x: rightShoulder.x, y: rightShoulder.y + slope),
                rightHip, leftHip,
                CGPoint(x: leftShoulder.x, y: leftShoulder.y + slope),
            ])
            torso.closeSubpath()
            outline = outline.union(torso.strokedPath(StrokeStyle(lineWidth: thickness, lineJoin: .round)).union(torso))
        }
        if let head = point(.nose) {
            let radius = box.height * 0.06
            outline = outline.union(Path(ellipseIn: CGRect(x: head.x - radius, y: head.y - radius, width: radius * 2, height: radius * 2)))
        }
        return outline
    }

    private func placement(in size: CGSize, box: CGRect) -> GuidePlacement {
        func onScreen(_ point: CGPoint) -> CGPoint {
            CGPoint(x: point.x / size.width, y: point.y / size.height)
        }
        func inGuide(_ a: Joint, _ b: Joint) -> CGPoint? {
            guard let pointA = exercise.guideRest[a], let pointB = exercise.guideRest[b] else { return nil }
            let middle = CGPoint(x: (pointA.x + pointB.x) / 2, y: (pointA.y + pointB.y) / 2)
            return onScreen(CGPoint(x: box.minX + middle.x * box.width, y: box.minY + middle.y * box.height))
        }
        func inBody(_ a: Joint, _ b: Joint) -> CGPoint? {
            bodyPoint(a, b, in: size).map(onScreen)
        }

        guard let guideShoulders = inGuide(.leftShoulder, .rightShoulder), let guideHips = inGuide(.leftHip, .rightHip)
        else { return .notVisible }
        let guide = GuidePlacement.Body(shoulders: guideShoulders, hips: guideHips, ankles: inGuide(.leftAnkle, .rightAnkle))

        var body: GuidePlacement.Body?
        if let shoulders = inBody(.leftShoulder, .rightShoulder), let hips = inBody(.leftHip, .rightHip) {
            body = GuidePlacement.Body(shoulders: shoulders, hips: hips, ankles: inBody(.leftAnkle, .rightAnkle))
        }
        return GuidePlacement.evaluate(body, guide: guide)
    }
}
