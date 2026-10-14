import CoreGraphics
import Foundation

/// Counts lunges seen from the front, either side.
///
/// - Forward (inline) lunge: one foot in front of the other, the hips go straight down and come back up.
///   The hips' drop is measured, in torso lengths, as for the squat.
/// - Side lunge: one leg steps out and bends while the other stays straight: the hips move sideways over the bent
///   leg. Their sideways shift is measured, in torso lengths, whichever side.
///
/// Everything is relative to the standing position, measured when the patient is still, and measured again
/// whenever they stand still between repetitions.
nonisolated struct LungeCounter: MovementCounter {
    enum Direction: Sendable {
        case forward
        case side
    }

    private struct Stance {
        let hips: CGPoint
        let torsoLength: Double
        let lean: Double
    }

    let direction: Direction
    /// Drop (forward) or shift (side) of the hips for a complete repetition, in torso lengths.
    let target: Double

    /// Measures (about 0.5 s) needed while standing still to learn the standing position.
    private let stillSamples = 8
    /// Maximum hips movement while "still", in torso lengths.
    private let stillTolerance = 0.08
    /// Torso leaning to one side, compared with standing, in torso lengths.
    private let maxSideLean: Double
    /// Leaning forward makes the torso look shorter, seen from the front.
    private let minTorsoRatio: Double
    /// By the way back, a knee must have bent under this angle, in degrees: the hips moved without a real
    /// lunge otherwise.
    private let maxBentKnee: Double
    /// Below this fraction of the standing torso length, Vision has lost the body: the frame is ignored.
    private let collapsedTorsoRatio = 0.35
    private let lostTimeout = 1.5
    private let smoothingWindow = 3

    private var stance: Stance?
    private var cycle: RepCycle
    private var recentValues: [Double] = []
    /// The most bent knee of the current repetition, in degrees.
    private var bentKnee = 180.0
    private var recentMeasures: [PoseMeasure] = []
    private var lastMeasureTime = 0.0
    private var progress = 0.0

    init(direction: Direction, target: Double) {
        self.direction = direction
        self.target = target
        switch direction {
        case .forward:
            // UI-PRMD inline lunges: correct ones lean sideways up to 0.26 and keep at least 78% of the torso
            // length; incorrect ones lean up to 0.8 and drop to 52%. Closer to the correct ones' limits,
            // Vision's noise on the shoulders would reject good lunges.
            maxSideLean = 0.25
            minTorsoRatio = 0.75
            // Correct ones bend a knee to 125° at most (front view), incorrect ones up to 168°.
            maxBentKnee = 145
        case .side:
            // Leaning forward over the bent leg is part of the side lunge (correct ones down to 56% of the torso
            // length): only the sideways lean is checked. Correct ones up to 0.47, incorrect ones up to 1.
            maxSideLean = 0.5
            minTorsoRatio = 0.45
            // Correct ones bend a knee to 148° at most (front view), incorrect ones up to 176°.
            maxBentKnee = 155
        }
        cycle = RepCycle(
            start: target * 0.35,
            target: target,
            back: target * 0.25,
            reversalMargin: target * 0.3,
            noise: target * 0.5,
            minDuration: 1.5,
            shortfall: direction == .forward ? .goLower : .lungeFurther
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
        lastMeasureTime = time
        recentMeasures.append(measure)
        if recentMeasures.count > stillSamples { recentMeasures.removeFirst() }

        guard let stance else {
            if let standing = standingPosition() {
                self.stance = standing
                return CounterUpdate(progress: 0, event: .calibrated)
            }
            return CounterUpdate(progress: 0, event: nil)
        }

        recentValues.append(value(measure, stance: stance))
        if recentValues.count > smoothingWindow { recentValues.removeFirst() }
        let value = RepCounter.median(recentValues)
        progress = max(0, value / target)

        // Standing still again, maybe a step further: follow the new position. Not lower than before
        // (forward), which would lower the bar for the next repetition.
        if cycle.phase == .rest, let standing = standingPosition(),
           direction == .side || standing.hips.y >= stance.hips.y - stillTolerance * stance.torsoLength {
            self.stance = standing
        }

        if cycle.phase == .rest { bentKnee = 180 }
        bentKnee = min(bentKnee, measure.kneeAngles.min() ?? 180)
        // The knee is judged once the patient comes back from the deepest point, where it bends most.
        let isComingBack = cycle.phase == .targetReached && value < cycle.peak - target * 0.15
        let fault: Correction? = if measure.torsoLength / stance.torsoLength < minTorsoRatio {
            .keepBackStraight
        } else if abs(measure.sideLean - stance.lean) > maxSideLean {
            .keepBackStraight
        } else if isComingBack, bentKnee > maxBentKnee {
            .bendFrontKnee
        } else {
            nil
        }
        let (event, posture) = cycle.advance(value, fault: fault, at: time)
        return CounterUpdate(progress: progress, event: event, posture: posture)
    }

    private func value(_ measure: PoseMeasure, stance: Stance) -> Double {
        switch direction {
        case .forward: (stance.hips.y - measure.hips.y) / stance.torsoLength
        case .side: abs(measure.hips.x - stance.hips.x) / stance.torsoLength
        }
    }

    /// The standing position, when the patient has been still for a moment.
    private func standingPosition() -> Stance? {
        guard recentMeasures.count == stillSamples else { return nil }
        let torsoLength = RepCounter.median(recentMeasures.map(\.torsoLength))
        guard torsoLength > 0 else { return nil }
        let xs = recentMeasures.map { Double($0.hips.x) }, ys = recentMeasures.map { Double($0.hips.y) }
        let tolerance = stillTolerance * torsoLength
        guard xs.max()! - xs.min()! < tolerance, ys.max()! - ys.min()! < tolerance else { return nil }
        return Stance(
            hips: CGPoint(x: RepCounter.median(xs), y: RepCounter.median(ys)),
            torsoLength: torsoLength,
            lean: RepCounter.median(recentMeasures.map(\.sideLean))
        )
    }
}
