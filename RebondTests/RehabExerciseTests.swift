import CoreGraphics
import Foundation
import Testing
@testable import Rebond

/// More synthetic bodies seen from the front, for the one-arm raises, sit-to-stands and leg raises.
/// Same units as `Body`: image height, origin bottom-left, torso 0.3 long.
enum RehabBody {
    static let torso = 0.3

    /// The upper body (neck and arms) moved sideways by `lean` torso lengths: the torso leaning to one side.
    static func leaning(_ measure: PoseMeasure, by lean: Double) -> PoseMeasure {
        let dx = lean * torso
        func shift(_ point: CGPoint?) -> CGPoint? { point.map { CGPoint(x: $0.x + dx, y: $0.y) } }
        return PoseMeasure(
            hips: measure.hips, neck: shift(measure.neck)!, leftHip: measure.leftHip, rightHip: measure.rightHip,
            leftKnee: measure.leftKnee, rightKnee: measure.rightKnee, leftAnkle: measure.leftAnkle, rightAnkle: measure.rightAnkle,
            leftShoulder: shift(measure.leftShoulder), rightShoulder: shift(measure.rightShoulder),
            leftElbow: shift(measure.leftElbow), rightElbow: shift(measure.rightElbow),
            leftWrist: shift(measure.leftWrist), rightWrist: shift(measure.rightWrist)
        )
    }

    /// Seated on a chair (`rise` 0), or getting up: the hips rise by `rise` torso lengths, up to about 0.9 standing.
    /// Seated, the thighs point at the camera, so the knees are about level with the hips.
    /// `torsoRatio` below 1 shortens the torso on screen, as when leaning toward the camera.
    static func sitToStand(rise: Double, torsoRatio: Double = 1, sideLean: Double = 0) -> PoseMeasure {
        let hipsY = 0.35 + rise * torso
        let standing = min(1, rise / 0.9)
        let kneeY = 0.33 + standing * (0.38 - 0.33)
        return PoseMeasure(
            hips: CGPoint(x: 0.5, y: hipsY), neck: CGPoint(x: 0.5 + sideLean * torso, y: hipsY + torso * torsoRatio),
            leftHip: CGPoint(x: 0.45, y: hipsY), rightHip: CGPoint(x: 0.55, y: hipsY),
            leftKnee: CGPoint(x: 0.42, y: kneeY), rightKnee: CGPoint(x: 0.58, y: kneeY),
            leftAnkle: CGPoint(x: 0.43, y: 0.1), rightAnkle: CGPoint(x: 0.57, y: 0.1)
        )
    }

    /// Standing on the right leg, the left one raised in front: the knee comes up toward the hip by `lift`
    /// torso lengths. Seen from hip height, a straight leg brings the ankle up a little more than the knee
    /// once the thigh is well up; a bent knee leaves it hanging low.
    static func legRaise(lift: Double, kneeBent: Bool = false, hipsDrop: Double = 0) -> PoseMeasure {
        let hipsY = 0.5 - hipsDrop * torso
        let kneeRise = lift * torso
        let ankleRise = kneeRise * (kneeBent ? 0.3 : 1.2)
        return PoseMeasure(
            hips: CGPoint(x: 0.5, y: hipsY), neck: CGPoint(x: 0.5, y: hipsY + torso),
            leftHip: CGPoint(x: 0.45, y: hipsY), rightHip: CGPoint(x: 0.55, y: hipsY),
            leftKnee: CGPoint(x: 0.45, y: 0.3 + kneeRise - hipsDrop * torso), rightKnee: CGPoint(x: 0.55, y: 0.3),
            leftAnkle: CGPoint(x: 0.45, y: 0.1 + ankleRise), rightAnkle: CGPoint(x: 0.55, y: 0.1)
        )
    }
}

@Suite("Élévation d'un bras")
struct OneArmRaiseTests {
    private func calibrated(left: Double = 15) -> Feeder<ArmRaiseCounter> {
        var feeder = Feeder(counter: ArmRaiseCounter(targetAngle: 110, arms: .either))
        feeder.feed(Body.arms(left: left, right: 15), frames: 10)
        return feeder
    }

