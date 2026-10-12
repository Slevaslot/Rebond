import Foundation

nonisolated enum Correction: Sendable {
    case goLower
    case keepBackStraight
    case slowDown

    var message: LocalizedStringResource {
        switch self {
        case .goLower: "Descendez encore un peu"
        case .keepBackStraight: "Gardez le dos plus droit"
        case .slowDown: "Plus lentement"
        }
    }
}

nonisolated struct RepResult: Sendable {
    /// Lowest angle reached (range of motion), in degrees.
    let bestAngle: Double
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
    /// The resting position has been measured: counting starts.
    case calibrated
    case repCompleted(RepResult)
    case repIncomplete(bestAngle: Double)
    case correction(Correction)
}

nonisolated struct CounterUpdate: Sendable {
    /// 0 at rest, 1 when the target depth is reached.
    let progress: Double
    let event: RepEvent?
}

/// Counts repetitions from a stream of measures.
/// Pure logic: can be tested by feeding recorded measures.
///
/// A repetition needs two independent signs at the same time:
/// both knees bending together (3D pose) and the upper body going down in the image (2D pose).
/// The 3D legs alone can't be trusted: Vision guesses them when they are hidden or blurred.
nonisolated struct RepCounter {
    private enum Phase {
        case calibrating
        case rest
        case descending
        case bottomReached
        /// Came back up before reaching the target depth.
        case risingTooEarly
    }

    private struct Sample {
        let angle: Double
        let lean: Double
        let neckHeight: Double
        let torsoLength: Double
    }

    let exercise: CatalogExercise

    /// Median over a few measures removes isolated detection errors.
    private let smoothingWindow = 3
    /// Measures needed while standing still to learn the resting position.
    private let calibrationSamples = 5
    private let calibrationTolerance = 15.0
    /// Maximum difference between both knees. Beyond, one leg moves alone
    /// (walking, lunge, knee lift) or Vision guessed wrong: the measure is ignored.
    private let symmetryTolerance = 35.0
    /// How far below the resting angle the movement counts as started.
    private let startMargin = 20.0
    /// How close to the resting angle the patient must come back to finish the repetition.
    private let returnMargin = 15.0
    /// How far the angle must rise from its lowest point to count as coming back up.
    private let reversalMargin = 15.0
    /// How far the neck must go down at the bottom, in torso lengths.
    private let minNeckDrop = 0.4
    /// Below this neck drop, the attempt didn't move the body at all: it is ignored without correction.
    private let noiseNeckDrop = 0.15
    /// Neck drop under which the patient is back up, in torso lengths.
    private let maxNeckDropAtRest = 0.2
    /// A repetition is cancelled when the body isn't measured for this long, in seconds.
    private let lostTimeout = 1.5
    /// Torso lean beyond the resting lean that triggers a correction, in degrees.
    private let maxLeanIncrease = 45.0
    /// Seconds from the start of the descent to the return to rest.
    private let minRepDuration = 1.2

    private var recentAngles: [Double] = []
    private var recentNecks: [Double] = []
    private var calibration: [Sample] = []
    private var phase = Phase.calibrating
    private var rest = Sample(angle: 0, lean: 0, neckHeight: 0, torsoLength: 1)
    private var bestAngle = Double.infinity
    private var maxNeckDrop = 0.0
    private var maxLean = 0.0
    private var repStart = 0.0
    private var lastValidTime = 0.0
    private var progress = 0.0

    init(exercise: CatalogExercise) {
        self.exercise = exercise
    }

    /// Target adapted to the patient: never asks for less than 45° of flexion from their resting angle.
    private var targetAngle: Double {
        min(exercise.targetAngle, rest.angle - 45)
    }

    private var isInRepetition: Bool {
        phase == .descending || phase == .bottomReached || phase == .risingTooEarly
    }

    mutating func process(_ measure: PoseMeasure, at time: Double) -> CounterUpdate {
        guard let maxAngle = measure.angles.max(), let minAngle = measure.angles.min(),
              maxAngle - minAngle <= symmetryTolerance,
              let neckHeight = measure.neckHeight
        else {
            cancelIfLost(at: time)
            return CounterUpdate(progress: progress, event: nil)
        }
        cancelIfLost(at: time)
        lastValidTime = time

        recentAngles.append((maxAngle + minAngle) / 2)
        recentNecks.append(neckHeight)
        if recentAngles.count > smoothingWindow {
            recentAngles.removeFirst()
            recentNecks.removeFirst()
        }
        let angle = Self.median(recentAngles)
        let neck = Self.median(recentNecks)

        if phase == .calibrating {
            guard let torsoLength = measure.torsoLength else {
                return CounterUpdate(progress: 0, event: nil)
            }
            let sample = Sample(angle: angle, lean: measure.torsoLean, neckHeight: neck, torsoLength: torsoLength)
            return CounterUpdate(progress: 0, event: calibrate(with: sample))
        }

        let neckDrop = (rest.neckHeight - neck) / rest.torsoLength
        // Both signs must agree for the gauge to reach the target.
        let angleProgress = (rest.angle - angle) / (rest.angle - targetAngle)
        progress = max(0, min(angleProgress, neckDrop / minNeckDrop))
        let event = advance(angle: angle, neckDrop: neckDrop, lean: measure.torsoLean, time: time)
        return CounterUpdate(progress: progress, event: event)
    }

    private mutating func calibrate(with sample: Sample) -> RepEvent? {
        calibration.append(sample)
        if calibration.count > calibrationSamples {
            calibration.removeFirst()
        }
        guard calibration.count == calibrationSamples else { return nil }

        let angles = calibration.map(\.angle)
        let necks = calibration.map(\.neckHeight)
        let torsoLength = Self.median(calibration.map(\.torsoLength))
        let isStill = angles.max()! - angles.min()! < calibrationTolerance
            && necks.max()! - necks.min()! < torsoLength * 0.1
        let isStanding = Self.median(angles) > exercise.targetAngle + 40
        guard isStill, isStanding else { return nil }

        rest = Sample(
            angle: Self.median(angles),
            lean: Self.median(calibration.map(\.lean)),
            neckHeight: Self.median(necks),
            torsoLength: torsoLength
        )
        phase = .rest
        return .calibrated
    }

    private mutating func advance(angle: Double, neckDrop: Double, lean: Double, time: Double) -> RepEvent? {
        let reachedBottom = angle <= targetAngle && neckDrop >= minNeckDrop
        let backUp = angle >= rest.angle - returnMargin && neckDrop <= maxNeckDropAtRest

        switch phase {
        case .calibrating:
            break
        case .rest:
            if angle < rest.angle - startMargin {
                phase = .descending
                bestAngle = angle
                maxNeckDrop = neckDrop
                maxLean = lean
                repStart = time
            }
        case .descending:
            track(angle: angle, neckDrop: neckDrop, lean: lean)
            if reachedBottom {
                phase = .bottomReached
            } else if angle > bestAngle + reversalMargin {
                guard maxNeckDrop >= noiseNeckDrop else {
                    // The knees "moved" but the body didn't go down: a detection error, not an attempt.
                    phase = .rest
                    return nil
                }
                phase = .risingTooEarly
                return .correction(.goLower)
            }
        case .bottomReached:
            track(angle: angle, neckDrop: neckDrop, lean: lean)
            if backUp {
                phase = .rest
                return .repCompleted(RepResult(
                    bestAngle: bestAngle,
                    tooFast: time - repStart < minRepDuration,
                    leanedForward: maxLean - rest.lean > maxLeanIncrease
                ))
            }
        case .risingTooEarly:
            track(angle: angle, neckDrop: neckDrop, lean: lean)
            if reachedBottom {
                phase = .bottomReached
            } else if backUp {
                phase = .rest
                return .repIncomplete(bestAngle: bestAngle)
            }
        }
        return nil
    }

    private mutating func track(angle: Double, neckDrop: Double, lean: Double) {
        bestAngle = min(bestAngle, angle)
        maxNeckDrop = max(maxNeckDrop, neckDrop)
        maxLean = max(maxLean, lean)
    }

    /// Drops the repetition in progress when the body has been lost for too long.
    private mutating func cancelIfLost(at time: Double) {
        guard isInRepetition, time - lastValidTime > lostTimeout else { return }
        phase = .rest
        recentAngles.removeAll()
        recentNecks.removeAll()
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}
