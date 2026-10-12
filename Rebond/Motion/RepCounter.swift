import CoreGraphics
import Foundation

nonisolated enum Correction: Sendable {
    case goLower
    case keepBackStraight
    case slowDown
    case keepFeetInPlace

    var message: LocalizedStringResource {
        switch self {
        case .goLower: "Descendez encore un peu"
        case .keepBackStraight: "Gardez le dos plus droit"
        case .slowDown: "Plus lentement"
        case .keepFeetInPlace: "Gardez les pieds en place"
        }
    }
}

nonisolated struct RepResult: Sendable {
    /// How far the hips went down, in torso lengths (range of motion).
    let depth: Double
    let tooFast: Bool
    let leanedForward: Bool

    /// The most important correction for this repetition, if any.
    var correction: Correction? {
        if leanedForward { return .keepBackStraight }
        if tooFast { return .slowDown }
        return nil
    }
}

nonisolated enum RepEvent: Sendable {
    /// The resting position has been measured for the first time: counting starts.
    case calibrated
    case repCompleted(RepResult)
    case repIncomplete(depth: Double)
    case correction(Correction)
}

nonisolated struct CounterUpdate: Sendable {
    /// 0 at rest, 1 when the target depth is reached.
    let progress: Double
    let event: RepEvent?
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
        let hipsHeight: Double
        let torsoLength: Double
        let lean: Double
        let leftAnkle: CGPoint?
        let rightAnkle: CGPoint?
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
    /// A repetition is cancelled when the body isn't measured for this long, in seconds.
    private let lostTimeout = 1.5
    /// Torso lean beyond the resting lean that triggers a correction, in degrees.
    private let maxLeanIncrease = 45.0
    /// Seconds from the start of the descent to the return to rest.
    private let minRepDuration = 1.2

    private var recentHips: [Double] = []
    private var recentMeasures: [PoseMeasure] = []
    private var phase = Phase.calibrating
    private var rest = Rest(hipsHeight: 0, torsoLength: 1, lean: 0, leftAnkle: nil, rightAnkle: nil)
    private var maxDepth = 0.0
    private var maxLean = 0.0
    private var repStart = 0.0
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
        return CounterUpdate(progress: progress, event: event)
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
        let candidate = Rest(
            hipsHeight: Self.median(hips),
            torsoLength: torsoLength,
            lean: Self.median(recentMeasures.map(\.torsoLean)),
            leftAnkle: last.leftAnkle,
            rightAnkle: last.rightAnkle
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
            maxDepth = max(maxDepth, depth)
            maxLean = max(maxLean, measure.torsoLean)
            if feetMoved(measure) {
                phase = .cancelled
                return maxDepth >= noiseDepth ? .correction(.keepFeetInPlace) : nil
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
                maxLean = measure.torsoLean
                repStart = time
            }
        case .descending:
            if depth >= exercise.targetDepth {
                phase = .bottomReached
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
                return .repCompleted(RepResult(
                    depth: maxDepth,
                    tooFast: time - repStart < minRepDuration,
                    leanedForward: maxLean - rest.lean > maxLeanIncrease
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
