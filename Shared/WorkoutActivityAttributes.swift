import ActivityKit
import Foundation

// Compiled into both the app (which starts and updates the activity) and the widget extension (which draws it).

/// The Live Activity of a session: the set in progress, on the Lock Screen and in the Dynamic Island.
nonisolated struct WorkoutActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable, Sendable {
        var exercise: String
        /// SF Symbol of the exercise.
        var symbol: String
        /// 1-based.
        var set: Int
        var totalSets: Int
        /// Repetitions done, or seconds held for a held exercise.
        var count: Int
        /// Repetitions or seconds to reach.
        var target: Int
        var isHold: Bool
        var isPaused: Bool
        /// Repetitions counted by hand can't be paused: no pause button for them.
        var canPause = true
        /// "côté droit" or "côté gauche" for an exercise done on both sides, already localized; nil otherwise.
        var side: String? = nil

        var isSetComplete: Bool { target > 0 && count >= target }
        var fraction: Double { target > 0 ? min(1, Double(count) / Double(target)) : 0 }
    }

    /// When the session started.
    var startedAt: Date
}
