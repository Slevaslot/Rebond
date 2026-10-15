import SwiftData
import SwiftUI

/// A full session, full screen: placement help, every set of the program, the pain level, then a summary.
struct WorkoutView: View {
    private enum Stage {
        case sets
        case pain
        case summary(Session)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var plan: WorkoutPlan
    @State private var stage: Stage
    @State private var start = Date.now
    /// Filmed exercises whose example the patient has watched in this session.
    @State private var examplesSeen: Set<Int> = []
    @State private var confirmingStop = false
    /// The set on screen has started (a repetition counted, the timer running): stopping would lose it.
    @State private var currentSetStarted = false
    /// Asked from the Passer menu: the set's screen answers with what it did so far.
    @State private var skipRequest: SkipRequest?
    private let offersMoreSets: Bool

    /// - Parameter onlyExercise: index of the single exercise to do, or nil for the whole program.
    init(program: Program, onlyExercise: Int? = nil) {
        var exercises = program.orderedExercises
        if let onlyExercise, exercises.indices.contains(onlyExercise) { exercises = [exercises[onlyExercise]] }
        self.init(exercises: exercises.map(\.workoutExercise), offersMoreSets: onlyExercise != nil)
    }

    /// Exercises without a program, e.g. one exercise chosen on its own: its last set offers one more.
    init(exercises: [WorkoutExercise], offersMoreSets: Bool = false) {
        self.offersMoreSets = offersMoreSets
        let plan = WorkoutPlan(exercises: exercises)
        _plan = State(initialValue: plan)
        _stage = State(initialValue: .sets)
    }

    var body: some View {
        NavigationStack {
            content
                .onDisappear { WorkoutLiveActivity.shared.end() }
                .toolbar {
                    if case .summary = stage {} else {
                        ToolbarItem(placement: .topBarLeading) {
                            // Anchored to the button, so the bubble points at it.
                            Button("Arrêter la séance", systemImage: "xmark") {
                                // Nothing done yet: nothing to lose, so no question (HIG: Feedback).
                                if plan.nothingDone, !currentSetStarted { dismiss() } else { confirmingStop = true }
                            }
                                .confirmationDialog("Arrêter la séance ?", isPresented: $confirmingStop, titleVisibility: .visible) {
                                    if !plan.nothingDone {
                                        Button("Enregistrer ce qui a été fait") {
                                            plan.finishEarly()
                                            stage = .pain
                                        }
                                    }
                                    Button("Abandonner la séance", role: .destructive) { dismiss() }
                                    Button("Continuer la séance", role: .cancel) {}
                                }
                        }
                        ToolbarItem(placement: .topBarTrailing) {
                            skipMenu
                        }
                    }
                }
        }
    }

