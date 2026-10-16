import HealthKit
import Observation
import TipKit
import WatchConnectivity

/// The iPhone's side of the Apple Watch link (WatchConnectivity): sends the set in progress to the watch, and
/// receives the patient's taps on the watch (pause, next set), which go to the session through `SessionRemote`.
/// Also sends today's session to the watch for its app and complications. Does nothing when no watch is paired.
///
/// The set state is forwarded by `WorkoutLiveActivity`, so every set screen that updates the Lock Screen also
/// updates the watch. The session's start and end are sent by `WorkoutView`.
@MainActor @Observable
final class PhoneWatchLink: NSObject {
    static let shared = PhoneWatchLink()

    /// The watch records the current session's workout in Health.
    private(set) var watchRecordsWorkout = false
    private(set) var isWatchAppInstalled = false
    /// An Apple Watch is paired with this iPhone, with or without Rebond on it.
    private(set) var isWatchPaired = false

    @ObservationIgnored private var lastSet: WatchSetState?
    @ObservationIgnored private var pendingContext: WidgetSnapshot?

    private var session: WCSession? { WCSession.isSupported() ? WCSession.default : nil }

    /// Called once at launch.
    func activate() {
        guard let session, session.delegate == nil else { return }
        session.delegate = self
        session.activate()
    }

    // MARK: Session

    /// Opens the watch app (it starts its workout, with the heart rate) and tells it the session started.
    func sessionStarted(at date: Date = .now) {
        watchRecordsWorkout = false
        lastSet = nil
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        // Brings the watch app to the front, even with the watch asleep: the only way to get it on the wrist
        // during the session without the patient touching it.
        let configuration = HKWorkoutConfiguration.rebond
        HKHealthStore().startWatchApp(with: configuration) { _, _ in }
        send(.sessionStarted(date), reliably: true)
    }

    func update(_ set: WatchSetState) {
        guard set != lastSet else { return }
        lastSet = set
        send(.set(set), reliably: false)
    }

    /// Every set is done; the pain comes next on the iPhone.
    func setsFinished() {
        lastSet = nil
        send(.setsFinished, reliably: true)
    }

    func sessionEnded(saved: Bool) {
        lastSet = nil
        send(.sessionEnded(saved: saved), reliably: true)
        watchRecordsWorkout = false
    }

    // MARK: Today's session, for the watch app and its complications

    func updateContext(_ snapshot: WidgetSnapshot) {
        guard let session, session.activationState == .activated else {
            pendingContext = snapshot
            return
        }
        pendingContext = nil
        guard session.isPaired, session.isWatchAppInstalled else { return }
        try? session.updateApplicationContext(WatchContext.encode(snapshot))
    }

    // MARK: Sending

    /// Live updates go only to a watch app on screen (`sendMessage`), otherwise they are stale by the time they
    /// arrive. The start and the end are queued (`transferUserInfo`) when the watch is out of reach.
    private func send(_ message: PhoneMessage, reliably: Bool) {
        guard let session, session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        let payload = WatchCoding.encode(message)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in
                if reliably { Task { @MainActor in _ = WCSession.default.transferUserInfo(WatchCoding.encode(message)) } }
            }
        } else if reliably {
            session.transferUserInfo(payload)
        }
    }

    /// A command as if it came from the watch. The watch's taps, Double Tap and Siri on the watch arrive here; they
    /// go to the session the same way as every other command (`SessionRemote`), resolved for the screen on display.
    func perform(_ message: WatchMessage) {
        receive(message)
    }

    private func receive(_ message: WatchMessage) {
        switch message {
        case .recordingWorkout:
            watchRecordsWorkout = true
        case .togglePause:
            SessionRemote.shared.send(.togglePause, from: .watch)
        case .nextSet:
            SessionRemote.shared.send(.nextSet, from: .watch)
        }
    }

    private func didActivate() {
        isWatchAppInstalled = session?.isWatchAppInstalled ?? false
        isWatchPaired = session?.isPaired ?? false
        if isWatchAppInstalled { WatchAppTip().invalidate(reason: .actionPerformed) }
        if let pendingContext { updateContext(pendingContext) }
    }
}

extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: (any Error)?) {
        Task { @MainActor in self.didActivate() }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in self.didActivate() }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    /// The patient switched to another watch: activate again for the new one.
    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let decoded = WatchCoding.decode(WatchMessage.self, from: message) else { return }
        Task { @MainActor in self.receive(decoded) }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        guard let decoded = WatchCoding.decode(WatchMessage.self, from: userInfo) else { return }
        Task { @MainActor in self.receive(decoded) }
    }
}
