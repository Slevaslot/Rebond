import SwiftUI
import Testing
import UIKit
@testable import Rebond

/// Renders the movement pictograms to PNG files, to look at them without a camera.
/// Only when `TEST_RUNNER_GUIDE_RENDER_DIR` is given to `xcodebuild test`: the files go in that folder.
@MainActor
struct GuideRenderTests {
    nonisolated private static let folder = ProcessInfo.processInfo.environment["GUIDE_RENDER_DIR"]
    private static let cell = CGSize(width: 170, height: 230)

    /// One row per exercise: the demonstration at five moments, then the placement outline over a dark background.
    @Test(.enabled(if: folder != nil)) func renderEveryExercise() throws {
        let steps = [0, 0.25, 0.5, 0.75, 1.0]
        let exercises = CatalogExercise.all
        try render("exercises", columns: steps.count + 1, rows: exercises.count) { context, column, row, frame in
            let exercise = exercises[row]
            if column < steps.count {
                let path = MovementGuide.outline(exercise.demonstrationRest, exercise.demonstrationTarget,
                                                 armStyle: exercise.demonstrationArmStyle, progress: steps[column], in: Self.box(in: frame),
                                                 view: exercise.demonstrationView)
                Self.draw(path, color: .white, width: 4, in: context)
            } else {
                Self.placement(exercise.guideRest, armStyle: exercise.armStyle, in: frame, context: context)
            }
        }
    }

    /// Deformed poses, as a filmed movement could give: the placement outline must stay a body.
    @Test(.enabled(if: folder != nil)) func renderDeformedPoses() throws {
        let poses = GuideFigureTests.deformedPoses
        try render("deformed", columns: poses.count, rows: 1) { context, column, _, frame in
            Self.placement(poses[column], in: frame, context: context)
        }
    }

    private func render(_ name: String, columns: Int, rows: Int,
                        draw: (CGContext, Int, Int, CGRect) -> Void) throws {
        let cell = Self.cell
        let size = CGSize(width: cell.width * Double(columns), height: cell.height * Double(rows))
        let image = UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for row in 0..<rows {
                for column in 0..<columns {
                    let frame = CGRect(x: cell.width * Double(column), y: cell.height * Double(row),
                                       width: cell.width, height: cell.height)
                    draw(context.cgContext, column, row, frame)
                }
            }
        }
        try image.pngData()!.write(to: URL(filePath: Self.folder!).appending(path: "\(name).png"))
    }

    private static func placement(_ pose: GuidePose, armStyle: CatalogExercise.ArmStyle = .straight, in frame: CGRect,
                                  context: CGContext) {
        context.setFillColor(UIColor.darkGray.cgColor)
        context.fill(frame.insetBy(dx: 1, dy: 1))
        let path = MovementGuide.outline(pose, pose, armStyle: armStyle, progress: 0, in: box(in: frame))
        draw(path, color: .yellow, width: 4, edge: true, in: context)
    }

    private static func box(in frame: CGRect) -> CGRect {
        let height = frame.height * 0.85
        let width = height * 0.65
        return CGRect(x: frame.midX - width / 2, y: frame.midY - height / 2, width: width, height: height)
    }

    private static func draw(_ path: Path, color: UIColor, width: Double, edge: Bool = false, in context: CGContext) {
        context.setLineJoin(.round)
        if edge {
            context.addPath(path.cgPath)
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.35).cgColor)
            context.setLineWidth(width * 1.8)
            context.strokePath()
        }
        context.addPath(path.cgPath)
        context.setStrokeColor(color.cgColor)
        context.setLineWidth(width)
        context.strokePath()
    }
}
