import Foundation
import SwiftData

/// One home session: what was done, and how painful it was.
@Model
final class Session {
    var date: Date
    /// 0 to 10, entered at the end of the session.
    var pain: Int
    /// Seconds from the first set to the pain entry.
    var duration: TimeInterval = 0
    @Relationship(deleteRule: .cascade) var results: [ExerciseResult]

    init(date: Date = .now, pain: Int, duration: TimeInterval = 0, results: [ExerciseResult]) {
        self.date = date
        self.pain = pain
        self.duration = duration
        self.results = results
    }

    var orderedResults: [ExerciseResult] {
        results.sorted { $0.order < $1.order }
    }
}

/// What was done for one exercise during a session.
/// A standalone copy, not linked to the program: the history survives a new program.
@Model
final class ExerciseResult {
    var exerciseName: String
    var catalogID: String?
    var order: Int = 0
    var plannedReps: Int
    var completedReps: Int
    var incompleteReps: Int
    /// For a held exercise: seconds planned over all sets, and seconds actually held.
    var plannedSeconds: Int = 0
    var heldSeconds: Int = 0
    /// Best repetition, in percent of the exercise's target. Nil when not measured by the camera.
    var amplitude: Double?

    init(exerciseName: String, catalogID: String?, order: Int = 0, plannedReps: Int, completedReps: Int, incompleteReps: Int,
         plannedSeconds: Int = 0, heldSeconds: Int = 0, amplitude: Double?) {
        self.exerciseName = exerciseName
        self.catalogID = catalogID
        self.order = order
        self.plannedReps = plannedReps
        self.completedReps = completedReps
        self.incompleteReps = incompleteReps
        self.plannedSeconds = plannedSeconds
        self.heldSeconds = heldSeconds
        self.amplitude = amplitude
    }

    var isHeld: Bool { plannedSeconds > 0 }
}
