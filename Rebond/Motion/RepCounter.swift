import CoreGraphics
import Foundation

nonisolated enum Correction: Sendable {
    case goLower
    case keepBackStraight
    case slowDown
    case keepFeetInPlace
    case bendBothKnees
    case showBothLegs

    var message: LocalizedStringResource {
        switch self {
        case .goLower: "Descendez encore un peu"
        case .keepBackStraight: "Gardez le buste plus droit"
        case .slowDown: "Plus lentement"
        case .keepFeetInPlace: "Gardez les pieds en place"
        case .bendBothKnees: "Pliez les deux genoux ensemble"
        case .showBothLegs: "Je ne vois pas vos deux jambes"
        }
    }
}

nonisolated struct RepResult: Sendable {
    /// How far the hips went down, in torso lengths (range of motion).
    let depth: Double
    let tooFast: Bool
    /// Already said during the movement, kept for the report.
    let leanedForward: Bool
}

nonisolated enum RepEvent: Sendable {
    /// The resting position has been measured for the first time: counting starts.
    case calibrated
    /// The target depth is reached: time to come back up.
    case bottomReached
    case repCompleted(RepResult)
    case repIncomplete(depth: Double)
    case correction(Correction)
}

nonisolated struct CounterUpdate: Sendable {
    /// 0 at rest, 1 when the target depth is reached.
    let progress: Double
    let event: RepEvent?
    /// Posture problem visible right now, to highlight on the body.
    var posture: Correction? = nil
}