    /// Moving on without finishing: always one tap away, whatever the set is doing.
    @ViewBuilder
    private var skipMenu: some View {
        if case .sets = stage, let step = plan.currentStep {
            Menu("Passer", systemImage: "forward.end.fill") {
                Button(plan.nextStep == nil ? "Terminer cette série" : "Passer à la série suivante", systemImage: "forward.frame") {
                    skipRequest = SkipRequest(kind: .set)
                }
                if step.exercise.sets > step.set || plan.nextStep?.exerciseIndex != step.exerciseIndex {
                    Button("Passer cet exercice", systemImage: "forward.end") {
                        skipRequest = SkipRequest(kind: .exercise)
                    }
                }
                Button("Terminer la séance", systemImage: "flag.checkered") {
                    if plan.nothingDone, !currentSetStarted { dismiss() } else { confirmingStop = true }
                }
            }
            .menuIndicator(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .sets:
            if let step = plan.currentStep {
                stepView(step)
                    .environment(\.reportSetActivity) { currentSetStarted = true }
                    .environment(\.skipRequest, skipRequest)
                    // A fresh screen (and camera analysis) for every set.
                    .id(plan.currentIndex)
                    .onChange(of: plan.currentIndex, initial: true) { showOnLockScreen(step) }
                    .onDisappear { if plan.isFinished { WorkoutLiveActivity.shared.end() } }
            }
        case .pain:
            PainView(nothingDone: plan.nothingDone, onSave: save, onDiscard: { dismiss() })
        case .summary(let session):
            WorkoutSummaryView(session: session) { dismiss() }
        }
    }

    @ViewBuilder
    private func stepView(_ step: WorkoutStep) -> some View {
        let title: LocalizedStringKey = "Série \(step.set) sur \(step.exercise.sets)"
        switch step.exercise.mode {
        case .camera(let catalogID):
            if let exercise = CatalogExercise.find(catalogID), let reference = exercise.reference,
               plan.isFirstSetOfExercise, !examplesSeen.contains(step.exerciseIndex) {
                // Filmed at the physiotherapist's: the patient watches their video before doing it.
                ReferenceExampleView(movement: reference, setTitle: title) {
                    examplesSeen.insert(step.exerciseIndex)
                }
            } else if let exercise = CatalogExercise.find(catalogID) {
                SessionView(
                    exercise: exercise,
                    targetReps: step.exercise.reps,
                    setTitle: title,
                    showsDemonstration: plan.isFirstSetOfExercise,
                    nextTitle: nextTitle,
                    onAnotherSet: anotherSetAction,
                    onFinish: finish
                )
            }
        case .manual:
            ManualSetView(name: step.exercise.name, targetReps: step.exercise.reps, setTitle: title, onFinish: finish)
        case .hold(let seconds):
            HoldSetView(name: step.exercise.name, targetSeconds: seconds, setTitle: title, onFinish: finish)
        }
    }

    /// The set in progress on the Lock Screen and in the Dynamic Island.
    private func showOnLockScreen(_ step: WorkoutStep) {
        let catalog = step.exercise.catalogID.flatMap(CatalogExercise.find)
        let seconds: Int? = if case .hold(let seconds) = step.exercise.mode { seconds } else { nil }
        WorkoutLiveActivity.shared.start(
            exercise: step.exercise.name,
            symbol: catalog?.symbol ?? "figure.cooldown",
            set: step.set,
            totalSets: step.exercise.sets,
            targetReps: seconds ?? step.exercise.reps,
            isHold: seconds != nil
        )
    }

    /// What comes after this set, for the end-of-set card.
    private var nextTitle: LocalizedStringKey? {
        guard let next = plan.nextStep else { return nil }
        return next.exerciseIndex == plan.currentStep?.exerciseIndex
            ? "Série \(next.set) sur \(next.exercise.sets)"
            : "\(next.exercise.name), série 1 sur \(next.exercise.sets)"
    }

    private var anotherSetAction: ((SetResult) -> Void)? {
        guard offersMoreSets else { return nil }
        return { result in anotherSet(result) }
    }

    /// Keeps the set just done and adds one more of the same exercise.
    private func anotherSet(_ result: SetResult) {
        currentSetStarted = false
        plan.record(result)
        plan.addSet()
    }

    private func finish(_ result: SetResult) {
        currentSetStarted = false
        if skipRequest?.kind == .exercise {
            plan.skipExercise(keeping: result)
        } else {
            plan.record(result)
        }
        skipRequest = nil
        if plan.isFinished { stage = .pain }
    }

    private func save(pain: Int) {
        let results = plan.summary.enumerated().map { index, item in
            let exercise = item.exercise, tally = item.tally
            let holdSeconds = if case .hold(let seconds) = exercise.mode { seconds } else { 0 }
            return ExerciseResult(
                exerciseName: exercise.name,
                catalogID: exercise.catalogID,
                order: index,
                plannedReps: holdSeconds == 0 ? exercise.sets * exercise.reps : 0,
                completedReps: tally.completedReps,
                incompleteReps: tally.incompleteReps,
                plannedSeconds: exercise.sets * holdSeconds,
                heldSeconds: tally.heldSeconds,
                amplitude: tally.amplitude
            )
        }
        let session = Session(pain: pain, duration: Date.now.timeIntervalSince(start), results: results)
        context.insert(session)
        stage = .summary(session)
    }
}

extension PlannedExercise {
    var workoutExercise: WorkoutExercise {
        let mode: WorkoutMode = if let holdSeconds {
            .hold(seconds: holdSeconds)
        } else if let catalogExercise {
            .camera(catalogID: catalogExercise.id)
        } else {
            .manual
        }
        return WorkoutExercise(name: name, catalogID: catalogID, mode: mode, sets: sets, reps: reps)
    }
}

/// "Passer" was chosen in the session's menu: the set's screen finishes with what it did so far.
struct SkipRequest: Equatable {
    enum Kind {
        /// Only this set.
        case set
        /// This set and the exercise's remaining sets.
        case exercise
    }

    let kind: Kind
    let id = UUID()
}

extension EnvironmentValues {
    /// Called by a set's screen once something was done in it, so stopping the session asks before losing it.
    @Entry var reportSetActivity: () -> Void = {}
    @Entry var skipRequest: SkipRequest? = nil
}
