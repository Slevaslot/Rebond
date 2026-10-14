import CoreGraphics
import Foundation
import Testing
@testable import Rebond

/// Synthetic bodies for the exercises added from the rest of UI-PRMD. Same units as `Body` and `RehabBody`:
/// image height, origin bottom-left, torso 0.3 long.
enum MoreBody {
    static let torso = RehabBody.torso

    /// The torso leaning toward the camera: seen from the front, the neck comes down toward the hips.
    static func leaningForward(_ measure: PoseMeasure, torsoRatio: Double) -> PoseMeasure {
        let neckY = measure.hips.y + (measure.neck.y - measure.hips.y) * torsoRatio
        return PoseMeasure(
            hips: measure.hips, neck: CGPoint(x: measure.neck.x, y: neckY),
            leftHip: measure.leftHip, rightHip: measure.rightHip, leftKnee: measure.leftKnee, rightKnee: measure.rightKnee,
            leftAnkle: measure.leftAnkle, rightAnkle: measure.rightAnkle
        )
    }
}

extension MoreBody {
    /// Standing, then lunging: the hips go down by `drop` and sideways by `shift` torso lengths, the left knee
    /// bends to `leftKnee` degrees (seen from the front), the right leg stays straight. Feet stay in place.
    static func lunge(drop: Double = 0, shift: Double = 0, leftKnee: Double = 178, lean: Double = 0) -> PoseMeasure {
        let hips = CGPoint(x: 0.5 + shift * torso, y: 0.5 - drop * torso)
        let leftHip = CGPoint(x: hips.x - 0.05, y: hips.y), rightHip = CGPoint(x: hips.x + 0.05, y: hips.y)
        let leftAnkle = CGPoint(x: 0.43, y: 0.1), rightAnkle = CGPoint(x: 0.57, y: 0.1)
        return PoseMeasure(
            hips: hips, neck: CGPoint(x: hips.x + lean * torso, y: hips.y + torso),
            leftHip: leftHip, rightHip: rightHip,
            leftKnee: knee(leftHip, leftAnkle, angle: leftKnee, outward: -1), rightKnee: knee(rightHip, rightAnkle, angle: 178, outward: 1),
            leftAnkle: leftAnkle, rightAnkle: rightAnkle
        )
    }

    /// The knee between hip and ankle, pushed outward so the leg bends to `angle` degrees.
    private static func knee(_ hip: CGPoint, _ ankle: CGPoint, angle: Double, outward: Double) -> CGPoint {
        let half = hypot(hip.x - ankle.x, hip.y - ankle.y) / 2
        let offset = half / tan(angle / 2 * .pi / 180)
        return CGPoint(x: (hip.x + ankle.x) / 2 + outward * offset, y: (hip.y + ankle.y) / 2)
    }
}

@Suite("Montée de genou")
struct HurdleStepTests {
    private func standing() -> Feeder<LegRaiseCounter> {
        var feeder = Feeder(counter: LegRaiseCounter(targetLift: 0.45, style: .bentKnee))
        feeder.feed(RehabBody.legRaise(lift: 0), frames: 10)
        return feeder
    }

    private func raise(_ feeder: inout Feeder<LegRaiseCounter>, to lift: Double, torsoRatio: Double = 1) {
        let body = { (lift: Double) in
            MoreBody.leaningForward(RehabBody.legRaise(lift: lift, kneeBent: true), torsoRatio: 1 - (1 - torsoRatio) * lift / 0.6)
        }
        feeder.move(from: 0, to: lift, seconds: 1, measure: body)
        feeder.feed(body(lift), frames: 3)
        feeder.move(from: lift, to: 0, seconds: 1, measure: body)
        feeder.feed(body(0), frames: 5)
    }

    @Test func calibratesStanding() {
        #expect(standing().calibrated)
    }

