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
