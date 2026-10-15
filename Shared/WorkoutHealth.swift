import HealthKit

// Compiled into the iPhone app and the Apple Watch app (folder `Shared/`).

nonisolated extension HKWorkoutConfiguration {
    /// A Rebond session in Health: functional strength training, indoors.
    static var rebond: HKWorkoutConfiguration {
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .functionalStrengthTraining
        configuration.locationType = .indoor
        return configuration
    }
}

/// What Rebond writes to and reads from Health. Asked once, on the iPhone or on the watch.
nonisolated enum HealthTypes {
    /// The session as a workout, and the calories the watch measures.
    static var share: Set<HKSampleType> {
        [HKObjectType.workoutType(), HKQuantityType(.activeEnergyBurned)]
    }

    /// The heart rate and calories shown on the watch during the session.
    static var read: Set<HKObjectType> {
        [HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned)]
    }
}

/// Who saves the session's workout in Health. Pure logic, tested.
nonisolated enum HealthRecording: Equatable, Sendable {
    /// The watch recorded it, with the heart rate: the iPhone saves nothing, so there is no duplicate.
    case watch
    /// No watch recorded it: the iPhone saves the workout (start and end).
    case phone
    /// Nothing is saved: Health is off, or the session is too short to be a workout.
    case none

    /// Shorter than this, a session is a try rather than a workout.
    static let minimumDuration: TimeInterval = 20

    static func decide(watchRecorded: Bool, healthEnabled: Bool, duration: TimeInterval) -> HealthRecording {
        if watchRecorded { return .watch }
        guard healthEnabled, duration >= minimumDuration else { return .none }
        return .phone
    }
}
