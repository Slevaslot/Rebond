import SwiftUI

/// The exercise's own pictogram: SF Symbols has no squat, sit-to-stand or leg raise.
/// Leg exercises are drawn from the side, where they read at a glance; arm exercises use the movement guide's
/// outline frozen at its target pose. Filled with the current tint.
struct ExerciseIcon: View {
    let exercise: CatalogExercise

    var body: some View {
        Canvas { context, size in
            let path = Self.sideView[exercise.id] ?? guideOutline
            let bounds = path.boundingRect
            guard bounds.width > 0, bounds.height > 0 else { return }
            let scale = min(size.width / bounds.width, size.height / bounds.height)
            let transform = CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY)
                .concatenating(CGAffineTransform(scaleX: scale, y: scale))
                .concatenating(CGAffineTransform(translationX: size.width / 2, y: size.height / 2))
            context.fill(path.applying(transform), with: .style(.tint))
        }
        .accessibilityHidden(true)
    }

    private var guideOutline: Path {
        MovementGuide.outline(exercise.guideRest, exercise.guideTarget, armStyle: exercise.armStyle, progress: 1,
                              in: CGRect(x: 0, y: 0, width: 65, height: 100))
    }

    /// Side views, facing right, in a 100-point box.
    private static let sideView: [String: Path] = [
        CatalogExercise.squat.id: figure(
            head: CGPoint(x: 53, y: 13),
            lines: [
                [CGPoint(x: 47, y: 31), CGPoint(x: 30, y: 58), CGPoint(x: 61, y: 60), CGPoint(x: 57, y: 92), CGPoint(x: 70, y: 92)],
                [CGPoint(x: 47, y: 33), CGPoint(x: 80, y: 37)],
            ]
        ),
        // Seated on a chair, about to stand up: arms forward.
        CatalogExercise.sitToStand.id: figure(
            head: CGPoint(x: 38, y: 13),
            lines: [
                [CGPoint(x: 36, y: 31), CGPoint(x: 32, y: 58), CGPoint(x: 62, y: 58), CGPoint(x: 62, y: 92), CGPoint(x: 74, y: 92)],
                [CGPoint(x: 37, y: 34), CGPoint(x: 68, y: 40)],
            ],
            extra: chair
        ),
        // Standing, one straight leg raised forward.
        CatalogExercise.legRaise.id: figure(
            head: CGPoint(x: 40, y: 10),
            lines: [
                [CGPoint(x: 40, y: 27), CGPoint(x: 40, y: 56), CGPoint(x: 40, y: 92), CGPoint(x: 52, y: 92)],
                [CGPoint(x: 40, y: 56), CGPoint(x: 80, y: 38)],
                [CGPoint(x: 40, y: 30), CGPoint(x: 30, y: 55)],
            ]
        ),
    ]

    private static var chair: Path {
        var chair = Path()
        chair.move(to: CGPoint(x: 14, y: 30))
        chair.addLine(to: CGPoint(x: 18, y: 66))
        chair.addLine(to: CGPoint(x: 50, y: 66))
        chair.addLine(to: CGPoint(x: 50, y: 95))
        chair.move(to: CGPoint(x: 18, y: 66))
        chair.addLine(to: CGPoint(x: 18, y: 95))
        return chair.strokedPath(StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
    }

    private static func figure(head: CGPoint, lines: [[CGPoint]], extra: Path = Path()) -> Path {
        var limbs = Path()
        for line in lines {
            limbs.move(to: line[0])
            for point in line.dropFirst() { limbs.addLine(to: point) }
        }
        return limbs.strokedPath(StrokeStyle(lineWidth: 11, lineCap: .round, lineJoin: .round))
            .union(Path(ellipseIn: CGRect(x: head.x - 9, y: head.y - 9, width: 18, height: 18)))
            .union(extra)
    }
}
