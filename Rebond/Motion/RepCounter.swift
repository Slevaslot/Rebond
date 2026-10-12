import Foundation

nonisolated enum RepEvent: Sendable {
    /// `bestAngle` is the lowest angle reached during the repetition (range of motion).
    case repCompleted(bestAngle: Double)
    case repIncomplete(bestAngle: Double)
    case correction(LocalizedStringResource)
}

/// Counts repetitions from a stream of joint angles.
/// Pure logic: can be tested by feeding recorded angle series.
nonisolated struct RepCounter {
    private enum Phase {
        case rest
        case descending
        case bottomReached
        /// Came back up before reaching the target angle.
        case risingTooEarly
    }

    let exercise: CatalogExercise

    private let smoothingWindow = 5
    /// How far below the rest angle the movement must go to count as started.
    private let startMargin = 15.0
    /// How far the angle must rise from its lowest point to count as coming back up.
    private let reversalMargin = 10.0

    private var recentAngles: [Double] = []
    private var phase = Phase.rest
    private var bestAngle = Double.infinity

    init(exercise: CatalogExercise) {
        self.exercise = exercise
    }

    mutating func process(angle: Double) -> RepEvent? {
        recentAngles.append(angle)
        if recentAngles.count > smoothingWindow {
            recentAngles.removeFirst()
        }
        let smoothed = recentAngles.reduce(0, +) / Double(recentAngles.count)

        switch phase {
        case .rest:
            if smoothed < exercise.restAngle - startMargin {
                phase = .descending
                bestAngle = smoothed
            }
        case .descending:
            bestAngle = min(bestAngle, smoothed)
            if smoothed <= exercise.targetAngle {
                phase = .bottomReached
            } else if smoothed > bestAngle + reversalMargin {
                phase = .risingTooEarly
                return .correction(exercise.correction)
            }
        case .bottomReached:
            bestAngle = min(bestAngle, smoothed)
            if smoothed >= exercise.restAngle {
                phase = .rest
                return .repCompleted(bestAngle: bestAngle)
            }
        case .risingTooEarly:
            if smoothed <= exercise.targetAngle {
                phase = .bottomReached
                bestAngle = min(bestAngle, smoothed)
            } else if smoothed >= exercise.restAngle {
                phase = .rest
                return .repIncomplete(bestAngle: bestAngle)
            }
        }
        return nil
    }
}
