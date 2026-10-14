import CoreGraphics
import Foundation

/// Counts shoulder rotations seen from the front, either arm, in the "90/90" position: the upper arm held out
/// sideways at shoulder height, the elbow bent at a right angle, the forearm pointing up. The forearm turns
/// forward, toward the camera, until about level, then comes back up (internal then external rotation).
///
/// Seen from the front, the forearm pointing up is at full length; turning toward the camera, it looks shorter
/// and the wrist comes down to the elbow's height. The turn is measured as the wrist coming down toward the elbow,
/// in forearm lengths: 0 pointing up, 1 with the wrist level with the elbow. The forearm's length is the highest
/// the wrist has been above the elbow at rest: some start with the forearm tilted back, and only show its full
/// length when it passes upright.
/// Turning backward would look the same from the front: the guide shows the forward turn.
nonisolated struct ShoulderRotationCounter: MovementCounter {
    private enum Side {
        case left, right
    }

    private struct Start {
        let side: Side
        /// Wrist above the elbow, pointing up: the highest seen at rest.
        var forearm: Double
        let lean: Double
        let torsoLength: Double
        /// Angle between the upper arm and the side of the body, in degrees: about 90 at shoulder height.
        let upperArm: Double
    }

    /// How far the wrist must come down toward the elbow, in forearm lengths.
    let targetTurn: Double

    /// Measures (about 0.5 s) needed while still in the starting position.
    private let stillSamples = 8
    /// Maximum wrist movement while "still", in upper arm lengths.
    private let stillTolerance = 0.15
    /// Starting position: the upper arm at least this far from the body, in degrees (90 is shoulder height).
    private let minRaisedUpperArm = 65.0
    /// Starting position: the wrist above the elbow by at least this much of the upper arm's length.
    /// The forearm may lean back a little (UI-PRMD: down to 0.3).
    private let minForearmUp = 0.25
    /// The elbow dropping, compared with the start, in degrees. UI-PRMD: incorrect rotations start with the
    /// upper arm as low as 54°, correct ones keep it above 85°.
    private let maxElbowDrop = 25.0
    /// Torso leaning to one side, compared with the start, in torso lengths. UI-PRMD: correct rotations stay under
    /// 0.03, incorrect ones lean up to 0.22.
    private let maxSideLean = 0.08
    /// Leaning forward makes the torso look shorter, seen from the front. UI-PRMD: correct rotations keep at least
    /// 98% of the starting length, incorrect ones drop to 61%.
    private let minTorsoRatio = 0.88
    private let lostTimeout = 1.5
    private let smoothingWindow = 3

    private var start: Start?
    private var cycle: RepCycle
    private var recentTurns: [Double] = []
    private var recentMeasures: [PoseMeasure] = []
    private var lastMeasureTime = 0.0
    private var progress = 0.0

    init(targetTurn: Double) {
        self.targetTurn = targetTurn
        cycle = RepCycle(
            start: targetTurn * 0.3,
            target: targetTurn,
            back: targetTurn * 0.2,
            reversalMargin: targetTurn * 0.25,
            noise: targetTurn * 0.6,
            // Slow and controlled, for the shoulder.
            minDuration: 1.5,
            shortfall: .turnForearmFurther
        )
    }

    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure else {
            if time - lastMeasureTime > lostTimeout { cycle.abandon() }
            return CounterUpdate(progress: progress, event: nil)
        }
        guard let start else {
            recentMeasures.append(measure)
            if recentMeasures.count > stillSamples { recentMeasures.removeFirst() }
            lastMeasureTime = time
            if let position = startingPosition() {
                self.start = position
                return CounterUpdate(progress: 0, event: .calibrated)
            }
            return CounterUpdate(progress: 0, event: nil)
        }
        guard let arm = Self.arm(start.side, in: measure) else {
            if time - lastMeasureTime > lostTimeout { cycle.abandon() }
            return CounterUpdate(progress: progress, event: nil, posture: cycle.posture)
        }
        lastMeasureTime = time

        let height = arm.wrist.y - arm.elbow.y
        if cycle.phase == .rest, height > start.forearm {
            self.start?.forearm = height
        }
        let forearm = max(start.forearm, height)
        recentTurns.append((forearm - height) / forearm)
        if recentTurns.count > smoothingWindow { recentTurns.removeFirst() }
        let turn = RepCounter.median(recentTurns)
        progress = max(0, turn / targetTurn)

        let upperArm = ArmRaiseCounter.angle(at: arm.shoulder, measure.hips, arm.elbow) ?? start.upperArm
        let fault: Correction? = if start.upperArm - upperArm > maxElbowDrop {
            .keepElbowUp
        } else if abs(measure.sideLean - start.lean) > maxSideLean || measure.torsoLength / start.torsoLength < minTorsoRatio {
            .keepBackStraight
        } else {
            nil
        }
        let (event, posture) = cycle.advance(turn, fault: fault, at: time)
        return CounterUpdate(progress: progress, event: event, posture: posture)
    }

    private struct Arm {
        let shoulder: CGPoint
        let elbow: CGPoint
        let wrist: CGPoint
    }

    private static func arm(_ side: Side, in measure: PoseMeasure) -> Arm? {
        let joints = side == .left
            ? (measure.leftShoulder, measure.leftElbow, measure.leftWrist)
            : (measure.rightShoulder, measure.rightElbow, measure.rightWrist)
        guard let shoulder = joints.0, let elbow = joints.1, let wrist = joints.2 else { return nil }
        return Arm(shoulder: shoulder, elbow: elbow, wrist: wrist)
    }

    /// The starting position, when the patient has been still for a moment with one upper arm out at about
    /// shoulder height and its forearm pointing up. Either arm; the higher forearm if both are up.
    private func startingPosition() -> Start? {
        guard recentMeasures.count == stillSamples, let last = recentMeasures.last else { return nil }
        let candidates: [(Side, Arm, Double)] = [Side.left, .right].compactMap { side in
            guard let arm = Self.arm(side, in: last),
                  let upperArm = ArmRaiseCounter.angle(at: arm.shoulder, last.hips, arm.elbow), upperArm >= minRaisedUpperArm
            else { return nil }
            let upperLength = hypot(arm.elbow.x - arm.shoulder.x, arm.elbow.y - arm.shoulder.y)
            guard arm.wrist.y - arm.elbow.y >= minForearmUp * upperLength else { return nil }
            return (side, arm, upperArm)
        }
        guard let (side, arm, upperArm) = candidates.max(by: { $0.1.wrist.y - $0.1.elbow.y < $1.1.wrist.y - $1.1.elbow.y })
        else { return nil }

        let forearms = recentMeasures.compactMap { Self.arm(side, in: $0).map { Double($0.wrist.y - $0.elbow.y) } }
        let upperLength = hypot(arm.elbow.x - arm.shoulder.x, arm.elbow.y - arm.shoulder.y)
        guard forearms.count == stillSamples, forearms.max()! - forearms.min()! < stillTolerance * upperLength else { return nil }
        return Start(
            side: side,
            forearm: RepCounter.median(forearms),
            lean: RepCounter.median(recentMeasures.map(\.sideLean)),
            torsoLength: RepCounter.median(recentMeasures.map(\.torsoLength)),
            upperArm: upperArm
        )
    }
}
