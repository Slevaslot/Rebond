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
    /// Repetitions per set, for an exercise done in repetitions.
    var reps: Int
    /// Seconds to hold per set, for a held exercise (plank…). Nil for repetitions.
    var holdSeconds: Int? = nil
    var order: Int

    init(catalogID: String?, name: String, sets: Int, reps: Int, holdSeconds: Int? = nil, order: Int) {
        self.catalogID = catalogID
        self.name = name
        self.sets = sets
        self.reps = reps
        self.holdSeconds = holdSeconds
        self.order = order
    }

    var catalogExercise: CatalogExercise? {
        guard holdSeconds == nil else { return nil }
        return catalogID.flatMap(CatalogExercise.find)
    }

    var symbol: String {
        if let catalogExercise { return catalogExercise.symbol }
        return holdSeconds == nil ? "figure.cooldown" : "timer"
    }
}
