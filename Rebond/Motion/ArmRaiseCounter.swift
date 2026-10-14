import CoreGraphics
import Foundation

/// Counts arm raises seen from the front: the arms go up to the target angle, then come back down along the body.
/// The angle of each arm is measured between the arm (shoulder to wrist) and the side of the body (shoulder to hip):
/// about 10–20° arms down, 90° at shoulder height, 180° straight up.
///
/// Two variants:
/// - both arms together, sideways (lateral raise): their average angle is followed and they must stay level;
/// - one arm, either side (shoulder abduction, scaption): the arm that goes up first is followed until it is back
///   down, the other may stay down or go up too. Raising one arm, patients tend to lean the torso to the other side:
///   that is checked instead of the symmetry.
nonisolated struct ArmRaiseCounter: MovementCounter {
    enum Arms: Sendable {
        /// Both arms together, kept level.
        case both
        /// One arm, whichever the patient raises (or both).
        case either
    }

    /// Angle to reach for a complete repetition, in degrees.
    let targetAngle: Double
    let arms: Arms

    /// Arms considered down at rest below this angle.
    private let restAngle = 35.0
    /// Below this angle, an attempt is too small to be worth a correction, and faults aren't looked at.
    private let noiseAngle = 50.0
    /// Maximum difference between both arms during a repetition, in degrees.
    private let maxAsymmetry = 30.0
    /// Minimum elbow angle for an arm to count as straight, in degrees.
    private let straightElbow = 130.0
    /// One arm up: maximum sideways movement of the neck relative to the hips, compared with rest, in torso lengths.
    /// UI-PRMD shoulder abductions and scaptions: correct ones stay under 0.08 (about 5° of lean), incorrect ones
    /// lean up to 0.45. 0.1 leaves a margin for Vision's noise on the shoulders.
    private let maxSideLean = 0.1
    /// Measures (about 0.5 s) needed with the arms down and still to calibrate.
    private let stillSamples = 8
    private let stillTolerance = 8.0
    private let lostTimeout = 1.5
    private let smoothingWindow = 3

    private var isCalibrated = false
    private var cycle: RepCycle
    private var recentAngles: [Double] = []
    private var stillAngles: [Double] = []
    private var stillLeans: [Double] = []
    /// Neck sideways from the hips at rest, in torso lengths: few people stand perfectly straight.
    private var restLean = 0.0
    /// One arm: the arm being raised, chosen when the repetition starts.
    private var raisedSide: Side?
    private var lastMeasureTime = 0.0
    private var progress = 0.0

    init(targetAngle: Double, arms: Arms = .both) {
        self.targetAngle = targetAngle
        self.arms = arms
        cycle = RepCycle(
            // One arm: a little more tolerant on the way down. Segmented UI-PRMD abductions often end
            // with the arm at 30–35°, and a sore shoulder may not hang fully along the body.
            start: arms == .both ? 40 : 45,
            target: targetAngle,
            back: arms == .both ? 30 : 38,
            // How far the arms must come down from their highest point to count as going back down.
            reversalMargin: 15,
            noise: noiseAngle,
            // Slower is better for the shoulder.
            minDuration: 1.5,
            shortfall: .raiseHigher
        )
    }

    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure, let both = Self.arms(in: measure) else {
            if time - lastMeasureTime > lostTimeout { cycle.abandon() }
            return CounterUpdate(progress: progress, event: nil)
        }
        lastMeasureTime = time
        let value: Double
        switch arms {
        case .both:
            value = (both.left.angle + both.right.angle) / 2
        case .either:
            // The arm left down may hang a little open (up to 30° on UI-PRMD): once a repetition starts,
            // only the raised arm is followed, until it is back down.
            if cycle.phase == .rest { raisedSide = nil }
            if raisedSide == nil, isCalibrated, max(both.left.angle, both.right.angle) >= cycle.start {
                raisedSide = both.left.angle > both.right.angle ? .left : .right
            }
            value = switch raisedSide {
            case .left: both.left.angle
            case .right: both.right.angle
            case nil: max(both.left.angle, both.right.angle)
            }
        }

        recentAngles.append(value)
        if recentAngles.count > smoothingWindow { recentAngles.removeFirst() }
        let angle = RepCounter.median(recentAngles)

        guard isCalibrated else {
            stillAngles.append(value)
            stillLeans.append(measure.sideLean)
            if stillAngles.count > stillSamples {
                stillAngles.removeFirst()
                stillLeans.removeFirst()
            }
            guard stillAngles.count == stillSamples,
                  stillAngles.allSatisfy({ $0 < restAngle }),
                  stillAngles.max()! - stillAngles.min()! < stillTolerance
            else { return CounterUpdate(progress: 0, event: nil) }
            isCalibrated = true
            restLean = RepCounter.median(stillLeans)
            return CounterUpdate(progress: 0, event: .calibrated)
        }

        progress = max(0, angle / targetAngle)
        let (event, posture) = cycle.advance(angle, fault: fault(both, measure: measure), at: time)
        return CounterUpdate(progress: progress, event: event, posture: posture)
    }

    private func fault(_ both: (left: Arm, right: Arm), measure: PoseMeasure) -> Correction? {
        let higher = max(both.left.angle, both.right.angle)
        guard higher > noiseAngle else { return nil }
        switch arms {
        case .both:
            if abs(both.left.angle - both.right.angle) > maxAsymmetry { return .raiseBothArms }
            let elbows = [both.left.elbow, both.right.elbow].compactMap { $0 }
            if elbows.contains(where: { $0 < straightElbow }) { return .keepArmsStraight }
        case .either:
            if abs(measure.sideLean - restLean) > maxSideLean { return .keepBackStraight }
            // Only the raised arms must be straight: the other one hangs as it likes.
            let raised = [both.left, both.right].filter { $0.angle > noiseAngle }
            if raised.contains(where: { ($0.elbow ?? 180) < straightElbow }) { return .keepArmStraight }
        }
        return nil
    }

    private enum Side {
        case left, right
    }

    struct Arm {
        /// Between the arm and the side of the body, in degrees.
        let angle: Double
        /// Between the upper arm and the forearm, when the elbow is seen, in degrees.
        let elbow: Double?
    }

    /// Both arms, or nil when one of them isn't seen well enough to be measured.
    /// Even for a one-arm exercise both are needed: the arm left down tells a raised arm whose wrist
    /// went out of view from a lowered one.
    static func arms(in measure: PoseMeasure) -> (left: Arm, right: Arm)? {
        guard let left = arm(shoulder: measure.leftShoulder, elbow: measure.leftElbow, wrist: measure.leftWrist, hip: measure.leftHip ?? measure.hips),
              let right = arm(shoulder: measure.rightShoulder, elbow: measure.rightElbow, wrist: measure.rightWrist, hip: measure.rightHip ?? measure.hips)
        else { return nil }
        return (left, right)
    }

    private static func arm(shoulder: CGPoint?, elbow: CGPoint?, wrist: CGPoint?, hip: CGPoint) -> Arm? {
        guard let shoulder, let wrist else { return nil }
        let angle = angle(at: shoulder, hip, wrist)
        guard let angle else { return nil }
        return Arm(angle: angle, elbow: elbow.flatMap { Self.angle(at: $0, shoulder, wrist) })
    }

    /// Angle at `vertex` between the directions to `a` and `b`, in degrees.
    static func angle(at vertex: CGPoint, _ a: CGPoint, _ b: CGPoint) -> Double? {
        let u = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let v = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
        let lengths = hypot(u.dx, u.dy) * hypot(v.dx, v.dy)
        guard lengths > 0 else { return nil }
        let cosine = Double((u.dx * v.dx + u.dy * v.dy) / lengths)
        return acos(max(-1, min(1, cosine))) * 180 / .pi
    }
}
