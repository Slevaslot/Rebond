import CoreGraphics
import Foundation

/// Counts standing straight leg raises, seen from the front: one leg, either side, goes up in front of the body
/// with the knee straight, then comes back down next to the other.
///
/// The phone stands at hip height, in front: the raised leg comes toward it, so the ankle hardly rises on screen
/// until the leg is well up (it even looks a little lower first, being closer). The knee, nearer the hip,
/// rises steadily: the raise is measured as the knee coming up toward the hip, in torso lengths
/// (about 0.15 at 45°, 0.3 at 55°, 0.6 at 75°, 0.9 with the thigh level, from 2–3 m).
///
/// A bent knee can't be seen in the knee angle from the front (hip, knee and ankle stay on one vertical line),
/// but in the heights: once the thigh is well up, a straight leg brings the ankle up at least as much as the knee,
/// while a shin left hanging keeps the ankle low.
///
/// The hurdle step (knee raise) is the same movement with the knee bent: the knee is followed the same way,
/// the bent knee is expected, and leaning the torso forward is checked instead.
nonisolated struct LegRaiseCounter: MovementCounter {
    enum Style: Sendable {
        /// Straight leg raise: the knee must stay straight.
        case straightLeg
        /// Hurdle step: the knee comes up bent, as when stepping over an obstacle.
        case bentKnee
    }

    private struct Leg {
        /// Hip height above the knee, standing.
        let thigh: Double
        let knee: CGPoint
        let ankle: CGPoint?
    }

    private struct Stance {
        let hipsHeight: Double
        let torsoLength: Double
        let lean: Double
        let left: Leg
        let right: Leg
    }

    private enum Side {
        case left, right
    }

    /// How far the knee must come up toward the hip for a complete repetition, in torso lengths.
    let targetLift: Double
    let style: Style

    /// Measures (about 0.5 s) needed while standing still to learn the standing position.
    private let stillSamples = 8
    /// Maximum hips and knees movement while "still", in torso lengths.
    private let stillTolerance = 0.1
    /// Maximum height difference between the knees, or the ankles, while standing, in torso lengths.
    /// Seen from hip height, a foot slightly in front of the other already looks a little lower.
    private let maxLevelGap = 0.25
    /// Minimum knee angle for a leg to count as straight while standing, in degrees.
    private let straightLeg = 150.0
    /// From this knee lift on (thigh at about 55°), the ankle tells a straight leg from a bent one.
    private let kneeCheckLift = 0.3
    /// Ankle rise over knee rise under which the knee is bent, once the thigh is well up:
    /// 1.1 or more with a straight leg, 0.5 or less with the shin hanging (2.5 m, hip height).
    private let minAnkleToKneeRise = 0.7
    /// The hips going down means the standing leg bends. UI-PRMD: correct raises stay under 0.15 torso lengths.
    private let maxHipsDrop = 0.15
    /// Torso leaning to one side over the standing leg, compared with standing, in torso lengths.
    /// UI-PRMD: correct raises up to 0.22 (shifting the weight is normal), incorrect ones up to 0.5.
    private let maxSideLean = 0.25
    /// Bent knee: UI-PRMD correct hurdle steps lean up to 0.19, incorrect ones up to 0.6.
    private let maxSideLeanBentKnee = 0.2
    /// Bent knee: leaning forward makes the torso look shorter, seen from the front. UI-PRMD hurdle steps:
    /// correct ones keep at least 93% of the standing length, incorrect ones drop to 61%.
    private let minTorsoRatio = 0.88
    /// Below this fraction of the standing torso length, Vision has lost the body: the frame is ignored.
    private let collapsedTorsoRatio = 0.5
    private let lostTimeout = 1.5
    private let smoothingWindow = 3

    private var stance: Stance?
    private var cycle: RepCycle
    /// The leg being raised, chosen when the repetition starts.
    private var side: Side?
    private var recentLifts: [Double] = []
    private var recentMeasures: [PoseMeasure] = []
    private var lastMeasureTime = 0.0
    private var progress = 0.0

    init(targetLift: Double, style: Style = .straightLeg) {
        self.targetLift = targetLift
        self.style = style
        cycle = RepCycle(
            start: targetLift * 0.35,
            target: targetLift,
            back: targetLift * 0.25,
            reversalMargin: targetLift * 0.3,
            noise: targetLift * 0.5,
            minDuration: 1.5,
            shortfall: style == .straightLeg ? .raiseLegHigher : .raiseKneeHigher
        )
    }

    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure else {
            if time - lastMeasureTime > lostTimeout { cycle.abandon() }
            return CounterUpdate(progress: progress, event: nil)
        }
        if let stance, measure.torsoLength / stance.torsoLength < collapsedTorsoRatio {
            return CounterUpdate(progress: progress, event: nil, posture: cycle.posture)
        }
        recentMeasures.append(measure)
        if recentMeasures.count > stillSamples { recentMeasures.removeFirst() }

        guard var stance else {
            lastMeasureTime = time
            if let standing = standingPosition() {
                self.stance = standing
                return CounterUpdate(progress: 0, event: .calibrated)
            }
            return CounterUpdate(progress: 0, event: nil)
        }

        var lifts = Self.lifts(in: measure, stance: stance)
        if cycle.phase == .rest {
            side = nil
            // Standing still on both feet again, maybe somewhere else: follow the new position.
            // Not with a knee already a little up, which would lower the bar for the next raise.
            if let standing = standingPosition(), isNewStance(standing, comparedWith: stance) {
                stance = standing
                self.stance = standing
                lifts = Self.lifts(in: measure, stance: standing)
            }
        }
        if side == nil, let left = lifts.left, let right = lifts.right, max(left, right) >= cycle.start {
            side = left > right ? .left : .right
        }
        // Following one leg: if its knee is lost, wait rather than read the other one.
        let lift: Double?
        switch side {
        case .left: lift = lifts.left
        case .right: lift = lifts.right
        case nil:
            if let left = lifts.left, let right = lifts.right { lift = max(left, right) } else { lift = nil }
        }
        guard let lift else {
            if time - lastMeasureTime > lostTimeout { cycle.abandon() }
            return CounterUpdate(progress: progress, event: nil, posture: cycle.posture)
        }
        lastMeasureTime = time

        recentLifts.append(lift)
        if recentLifts.count > smoothingWindow { recentLifts.removeFirst() }
        let smoothed = RepCounter.median(recentLifts)
        progress = max(0, smoothed / targetLift)

        let isGoingUp = smoothed >= cycle.peak - 0.05
        let (event, posture) = cycle.advance(smoothed, fault: fault(measure, lift: lift, isGoingUp: isGoingUp, stance: stance), at: time)
        return CounterUpdate(progress: progress, event: event, posture: posture)
    }

    /// A still standing position replaces the current one when the knees aren't higher (a raise starting slowly
    /// looks still for a moment), or when the patient moved elsewhere.
    private func isNewStance(_ candidate: Stance, comparedWith stance: Stance) -> Bool {
        // No tolerance: one step at a time, a slow raise would otherwise drag the standing position up with it.
        let kneesNotHigher = candidate.left.thigh >= stance.left.thigh && candidate.right.thigh >= stance.right.thigh
        let moved = abs(candidate.hipsHeight - stance.hipsHeight) > stillTolerance * stance.torsoLength
        return kneesNotHigher || moved
    }

    /// How far each knee came up toward its hip, in torso lengths.
    private static func lifts(in measure: PoseMeasure, stance: Stance) -> (left: Double?, right: Double?) {
        (
            left: lift(hip: measure.leftHip ?? measure.hips, knee: measure.leftKnee, leg: stance.left, torso: stance.torsoLength),
            right: lift(hip: measure.rightHip ?? measure.hips, knee: measure.rightKnee, leg: stance.right, torso: stance.torsoLength)
        )
    }

    /// How far the knee came up toward the hip, in torso lengths.
    private static func lift(hip: CGPoint, knee: CGPoint?, leg: Leg, torso: Double) -> Double? {
        guard let knee else { return nil }
        return (leg.thigh - (hip.y - knee.y)) / torso
    }

    private func fault(_ measure: PoseMeasure, lift: Double, isGoingUp: Bool, stance: Stance) -> Correction? {
        if (stance.hipsHeight - measure.hips.y) / stance.torsoLength > maxHipsDrop {
            return .keepStandingLegStraight
        }
        if abs(measure.sideLean - stance.lean) > (style == .bentKnee ? maxSideLeanBentKnee : maxSideLean) {
            return .keepBackStraight
        }
        if style == .bentKnee {
            return measure.torsoLength / stance.torsoLength < minTorsoRatio ? .keepBackStraight : nil
        }
        // The knee is judged on the way up only: many lower the leg bending the knee a little
        // (UI-PRMD correct raises included), which doesn't take anything from the raise.
        let leg = side == .left ? stance.left : stance.right
        let knee = side == .left ? measure.leftKnee : measure.rightKnee
        let ankle = side == .left ? measure.leftAnkle : measure.rightAnkle
        if isGoingUp, lift >= kneeCheckLift, let knee, let ankle, let standingAnkle = leg.ankle {
            let kneeRise = knee.y - leg.knee.y
            let ankleRise = ankle.y - standingAnkle.y
            if kneeRise > 0, ankleRise / kneeRise < minAnkleToKneeRise {
                return .keepLegStraight
            }
        }
        return nil
    }

    /// The standing position, when the patient has been still for a moment on both feet, legs straight.
    private func standingPosition() -> Stance? {
        guard recentMeasures.count == stillSamples else { return nil }
        let torsoLength = RepCounter.median(recentMeasures.map(\.torsoLength))
        guard torsoLength > 0 else { return nil }
        let tolerance = stillTolerance * torsoLength
        func isStill(_ values: [Double]) -> Bool {
            values.count == stillSamples && values.max()! - values.min()! < tolerance
        }
        let hips = recentMeasures.map { Double($0.hips.y) }
        let leftKnees = recentMeasures.compactMap { $0.leftKnee.map { Double($0.y) } }
        let rightKnees = recentMeasures.compactMap { $0.rightKnee.map { Double($0.y) } }
        guard isStill(hips), isStill(leftKnees), isStill(rightKnees) else { return nil }

        let last = recentMeasures.last!
        guard let leftKnee = last.leftKnee, let rightKnee = last.rightKnee,
              // Both feet on the floor: a leg held up isn't a standing position.
              abs(leftKnee.y - rightKnee.y) < maxLevelGap * torsoLength,
              last.kneeAngles.allSatisfy({ $0 >= straightLeg })
        else { return nil }
        if let leftAnkle = last.leftAnkle, let rightAnkle = last.rightAnkle,
           abs(leftAnkle.y - rightAnkle.y) >= maxLevelGap * torsoLength {
            return nil
        }
        // Medians over the still moment: a single noisy frame doesn't set the standing position.
        func thigh(_ hip: (PoseMeasure) -> CGPoint?, _ knee: (PoseMeasure) -> CGPoint?) -> Double {
            RepCounter.median(recentMeasures.compactMap { measure in
                knee(measure).map { Double((hip(measure) ?? measure.hips).y - $0.y) }
            })
        }
        return Stance(
            hipsHeight: RepCounter.median(hips),
            torsoLength: torsoLength,
            lean: RepCounter.median(recentMeasures.map(\.sideLean)),
            left: Leg(thigh: thigh(\.leftHip, \.leftKnee), knee: leftKnee, ankle: last.leftAnkle),
            right: Leg(thigh: thigh(\.rightHip, \.rightKnee), knee: rightKnee, ankle: last.rightAnkle)
        )
    }
}
