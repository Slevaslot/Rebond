import Foundation

/// How one exercise of the program is done during a session.
nonisolated enum WorkoutMode: Hashable, Sendable {
    /// Followed by the camera.
    case camera(catalogID: String)
    /// Counted by the patient with the buttons.
    case manual
    /// Held for a number of seconds, with a timer.
    case hold(seconds: Int)
}

/// One exercise of the program, copied from SwiftData so the session logic stays pure.
nonisolated struct WorkoutExercise: Hashable, Sendable {
    let name: String
    let catalogID: String?
    let mode: WorkoutMode
    let sets: Int
    let reps: Int
}

/// One set to do: the screen shown during the session.
nonisolated struct WorkoutStep: Hashable, Sendable {
    let exerciseIndex: Int
    let exercise: WorkoutExercise
    /// 1-based.
    let set: Int
}

/// What one set produced.
nonisolated struct SetResult: Sendable {
    var completedReps = 0
    var incompleteReps = 0
    var heldSeconds = 0
    /// Best repetition, in percent of the exercise's target. Nil when nothing was measured.
    var amplitude: Double?
}

/// Totals of one exercise over the session.
nonisolated struct ExerciseTally: Sendable, Equatable {
    var completedReps = 0
    var incompleteReps = 0
    var heldSeconds = 0
    var amplitude: Double?
    var setsDone = 0
}

/// The steps of a session and what was done so far. Pure logic, tested without a screen.
nonisolated struct WorkoutPlan: Sendable {
    let exercises: [WorkoutExercise]
    let steps: [WorkoutStep]
    private(set) var tallies: [ExerciseTally]
    private(set) var currentIndex = 0

    /// A session this short with nothing done isn't worth saving without asking.
    static let minimumDuration: TimeInterval = 30

    init(exercises: [WorkoutExercise]) {
        self.exercises = exercises
        steps = exercises.enumerated().flatMap { index, exercise in
            (1...max(1, exercise.sets)).map { WorkoutStep(exerciseIndex: index, exercise: exercise, set: $0) }
        }
        tallies = Array(repeating: ExerciseTally(), count: exercises.count)
    }

    var currentStep: WorkoutStep? {
        steps.indices.contains(currentIndex) ? steps[currentIndex] : nil
    }

    var isFinished: Bool { currentIndex >= steps.count }

    /// Exercises whose camera follows the movement, to show the placement help first.
    var usesCamera: Bool {
        exercises.contains { if case .camera = $0.mode { true } else { false } }
    }

    var nothingDone: Bool {
        tallies.allSatisfy { $0.completedReps == 0 && $0.heldSeconds == 0 }
    }

    mutating func record(_ result: SetResult) {
        guard let step = currentStep else { return }
        var tally = tallies[step.exerciseIndex]
        tally.completedReps += result.completedReps
        tally.incompleteReps += result.incompleteReps
        tally.heldSeconds += result.heldSeconds
        tally.setsDone += 1
        if let amplitude = result.amplitude {
            tally.amplitude = max(tally.amplitude ?? 0, amplitude)
        }
        tallies[step.exerciseIndex] = tally
        currentIndex += 1
    }

    /// The set after the current one, if any.
    var nextStep: WorkoutStep? {
        steps.indices.contains(currentIndex + 1) ? steps[currentIndex + 1] : nil
    }

    /// Whether the current step is the first set of its exercise: the guide shows the movement only then.
    var isFirstSetOfExercise: Bool {
        currentStep?.set == 1
    }

    /// Skips the current set and the exercise's remaining sets, keeping what the current set produced.
    mutating func skipExercise(keeping result: SetResult = SetResult()) {
        guard let step = currentStep else { return }
        record(result)
        while let next = currentStep, next.exerciseIndex == step.exerciseIndex {
            currentIndex += 1
        }
    }

    /// Stops early: the remaining sets are left undone.
    mutating func finishEarly() {
        currentIndex = steps.count
    }

    /// Every exercise of the program, done or not, so the report shows what was skipped.
    var summary: [(exercise: WorkoutExercise, tally: ExerciseTally)] {
        Array(zip(exercises, tallies))
    }
}
