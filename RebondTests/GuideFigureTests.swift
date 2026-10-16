import CoreGraphics
import SwiftUI
import Testing
import Vision
@testable import Rebond

/// The movement pictogram stays a sane body whatever the poses it is given.
struct GuideFigureTests {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    static let box = CGRect(x: 100, y: 50, width: 260, height: 400)

    /// Poses a filmed movement could give: crossed hips, a wrist far away, missing joints, upside down…
    static let deformedPoses: [GuidePose] = {
        let standing = CatalogExercise.lateralRaise.guideRest
        var crossed = standing
        crossed[.leftHip] = CGPoint(x: 0.62, y: 0.5)
        crossed[.rightHip] = CGPoint(x: 0.38, y: 0.5)
        crossed[.leftShoulder] = CGPoint(x: 0.66, y: 0.2)
        crossed[.rightShoulder] = CGPoint(x: 0.34, y: 0.2)
        var farWrist = standing
        farWrist[.leftWrist] = CGPoint(x: -0.3, y: 1.2)
        farWrist[.rightElbow] = CGPoint(x: 1.2, y: -0.2)
        var missing = standing
        for joint: Joint in [.leftWrist, .rightKnee, .leftKnee, .rightAnkle, .leftHip] { missing[joint] = nil }
        let torsoOnly: GuidePose = [
            .leftShoulder: CGPoint(x: 0.4, y: 0.3), .rightShoulder: CGPoint(x: 0.6, y: 0.3),
            .leftHip: CGPoint(x: 0.45, y: 0.55), .rightHip: CGPoint(x: 0.55, y: 0.55),
        ]
        var upsideDown = standing
        upsideDown[.leftShoulder] = CGPoint(x: 0.36, y: 0.6)
        upsideDown[.rightShoulder] = CGPoint(x: 0.64, y: 0.6)
        let collapsed = standing.mapValues { _ in CGPoint(x: 0.5, y: 0.5) }
        var invalid = standing
        invalid[.leftKnee] = CGPoint(x: .nan, y: 0.7)
        invalid[.rightWrist] = CGPoint(x: .infinity, y: 0.5)
        var lying = standing
        lying[.leftShoulder] = CGPoint(x: 0.1, y: 0.45)
        lying[.rightShoulder] = CGPoint(x: 0.1, y: 0.55)
        return [crossed, farWrist, missing, torsoOnly, upsideDown, collapsed, invalid, lying, [:]]
    }()

    private func expectSane(_ figure: GuideFigure, in box: CGRect = box, _ comment: Comment? = nil) {
        let height = box.height
        let limit = box.insetBy(dx: -height * 0.6, dy: -height * 0.6)
        for point in figure.points {
            #expect(point.x.isFinite && point.y.isFinite, comment)
            #expect(limit.contains(point), comment)
        }
        #expect(figure.torsoSize.width >= height * (GuideFigure.minimumHipSpan + GuideFigure.limbWidth) - 0.01, comment)
        #expect(figure.torsoSize.width <= height * (GuideFigure.maximumHipSpan + GuideFigure.limbWidth) + 0.01, comment)
        #expect(figure.torsoSize.height >= height * GuideFigure.torsoLengthRange.lowerBound, comment)
        #expect(abs(figure.torsoAngle) <= GuideFigure.maximumLean + 0.001, comment)
        for limb in figure.limbs {
            #expect(hypot(limb.end.x - limb.start.x, limb.end.y - limb.start.y) <= height * GuideFigure.maximumLowerLimb * 2 + 0.01, comment)
        }
        // The head stays above the hips.
        #expect(figure.head.y < figure.torsoCenter.y, comment)
    }

    @Test func everyExerciseGivesASaneFigure() {
        for exercise in CatalogExercise.all {
            for progress in stride(from: 0.0, through: 1.0, by: 0.125) {
                let front = GuideFigure(rest: exercise.guideRest, target: exercise.guideTarget, armStyle: exercise.armStyle,
                                        progress: progress, in: Self.box)
                expectSane(front, "\(exercise.id) \(progress)")
                let demonstration = GuideFigure(rest: exercise.demonstrationRest, target: exercise.demonstrationTarget,
                                                armStyle: exercise.demonstrationArmStyle, progress: progress, in: Self.box,
                                                view: exercise.demonstrationView)
                expectSane(demonstration, "\(exercise.id) demonstration \(progress)")
                // Four limbs at least, two segments each for the legs.
                #expect(demonstration.limbs.count >= 6)
            }
        }
    }

