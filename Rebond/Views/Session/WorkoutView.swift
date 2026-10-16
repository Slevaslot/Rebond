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
    /// Pause or resume, asked from afar (hand sign, Siri, the Apple Watch, the Live Activity).
    @State private var pauseRequest: UUID?
    /// The model large or back in its card, asked by a hand sign.
    @State private var modelRequest: ModelRequest?
    /// Every command, from every source, comes through here.
    private let remote = SessionRemote.shared
    /// Says the commands understood from afar.
    @State private var voice = Coach()
    /// The session was saved: leaving it no longer abandons it on the watch.
    @State private var saved = false
    /// The confirmation of a command from afar stays until then.
    @State private var bannerUntil = Date.distantPast
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
                .onChange(of: remote.request) { _, request in
                    if let request { carryOut(request) }
                }
                .onChange(of: remote.feedback) { _, feedback in
                    if let feedback {
                        bannerUntil = .now.addingTimeInterval(2.5)
                        announce(feedback)
                    }
                }
                .overlay(alignment: .top) { commandBanner }
                .onDisappear { remote.screen = .none }
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
                                            // The set on screen keeps what it did.
                                            remote.send(.endSession, from: .screen)
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
                    remote.send(.nextSet, from: .screen)
                }
                if step.exercise.sets > step.set || plan.nextStep?.exerciseIndex != step.exerciseIndex {
                    Button("Passer cet exercice", systemImage: "forward.end") {
                        remote.send(.nextExercise, from: .screen)
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
                    .environment(\.modelRequest, modelRequest)
                    .environment(\.handlesSessionRequests, true)
                    // A fresh screen (and camera analysis) for every set.
                    .id(plan.currentIndex)
                    .onChange(of: plan.currentIndex, initial: true) {
                        showOnLockScreen(step)
                        remote.hasNextExercise = plan.steps.contains { $0.exerciseIndex > step.exerciseIndex }
                    }
                    // Switched to counting by hand: the watch and the Live Activity drop the pause button.
                    .onChange(of: countedByHand) { showOnLockScreen(step) }
                    .onDisappear { if plan.isFinished { WorkoutLiveActivity.shared.end() } }
            }
        case .pain:
            PainView(nothingDone: plan.nothingDone, onSave: save, onDiscard: { dismiss() })
                .sessionScreen(.finishing)
        case .summary(let session):
            WorkoutSummaryView(session: session) { dismiss() }
                .sessionScreen(.finishing)
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
                    side: step.isMirrored ? .mirrored : .asFilmed,
                    onFinish: finish
                )
            }
        case .manual:
            ManualSetView(name: step.exercise.name, targetReps: step.exercise.reps, setTitle: title, onFinish: finish)
        case .hold(let seconds):
            if let exercise = step.exercise.catalogID.flatMap(CatalogExercise.find), exercise.reference?.isHold == true,
               !countedByHand.contains(step.exerciseIndex) {
                // A position filmed at the physiotherapist's: the camera runs the timer while it is held.
                SessionView(
                    exercise: exercise,
                    targetReps: 1,
                    setTitle: title,
                    showsDemonstration: plan.isFirstSetOfExercise,
                    nextTitle: nextTitle,
                    onAnotherSet: anotherSetAction,
                    onCountByHand: { countedByHand.insert(step.exerciseIndex) },
                    mirrorsModel: step.isMirrored,
                    targetSeconds: seconds,
                    side: step.isMirrored ? .mirrored : .asFilmed,
                    onFinish: finish
                )
            } else {
                HoldSetView(name: step.exercise.name, targetSeconds: seconds, setTitle: title, onFinish: finish)
            }
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

    /// A command from any source, already resolved for the screen on display (`SessionRemote`).
    private func carryOut(_ request: SessionRemote.Request) {
        guard case .sets = stage, plan.currentStep != nil else { return }
        let watchingExample = remote.screen == .example
        switch request.action {
        case .pause, .resume, .startTimer:
            pauseRequest = UUID()
        case .expandModel:
            modelRequest = ModelRequest(expand: true)
        case .shrinkModel:
            modelRequest = ModelRequest(expand: false)
        case .finishSet:
            if watchingExample, let step = plan.currentStep {
                examplesSeen.insert(step.exerciseIndex)
            } else {
                skipRequest = SkipRequest(kind: .set)
            }
        case .skipExercise:
            if watchingExample { plan.skipExercise() } else { skipRequest = SkipRequest(kind: .exercise) }
            if plan.isFinished { finishSets() }
        case .endSession:
            if plan.nothingDone, !currentSetStarted {
                dismiss()
            } else if watchingExample {
                plan.finishEarly()
                finishSets()
            } else {
                // The set on screen answers with what it did, then the session ends (`finish`).
                skipRequest = SkipRequest(kind: .session)
            }
        case .ignored:
            break
        }
    }

    /// Said aloud, for a command understood from afar (the screen shows it too, `commandBanner`).
    /// Pause and resume are said by the set's screen itself.
    private func announce(_ feedback: SessionRemote.Request) {
        switch feedback.action {
        case .finishSet, .skipExercise, .endSession:
            if let text = feedback.action.confirmation { voice.say(text, urgency: .immediate) }
        default:
            break
        }
    }

    /// The command understood from afar, at the top of the screen for a moment; ending the session by a hand sign
    /// is asked again here, with buttons for those who walked back to the phone.
    @ViewBuilder
    private var commandBanner: some View {
        if let feedback = remote.feedback, let text = feedback.action.confirmation {
            TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
                let asking = remote.isAskingToEnd
                if asking || timeline.date < bannerUntil {
                    VStack(spacing: 12) {
                        Label {
                            Text(text)
                        } icon: {
                            Image(systemName: feedback.action.symbol)
                        }
                        .font(.title3.bold())
                        if asking {
                            HStack {
                                Button("Continuer la séance") { remote.cancelEnd() }
                                    .buttonStyle(.glass)
                                Button("Terminer", systemImage: "flag.checkered") {
                                    remote.cancelEnd()
                                    remote.send(.endSession, from: .screen)
                                }
                                .buttonStyle(.glassProminent)
                            }
                            .controlSize(.large)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .glassEffect(in: .rect(cornerRadius: 24))
                    .padding(.top, 60)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .accessibilityElement(children: .contain)
                }
            }
            .id(feedback.id)
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
        switch skipRequest?.kind {
        case .exercise:
            plan.skipExercise(keeping: result)
        case .session:
            plan.record(result)
            plan.finishEarly()
        case .set, nil:
            plan.record(result)
        }
        skipRequest = nil
        if plan.isFinished { finishSets() }
    }

    /// Every set done (or the session ended early): the pain comes next.
    private func finishSets() {
        guard case .sets = stage else { return }
        stage = .pain
        watch.setsFinished()
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
        /// This set, then the session ends.
        case session
    }

    let kind: Kind
    let id = UUID()
}

extension EnvironmentValues {
    /// Called by a set's screen once something was done in it, so stopping the session asks before losing it.
    @Entry var reportSetActivity: () -> Void = {}
    @Entry var skipRequest: SkipRequest? = nil
    /// Pause or resume the set, asked from afar: a new value at each request.
    @Entry var pauseRequest: UUID? = nil
    /// The model large or back in its card, asked by a hand sign.
    @Entry var modelRequest: ModelRequest? = nil
    /// The screen is inside a whole session: `WorkoutView` carries out the commands.
    @Entry var handlesSessionRequests = false
}

struct ModelRequest: Equatable {
    let expand: Bool
    let id = UUID()
}
