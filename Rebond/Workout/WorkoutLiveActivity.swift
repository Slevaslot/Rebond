import ActivityKit
import Foundation

/// The Live Activity of the session in progress (Lock Screen and Dynamic Island): exercise, "4 / 10",
/// "Série 2 sur 3". One activity for the whole session, updated at each set, ended with the session.
/// Drawn by the widget extension (`RebondWidgets/WorkoutLiveActivityWidget.swift`).
/// Every change is also sent to the Apple Watch app (`PhoneWatchLink`), which shows the set and taps the wrist.
///
/// Call from the session screens:
/// - `start(…)` when a set appears (it updates the running activity instead of starting a second one);
/// - `update(count:)` at each counted repetition, or each second of a hold;
/// - `setPaused(_:)` on the hand gesture or the pause button;
/// - `end()` when the session is saved, abandoned or closed.
@MainActor
final class WorkoutLiveActivity {
    static let shared = WorkoutLiveActivity()

    typealias State = WorkoutActivityAttributes.ContentState

    /// The running activity, by id: `Activity` is not Sendable, so it is looked up where it is used.
    private var activityID: String?
    private(set) var state: State?

    /// Shows a new set: starts the activity on the first set, then updates it.
    /// - Parameters:
    ///   - target: repetitions to do, or seconds to hold when `isHold`.
    ///   - startsPaused: a held set waits for the patient to start its timer.
    func start(exercise: String, symbol: String = "figure.cooldown", set: Int, totalSets: Int, targetReps target: Int,
               isHold: Bool = false, canPause: Bool = true, startsPaused: Bool = false, side: String? = nil) {
        let state = State(exercise: exercise, symbol: symbol, set: set, totalSets: totalSets, count: 0,
                          target: target, isHold: isHold, isPaused: startsPaused, canPause: canPause, side: side)
        self.state = state
        sendToWatch(state)
        if activityID != nil {
            push(state)
            return
        }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        // An activity left over by a session that never ended (app killed): replaced by this one. Only those
        // listed now: the ending runs later, and must not end the activity requested just below.
        endAll()
        activityID = try? Activity.request(
            attributes: WorkoutActivityAttributes(startedAt: .now),
            content: ActivityContent(state: state, staleDate: nil),
            pushType: nil
        ).id
    }

    /// Repetitions done in the current set (or seconds held).
    func update(count: Int) {
        guard var state, state.count != count else { return }
        state.count = count
        self.state = state
        push(state)
    }

    func setPaused(_ paused: Bool) {
        guard var state, state.isPaused != paused else { return }
        state.isPaused = paused
        self.state = state
        push(state)
    }

    /// Removes the activity from the Lock Screen and the Dynamic Island.
    func end() {
        state = nil
        activityID = nil
        endAll()
    }

    private func push(_ state: State) {
        sendToWatch(state)
        guard let activityID else { return }
        Task { await Self.update(activityID, to: state) }
    }

    private func sendToWatch(_ state: State) {
        PhoneWatchLink.shared.update(WatchSetState(
            exercise: state.exercise, symbol: state.symbol, set: state.set, totalSets: state.totalSets,
            count: state.count, target: state.target, isHold: state.isHold, isPaused: state.isPaused, canPause: state.canPause,
            side: state.side
        ))
    }

    private func endAll() {
        let ids = Activity<WorkoutActivityAttributes>.activities.map(\.id)
        guard !ids.isEmpty else { return }
        Task { await Self.end(ids) }
    }

    private nonisolated static func update(_ id: String, to state: State) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where activity.id == id {
            await activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    private nonisolated static func end(_ ids: [String]) async {
        for activity in Activity<WorkoutActivityAttributes>.activities where ids.contains(activity.id) {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
    }
}
