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
    @State private var confirmingStop = false
    /// The set on screen has started (a repetition counted, the timer running): stopping would lose it.
    @State private var currentSetStarted = false

    init(program: Program) {
        let plan = WorkoutPlan(exercises: program.orderedExercises.map(\.workoutExercise))
        _plan = State(initialValue: plan)
        _stage = State(initialValue: .sets)
    }

    var body: some View {
        NavigationStack {
            content
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
                    }
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch stage {
        case .sets:
            if let step = plan.currentStep {
                stepView(step)
                    .environment(\.reportSetActivity) { currentSetStarted = true }
                    // A fresh screen (and camera analysis) for every set.
                    .id(plan.currentIndex)
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
            if let exercise = CatalogExercise.find(catalogID) {
                SessionView(exercise: exercise, targetReps: step.exercise.reps, setTitle: title, onFinish: finish)
            }
        case .manual:
            ManualSetView(name: step.exercise.name, targetReps: step.exercise.reps, setTitle: title, onFinish: finish)
        case .hold(let seconds):
            HoldSetView(name: step.exercise.name, targetSeconds: seconds, setTitle: title, onFinish: finish)
        }
    }

    private func finish(_ result: SetResult) {
        currentSetStarted = false
        plan.record(result)
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
        #if DEBUG
        Task { await DemoServer.shared.pushReport(context: context) }
        #endif
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

extension EnvironmentValues {
    /// Called by a set's screen once something was done in it, so stopping the session asks before losing it.
    @Entry var reportSetActivity: () -> Void = {}
}
