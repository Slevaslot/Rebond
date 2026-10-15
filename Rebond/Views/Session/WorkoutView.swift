import SwiftData
import SwiftUI
import TipKit

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
    /// Exercises counted by hand because the camera is unavailable.
    @State private var countedByHand: Set<Int> = []
    @State private var confirmingStop = false
    /// The set on screen has started (a repetition counted, the timer running): stopping would lose it.
    @State private var currentSetStarted = false
    /// Asked from the Passer menu: the set's screen answers with what it did so far.
    @State private var skipRequest: SkipRequest?
    /// Pause or resume, asked from the Apple Watch.
    @State private var pauseRequest: UUID?
    /// The session was saved: leaving it no longer abandons it on the watch.
    @State private var saved = false
    private let watch = PhoneWatchLink.shared
    private let offersMoreSets: Bool
    /// An exercise tried outside any program: saved, but not counted as a session of the program.
    private let isTrial: Bool

    /// - Parameter onlyExercise: index of the single exercise to do, or nil for the whole program.
    init(program: Program, onlyExercise: Int? = nil) {
        var exercises = program.orderedExercises
        if let onlyExercise, exercises.indices.contains(onlyExercise) { exercises = [exercises[onlyExercise]] }
        self.init(exercises: exercises.map(\.workoutExercise), offersMoreSets: onlyExercise != nil)
    }

    /// Exercises without a program, e.g. one exercise chosen on its own: its last set offers one more.
    init(exercises: [WorkoutExercise], offersMoreSets: Bool = false, isTrial: Bool = false) {
        self.offersMoreSets = offersMoreSets
        self.isTrial = isTrial
        let plan = WorkoutPlan(exercises: exercises)
        _plan = State(initialValue: plan)
        _stage = State(initialValue: .sets)
    }

    var body: some View {
        NavigationStack {
            content
                .onAppear { watch.sessionStarted(at: start) }
                .onDisappear {
                    WorkoutLiveActivity.shared.end()
                    if !saved { watch.sessionEnded(saved: false) }
                }
                .onChange(of: watch.command) { _, command in
                    if let command { handleWatch(command.message) }
                }
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
                                            watch.setsFinished()
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
                    .environment(\.pauseRequest, pauseRequest)
                    // A fresh screen (and camera analysis) for every set.
                    .id(plan.currentIndex)
                    .onChange(of: plan.currentIndex, initial: true) { showOnLockScreen(step) }
                    // Switched to counting by hand: the watch and the Live Activity drop the pause button.
                    .onChange(of: countedByHand) { showOnLockScreen(step) }
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
        let title: LocalizedStringKey = switch step.side {
        case .right: "Série \(step.set) sur \(step.exercise.sets) · côté droit"
        case .left: "Série \(step.set) sur \(step.exercise.sets) · côté gauche"
        case nil: "Série \(step.set) sur \(step.exercise.sets)"
        }
        switch step.exercise.mode {
        case .camera where countedByHand.contains(step.exerciseIndex):
            ManualSetView(name: step.exercise.name, targetReps: step.exercise.reps, setTitle: title, onFinish: finish)
        case .camera(let catalogID):
            if let exercise = CatalogExercise.find(catalogID), let reference = exercise.reference,
               plan.isFirstSetOfExercise, !examplesSeen.contains(step.exerciseIndex) {
                // Filmed at the physiotherapist's: the patient watches their video before doing it.
                ReferenceExampleView(movement: reference, setTitle: title, isMirrored: step.isMirrored) {
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
                    onCountByHand: { countedByHand.insert(step.exerciseIndex) },
                    mirrorsModel: step.isMirrored,
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
        let side: String? = switch step.side {
        case .right: String(localized: "côté droit")
        case .left: String(localized: "côté gauche")
        case nil: nil
        }
        WorkoutLiveActivity.shared.start(
            exercise: step.exercise.name,
            symbol: catalog?.symbol ?? "figure.cooldown",
            set: step.set,
            totalSets: step.exercise.sets,
            targetReps: seconds ?? step.exercise.reps,
            isHold: seconds != nil,
            // Counted by hand (no camera follows it, or none available): nothing to pause.
            canPause: step.exercise.mode != .manual && !countedByHand.contains(step.exerciseIndex),
            startsPaused: seconds != nil,
            side: side
        )
    }

    /// A tap on the Apple Watch: the same as the Passer menu's next set, or the pause button.
    private func handleWatch(_ message: WatchMessage) {
        guard case .sets = stage, plan.currentStep != nil else { return }
        switch message {
        case .nextSet: skipRequest = SkipRequest(kind: .set)
        case .togglePause: pauseRequest = UUID()
        case .recordingWorkout: break
        }
    }

    /// What comes after this set, for the end-of-set card.
    private var nextTitle: LocalizedStringKey? {
        guard let next = plan.nextStep else { return nil }
        // The other side of the same set: say only which side.
        if next.exerciseIndex == plan.currentStep?.exerciseIndex, next.set == plan.currentStep?.set, let side = next.side {
            return side == .left ? "Côté gauche" : "Côté droit"
        }
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
        if plan.isFinished {
            stage = .pain
            watch.setsFinished()
        }
    }

    private func save(pain: Int) {
        let results = plan.summary.enumerated().map { index, item in
            let exercise = item.exercise, tally = item.tally
            let holdSeconds = if case .hold(let seconds) = exercise.mode { seconds } else { 0 }
            return ExerciseResult(
                exerciseName: exercise.name,
                catalogID: exercise.catalogID,
                order: index,
                plannedReps: holdSeconds == 0 ? exercise.sets * exercise.reps * exercise.sideCount : 0,
                completedReps: tally.completedReps,
                incompleteReps: tally.incompleteReps,
                plannedSeconds: exercise.sets * holdSeconds * exercise.sideCount,
                heldSeconds: tally.heldSeconds,
                amplitude: tally.amplitude
            )
        }
        let session = Session(pain: pain, duration: Date.now.timeIntervalSince(start), results: results, isTrial: isTrial)
        context.insert(session)
        saved = true
        PhoneHealth.shared.record(start: start, end: .now, watchRecorded: watch.watchRecordsWorkout)
        watch.sessionEnded(saved: true)
        SiriPauseTip.sessionSaved.sendDonation()
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
        // A film starts on the side it shows, the other one mirrored; Rebond's models start on the right.
        let firstSide = catalogExercise?.reference?.filmedSide ?? .right
        return WorkoutExercise(name: name, catalogID: catalogID, mode: mode, sets: sets, reps: reps,
                               bothSides: bothSides, firstSide: firstSide)
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
    /// Pause or resume the set, asked from the Apple Watch: a new value at each request.
    @Entry var pauseRequest: UUID? = nil
}
