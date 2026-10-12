import Foundation
import SwiftData

/// The exercise program given by the physiotherapist.
@Model
final class Program {
    var createdAt: Date
    var sessionsPerWeek: Int
    @Relationship(deleteRule: .cascade) var exercises: [PlannedExercise]

    init(createdAt: Date = .now, sessionsPerWeek: Int, exercises: [PlannedExercise]) {
        self.createdAt = createdAt
        self.sessionsPerWeek = sessionsPerWeek
        self.exercises = exercises
    }

    var orderedExercises: [PlannedExercise] {
        exercises.sorted { $0.order < $1.order }
    }
}

@Model
final class PlannedExercise {
    /// Catalog entry followed by the camera, or nil for an exercise counted by hand.
    var catalogID: String?
    var name: String
    var sets: Int
    var reps: Int
    var order: Int

    init(catalogID: String?, name: String, sets: Int, reps: Int, order: Int) {
        self.catalogID = catalogID
        self.name = name
        self.sets = sets
        self.reps = reps
        self.order = order
    }

    var catalogExercise: CatalogExercise? {
        catalogID.flatMap(CatalogExercise.find)
    }
}