    /// Raises the right arm while the left one stays where it is.
    private func raiseRight(_ feeder: inout Feeder<ArmRaiseCounter>, to angle: Double, left: Double = 15, lean: Double = 0, elbowBend: Double = 0) {
        let body = { (right: Double) in RehabBody.leaning(Body.arms(left: left, right: right, elbowBend: elbowBend), by: lean) }
        feeder.move(from: 15, to: angle, seconds: 1, measure: body)
        feeder.feed(body(angle), frames: 3)
        feeder.move(from: angle, to: 15, seconds: 1, measure: body)
        feeder.feed(body(15), frames: 5)
    }

    @Test func calibratesWithArmsDown() {
        #expect(calibrated().calibrated)
    }

    @Test func countsEitherArm() throws {
        var feeder = calibrated()
        raiseRight(&feeder, to: 120)
        feeder.move(from: 15, to: 120, seconds: 1) { Body.arms(left: $0, right: 15) }
        feeder.move(from: 120, to: 15, seconds: 1) { Body.arms(left: $0, right: 15) }
        feeder.feed(Body.arms(left: 15, right: 15), frames: 5)
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.03 && amplitude < 1.12)
        #expect(feeder.corrections.isEmpty)
    }

    @Test func armLeftHangingOpenDoesNotBlockTheReturn() {
        var feeder = calibrated(left: 32)
        raiseRight(&feeder, to: 120, left: 32)
        #expect(feeder.completed.count == 1)
    }

    @Test func partialRaiseIsIncomplete() {
        var feeder = calibrated()
        // Under 70% of the 110° target (77°).
        raiseRight(&feeder, to: 70)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.raiseHigher])
    }

    @Test func leaningToTheSideIsRejected() {
        var feeder = calibrated()
        raiseRight(&feeder, to: 120, lean: 0.25)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepBackStraight))
    }

    @Test func bentRaisedArmIsRejected() {
        var feeder = calibrated()
        raiseRight(&feeder, to: 120, elbowBend: 70)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepArmStraight))
    }
}

@Suite("Assis-debout")
struct SitToStandCounterTests {
    private func seated() -> Feeder<SitToStandCounter> {
        var feeder = Feeder(counter: SitToStandCounter(targetRise: 0.6))
        feeder.feed(RehabBody.sitToStand(rise: 0), frames: 10)
        return feeder
    }

    private func standUp(_ feeder: inout Feeder<SitToStandCounter>, to rise: Double, torsoRatio: Double = 1, sideLean: Double = 0) {
        let body = { (rise: Double) in RehabBody.sitToStand(rise: rise, torsoRatio: torsoRatio, sideLean: sideLean) }
        feeder.move(from: 0, to: rise, seconds: 1.2, measure: body)
        feeder.feed(body(rise), frames: 5)
        feeder.move(from: rise, to: 0, seconds: 1.5, measure: body)
        feeder.feed(body(0), frames: 5)
    }

    @Test func calibratesSeated() {
        #expect(seated().calibrated)
    }

    @Test func doesNotCalibrateStanding() {
        var feeder = Feeder(counter: SitToStandCounter(targetRise: 0.6))
        // Standing, the knees are well below the hips.
        let standing = PoseMeasure(
            hips: CGPoint(x: 0.5, y: 0.5), neck: CGPoint(x: 0.5, y: 0.8),
            leftHip: CGPoint(x: 0.45, y: 0.5), rightHip: CGPoint(x: 0.55, y: 0.5),
            leftKnee: CGPoint(x: 0.45, y: 0.3), rightKnee: CGPoint(x: 0.55, y: 0.3),
            leftAnkle: CGPoint(x: 0.45, y: 0.1), rightAnkle: CGPoint(x: 0.55, y: 0.1)
        )
        feeder.feed(standing, frames: 20)
        #expect(!feeder.calibrated)
    }

