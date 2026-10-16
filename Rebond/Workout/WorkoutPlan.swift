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

/// A side of the body, as the patient names it (their own left and right).
nonisolated enum BodySide: Hashable, Sendable {
    case right, left

    var other: BodySide { self == .right ? .left : .right }

    /// The patient's side from the side Vision names in the session's picture. The front camera's picture is
    /// mirrored (the patient sees themselves as in a mirror), and Vision names the sides of the body it sees as
    /// if it faced the camera: what it calls the left arm is the patient's right arm (checked on the team's films).
    init(visionSide: BodySide) {
        self = visionSide.other
    }
}

/// One exercise of the program, copied from SwiftData so the session logic stays pure.
nonisolated struct WorkoutExercise: Hashable, Sendable {
    let name: String
    let catalogID: String?
    let mode: WorkoutMode
    let sets: Int
    let reps: Int
    /// Done on one side, then the other, at each set: a single film or model serves both, mirrored.
    var bothSides = false
    /// The side shown by the film or the model: done first, the other one mirrored.
    var firstSide = BodySide.right

    /// Sides done at each set.
    var sideCount: Int { bothSides ? 2 : 1 }
}

/// One set to do: the screen shown during the session.
nonisolated struct WorkoutStep: Hashable, Sendable {
    let exerciseIndex: Int
    let exercise: WorkoutExercise
    /// 1-based.
    let set: Int
    /// For an exercise done on both sides: which one, this time. Nil otherwise.
    var side: BodySide? = nil

    /// The film or the model is shown mirrored: the side opposite to the one it shows.
    var isMirrored: Bool { side != nil && side != exercise.firstSide }
}

/// What one set produced.
nonisolated struct SetResult: Sendable {
    var completedReps = 0
    var incompleteReps = 0
    var heldSeconds = 0
    /// Each counted repetition measured by the camera, in percent of the exercise's target. Empty when nothing
    /// was measured (counted by hand, timer): the amplitude is then unavailable, never zero.
    var amplitudes: [Double] = []

    init(completedReps: Int = 0, incompleteReps: Int = 0, heldSeconds: Int = 0, amplitudes: [Double] = []) {
        self.completedReps = completedReps
        self.incompleteReps = incompleteReps
        self.heldSeconds = heldSeconds
        self.amplitudes = amplitudes
    }

    /// The set's usual repetition (median of those measured), in percent of the target: a single great one
    /// doesn't hide the others. Nil when nothing was measured.
    var amplitude: Double? { SetResult.median(amplitudes) }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}

/// Totals of one exercise over the session.
nonisolated struct ExerciseTally: Sendable, Equatable {
    var completedReps = 0
    var incompleteReps = 0
    var heldSeconds = 0
    /// Every measured repetition of the session, in percent of the target.
    var amplitudes: [Double] = []
    var setsDone = 0

    /// The session's usual repetition (median of every measured one). Nil when nothing was measured.
    var amplitude: Double? { SetResult.median(amplitudes) }
}

/// The steps of a session and what was done so far. Pure logic, tested without a screen.
nonisolated struct WorkoutPlan: Sendable {
    private(set) var exercises: [WorkoutExercise]
    private(set) var steps: [WorkoutStep]
    private(set) var tallies: [ExerciseTally]
    private(set) var currentIndex = 0

    /// A session this short with nothing done isn't worth saving without asking.
    static let minimumDuration: TimeInterval = 30

    init(exercises: [WorkoutExercise]) {
        self.exercises = exercises
        steps = exercises.enumerated().flatMap { index, exercise in
            (1...max(1, exercise.sets)).flatMap { set -> [WorkoutStep] in
                guard exercise.bothSides else { return [WorkoutStep(exerciseIndex: index, exercise: exercise, set: set)] }
                // Both sides at each set: the patient keeps the same position, one side then the other.
                return [exercise.firstSide, exercise.firstSide.other].map {
                    WorkoutStep(exerciseIndex: index, exercise: exercise, set: set, side: $0)
                }
            }
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
        tally.amplitudes += result.amplitudes
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

    /// One more set of the last exercise, after it was finished (an exercise done on its own).
    mutating func addSet() {
        guard let last = steps.last else { return }
        let index = last.exerciseIndex
        let old = exercises[index]
        let exercise = WorkoutExercise(name: old.name, catalogID: old.catalogID, mode: old.mode,
                                       sets: old.sets + 1, reps: old.reps, bothSides: old.bothSides, firstSide: old.firstSide)
        exercises[index] = exercise
        let added = exercise.bothSides
            ? [exercise.firstSide, exercise.firstSide.other].map { WorkoutStep(exerciseIndex: index, exercise: exercise, set: exercise.sets, side: $0) }
            : [WorkoutStep(exerciseIndex: index, exercise: exercise, set: exercise.sets)]
        steps = steps.map {
            $0.exerciseIndex == index ? WorkoutStep(exerciseIndex: index, exercise: exercise, set: $0.set, side: $0.side) : $0
        } + added
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
