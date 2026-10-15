import Foundation
import Observation
import SwiftData

/// "Mes exercices": the movements filmed at the physiotherapist's, each on its own, apart from any séance.
/// A séance picks its exercises here, with its own sets and repetitions.
@Observable
final class ExerciseLibrary {
    static let shared = ExerciseLibrary()

    /// The latest first.
    private(set) var movements: [ReferenceMovement] = ReferenceStore.all()

    func reload() {
        movements = ReferenceStore.all()
    }

    func rename(_ movement: ReferenceMovement, to name: String, in context: ModelContext) {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        ReferenceStore.rename(movement.id, to: trimmed)
        // The séances show the exercise under the same name.
        for exercise in plannedExercises(of: movement, in: context) { exercise.name = trimmed }
        reload()
    }

    /// A new video for the same exercise: the séances that use it keep it.
    func replaceVideo(of movement: ReferenceMovement, with new: ReferenceMovement) {
        ReferenceStore.replace(movement.id, with: new)
        reload()
    }

    /// Deletes the exercise and its video, and takes it out of the séances.
    func delete(_ movement: ReferenceMovement, in context: ModelContext) {
        for exercise in plannedExercises(of: movement, in: context) { context.delete(exercise) }
        ReferenceStore.delete(movement.id)
        reload()
    }

    /// The séances that use this exercise.
    func programs(using movement: ReferenceMovement, in context: ModelContext) -> [Program] {
        let programs = (try? context.fetch(FetchDescriptor<Program>())) ?? []
        return programs.filter { $0.exercises.contains { $0.catalogID == movement.catalogID } }
    }

    private func plannedExercises(of movement: ReferenceMovement, in context: ModelContext) -> [PlannedExercise] {
        let catalogID: String? = movement.catalogID
        return (try? context.fetch(FetchDescriptor<PlannedExercise>(predicate: #Predicate { $0.catalogID == catalogID }))) ?? []
    }
}

extension Program {
    /// Adds an exercise at the end of the séance, in 3 × 10.
    func append(catalogID: String, name: String) {
        let next = (exercises.map(\.order).max() ?? -1) + 1
        exercises.append(PlannedExercise(catalogID: catalogID, name: name, sets: EditableProgram.defaultSets,
                                         reps: EditableProgram.defaultReps, order: next))
    }
}