/// Counts repetitions from a stream of 2D measures.
/// Pure logic: can be tested by feeding recorded measures.
///
/// A repetition is the hips going down by `targetDepth` torso lengths and coming back up,
/// feet staying in place. Everything is relative to the patient's resting position,
/// measured again whenever they stand still.
nonisolated struct RepCounter {
    private enum Phase {
        case calibrating
        case rest
        case descending
        case bottomReached
        /// Came back up before reaching the target depth.
        case risingTooEarly
        /// The feet moved during the repetition: waiting for the patient to settle again.
        case cancelled
    }

    private struct Rest {
        let hipsX: Double
        let hipsHeight: Double
        let torsoLength: Double
        let lean: Double
        let leftAnkle: CGPoint?
        let rightAnkle: CGPoint?
        /// Distance between the ankles, when both were visible.
        let stance: Double?
    }

    let exercise: CatalogExercise

    /// Median over a few measures removes isolated detection errors.
    private let smoothingWindow = 3
    /// Measures (about 0.5 s) needed while standing still to learn the resting position.
    private let stillSamples = 8
    /// Maximum hips movement while "still", in torso lengths.
    private let stillTolerance = 0.1
    /// Hips drop at which a repetition starts, in torso lengths.
    private let startDepth = 0.25
    /// Hips drop under which the patient is back up, in torso lengths.
    private let returnDepth = 0.2
    /// How far the hips must rise from their lowest point to count as coming back up.
    private let reversalMargin = 0.2
    /// Below this depth, an attempt is too small to be worth a correction.
    private let noiseDepth = 0.4
    /// Maximum ankle movement during a repetition, in torso lengths. Beyond: a step, a lunge, walking.
    private let feetTolerance = 0.5
    /// Maximum widening of the stance during a repetition, in torso lengths.
    private let stanceTolerance = 0.25
    /// Maximum distance between the ankles during a repetition, in torso lengths. Beyond: a lunge or a sumo squat.
    private let maxStance = 1.0
    /// Maximum height difference between the knees, in torso lengths. Beyond: a lunge, one knee going down.
    private let maxKneeGap = 0.4
    /// Maximum horizontal movement of the hips, in torso lengths. Beyond: a side lunge.
    private let maxHipShiftFacing = 0.35
    /// Seen from the side, sitting back in a deep squat moves the hips up to about 0.7, but only as they go down:
    /// the allowed movement grows with the depth reached.
    private let hipShiftSidewaysBase = 0.35
    private let hipShiftSidewaysPerDepth = 0.5
    /// Hips width on screen, in torso lengths, above which the patient faces the camera.
    /// Measured with Vision: about 0.4 from the front, 0.1 to 0.2 from the side (noisy, hence the median).
    private let facingHipWidth = 0.25
    /// Minimum knee angle for a leg to count as straight, in degrees.
    private let straightLeg = 150.0
    /// A repetition is cancelled when the body isn't measured for this long, in seconds.
    private let lostTimeout = 1.5
    /// Torso lean beyond the resting lean that triggers a correction, in degrees: leaning forward seen
    /// from the side, tilting sideways seen from the front. Set from the UI-PRMD deep squats
    /// (correct squats: 90% under 47° from the side and 14° from the front).
    private let maxLeanIncreaseSideways = 55.0
    private let maxLeanIncreaseFacing = 25.0
    /// Seconds from the start of the descent to the return to rest.
    private let minRepDuration = 1.2

    private var recentHips: [Double] = []
    private var recentMeasures: [PoseMeasure] = []
    private var phase = Phase.calibrating
    private var rest = Rest(hipsX: 0, hipsHeight: 0, torsoLength: 1, lean: 0, leftAnkle: nil, rightAnkle: nil, stance: nil)
    private var maxDepth = 0.0
    private var repStart = 0.0
    /// Whether the patient faced the camera when the repetition started: some limits depend on the view.
    private var repFacingCamera = true
    /// The lean correction is said once per repetition, as soon as it happens.
    private var leanWarned = false
    /// Facing the camera, the checks comparing both legs need both knees seen at the bottom,
    /// otherwise a lunge or a collapsed squat would slip through unchecked.
    private var sawBothKneesAtBottom = false
    private var lastMeasureTime = 0.0
    private var progress = 0.0

    init(exercise: CatalogExercise) {
        self.exercise = exercise
    }

    private var isInRepetition: Bool {
        phase == .descending || phase == .bottomReached || phase == .risingTooEarly
    }

    /// Call for every frame, with nil when the body isn't measured.
    mutating func process(_ measure: PoseMeasure?, at time: Double) -> CounterUpdate {
        guard let measure else {
            if isInRepetition, time - lastMeasureTime > lostTimeout {
                phase = .rest
            }
            return CounterUpdate(progress: progress, event: nil)
        }
        lastMeasureTime = time

        recentHips.append(measure.hips.y)
        if recentHips.count > smoothingWindow { recentHips.removeFirst() }
        recentMeasures.append(measure)
        if recentMeasures.count > stillSamples { recentMeasures.removeFirst() }

        if let event = updateRestIfStill() {
            return CounterUpdate(progress: 0, event: event)
        }
        guard phase != .calibrating else { return CounterUpdate(progress: 0, event: nil) }

        let depth = (rest.hipsHeight - Self.median(recentHips)) / rest.torsoLength
        progress = max(0, depth / exercise.targetDepth)
        let event = advance(depth: depth, measure: measure, time: time)
        let leaning = isInRepetition && isLeaning(measure)
        if leaning, event == nil, !leanWarned {
            leanWarned = true
            return CounterUpdate(progress: progress, event: .correction(.keepBackStraight), posture: .keepBackStraight)
        }
        return CounterUpdate(progress: progress, event: event, posture: leaning ? .keepBackStraight : nil)
    }

    /// Learns the resting position when the patient stands still,
    /// at the start and again whenever they settle somewhere else.
    private mutating func updateRestIfStill() -> RepEvent? {
        guard phase == .calibrating || phase == .rest || phase == .cancelled,
              recentMeasures.count == stillSamples
        else { return nil }

        let torsoLength = Self.median(recentMeasures.map(\.torsoLength))
        let hips = recentMeasures.map { Double($0.hips.y) }
        guard torsoLength > 0, hips.max()! - hips.min()! < stillTolerance * torsoLength else { return nil }

        let last = recentMeasures.last!
        let kneeAngles = last.kneeAngles
        let legsStraight = kneeAngles.allSatisfy { $0 >= straightLeg }
        // A held lunge is still, but isn't a resting position. Legs hidden can only be accepted at the very start.
        guard legsStraight, !kneeAngles.isEmpty || phase == .calibrating else { return nil }

        let stances = recentMeasures.compactMap { measure -> Double? in
            guard let left = measure.leftAnkle, let right = measure.rightAnkle else { return nil }
            return hypot(left.x - right.x, left.y - right.y)
        }
        let candidate = Rest(
            hipsX: Self.median(recentMeasures.map { Double($0.hips.x) }),
            hipsHeight: Self.median(hips),
            torsoLength: torsoLength,
            lean: Self.median(recentMeasures.map(\.torsoLean)),
            leftAnkle: last.leftAnkle,
            rightAnkle: last.rightAnkle,
            stance: stances.isEmpty ? nil : Self.median(stances)
        )

        switch phase {
        case .calibrating:
            rest = candidate
            phase = .rest
            return .calibrated
        case .rest:
            // Don't take a held half squat for the new resting position, unless the patient moved elsewhere.
            let notLower = candidate.hipsHeight >= rest.hipsHeight - stillTolerance * rest.torsoLength
            if notLower || feetMoved(last) { rest = candidate }
        default:
            rest = candidate
            phase = .rest
        }
        return nil
    }

    private mutating func advance(depth: Double, measure: PoseMeasure, time: Double) -> RepEvent? {
        if isInRepetition {
            if depth >= exercise.targetDepth * 0.8, measure.leftKnee != nil, measure.rightKnee != nil {
                sawBothKneesAtBottom = true
            }
            maxDepth = max(maxDepth, depth)
            if let fault = fault(in: measure, depth: depth) {
                phase = .cancelled
                return .correction(fault)
            }
        }

        switch phase {
        case .calibrating:
            break
        case .cancelled:
            // Back up with the feet where they were: resume without waiting to stand still.
            if depth <= returnDepth, !feetMoved(measure) {
                phase = .rest
            }
        case .rest:
            if depth >= startDepth {
                phase = .descending
                maxDepth = depth
                repStart = time
                repFacingCamera = isFacingCamera()
                leanWarned = false
                sawBothKneesAtBottom = false
            }
        case .descending:
            if depth >= exercise.targetDepth {
                phase = .bottomReached
                return .bottomReached
            } else if depth < maxDepth - reversalMargin {
                guard maxDepth >= noiseDepth else {
                    phase = .rest
                    return nil
                }
                phase = .risingTooEarly
                return .correction(.goLower)
            }
        case .bottomReached:
            if depth <= returnDepth {
                phase = .rest
                if repFacingCamera, !sawBothKneesAtBottom {
                    return .correction(.showBothLegs)
                }
                return .repCompleted(RepResult(
                    depth: maxDepth,
                    tooFast: time - repStart < minRepDuration,
                    leanedForward: leanWarned
                ))
            }
        case .risingTooEarly:
            if depth >= exercise.targetDepth {
                phase = .bottomReached
            } else if depth <= returnDepth {
                phase = .rest
                return .repIncomplete(depth: maxDepth)
            }
        }
        return nil
    }

    /// What makes this frame something else than a squat: one knee lower than the other (lunge),
    /// or feet moving or spreading (step, lunge, sumo squat). Measured against the standing torso,
    /// which doesn't shrink when the patient leans forward.
    private func fault(in measure: PoseMeasure, depth: Double) -> Correction? {
        if let leftKnee = measure.leftKnee, let rightKnee = measure.rightKnee,
           abs(leftKnee.y - rightKnee.y) / rest.torsoLength > maxKneeGap {
            return .bendBothKnees
        }
        let maxHipShift = repFacingCamera
            ? maxHipShiftFacing
            : hipShiftSidewaysBase + hipShiftSidewaysPerDepth * max(0, depth)
        if feetMoved(measure) || abs(measure.hips.x - rest.hipsX) / rest.torsoLength > maxHipShift {
            return .keepFeetInPlace
        }
        if let leftAnkle = measure.leftAnkle, let rightAnkle = measure.rightAnkle {
            let stance = hypot(leftAnkle.x - rightAnkle.x, leftAnkle.y - rightAnkle.y) / rest.torsoLength
            if stance > maxStance { return .keepFeetInPlace }
            if let restStance = rest.stance, stance - restStance / rest.torsoLength > stanceTolerance {
                return .keepFeetInPlace
            }
        }
        return nil
    }

    private func isLeaning(_ measure: PoseMeasure) -> Bool {
        measure.torsoLean - rest.lean > (repFacingCamera ? maxLeanIncreaseFacing : maxLeanIncreaseSideways)
    }

    /// Seen from the front, both hips are apart on screen; seen from the side, they overlap.
    private func isFacingCamera() -> Bool {
        let widths = recentMeasures.compactMap { measure -> Double? in
            guard let left = measure.leftHip, let right = measure.rightHip else { return nil }
            return abs(left.x - right.x) / rest.torsoLength
        }
        guard !widths.isEmpty else { return true }
        return Self.median(widths) >= facingHipWidth
    }

    /// True when a visible ankle moved away from its resting position.
    private func feetMoved(_ measure: PoseMeasure) -> Bool {
        let limit = feetTolerance * rest.torsoLength
        for (now, before) in [(measure.leftAnkle, rest.leftAnkle), (measure.rightAnkle, rest.rightAnkle)] {
            if let now, let before, hypot(now.x - before.x, now.y - before.y) > limit {
                return true
            }
        }
        return false
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
