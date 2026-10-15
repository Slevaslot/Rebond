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

    /// Optional: without a name, the program is named after its physiotherapist or its date.
    var name = ""
    /// Calendar weekdays (1 is Sunday), Monday first.
    var weekdays = ReminderScheduler.sessionDays(count: defaultSessionsPerWeek)
    var sessionsPerWeekGuessed = false
    var exercises: [Exercise] = []

    /// How many days a week. Setting it spreads that many days over the week, as a sheet only gives a count.
    var sessionsPerWeek: Int {
        get { weekdays.count }
        set { weekdays = ReminderScheduler.sessionDays(count: newValue) }
    }

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
        name = program.name
        weekdays = program.days
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

    /// No name to type: an unnamed exercise takes the name of the camera exercise chosen, or a number.
    var isValid: Bool {
        !weekdays.isEmpty && !exercises.isEmpty
    }

    /// The program's name when the patient leaves it empty.
    var suggestedName: String {
        ProgramNaming.suggestedName(for: exercises.map { (displayName(of: $0), $0.mode == .reps ? $0.catalogID : nil) })
    }

    /// The exercise's name, or the one it gets when left empty.
    func displayName(of exercise: Exercise) -> String {
        let name = exercise.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { return name }
        if exercise.mode == .reps, let catalog = exercise.catalogID.flatMap(CatalogExercise.find) {
            return String(localized: catalog.name)
        }
        let number = (exercises.firstIndex { $0.id == exercise.id } ?? exercises.count) + 1
        return exercise.mode == .hold ? String(localized: "Maintien \(number)") : String(localized: "Exercice \(number)")
    }

    var hasGuesses: Bool {
        sessionsPerWeekGuessed || exercises.contains { !$0.guessed.isEmpty }
    }
}

extension Program {
    /// Replaces every program with this one (demo data). Past sessions are kept for the history and the report.
    static func replaceAll(with editable: EditableProgram, in context: ModelContext) {
        try? context.delete(model: Program.self)
        add(editable, in: context)
    }

    /// A new séance, next to the others. Its days are taken from the séances that had them.
    @discardableResult
    static func add(_ editable: EditableProgram, prescriber: String? = nil, in context: ModelContext) -> Program {
        let program = Program(sessionsPerWeek: editable.sessionsPerWeek, exercises: Self.exercises(of: editable),
                              name: editable.name.trimmingCharacters(in: .whitespaces),
                              weekdays: editable.weekdays, prescriber: prescriber)
        context.insert(program)
        program.setDays(program.days, in: context)
        // A permanent identifier right away: the session and the pages find the program by it.
        try? context.save()
        return program
    }

    /// Changes this séance in place: its past sessions and its place among the others stay.
    func update(with editable: EditableProgram, in context: ModelContext) {
        for exercise in exercises { context.delete(exercise) }
        exercises = Self.exercises(of: editable)
        name = editable.name.trimmingCharacters(in: .whitespaces)
        setDays(ProgramSchedule.days(weekdays: editable.weekdays, sessionsPerWeek: editable.sessionsPerWeek), in: context)
    }

    /// Plans this séance on these days; another séance planned on one of them loses it.
    func setDays(_ days: [Int], in context: ModelContext) {
        weekdays = ProgramSchedule.days(weekdays: days, sessionsPerWeek: 0)
        sessionsPerWeek = weekdays.count
        claimDays(in: context)
    }

    /// Puts this séance on `weekday`, or takes it off.
    func toggle(_ weekday: Int, in context: ModelContext) {
        setDays(days.contains(weekday) ? days.filter { $0 != weekday } : days + [weekday], in: context)
    }

    /// At most one séance a day: the others planned on this one's days lose them.
    private func claimDays(in context: ModelContext) {
        let mine = Set(weekdays)
        guard !mine.isEmpty, let others = try? context.fetch(FetchDescriptor<Program>()) else { return }
        for other in others where other.persistentModelID != persistentModelID {
            // Its days written out first: older séances keep theirs only as a number per week.
            let kept = other.days.filter { !mine.contains($0) }
            guard kept.count != other.days.count || other.weekdays.isEmpty else { continue }
            other.weekdays = kept
            other.sessionsPerWeek = kept.count
        }
    }

    private static func exercises(of editable: EditableProgram) -> [PlannedExercise] {
        editable.exercises.enumerated().map { index, exercise in
            PlannedExercise(
                catalogID: exercise.mode == .reps ? exercise.catalogID : nil,
                name: editable.displayName(of: exercise),
                sets: exercise.sets,
                reps: exercise.reps,
                holdSeconds: exercise.mode == .hold ? exercise.holdSeconds : nil,
                order: index
            )
        }
    }
}

extension EditableProgram.Exercise {
    /// A movement filmed at the physiotherapist's, followed by the camera.
    init(_ movement: ReferenceMovement) {
        self.init(name: movement.name, catalogID: movement.catalogID,
                  sets: EditableProgram.defaultSets, reps: EditableProgram.defaultReps)
    }
}
