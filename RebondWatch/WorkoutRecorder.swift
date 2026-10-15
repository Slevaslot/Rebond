import Foundation
import HealthKit
import Observation

/// The session's workout on the watch (HealthKit): keeps the app on the wrist during the session, shows the
/// heart rate and the calories, and saves the workout in Health (it counts in the Activity rings).
/// Saved only when the patient saves the session on the iPhone; discarded when they abandon it.
@MainActor @Observable
final class WorkoutRecorder: NSObject {
    struct Summary: Equatable {
        let duration: TimeInterval
        /// Kilocalories, nil when not measured.
        let calories: Double?
        /// Beats per minute, nil when not measured.
        let averageHeartRate: Double?
    }

    private(set) var isRunning = false
    /// Beats per minute, the latest measure.
    private(set) var heartRate: Double?
    /// Kilocalories since the start.
    private(set) var calories: Double = 0
    private(set) var startDate: Date?

    @ObservationIgnored private let store = HKHealthStore()
    @ObservationIgnored private var session: HKWorkoutSession?
    @ObservationIgnored private var builder: HKLiveWorkoutBuilder?

    /// Starts the workout, asking for Health access the first time. Returns true when it records.
    func start() async -> Bool {
        if isRunning { return true }
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        try? await store.requestAuthorization(toShare: HealthTypes.share, read: HealthTypes.read)
        guard store.authorizationStatus(for: HKObjectType.workoutType()) == .sharingAuthorized else { return false }
        do {
            let configuration = HKWorkoutConfiguration.rebond
            let session = try HKWorkoutSession(healthStore: store, configuration: configuration)
            let builder = session.associatedWorkoutBuilder()
            builder.dataSource = HKLiveWorkoutDataSource(healthStore: store, workoutConfiguration: configuration)
            session.delegate = self
            builder.delegate = self
            self.session = session
            self.builder = builder
            let start = Date.now
            session.startActivity(with: start)
            try await builder.beginCollection(at: start)
            startDate = start
            isRunning = true
            return true
        } catch {
            reset()
            return false
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }

    /// Ends the workout: saved in Health with its summary, or discarded.
    func end(save: Bool) async -> Summary? {
        guard let session, let builder else { return nil }
        let summary = Summary(
            duration: Date.now.timeIntervalSince(startDate ?? .now),
            calories: calories > 0 ? calories : nil,
            averageHeartRate: builder.statistics(for: HKQuantityType(.heartRate))?
                .averageQuantity()?.doubleValue(for: .beatsPerMinute)
        )
        session.end()
        defer { reset() }
        do {
            try await builder.endCollection(at: .now)
            guard save else {
                builder.discardWorkout()
                return nil
            }
            try await builder.addMetadata([HKMetadataKeyIndoorWorkout: true])
            _ = try await builder.finishWorkout()
            return summary
        } catch {
            return nil
        }
    }

    private func reset() {
        session = nil
        builder = nil
        isRunning = false
        heartRate = nil
        calories = 0
        startDate = nil
    }

    private func update(heartRate: Double?, calories: Double?) {
        if let heartRate { self.heartRate = heartRate }
        if let calories { self.calories = calories }
    }
}

extension WorkoutRecorder: HKLiveWorkoutBuilderDelegate {
    nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
        let heartRate = collectedTypes.contains(HKQuantityType(.heartRate))
            ? workoutBuilder.statistics(for: HKQuantityType(.heartRate))?.mostRecentQuantity()?.doubleValue(for: .beatsPerMinute)
            : nil
        let calories = collectedTypes.contains(HKQuantityType(.activeEnergyBurned))
            ? workoutBuilder.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie())
            : nil
        Task { @MainActor in self.update(heartRate: heartRate, calories: calories) }
    }

    nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}

extension WorkoutRecorder: HKWorkoutSessionDelegate {
    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo toState: HKWorkoutSessionState,
                                    from fromState: HKWorkoutSessionState, date: Date) {}

    nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: any Error) {}
}

nonisolated extension HKUnit {
    static var beatsPerMinute: HKUnit { .count().unitDivided(by: .minute()) }
}
