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
        // Filmed on one side: both sides by default, the film mirrored for the other one.
        exercise.bothSides = holdSeconds == nil && catalogID.flatMap(CatalogExercise.find)?.reference?.filmedSide != nil
        return exercise
    }

    /// The exercise of a program, as a planned exercise, to do it on its own.
    var planned: PlannedExercise {
        PlannedExercise(catalogID: catalogID, name: name, sets: 1, reps: EditableProgram.defaultReps,
                        holdSeconds: holdSeconds, order: 0)
    }

    /// To do it right now, on its own: one set of `reps` (or one hold of `holdSeconds`), on both sides when filmed
    /// on one.
    func workoutExercise(reps: Int, holdSeconds: Int? = nil) -> WorkoutExercise {
        let exercise = planned.workoutExercise
        let mode: WorkoutMode = if case .hold = exercise.mode, let holdSeconds { .hold(seconds: holdSeconds) } else { exercise.mode }
        return WorkoutExercise(name: exercise.name, catalogID: exercise.catalogID, mode: mode, sets: 1,
                               reps: reps, bothSides: editable.bothSides, firstSide: exercise.firstSide)
    }

    /// Filmed (the patient's model movement), followed by the camera.
    var isFilmed: Bool { catalogExercise?.reference != nil }

    /// One of Rebond's, followed by the camera.
    var isRebond: Bool { !isFilmed && catalogExercise != nil }

    /// Adds it at the end of a program, in 3 × 10 (or 3 × its hold).
    func append(to program: Program) {
        let next = (program.exercises.map(\.order).max() ?? -1) + 1
        program.exercises.append(PlannedExercise(catalogID: catalogID, name: name,
                                                 sets: EditableProgram.defaultSets, reps: EditableProgram.defaultReps,
                                                 holdSeconds: holdSeconds, order: next))
    }

    /// Set once Rebond's exercises were put in "Mes exercices": one the patient deletes doesn't come back.
    static let defaultsAddedKey = "defaultExercisesAdded"

    /// "Mes exercices" starts with Rebond's exercises followed by the camera, so a program can be made right away.
    /// Only once (see `defaultsAddedKey`), and without repeating one already there under the same name.
    static func addDefaults(in context: ModelContext, defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: defaultsAddedKey) else { return }
        let known = Set(((try? context.fetch(FetchDescriptor<LibraryExercise>())) ?? []).map(\.name))
        // A second apart, in the catalog's order: the list is sorted by creation date.
        let start = Date.now
        for (index, catalog) in CatalogExercise.all.enumerated() {
            let name = String(localized: catalog.name)
            guard !known.contains(name) else { continue }
            context.insert(LibraryExercise(createdAt: start.addingTimeInterval(Double(index)), catalogID: catalog.id, name: name))
        }
        defaults.set(true, forKey: defaultsAddedKey)
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
