import Foundation
import SwiftData

/// Editable copy of a program, used by the review screen before anything is saved.
nonisolated struct EditableProgram {
    /// Repetitions or a held position.
    enum Mode: Hashable {
        case reps
        case hold
    }

    struct Exercise: Identifiable {
        let id = UUID()
        var name: String
        var catalogID: String?
        var sets: Int
        var mode = Mode.reps
        var reps: Int
        var holdSeconds = 30
        /// Values the model didn't find on the sheet and that were filled in by default: to check.
        var guessed: Set<Field> = []
    }

    enum Field: Hashable {
        case sets, reps, holdSeconds
    }

    static let defaultSessionsPerWeek = 3
    static let defaultSets = 3
    static let defaultReps = 10
    static let defaultHoldSeconds = 30

    var sessionsPerWeek = defaultSessionsPerWeek
    var sessionsPerWeekGuessed = false
    var exercises: [Exercise] = []

    init() {}

    /// Fills in what the sheet doesn't say, and remembers it to flag it on the review screen.
    init(_ draft: ProgramDraft) {
        sessionsPerWeek = draft.sessionsPerWeek ?? Self.defaultSessionsPerWeek
        sessionsPerWeekGuessed = draft.sessionsPerWeek == nil
        exercises = draft.exercises.map { item in
            var exercise = Exercise(
                name: item.name,
                catalogID: item.kind.catalogID,
                sets: item.sets ?? Self.defaultSets,
                reps: item.reps ?? Self.defaultReps
            )
            if item.sets == nil { exercise.guessed.insert(.sets) }
            if let hold = item.holdSeconds, item.reps == nil {
                exercise.mode = .hold
                exercise.holdSeconds = hold
                exercise.catalogID = nil
            } else if item.reps == nil {
                exercise.guessed.insert(.reps)
            }
            return exercise
        }
    }

    init(_ program: Program) {
        sessionsPerWeek = program.sessionsPerWeek
        exercises = program.orderedExercises.map {
            Exercise(
                name: $0.name,
                catalogID: $0.catalogID,
                sets: $0.sets,
                mode: $0.holdSeconds == nil ? .reps : .hold,
                reps: $0.reps,
                holdSeconds: $0.holdSeconds ?? Self.defaultHoldSeconds
            )
        }
    }

    var isValid: Bool {
        !exercises.isEmpty && exercises.allSatisfy { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var hasGuesses: Bool {
        sessionsPerWeekGuessed || exercises.contains { !$0.guessed.isEmpty }
    }
}

extension Program {
    /// The patient follows one program at a time: saving a new one replaces the previous.
    /// Past sessions are kept for the history and the report.
    static func replaceAll(with editable: EditableProgram, in context: ModelContext) {
        try? context.delete(model: Program.self)
        let exercises = editable.exercises.enumerated().map { index, exercise in
            PlannedExercise(
                catalogID: exercise.mode == .reps ? exercise.catalogID : nil,
                name: exercise.name.trimmingCharacters(in: .whitespaces),
                sets: exercise.sets,
                reps: exercise.reps,
                holdSeconds: exercise.mode == .hold ? exercise.holdSeconds : nil,
                order: index
            )
        }
        context.insert(Program(sessionsPerWeek: editable.sessionsPerWeek, exercises: exercises))
    }
}
