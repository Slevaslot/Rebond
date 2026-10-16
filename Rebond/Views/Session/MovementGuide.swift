import SwiftUI
import Vision

/// Pictogram of a person. Before the set it stands still, showing where to stand: it turns yellow when the
/// patient is close, then green once their body lines up with it. During the set it does the exercise in a loop.
struct MovementGuide: View, Animatable {
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
    /// Line thickness, in points.
    var lineWidth: Double?
    /// Line color of the demonstration; white over the camera by default.
    var tint: Color = .white
    /// The dark edge under the line keeps it readable over the camera; useless on a plain background.
    var hasEdge = true
    var onPlacement: (GuidePlacement) -> Void = { _ in }

    /// The line follows the figure's size change instead of jumping from one thickness to the other.
    var animatableData: Double {
        get { lineWidth ?? 0 }
        set { if lineWidth != nil { lineWidth = newValue } }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Where the patient's feet are on screen, steadied: the outline stands on them without shaking.
    @State private var feet = GuideAnchor()

    /// Seconds for one full movement, down and back up.
    private static let cycle = MotionSession.demonstrationDuration

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size
            let box = figureBox(in: size, feetY: feet.value)
            let placement = placement(in: size, box: box)

            TimelineView(.animation(paused: reduceMotion || !isDemonstrating)) { timeline in
                Canvas { context, _ in
                    let figure: Path
                    if isDemonstrating {
                        // With "Réduire les animations", the figure stays still in the movement's key position.
                        let progress = reduceMotion ? 1 : Self.progress(since: demonstrationStart, at: timeline.date)
                        figure = Self.outline(exercise.demonstrationRest, exercise.demonstrationTarget,
                                              armStyle: exercise.demonstrationArmStyle, progress: progress, in: box,
                                              view: exercise.demonstrationView)
                    } else {
                        // Where to stand: the resting pose, from the front, as the camera sees the patient.
                        figure = Self.outline(exercise.guideRest, exercise.guideRest, armStyle: exercise.armStyle,
                                              progress: 0, in: box)
                    }
                    let color: Color = if isDemonstrating { tint } else {
                        switch placement {
                        case .aligned: .green
                        case .almost: .yellow
                        default: .white
                        }
                    }
                    // A dark edge under the line keeps it visible on a bright room.
                    let line = lineWidth ?? (isCompact ? 3.0 : 6.0)
                    if hasEdge {
                        context.stroke(figure, with: .color(.black.opacity(0.35)), style: StrokeStyle(lineWidth: line * 1.8, lineJoin: .round))
                    }
                    context.stroke(figure, with: .color(color), style: StrokeStyle(lineWidth: line, lineJoin: .round))
                }
            }
            .onChange(of: placement, initial: true) { onPlacement(placement) }
            .onChange(of: bodyPoint(.leftAnkle, .rightAnkle, in: size).map { Double($0.y) }, initial: true) { _, y in
                feet.update(y, tolerance: size.height * 0.03)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// Where the figure sits: the size of a person standing about 3 m away (at 2 to 3 m, shoulders to
    /// ankles fill about 56% of the screen height on real videos). Once the feet are seen, the figure stands
    /// on them: their height on screen depends on how the phone is set, not on where the patient stands.
    func figureBox(in size: CGSize) -> CGRect {
        figureBox(in: size, feetY: bodyPoint(.leftAnkle, .rightAnkle, in: size).map { Double($0.y) })
    }

    /// The same, standing on feet seen at `feetY` points from the top (nil: not seen yet).
    func figureBox(in size: CGSize, feetY: Double?) -> CGRect {
        if isCompact {
            let height = size.height * 0.9
            let width = height * 0.65
            return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
        }
        let height = size.height * 0.6
        let width = height * 0.65
        var top = size.height * 0.28
        if let feetY, feetY.isFinite, let guideFeet = exercise.guideRest[.leftAnkle]?.y {
            top = min(max(feetY - guideFeet * height, size.height * 0.05), size.height * 0.3)
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
    /// arms and legs of even thickness. Any pair of poses gives a sane figure (see `GuideFigure`).
    static func outline(_ rest: GuidePose, _ target: GuidePose, armStyle: CatalogExercise.ArmStyle, progress: Double,
                        in box: CGRect, view: GuideFigure.View = .front) -> Path {
        path(of: GuideFigure(rest: rest, target: target, armStyle: armStyle, progress: progress, in: box, view: view))
    }

    /// The figure's contour: every part joined in one shape.
    static func path(of figure: GuideFigure) -> Path {
        let size = figure.torsoSize
        let torso = Path(roundedRect: CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height),
                         cornerRadius: figure.torsoCornerRadius)
            .applying(CGAffineTransform(rotationAngle: figure.torsoAngle)
                .concatenating(CGAffineTransform(translationX: figure.torsoCenter.x, y: figure.torsoCenter.y)))
        let radius = figure.headRadius
        var outline = torso
            .union(Path(ellipseIn: CGRect(x: figure.head.x - radius, y: figure.head.y - radius, width: radius * 2, height: radius * 2)))
            .union(segment(figure.neck, cap: .butt))
        for limb in figure.limbs {
            outline = outline.union(segment(limb, cap: .round))
        }
        if !figure.chair.isEmpty {
            var chair = Path()
            for line in figure.chair { chair.addLines(line) }
            outline = outline.union(chair.strokedPath(StrokeStyle(lineWidth: figure.chairWidth, lineCap: .round, lineJoin: .round)))
        }
        return outline
    }

    /// One piece of limb with round ends, wider at its end when it comes toward the camera.
    private static func segment(_ segment: GuideFigure.Segment, cap: CGLineCap) -> Path {
        let dx = segment.end.x - segment.start.x, dy = segment.end.y - segment.start.y
        let length = hypot(dx, dy)
        func disc(_ center: CGPoint, _ width: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - width / 2, y: center.y - width / 2, width: width, height: width))
        }
        guard length > 0.01 else { return disc(segment.end, max(segment.width, segment.endWidth)) }
        guard abs(segment.endWidth - segment.width) > 0.01 else {
            var line = Path()
            line.move(to: segment.start)
            line.addLine(to: segment.end)
            return line.strokedPath(StrokeStyle(lineWidth: segment.width, lineCap: cap))
        }
        let normal = CGVector(dx: -dy / length, dy: dx / length)
        let start = segment.width / 2, end = segment.endWidth / 2
        var tapered = Path()
        tapered.addLines([
            CGPoint(x: segment.start.x + normal.dx * start, y: segment.start.y + normal.dy * start),
            CGPoint(x: segment.end.x + normal.dx * end, y: segment.end.y + normal.dy * end),
            CGPoint(x: segment.end.x - normal.dx * end, y: segment.end.y - normal.dy * end),
            CGPoint(x: segment.start.x - normal.dx * start, y: segment.start.y - normal.dy * start),
        ])
        tapered.closeSubpath()
        return tapered.union(disc(segment.start, segment.width)).union(disc(segment.end, segment.endWidth))
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

nonisolated extension CatalogExercise {
    /// The poses the demonstration plays: from the side when the movement reads better that way.
    var demonstrationRest: GuidePose { guideProfile?.rest ?? guideRest }
    var demonstrationTarget: GuidePose { guideProfile?.target ?? guideTarget }
    var demonstrationView: GuideFigure.View { guideProfile == nil ? .front : .profile }
    var demonstrationArmStyle: ArmStyle { guideProfile?.armStyle ?? armStyle }
}
