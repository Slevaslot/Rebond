import SwiftUI
import Vision

/// Hollow outline of a person doing the exercise in a loop. The patient steps inside it to be well framed:
/// it turns yellow when they are close, then green and still once their body lines up with it.
struct MovementGuide: View {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let exercise: CatalogExercise
    /// The patient's detected body, to check the placement.
    let skeleton: PoseSkeleton?
    let onPlacement: (GuidePlacement) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Limbs and their thickness, in guide heights: thighs thicker than shins, upper arms than forearms.
    private static let limbs: [(Joint, Joint, width: Double)] = [
        (.neck, .nose, 0.04),
        (.leftShoulder, .leftElbow, 0.05), (.leftElbow, .leftWrist, 0.04),
        (.rightShoulder, .rightElbow, 0.05), (.rightElbow, .rightWrist, 0.04),
        (.leftHip, .leftKnee, 0.075), (.leftKnee, .leftAnkle, 0.055),
        (.rightHip, .rightKnee, 0.075), (.rightKnee, .rightAnkle, 0.055),
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
                    let outline = Self.silhouette(exercise.guideRest, exercise.guideTarget, progress: progress, in: box)
                    let color: Color = switch placement {
                    case .aligned: .green
                    case .almost: .yellow
                    default: .white
                    }
                    context.fill(outline, with: .color(color.opacity(0.08)))
                    // A dark edge under the line keeps it visible on a bright room.
                    context.stroke(outline, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: 6, lineJoin: .round))
                    context.stroke(outline, with: .color(color), style: StrokeStyle(lineWidth: 3, lineJoin: .round))
                }
            }
            .onChange(of: placement, initial: true) { onPlacement(placement) }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the outline sits: the size of a person standing 2 to 3 m away, measured on real videos
    /// (shoulders to ankles: about 56% of the screen height). Once the feet are seen, the outline stands
    /// on them: their height on screen depends on how the phone is set, not on where the patient stands.
    private func box(in size: CGSize) -> CGRect {
        let height = size.height * 0.74
        let width = height * 0.5
        var top = size.height * 0.17
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

    private static func silhouette(_ rest: GuidePose, _ target: GuidePose, progress: Double, in box: CGRect) -> Path {
        func point(_ joint: Joint) -> CGPoint? {
            guard let a = rest[joint], let b = target[joint] else { return nil }
            return CGPoint(
                x: box.minX + (a.x + (b.x - a.x) * progress) * box.width,
                y: box.minY + (a.y + (b.y - a.y) * progress) * box.height
            )
        }

        var outline = Path()
        for (a, b, width) in limbs {
            guard let pointA = point(a), let pointB = point(b) else { continue }
            var limb = Path()
            limb.move(to: pointA)
            limb.addLine(to: pointB)
            outline = outline.union(limb.strokedPath(StrokeStyle(lineWidth: box.height * width, lineCap: .round)))
        }
        if let leftShoulder = point(.leftShoulder), let rightShoulder = point(.rightShoulder),
           let leftHip = point(.leftHip), let rightHip = point(.rightHip) {
            var torso = Path()
            torso.addLines([leftShoulder, rightShoulder, rightHip, leftHip])
            torso.closeSubpath()
            outline = outline.union(torso.strokedPath(StrokeStyle(lineWidth: box.height * 0.04, lineJoin: .round)).union(torso))
        }
        if let head = point(.nose) {
            let width = box.height * 0.1, height = box.height * 0.125
            outline = outline.union(Path(ellipseIn: CGRect(x: head.x - width / 2, y: head.y - height / 2, width: width, height: height)))
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
