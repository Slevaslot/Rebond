import Foundation

// Compiled into the iPhone app and the Apple Watch app (folder `Shared/`). Pure logic, tested without a screen.
//
// The iPhone counts with the camera; the watch shows the set on the wrist, taps at each repetition, records the
// workout in Health with the heart rate, and sends the patient's taps back (pause, next set).
// Everything goes through WatchConnectivity, directly between the two devices: no server.

/// The set in progress, as the watch shows it.
nonisolated struct WatchSetState: Codable, Equatable, Sendable {
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
    /// The set can be paused (camera and held sets; not repetitions counted by hand).
    var canPause: Bool
    /// "côté droit" or "côté gauche" for an exercise done on both sides, already localized; nil otherwise.
    var side: String? = nil

    var isSetComplete: Bool { target > 0 && count >= target }
    /// Paused before anything was done: a held set whose timer has not started.
    var isWaitingToStart: Bool { isPaused && count == 0 }
    var fraction: Double { target > 0 ? min(1, Double(count) / Double(target)) : 0 }

    /// Same set of the same exercise, on the same side: only the count or the pause changed.
    func isSameSet(as other: WatchSetState) -> Bool {
        exercise == other.exercise && set == other.set && totalSets == other.totalSets && side == other.side
    }
}

/// From the iPhone to the watch.
nonisolated enum PhoneMessage: Codable, Equatable, Sendable {
    /// A session starts: the watch starts its workout (heart rate, Health).
    case sessionStarted(Date)
    /// A new set, a repetition, a pause.
    case set(WatchSetState)
    /// Every set is done: the patient now enters their pain on the iPhone.
    case setsFinished
    /// The session ended: saved on the iPhone (the workout is saved in Health), or abandoned (it is discarded).
    case sessionEnded(saved: Bool)
}

/// From the watch to the iPhone.
nonisolated enum WatchMessage: Codable, Equatable, Sendable {
    case togglePause
    case nextSet
    /// The watch records this session's workout in Health: the iPhone must not save a second one.
    case recordingWorkout
}

/// The taps the watch plays, chosen from what changed. Maps to `WKHapticType` on the watch.
nonisolated enum WatchHaptic: Equatable, Sendable {
    /// One more repetition (or, for a held set, every 10 seconds).
    case repetition
    /// The set's target is reached.
    case setComplete
    case paused
    case resumed
    /// A new set or a new exercise begins.
    case newSet
    /// The session is over.
    case sessionEnd

    /// What to play when the set goes from `old` to `new`; nil when nothing worth a tap changed.
    /// One tap at a time, the most important: reaching the target wins over the repetition that reached it.
    static func feedback(from old: WatchSetState?, to new: WatchSetState) -> WatchHaptic? {
        guard let old, old.isSameSet(as: new) else { return .newSet }
        if old.isPaused != new.isPaused { return new.isPaused ? .paused : .resumed }
        guard new.count > old.count else { return nil }
        if new.isSetComplete, !old.isSetComplete { return .setComplete }
        if new.isHold {
            // Every second would buzz all the time: one tap every 10 seconds held.
            return new.count / 10 > old.count / 10 ? .repetition : nil
        }
        return .repetition
    }
}

/// WatchConnectivity carries property lists: each message is JSON under a single key.
nonisolated enum WatchCoding {
    static let key = "rebond"

    static func encode<Message: Encodable>(_ message: Message) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(message) else { return [:] }
        return [key: data]
    }

    static func decode<Message: Decodable>(_ type: Message.Type, from dictionary: [String: Any]) -> Message? {
        guard let data = dictionary[key] as? Data else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

/// The application context sent to the watch: today's session and the week, for the watch app and its
/// complications. The same snapshot as the iPhone widgets.
nonisolated enum WatchContext {
    static let snapshotKey = "snapshot"

    static func encode(_ snapshot: WidgetSnapshot) -> [String: Any] {
        guard let data = try? JSONEncoder().encode(snapshot) else { return [:] }
        return [snapshotKey: data]
    }

    static func decode(_ dictionary: [String: Any]) -> WidgetSnapshot? {
        guard let data = dictionary[snapshotKey] as? Data else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }
}