    @MainActor @Test func everyExerciseHasAnOutline() {
        for exercise in CatalogExercise.all {
            for pose in [exercise.guideRest, exercise.guideTarget] {
                let bounds = MovementGuide.outline(pose, pose, armStyle: exercise.armStyle, progress: 0, in: Self.box).boundingRect
                #expect(bounds.height > Self.box.height * 0.6, "\(exercise.id)")
                #expect(bounds.width > Self.box.width * 0.3, "\(exercise.id)")
            }
        }
    }

    @MainActor @Test func deformedPosesStillGiveABody() {
        for (index, pose) in Self.deformedPoses.enumerated() {
            for progress in [0.0, 0.5, 1.0] {
                let figure = GuideFigure(rest: pose, target: Self.deformedPoses[(index + 1) % Self.deformedPoses.count],
                                         armStyle: .straight, progress: progress, in: Self.box)
                expectSane(figure, "pose \(index) \(progress)")
            }
            let bounds = MovementGuide.outline(pose, pose, armStyle: .straight, progress: 0, in: Self.box).boundingRect
            #expect(bounds.height > Self.box.height * 0.5, "pose \(index)")
            #expect(bounds.width < Self.box.height, "pose \(index)")
        }
    }

    /// The shoulder rotation's arm bends at the elbow: an "L", not a straight line to the hand.
    @Test func shoulderRotationArmGoesThroughTheElbow() {
        let exercise = CatalogExercise.shoulderRotation
        let figure = GuideFigure(rest: exercise.guideRest, target: exercise.guideTarget, armStyle: exercise.armStyle,
                                 progress: 0, in: Self.box)
        let elbow = CGPoint(x: Self.box.minX + 0.14 * Self.box.width, y: Self.box.minY + 0.2 * Self.box.height)
        #expect(figure.limbs.contains { hypot($0.end.x - elbow.x, $0.end.y - elbow.y) < 1 })
        // At the target the forearm points at the camera: its hand is drawn bigger.
        let turned = GuideFigure(rest: exercise.guideRest, target: exercise.guideTarget, armStyle: exercise.armStyle,
                                 progress: 1, in: Self.box)
        #expect(turned.limbs.contains { $0.endWidth > $0.width * 1.3 })
    }

    /// A raised arm turns around the shoulder: it keeps its length on the way, instead of cutting the corner.
    @Test func raisedArmMovesInAnArc() {
        let exercise = CatalogExercise.lateralRaise
        func armLength(_ progress: Double) -> CGFloat {
            let arm = GuideFigure(rest: exercise.guideRest, target: exercise.guideTarget, armStyle: exercise.armStyle,
                                  progress: progress, in: Self.box).limbs[0]
            return hypot(arm.end.x - arm.start.x, arm.end.y - arm.start.y)
        }
        #expect(abs(armLength(0.5) - armLength(0)) < armLength(0) * 0.06)
    }

    /// Feet that stay on the floor don't slide or lift during a squat.
    @Test func plantedFeetStayOnTheFloor() {
        let exercise = CatalogExercise.squat
        let ankles = [0.0, 0.5, 1.0].map {
            GuideFigure(rest: exercise.guideRest, target: exercise.guideTarget, armStyle: exercise.armStyle,
                        progress: $0, in: Self.box).limbs.last!.end.y
        }
        #expect(ankles.allSatisfy { abs($0 - ankles[0]) < 1 })
    }

    @Test func anchorIgnoresNoiseAndFollowsRealMoves() {
        var anchor = GuideAnchor()
        anchor.update(nil, tolerance: 10)
        #expect(anchor.value == nil)
        anchor.update(500, tolerance: 10)
        #expect(anchor.value == 500)
        // Small wobbles and a one-frame error: it doesn't move.
        for y in [503.0, 497, 504, 620, 498, 502] { anchor.update(y, tolerance: 10) }
        #expect(anchor.value == 500)
        // Feet lost: it stays.
        anchor.update(nil, tolerance: 10)
        #expect(anchor.value == 500)
        // The phone moved: it follows, smoothly.
        anchor.update(560, tolerance: 10)
        anchor.update(560, tolerance: 10)
        anchor.update(560, tolerance: 10)
        let first = anchor.value!
        #expect(first > 500 && first < 560)
        for _ in 0..<30 { anchor.update(560, tolerance: 10) }
        #expect(abs(anchor.value! - 560) < 2)
    }
}