    @Test func countsBentKneeRaises() throws {
        var feeder = standing()
        raise(&feeder, to: 0.6)
        raise(&feeder, to: 0.6)
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.25 && amplitude < 1.4)
        // The bent knee is the exercise: no "keep the leg straight".
        #expect(feeder.corrections.isEmpty)
    }

    @Test func lowRaiseIsIncomplete() {
        var feeder = standing()
        raise(&feeder, to: 0.3)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.raiseKneeHigher])
    }

    @Test func leaningForwardIsRejected() {
        var feeder = standing()
        raise(&feeder, to: 0.6, torsoRatio: 0.75)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepBackStraight))
    }

    @Test func isInTheCatalog() {
        #expect(ExerciseKind.hurdleStep.catalogID == "hurdle-step")
        #expect(CatalogExercise.find("hurdle-step")?.makeCounter() is LegRaiseCounter)
    }
}

@Suite("Fente avant")
struct ForwardLungeTests {
    private func standing() -> Feeder<LungeCounter> {
        var feeder = Feeder(counter: LungeCounter(direction: .forward, target: 0.45))
        feeder.feed(MoreBody.lunge(), frames: 10)
        return feeder
    }

    private func lunge(_ feeder: inout Feeder<LungeCounter>, to drop: Double, knee: Double = 120, lean: Double = 0) {
        let body = { (drop: Double) in
            let depth = drop / 0.6
            return MoreBody.lunge(drop: drop, leftKnee: 178 - (178 - knee) * depth, lean: lean * depth)
        }
        feeder.move(from: 0, to: drop, seconds: 1, measure: body)
        feeder.feed(body(drop), frames: 3)
        feeder.move(from: drop, to: 0, seconds: 1, measure: body)
        feeder.feed(body(0), frames: 5)
    }

    @Test func calibratesStanding() {
        #expect(standing().calibrated)
    }

    @Test func countsLunges() throws {
        var feeder = standing()
        lunge(&feeder, to: 0.6)
        lunge(&feeder, to: 0.6)
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.25 && amplitude < 1.4)
        #expect(feeder.corrections.isEmpty)
    }

    @Test func shallowLungeIsIncomplete() {
        var feeder = standing()
        lunge(&feeder, to: 0.3)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.goLower])
    }

    @Test func leaningToTheSideIsRejected() {
        var feeder = standing()
        lunge(&feeder, to: 0.6, lean: 0.4)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepBackStraight))
    }

    @Test func goingDownWithoutBendingTheKneeIsRejected() {
        var feeder = standing()
        lunge(&feeder, to: 0.6, knee: 170)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.bendFrontKnee))
    }
}

@Suite("Fente latérale")
struct SideLungeTests {
    private func standing() -> Feeder<LungeCounter> {
        var feeder = Feeder(counter: LungeCounter(direction: .side, target: 0.4))
        feeder.feed(MoreBody.lunge(), frames: 10)
        return feeder
    }

    private func lunge(_ feeder: inout Feeder<LungeCounter>, to shift: Double, knee: Double = 130, lean: Double = 0) {
        let body = { (shift: Double) in
            let depth = abs(shift) / 0.5
            return MoreBody.lunge(drop: 0.3 * depth, shift: shift, leftKnee: 178 - (178 - knee) * depth, lean: lean * depth)
        }
        feeder.move(from: 0, to: shift, seconds: 1, measure: body)
        feeder.feed(body(shift), frames: 3)
        feeder.move(from: shift, to: 0, seconds: 1, measure: body)
        feeder.feed(body(0), frames: 5)
    }

    @Test func calibratesStanding() {
        #expect(standing().calibrated)
    }

    @Test func countsLungesOnEitherSide() throws {
        var feeder = standing()
        lunge(&feeder, to: -0.5)
        lunge(&feeder, to: 0.5)
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.15 && amplitude < 1.35)
        #expect(feeder.corrections.isEmpty)
    }

    @Test func shortLungeIsIncomplete() {
        var feeder = standing()
        lunge(&feeder, to: -0.25)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.lungeFurther])
    }

    @Test func movingTheHipsWithoutBendingTheKneeIsRejected() {
        var feeder = standing()
        lunge(&feeder, to: -0.5, knee: 170)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.bendFrontKnee))
    }
}

@Suite("Catalogue des exercices ajoutés")
struct MoreCatalogTests {
    @Test func sheetKindsMapToTheCatalog() {
        let kinds: [(ExerciseKind, String)] = [(.forwardLunge, "forward-lunge"), (.sideLunge, "side-lunge")]
        for (kind, id) in kinds {
            #expect(kind.catalogID == id)
            #expect(CatalogExercise.find(id)?.makeCounter() is LungeCounter)
        }
    }