    @Test func countsStandingUpAndSittingDown() throws {
        var feeder = seated()
        standUp(&feeder, to: 0.85)
        standUp(&feeder, to: 0.85)
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.3 && amplitude < 1.5)
        #expect(feeder.completed.allSatisfy { !$0.tooFast })
    }

    @Test func halfwayIsIncomplete() {
        var feeder = seated()
        standUp(&feeder, to: 0.4)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.standUpFully])
    }

    @Test func chestThrownForwardIsRejected() {
        var feeder = seated()
        standUp(&feeder, to: 0.85, torsoRatio: 0.45)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepBackStraight))
    }

    @Test func leaningOnOneLegIsRejected() {
        var feeder = seated()
        standUp(&feeder, to: 0.85, sideLean: 0.3)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.useBothLegs))
    }
}

@Suite("Élévation de la jambe tendue")
struct LegRaiseCounterTests {
    private func standing() -> Feeder<LegRaiseCounter> {
        var feeder = Feeder(counter: LegRaiseCounter(targetLift: 0.3))
        feeder.feed(RehabBody.legRaise(lift: 0), frames: 10)
        return feeder
    }

    private func raise(_ feeder: inout Feeder<LegRaiseCounter>, to lift: Double, kneeBent: Bool = false, hipsDrop: Double = 0) {
        let body = { (lift: Double) in RehabBody.legRaise(lift: lift, kneeBent: kneeBent, hipsDrop: hipsDrop * lift / 0.45) }
        feeder.move(from: 0, to: lift, seconds: 1, measure: body)
        feeder.feed(body(lift), frames: 3)
        feeder.move(from: lift, to: 0, seconds: 1, measure: body)
        feeder.feed(body(0), frames: 5)
    }

    @Test func calibratesStanding() {
        #expect(standing().calibrated)
    }

    @Test func doesNotCalibrateOnOneLeg() {
        var feeder = Feeder(counter: LegRaiseCounter(targetLift: 0.3))
        feeder.feed(RehabBody.legRaise(lift: 0.45), frames: 20)
        #expect(!feeder.calibrated)
    }

    @Test func countsStraightLegRaises() throws {
        var feeder = standing()
        raise(&feeder, to: 0.45)
        raise(&feeder, to: 0.45)
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.4 && amplitude < 1.6)
        #expect(feeder.corrections.isEmpty)
    }

    @Test func lowRaiseIsIncomplete() {
        var feeder = standing()
        // Under 70% of the 0.3 target (0.21), above half of it.
        raise(&feeder, to: 0.18)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.raiseLegHigher])
    }

    @Test func bentKneeIsRejected() {
        var feeder = standing()
        raise(&feeder, to: 0.6, kneeBent: true)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepLegStraight))
    }

    @Test func bendingTheStandingLegIsRejected() {
        var feeder = standing()
        raise(&feeder, to: 0.45, hipsDrop: 0.25)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepStandingLegStraight))
    }
}

@Suite("Catalogue des exercices suivis")
struct RehabCatalogTests {
    @Test func sheetKindsMapToTheCatalog() throws {
        let kinds: [(ExerciseKind, String)] = [
            (.shoulderAbduction, "shoulder-abduction"), (.scaption, "scaption"),
            (.sitToStand, "sit-to-stand"), (.legRaise, "leg-raise"),
        ]
        for (kind, id) in kinds {
            #expect(kind.catalogID == id)
            #expect(CatalogExercise.find(id) != nil)
        }
    }

    @Test func eachExerciseMakesItsCounter() {
        #expect(CatalogExercise.shoulderAbduction.makeCounter() is ArmRaiseCounter)
        #expect(CatalogExercise.scaption.makeCounter() is ArmRaiseCounter)
        #expect(CatalogExercise.sitToStand.makeCounter() is SitToStandCounter)
        #expect(CatalogExercise.legRaise.makeCounter() is LegRaiseCounter)
        #expect(!CatalogExercise.squat.fillsGaugeUpward)
        #expect(CatalogExercise.sitToStand.fillsGaugeUpward)
    }

    /// The chair is drawn only for the exercise that starts seated.
    @Test func onlySitToStandHasAChair() {
        for exercise in CatalogExercise.all {
            #expect((exercise.guideRest[.guideChairSeat] != nil) == (exercise.id == "sit-to-stand"))
        }
    }
}
