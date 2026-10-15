import Foundation
import Observation
import WatchConnectivity
import WatchKit
import WidgetKit

/// The watch's side of the link with the iPhone (WatchConnectivity): receives the set the iPhone counts with
/// its camera and taps the wrist, sends the patient's taps (pause, next set), runs the workout, and keeps
/// today's session for the app and the complications.
@MainActor @Observable
final class WatchModel: NSObject {
    static let shared = WatchModel()

    enum Stage: Equatable {
        /// No session: today's session, to start on the iPhone.
        case idle
        /// A session is running on the iPhone; `set` is nil until the first set appears.
        case session
        /// Every set is done; the patient enters their pain on the iPhone.
        case painOnPhone
        /// Saved on the iPhone; what the watch recorded.
        case finished(WorkoutRecorder.Summary?)
    }

    private(set) var stage = Stage.idle
    private(set) var set: WatchSetState?
    private(set) var snapshot: WidgetSnapshot = WidgetSnapshot.load() ?? .empty
    /// The iPhone can be reached right now: the buttons work.
    private(set) var isPhoneReachable = false
    let recorder = WorkoutRecorder()

    /// Background refreshes for WatchConnectivity, completed once the content they bring is received.
    @ObservationIgnored private var pendingTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    func activate() {
        guard WCSession.isSupported(), WCSession.default.delegate == nil else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    // MARK: From the iPhone

    /// The iPhone opened the app for a session (`HKHealthStore.startWatchApp`).
    func phoneStartedSession() {
        beginSession()
    }

    private func receive(_ message: PhoneMessage) {
        switch message {
        case .sessionStarted:
            beginSession()
        case .set(let new):
            if stage != .session { beginSession() }
            if let haptic = WatchHaptic.feedback(from: set, to: new) { play(haptic) }
            if new.isPaused != set?.isPaused, set != nil {
                if new.isPaused { recorder.pause() } else { recorder.resume() }
            }
            set = new
        case .setsFinished:
            set = nil
            stage = .painOnPhone
            play(.setComplete)
        case .sessionEnded(let saved):
            set = nil
            Task {
                let summary = await recorder.end(save: saved)
                if saved {
                    stage = .finished(summary)
                    play(.sessionEnd)
                } else {
                    stage = .idle
                }
            }
        }
    }

    private func beginSession() {
        guard stage != .session else { return }
        stage = .session
        set = nil
        Task {
            // Tells the iPhone not to save a second workout.
            if await recorder.start() { send(.recordingWorkout) }
        }
    }

    private func receive(_ snapshot: WidgetSnapshot) {
        self.snapshot = snapshot
        if snapshot.save() {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: To the iPhone

    func togglePause() {
        send(.togglePause)
    }

    func nextSet() {
        send(.nextSet)
    }

    /// Back to today's session after the end of a session.
    func dismissSummary() {
        stage = .idle
    }

    private func send(_ message: WatchMessage) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload = WatchCoding.encode(message)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                // The workout notice must arrive; the buttons are only worth it right now.
                if message == .recordingWorkout {
                    Task { @MainActor in _ = WCSession.default.transferUserInfo(WatchCoding.encode(message)) }
                }
            }
        } else if message == .recordingWorkout {
            session.transferUserInfo(payload)
        }
    }

    private func play(_ haptic: WatchHaptic) {
        let type: WKHapticType = switch haptic {
        case .repetition: .click
        case .setComplete: .success
        case .paused: .stop
        case .resumed: .start
        case .newSet: .notification
        case .sessionEnd: .success
        }
        WKInterfaceDevice.current().play(type)
    }

    // MARK: Background

    func handle(_ task: WKWatchConnectivityRefreshBackgroundTask) {
        pendingTasks.append(task)
        completePendingTasks()
    }

    private func completePendingTasks() {
        guard !WCSession.default.hasContentPending else { return }
        pendingTasks.forEach { $0.setTaskCompletedWithSnapshot(false) }
        pendingTasks.removeAll()
    }

    private func didActivate() {
        isPhoneReachable = WCSession.default.isReachable
        if let snapshot = WatchContext.decode(WCSession.default.receivedApplicationContext) {
            receive(snapshot)
        }
        completePendingTasks()
    }
}

extension WatchModel: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.didActivate() }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isPhoneReachable = reachable }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = WatchCoding.decode(PhoneMessage.self, from: message) else { return }
        Task { @MainActor in self.receive(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let decoded = WatchCoding.decode(PhoneMessage.self, from: userInfo) else { return }
        Task { @MainActor in
            self.receive(decoded)
            self.completePendingTasks()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        guard let snapshot = WatchContext.decode(applicationContext) else { return }
        Task { @MainActor in
            self.receive(snapshot)
            self.completePendingTasks()
        }
    }
}
