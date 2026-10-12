import Foundation
import SwiftData

/// One home session: what was done, and how painful it was.
@Model
final class Session {
    var date: Date
    /// 0 to 10, entered at the end of the session.
    var pain: Int
    @Relationship(deleteRule: .cascade) var results: [ExerciseResult]

    init(date: Date = .now, pain: Int, results: [ExerciseResult]) {
        self.date = date
        self.pain = pain
        self.results = results
    }
}

@Model
final class ExerciseResult {
    var exerciseName: String
    var catalogID: String?
    var plannedReps: Int
    var completedReps: Int
    var incompleteReps: Int
    /// Deepest repetition, in percent of the target depth. Nil for an exercise counted by hand.
    var amplitude: Double?

    init(exerciseName: String, catalogID: String?, plannedReps: Int, completedReps: Int, incompleteReps: Int, amplitude: Double?) {
        self.exerciseName = exerciseName
        self.catalogID = catalogID
        self.plannedReps = plannedReps
        self.completedReps = completedReps
        self.incompleteReps = incompleteReps
        self.amplitude = amplitude
    }
}
