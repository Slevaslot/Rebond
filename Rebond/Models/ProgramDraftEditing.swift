import Foundation
import SwiftData

/// Editable copy of a program, used by the review screen before anything is saved.
struct EditableProgram {
    struct Exercise: Identifiable {
        let id = UUID()
        var name: String
        var catalogID: String?
        var sets: Int
        var reps: Int
    }

    var sessionsPerWeek = 3
    var exercises: [Exercise] = []

    init() {}

    init(_ draft: ProgramDraft) {
        sessionsPerWeek = draft.sessionsPerWeek
        exercises = draft.exercises.map {
            Exercise(name: $0.name, catalogID: $0.catalogID, sets: $0.sets, reps: $0.reps)
        }
    }

    init(_ program: Program) {
        sessionsPerWeek = program.sessionsPerWeek
        exercises = program.orderedExercises.map {
            Exercise(name: $0.name, catalogID: $0.catalogID, sets: $0.sets, reps: $0.reps)
        }
    }

    var isValid: Bool {
        !exercises.isEmpty && exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }
}

extension Program {
    /// The patient follows one program at a time: saving a new one replaces the previous.
    /// Past sessions are kept for the history and the report.
    static func replaceAll(with editable: EditableProgram, in context: ModelContext) {
        try? context.delete(model: Program.self)
        let exercises = editable.exercises.enumerated().map { index, exercise in
            PlannedExercise(catalogID: exercise.catalogID, name: exercise.name, sets: exercise.sets, reps: exercise.reps, order: index)
        }
        context.insert(Program(sessionsPerWeek: editable.sessionsPerWeek, exercises: exercises))
    }
}
