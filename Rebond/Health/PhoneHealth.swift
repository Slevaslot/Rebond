import Foundation
import HealthKit
import Observation

/// Saves the sessions in Health as workouts from the iPhone, when no Apple Watch recorded them.
/// Off until the patient turns it on (end of a session, or Réglages); the system asks the authorization then.
@MainActor @Observable
final class PhoneHealth {
    static let shared = PhoneHealth()

    static let enabledKey = "saveToHealth"
    static let offeredKey = "hasOfferedHealth"

    /// How the last saved session went to Health, for its summary.
    private(set) var lastRecording: HealthRecording = .none

    @ObservationIgnored private let store = HKHealthStore()

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    var isEnabled: Bool {
        get { access(keyPath: \.isEnabled); return UserDefaults.standard.bool(forKey: Self.enabledKey) }
        set { withMutation(keyPath: \.isEnabled) { UserDefaults.standard.set(newValue, forKey: Self.enabledKey) } }
    }

    /// Shows the system sheet the first time. Returns false when Health is unavailable or the sheet failed;
    /// the patient's choices themselves stay private (HealthKit does not tell whether reading was allowed).
    func enable() async -> Bool {
        guard Self.isAvailable else { return false }
        do {
            try await store.requestAuthorization(toShare: HealthTypes.share, read: HealthTypes.read)
        } catch {
            return false
        }
        isEnabled = store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized
        return isEnabled
    }

    /// Called when a session is saved: tells the watch to save its workout, or saves one from the iPhone.
    func record(start: Date, end: Date, watchRecorded: Bool) {
        lastRecording = HealthRecording.decide(watchRecorded: watchRecorded, healthEnabled: isEnabled,
                                               duration: end.timeIntervalSince(start))
        guard lastRecording == .phone else { return }
        Task { await save(start: start, end: end) }
    }

    /// The session just saved, after the patient turned Health on from its summary.
    func recordAfterEnabling(start: Date, end: Date) {
        guard lastRecording == .none, isEnabled else { return }
        record(start: start, end: end, watchRecorded: false)
    }

    private func save(start: Date, end: Date) async {
        let builder = HKWorkoutBuilder(healthStore: store, configuration: .rebond, device: .local())
        do {
            try await builder.beginCollection(at: start)
            try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true])
            try await builder.endCollection(at: end)
            _ = try await builder.finishWorkout()
        } catch {
            lastRecording = .none
        }
    }
}
