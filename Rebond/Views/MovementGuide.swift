import SwiftUI
import Vision

/// Pictogram of a person. Before the set it stands still, showing where to stand: it turns yellow when the
/// patient is close, then green once their body lines up with it. During the set it does the exercise in a loop.
struct MovementGuide: View {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    let exercise: CatalogExercise
    /// The patient's detected body, to check the placement.
    let skeleton: PoseSkeleton?
    /// Doing the exercise (during the set) or standing still (before).
    let isDemonstrating: Bool
    /// When the movement starts, so it begins standing.
    var demonstrationStart = Date.distantPast
    /// Small version in a corner: the figure fills its frame.
    var isCompact = false
    var onPlacement: (GuidePlacement) -> Void = { _ in }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Seconds for one full movement, down and back up.
    private static let cycle = MotionSession.demonstrationDuration

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let box = box(in: size)
            let placement = placement(in: size, box: box)

            TimelineView(.animation(paused: reduceMotion || !isDemonstrating)) { timeline in
                Canvas { context, _ in
                    let progress = isDemonstrating && !reduceMotion ? Self.progress(since: demonstrationStart, at: timeline.date) : 0
                    let figure = Self.outline(exercise.guideRest, exercise.guideTarget, progress: progress, in: box)
                    let color: Color = if isDemonstrating { .white } else {
                        switch placement {
                        case .aligned: .green
                        case .almost: .yellow
                        default: .white
                        }
                    }
                    // A dark edge under the line keeps it visible on a bright room.
                    let line = isCompact ? 3.0 : 6.0
                    context.stroke(figure, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: line * 1.8, lineJoin: .round))
                    context.stroke(figure, with: .color(color), style: StrokeStyle(lineWidth: line, lineJoin: .round))
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
        if isCompact {
            let height = size.height * 0.9
            let width = height * 0.65
            return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        }
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
    private static func progress(since start: Date, at date: Date) -> Double {
        let phase = max(0, date.timeIntervalSince(start)).truncatingRemainder(dividingBy: cycle) / cycle
        let wave = (1 - cos(phase * 2 * .pi)) / 2
        let held = min(1, max(0, (wave - 0.15) / 0.7))
        return held * held * (3 - 2 * held)
    }

    /// A signage-style pictogram drawn as one single contour: round head, torso with rounded corners,
    /// arms and legs of even thickness.
    /// Going down, the hands come together in front of the body, as in a real squat.
    private static func outline(_ rest: GuidePose, _ target: GuidePose, progress: Double, in box: CGRect) -> Path {
        func point(_ joint: Joint, at progress: Double) -> CGPoint? {
            guard let a = rest[joint], let b = target[joint] else { return nil }
            return CGPoint(
                x: box.minX + (a.x + (b.x - a.x) * progress) * box.width,
                y: box.minY + (a.y + (b.y - a.y) * progress) * box.height
            )
        }
        let limb = box.height * 0.075
        let arm = limb * 0.8

        func torso(at progress: Double) -> CGRect? {
            guard let leftShoulder = point(.leftShoulder, at: progress), let rightShoulder = point(.rightShoulder, at: progress),
                  let leftHip = point(.leftHip, at: progress), let rightHip = point(.rightHip, at: progress)
            else { return nil }
            let top = (leftShoulder.y + rightShoulder.y) / 2
            return CGRect(
                x: leftHip.x - limb / 2,
                y: top,
                width: rightHip.x - leftHip.x + limb,
                height: (leftHip.y + rightHip.y) / 2 - top + limb / 2
            )
        }
        guard let body = torso(at: progress), let standing = torso(at: 0) else { return Path() }

        // Top corners rounded like the end of the arms, so each arm covers its corner exactly.
        var outline = Path(roundedRect: body, cornerRadius: arm / 2)

        // Arms from the top corners of the torso: straight when standing, then the elbows bend and the
        // hands come together in front of the chest. Upper arm and forearm keep their length.
        var armShape = Path()
        func addSegment(_ a: CGPoint, _ b: CGPoint) {
            var segment = Path()
            segment.move(to: a)
            segment.addLine(to: b)
            armShape = armShape.union(segment.strokedPath(StrokeStyle(lineWidth: arm, lineCap: .round)))
        }
        let sides: [(x: (CGRect) -> CGFloat, wrist: Joint, outward: CGFloat)] = [
            ({ $0.minX + arm / 2 }, .leftWrist, -1), ({ $0.maxX - arm / 2 }, .rightWrist, 1),
        ]
        func unit(_ v: CGVector) -> CGVector {
            let length = max(hypot(v.dx, v.dy), 0.0001)
            return CGVector(dx: v.dx / length, dy: v.dy / length)
        }
        func mix(_ a: CGVector, _ b: CGVector) -> CGVector {
            unit(CGVector(dx: a.dx + (b.dx - a.dx) * progress, dy: a.dy + (b.dy - a.dy) * progress))
        }
        for side in sides {
            guard let standingHand = point(side.wrist, at: 0) else { continue }
            let standingStart = CGPoint(x: side.x(standing), y: standing.minY + arm / 2)
            let straight = CGVector(dx: standingHand.x - standingStart.x, dy: standingHand.y - standingStart.y)
            let segment = hypot(straight.dx, straight.dy) / 2
            let start = CGPoint(x: side.x(body), y: body.minY + arm / 2)

            // At the bottom: hands joined in front of the chest, elbows out and down.
            let chest = CGPoint(x: body.midX, y: body.minY + body.height * 0.3)
            let reach = min(hypot(chest.x - start.x, chest.y - start.y), segment * 2 * 0.999)
            let toChest = unit(CGVector(dx: chest.x - start.x, dy: chest.y - start.y))
            let bend = sqrt(max(0, segment * segment - reach * reach / 4))
            var normal = CGVector(dx: -toChest.dy, dy: toChest.dx)
            if normal.dx * side.outward < 0 { normal = CGVector(dx: -normal.dx, dy: -normal.dy) }
            let bottomElbow = CGPoint(
                x: start.x + toChest.dx * reach / 2 + normal.dx * bend,
                y: start.y + toChest.dy * reach / 2 + normal.dy * bend
            )
            let bottomUpper = unit(CGVector(dx: bottomElbow.x - start.x, dy: bottomElbow.y - start.y))
            let bottomFore = unit(CGVector(dx: chest.x - bottomElbow.x, dy: chest.y - bottomElbow.y))

            // In between, each segment turns smoothly from straight to bent, keeping its length.
            let upper = mix(unit(straight), bottomUpper)
            let fore = mix(unit(straight), bottomFore)
            let elbow = CGPoint(x: start.x + upper.dx * segment, y: start.y + upper.dy * segment)
            let hand = CGPoint(x: elbow.x + fore.dx * segment, y: elbow.y + fore.dy * segment)
            addSegment(start, elbow)
            addSegment(elbow, hand)
        }

        var legs = Path()
        for (hip, knee, ankle) in [(Joint.leftHip, Joint.leftKnee, Joint.leftAnkle), (.rightHip, .rightKnee, .rightAnkle)] {
            guard let hip = point(hip, at: progress), let knee = point(knee, at: progress), let ankle = point(ankle, at: progress) else { continue }
            legs.move(to: CGPoint(x: hip.x, y: body.maxY - limb))
            legs.addLine(to: knee)
            legs.addLine(to: ankle)
        }
        outline = outline.union(legs.strokedPath(StrokeStyle(lineWidth: limb, lineCap: .round, lineJoin: .round)))

        // Head joined to the torso by a short neck: the whole figure is a single contour.
        let radius = box.height * 0.065
        let head = CGRect(x: body.midX - radius, y: body.minY - box.height * 0.02 - radius * 2, width: radius * 2, height: radius * 2)
        let neck = CGRect(x: body.midX - radius * 0.45, y: head.midY, width: radius * 0.9, height: body.minY - head.midY + arm)
        return outline
            .union(Path(ellipseIn: head))
            .union(Path(roundedRect: neck, cornerRadius: radius * 0.3))
            .union(armShape)
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
