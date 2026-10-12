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
nonisolated struct RepCounter {
    private enum Phase {
        case calibrating
        case rest
        case descending
        case bottomReached
        /// Came back up before reaching the target angle.
        case risingTooEarly
    }

    let exercise: CatalogExercise

    /// Median over a few measures removes isolated detection errors.
    private let smoothingWindow = 3
    /// Measures needed while standing still to learn the resting angle.
    private let calibrationSamples = 5
    private let calibrationTolerance = 15.0
    /// How far below the resting angle the movement counts as started.
    private let startMargin = 20.0
    /// How close to the resting angle the patient must come back to finish the repetition.
    private let returnMargin = 15.0
    /// How far the angle must rise from its lowest point to count as coming back up.
    private let reversalMargin = 15.0
    /// Torso lean beyond the resting lean that triggers a correction, in degrees.
    private let maxLeanIncrease = 45.0
    /// Seconds from the start of the descent to the return to rest.
    private let minRepDuration = 1.2

    private var recentAngles: [Double] = []
    private var calibration: [(angle: Double, lean: Double)] = []
    private var phase = Phase.calibrating
    private var restAngle = 0.0
    private var restLean = 0.0
    private var bestAngle = Double.infinity
    private var maxLean = 0.0
    private var repStart = 0.0

    init(exercise: CatalogExercise) {
        self.exercise = exercise
    }

    /// Target adapted to the patient: never asks for less than 45° of flexion from their resting angle.
    private var targetAngle: Double {
        min(exercise.targetAngle, restAngle - 45)
    }

    mutating func process(_ measure: PoseMeasure, at time: Double) -> CounterUpdate {
        recentAngles.append(measure.angle)
        if recentAngles.count > smoothingWindow {
            recentAngles.removeFirst()
        }
        let smoothed = Self.median(recentAngles)

        if phase == .calibrating {
            return CounterUpdate(progress: 0, event: calibrate(angle: smoothed, lean: measure.torsoLean))
        }
        let progress = max(0, (restAngle - smoothed) / (restAngle - targetAngle))
        return CounterUpdate(progress: progress, event: advance(angle: smoothed, lean: measure.torsoLean, time: time))
    }

    private mutating func calibrate(angle: Double, lean: Double) -> RepEvent? {
        calibration.append((angle, lean))
        if calibration.count > calibrationSamples {
            calibration.removeFirst()
        }
        guard calibration.count == calibrationSamples else { return nil }

        let angles = calibration.map(\.angle)
        let isStill = angles.max()! - angles.min()! < calibrationTolerance
        let isStanding = Self.median(angles) > exercise.targetAngle + 40
        guard isStill, isStanding else { return nil }

        restAngle = Self.median(angles)
        restLean = Self.median(calibration.map(\.lean))
        phase = .rest
        return .calibrated
    }

    private mutating func advance(angle: Double, lean: Double, time: Double) -> RepEvent? {
        switch phase {
        case .calibrating:
            break
        case .rest:
            if angle < restAngle - startMargin {
                phase = .descending
                bestAngle = angle
                maxLean = lean
                repStart = time
            }
        case .descending:
            track(angle: angle, lean: lean)
            if angle <= targetAngle {
                phase = .bottomReached
            } else if angle > bestAngle + reversalMargin {
                phase = .risingTooEarly
                return .correction(.goLower)
            }
        case .bottomReached:
            track(angle: angle, lean: lean)
            if angle >= restAngle - returnMargin {
                phase = .rest
                return .repCompleted(RepResult(
                    bestAngle: bestAngle,
                    tooFast: time - repStart < minRepDuration,
                    leanedForward: maxLean - restLean > maxLeanIncrease
                ))
            }
        case .risingTooEarly:
            track(angle: angle, lean: lean)
            if angle <= targetAngle {
                phase = .bottomReached
            } else if angle >= restAngle - returnMargin {
                phase = .rest
                return .repIncomplete(bestAngle: bestAngle)
            }
        }
        return nil
    }

    private mutating func track(angle: Double, lean: Double) {
        bestAngle = min(bestAngle, angle)
        maxLean = max(maxLean, lean)
    }

    static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