    @Test func forwardLungeFillsTheGaugeDownward() {
        #expect(!CatalogExercise.forwardLunge.fillsGaugeUpward)
        #expect(CatalogExercise.sideLunge.fillsGaugeUpward)
    }
}

extension MoreBody {
    /// Shoulder rotation in the 90/90 position, right arm: the upper arm out at shoulder height (dropped by
    /// `elbowDrop` image units), the forearm up and turned forward by `turn` (0 upright, 1 pointing at the camera).
    /// The left arm hangs.
    static func rotation(turn: Double, elbowDrop: Double = 0, lean: Double = 0) -> PoseMeasure {
        let dx = lean * torso
        let shoulder = CGPoint(x: 0.56 + dx, y: 0.78)
        let elbow = CGPoint(x: 0.68 + dx, y: 0.78 - elbowDrop)
        return PoseMeasure(
            hips: CGPoint(x: 0.5, y: 0.5), neck: CGPoint(x: 0.5 + dx, y: 0.8),
            leftHip: CGPoint(x: 0.45, y: 0.5), rightHip: CGPoint(x: 0.55, y: 0.5),
            leftKnee: CGPoint(x: 0.45, y: 0.3), rightKnee: CGPoint(x: 0.55, y: 0.3),
            leftAnkle: CGPoint(x: 0.45, y: 0.1), rightAnkle: CGPoint(x: 0.55, y: 0.1),
            leftShoulder: CGPoint(x: 0.44 + dx, y: 0.78), rightShoulder: shoulder,
            leftElbow: CGPoint(x: 0.42 + dx, y: 0.66), rightElbow: elbow,
            leftWrist: CGPoint(x: 0.42 + dx, y: 0.56), rightWrist: CGPoint(x: elbow.x, y: elbow.y + 0.1 * (1 - turn))
        )
    }
}

@Suite("Rotation de l'épaule")
struct ShoulderRotationTests {
    private func ready() -> Feeder<ShoulderRotationCounter> {
        var feeder = Feeder(counter: ShoulderRotationCounter(targetTurn: 0.6))
        feeder.feed(MoreBody.rotation(turn: 0), frames: 10)
        return feeder
    }

    private func turn(_ feeder: inout Feeder<ShoulderRotationCounter>, to turn: Double, elbowDrop: Double = 0, lean: Double = 0) {
        let body = { (turn: Double) in MoreBody.rotation(turn: turn, elbowDrop: elbowDrop * turn, lean: lean * turn) }
        feeder.move(from: 0, to: turn, seconds: 1, measure: body)
        feeder.feed(body(turn), frames: 3)
        feeder.move(from: turn, to: 0, seconds: 1, measure: body)
        feeder.feed(body(0), frames: 5)
    }

    @Test func calibratesInTheStartingPosition() {
        #expect(ready().calibrated)
    }

    @Test func doesNotCalibrateWithArmsDown() {
        var feeder = Feeder(counter: ShoulderRotationCounter(targetTurn: 0.6))
        feeder.feed(Body.arms(left: 15, right: 15), frames: 20)
        #expect(!feeder.calibrated)
    }

    @Test func countsRotations() throws {
        var feeder = ready()
        turn(&feeder, to: 0.9)
        turn(&feeder, to: 0.9)
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.4 && amplitude < 1.6)
        #expect(feeder.corrections.isEmpty)
    }

    @Test func smallTurnIsIncomplete() {
        var feeder = ready()
        turn(&feeder, to: 0.4)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.turnForearmFurther])
    }

    @Test func droppingTheElbowIsRejected() {
        var feeder = ready()
        turn(&feeder, to: 0.9, elbowDrop: 0.08)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepElbowUp))
    }

    @Test func isInTheCatalogWithoutThePalmGesture() {
        #expect(ExerciseKind.shoulderRotation.catalogID == "shoulder-rotation")
        #expect(CatalogExercise.shoulderRotation.makeCounter() is ShoulderRotationCounter)
        #expect(!CatalogExercise.shoulderRotation.allowsHandGestures)
        #expect(CatalogExercise.squat.allowsHandGestures)
    }
}
