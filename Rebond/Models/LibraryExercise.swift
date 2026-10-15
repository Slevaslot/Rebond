import Foundation
import SwiftData

/// An exercise of "Mes exercices": a movement filmed at the physiotherapist's, one of Rebond's, or one counted by hand
/// or held. It has no days: a program picks exercises here and sets their days, sets and repetitions.
@Model
final class LibraryExercise {
    var createdAt: Date
    /// Catalog entry or filmed movement followed by the camera; nil for an exercise counted by hand or held.
    var catalogID: String?
    var name: String
    /// Seconds held, for a held exercise; nil for repetitions.
    var holdSeconds: Int?

    init(createdAt: Date = .now, catalogID: String?, name: String, holdSeconds: Int? = nil) {
        self.createdAt = createdAt
        self.catalogID = catalogID
        self.name = name
        self.holdSeconds = holdSeconds
    }

    var catalogExercise: CatalogExercise? {
        holdSeconds == nil ? catalogID.flatMap(CatalogExercise.find) : nil
    }

    /// The same exercise in a program, in 3 × 10 (or 3 × 30 s).
    var editable: EditableProgram.Exercise {
        var exercise = EditableProgram.Exercise(name: name, catalogID: catalogID, sets: EditableProgram.defaultSets,
                                                reps: EditableProgram.defaultReps)
        if let holdSeconds {
            exercise.mode = .hold
            exercise.holdSeconds = holdSeconds
        }
        return exercise
    }

    /// The exercise of a program, as a planned exercise, to do it on its own.
    var planned: PlannedExercise {
        PlannedExercise(catalogID: catalogID, name: name, sets: 1, reps: EditableProgram.defaultReps,
                        holdSeconds: holdSeconds, order: 0)
    }

    /// Adds the exercises of a program that aren't in "Mes exercices" yet (same name).
    static func addMissing(_ exercises: [PlannedExercise], in context: ModelContext) {
        let known = Set(((try? context.fetch(FetchDescriptor<LibraryExercise>())) ?? []).map(\.name))
        var added = Set<String>()
        for exercise in exercises where !known.contains(exercise.name) && !added.contains(exercise.name) {
            added.insert(exercise.name)
            context.insert(LibraryExercise(catalogID: exercise.catalogID, name: exercise.name,
                                           holdSeconds: exercise.holdSeconds))
        }
    }
}
