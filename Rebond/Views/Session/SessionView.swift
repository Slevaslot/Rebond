import SwiftUI

/// Guided session: camera feed with the skeleton, repetition counter, depth gauge and corrections on top.
struct SessionView: View {
    let exercise: CatalogExercise
    /// Shown under the exercise name, e.g. "Série 1 sur 3".
    let setTitle: LocalizedStringKey
    /// What comes next, shown at the end of the set. Nil after the last set.
    let nextTitle: LocalizedStringKey?
    /// After the last set of an exercise done on its own: one more set, instead of ending on a countdown.
    var onAnotherSet: ((SetResult) -> Void)?
    let onFinish: (SetResult) -> Void

    @State private var motion: MotionSession
    @Environment(\.reportSetActivity) private var reportSetActivity
    @Environment(\.skipRequest) private var skipRequest
    @Environment(\.pauseRequest) private var pauseRequest
    /// Seconds before the next set starts on its own, once this one is finished.
    @State private var restRemaining = SessionView.restDuration
    /// Long enough to breathe and walk back, short enough not to have to touch the phone.
    private static let restDuration = 20
    @State private var placement = GuidePlacement.notVisible
    @ScaledMetric private var ringSize = 64
    /// The model's card during the set: fixed, in the middle of the left edge.
    @ScaledMetric private var cardWidth = 110
    @ScaledMetric private var pauseIconSize = 72

    init(
        exercise: CatalogExercise,
        targetReps: Int,
        setTitle: LocalizedStringKey,
        showsDemonstration: Bool = true,
        nextTitle: LocalizedStringKey? = nil,
        onAnotherSet: ((SetResult) -> Void)? = nil,
        onFinish: @escaping (SetResult) -> Void
    ) {
        self.exercise = exercise
        self.setTitle = setTitle
        self.nextTitle = nextTitle
        self.onAnotherSet = onAnotherSet
        self.onFinish = onFinish
        _motion = State(initialValue: MotionSession(exercise: exercise, targetReps: targetReps, showsDemonstration: showsDemonstration))
    }

    var body: some View {
        ZStack {
            Color.black
            if !motion.cameraUnavailable {
                // Watching the model or paused, the camera fades back: the whole picture is blurred by the camera
                // processing itself, in a single blur with the background, and dimmed here.
                CameraFrameView(frame: motion.liveFrame)
                if isWatching || motion.isPaused {
                    Color.black.opacity(0.3)
                }
                if let skeleton = motion.skeleton, !isWatching, !motion.isPaused {
                    SkeletonOverlay(
                        skeleton: skeleton,
                        highlightedJoints: exercise.highlightedJoints,
                        highlightColor: AmplitudeTier(progress: motion.depthProgress)?.color ?? .yellow,
                        faultyJoints: motion.faultToHighlight?.bodyJoints ?? []
                    )
                }
            }
            if showsPlacementGuide {
                // Still measuring the placement while hidden: the outline appears once the patient stands
                // far enough for their whole body to fit.
                MovementGuide(exercise: exercise, skeleton: motion.skeleton, isDemonstrating: false) { placement in
                    self.placement = placement
                    motion.updatePlacement(placement)
                }
                .opacity(isFarEnough ? 1 : 0)
                .animation(.smooth(duration: 0.6), value: isFarEnough)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Group {
                if motion.cameraUnavailable {
                    topCard(title: "Caméra indisponible", detail: motion.cameraAccessDenied
                        ? "Autorisez l'accès à la caméra dans Réglages pour que Rebond suive vos mouvements."
                        : "Aucune caméra avant n'est disponible. Vous pouvez terminer la série.")
                } else if motion.isPaused {
                    EmptyView()
                } else if motion.phase == .calibrating, !motion.showsDemonstration {
                    topCard(title: "Mettez-vous en position de départ",
                            detail: "La série reprend dès que vous êtes immobile")
                } else if motion.phase == .calibrating, placement == .notVisible {
                    topCard(title: "Posez votre iPhone debout",
                            detail: "Calez-le à hauteur de hanche, puis reculez à 2 ou 3 mètres pour voir tout votre corps.")
                } else if motion.phase == .calibrating || motion.isLost, !isFarEnough {
                    topCard(title: "Reculez",
                            detail: "Éloignez-vous du téléphone jusqu'à voir tout votre corps, pieds compris. La silhouette apparaîtra alors.")
                } else if motion.phase == .calibrating || motion.isLost {
                    placementHint
                } else if motion.phase == .demonstrating {
                    topCard(title: "Faites le mouvement avec le modèle", detail: "Vos répétitions comptent déjà")
                } else if isWatching, !motion.isPaused {
                    topCard(title: "Regardez le mouvement", detail: "Touchez le modèle pour reprendre")
                } else {
                    counter
                }
            }
            .padding()
        }
        .overlay {
            if showsFloatingGuide, !motion.isPaused, !motion.isLost {
                floatingGuide
            }
        }
        .overlay {
            if motion.isPaused {
                Button("Reprendre", systemImage: "pause.fill") { motion.togglePause() }
                    .labelStyle(.iconOnly)
                    .font(.system(size: pauseIconSize))
                    .padding(pauseIconSize * 0.4)
                    .glassEffect(in: .circle)
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.3), value: motion.isPaused)
        .animation(.smooth(duration: 0.55), value: motion.guideDisplay)
        .overlay(alignment: .trailing) {
            if motion.phase == .active, motion.bodyVisible, !motion.isPaused, !motion.isLost, !isWatching {
                DepthGauge(progress: motion.depthProgress, fillsUpward: exercise.fillsGaugeUpward)
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.4 }
                    .padding()
                    .transition(.opacity)
            }
        }
        .overlay {
            statusCard.padding()
        }
        .overlay(alignment: .bottom) {
            // While paused, only the top bar and the pause button remain.
            if !motion.isPaused {
                VStack(spacing: 16) {
                    if let feedback = motion.feedback {
                        feedbackBanner(feedback)
                    }
                    // During setup the guide outline needs the space; Passer stays in the toolbar.
                    if motion.phase == .active || motion.cameraUnavailable {
                        Button("Terminer la série") { onFinish(motion.result) }
                            .buttonStyle(.glass)
                            .controlSize(.extraLarge)
                    }
                    if motion.phase == .active, exercise.allowsHandGestures {
                        gestureReminder
                    }
                }
                .padding()
                .animation(.spring(duration: 0.35), value: motion.feedback)
            }
        }
        .navigationTitle(Text(exercise.name))
        .navigationSubtitle(Text(setTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if motion.phase != .finished, !motion.cameraUnavailable {
                    Button(motion.isPaused ? "Reprendre" : "Pause",
                           systemImage: motion.isPaused ? "play.fill" : "pause.fill") {
                        motion.togglePause()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(motion.isMuted ? "Activer la voix" : "Couper la voix",
                       systemImage: motion.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    motion.isMuted.toggle()
                }
            }
        }
        .onChange(of: isWatching || motion.isPaused, initial: true) { _, blurred in
            motion.blurWholePicture(blurred)
        }
        .task {
            // Thumbs up from where the patient stands: next set.
            let session = motion
            session.onNext = { [weak session] in
                guard let session else { return }
                onFinish(session.result)
            }
            await motion.start()
        }
        .onChange(of: skipRequest) { if skipRequest != nil { onFinish(motion.result) } }
        // The pause button of the Apple Watch.
        .onChange(of: pauseRequest) {
            if motion.phase != .finished, !motion.cameraUnavailable { motion.togglePause() }
        }
        .task(id: motion.phase == .finished) {
            // The next set starts on its own after a short rest: no need to walk back to the phone.
            // Not when the patient chooses between one more set and stopping.
            guard motion.phase == .finished, !offersAnotherSet else { return }
            restRemaining = Self.restDuration
            while restRemaining > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, motion.phase == .finished else { return }
                restRemaining -= 1
            }
            onFinish(motion.result)
        }
        .onDisappear { motion.stop() }
        .onChange(of: motion.repCount + motion.incompleteCount) { reportSetActivity() }
        .onChange(of: motion.repCount) { WorkoutLiveActivity.shared.update(count: motion.repCount) }
        .onChange(of: motion.isPaused) { WorkoutLiveActivity.shared.setPaused(motion.isPaused) }
        .sensoryFeedback(.success, trigger: motion.repCount)
        .sensoryFeedback(.warning, trigger: motion.incompleteCount)
        .animation(.default, value: motion.phase)
        .animation(.default, value: motion.bodyVisible)
        .animation(.default, value: motion.isLost)
    }

    private var counter: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(.white.opacity(0.25), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: Double(motion.repCount) / Double(motion.targetReps))
                    .stroke(.green, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: motion.repCount)
                Text(motion.repCount, format: .number)
                    .font(.title.bold())
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.default, value: motion.repCount)
            }
            .frame(width: ringSize, height: ringSize)
            .keyframeAnimator(initialValue: 1.0, trigger: motion.repCount) { content, scale in
                content.scaleEffect(scale)
            } keyframes: { _ in
                SpringKeyframe(1.2, duration: 0.15)
                SpringKeyframe(1.0, duration: 0.35)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("sur \(motion.targetReps) répétitions")
                    .font(.headline)
                if motion.incompleteCount > 0 {
                    Text("Incomplètes : \(motion.incompleteCount)")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding()
        .glassEffect(in: .rect(cornerRadius: 28))
        .accessibilityElement(children: .combine)
    }

    /// The last set of an exercise done on its own: the patient decides whether to do another one.
    private var offersAnotherSet: Bool {
        onAnotherSet != nil && nextTitle == nil
    }

    /// Far enough from the phone for the outline: the whole body is seen at a size that fits it.
    private var isFarEnough: Bool {
        switch placement {
        case .notVisible, .showFeet, .stepBack: false
        case .stepCloser, .moveLeft, .moveRight, .almost, .aligned: true
        }
    }

    /// The hand signs, from where the patient stands.
    private var gestureReminder: some View {
        HStack(spacing: 16) {
            Label("Pause", systemImage: "hand.raised.fill")
            Label("Série suivante", systemImage: "hand.thumbsup.fill")
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("Main ouverte levée : pause. Pouce levé : série suivante."))
    }

    /// The model is large: the patient watches, the camera fades back.
    private var isWatching: Bool {
        motion.isWatching
    }

    /// Before the set: the large guide, to get in place.
    /// Before the set, and during it when the camera lost the patient.
    /// Only before the first set of an exercise: later sets start where the patient already stands.
    private var showsPlacementGuide: Bool {
        (motion.phase == .calibrating && motion.showsDemonstration) || motion.isLost
    }

    /// From the demonstration on: one guide that moves between large (demonstrating) and its card.
    private var showsFloatingGuide: Bool {
        switch motion.phase {
        case .demonstrating, .active: true
        case .calibrating, .finished: false
        }
    }

    private var guideInCard: Bool {
        motion.guideDisplay == .corner
    }

    /// The model's card: full screen to watch the movement, or a fixed card on the left.
    private func floatingGuideFrame(in size: CGSize) -> CGRect {
        guard guideInCard else { return CGRect(origin: .zero, size: size) }
        // A video needs more room than the pictogram to be seen from 2 or 3 meters.
        let width = exercise.reference != nil ? cardWidth * 1.4 : cardWidth
        let height = width * 1.5
        return CGRect(x: 16, y: (size.height - height) / 2, width: width, height: height)
    }

    /// Where the figure is drawn when large: the size and place it had to get in place.
    private func largeFigureFrame(in screen: CGSize) -> CGRect {
        let figure = MovementGuide(exercise: exercise, skeleton: nil, isDemonstrating: false).figureBox(in: screen)
        let height = figure.height / 0.9
        return CGRect(x: figure.midX - height / 2, y: figure.midY - height / 2, width: height, height: height)
    }

    /// Where the figure goes: large in front of the patient, or filling its card.
    private func figureFrame(in card: CGRect, screen: CGSize) -> CGRect {
        guard guideInCard else { return largeFigureFrame(in: screen) }
        let side = min(card.width, card.height) - 16
        return CGRect(x: card.midX - side / 2, y: card.midY - side / 2, width: side, height: side)
    }

    /// One card for the model at every size: it shrinks from large into its card, and opens back up.
    /// A tap opens it large in front of the patient, without pausing; another tap puts it back.
    private var floatingGuide: some View {
        GeometryReader { geometry in
            let card = floatingGuideFrame(in: geometry.size)
            let figure = figureFrame(in: card, screen: geometry.size)
            // Always drawn at its large size and scaled down: it shrinks smoothly, like its card.
            let large = largeFigureFrame(in: geometry.size)
            let scale = figure.height / large.height
            ZStack {
                RoundedRectangle(cornerRadius: guideInCard ? 20 : 0)
                    .fill(.clear)
                    .glassEffect(in: .rect(cornerRadius: guideInCard ? 20 : 0))
                    .opacity(guideInCard ? 1 : 0)
                    .frame(width: card.width, height: card.height)
                    .position(x: card.midX, y: card.midY)
                if let reference = exercise.reference {
                    // A filmed movement: the video of the physiotherapist's, moving as the patient moves.
                    ReferenceFramesView(movement: reference,
                                        progress: guideInCard ? motion.depthProgress : nil,
                                        contentMode: guideInCard ? .fill : .fit)
                        .frame(width: card.width, height: card.height)
                        .clipShape(.rect(cornerRadius: guideInCard ? 20 : 0))
                        .position(x: card.midX, y: card.midY)
                } else {
                    MovementGuide(
                        exercise: exercise,
                        skeleton: nil,
                        isDemonstrating: true,
                        demonstrationStart: motion.demonstrationStart,
                        isCompact: true,
                        lineWidth: guideInCard ? 3 / scale : 6
                    )
                    .frame(width: large.width, height: large.height)
                    .scaleEffect(scale)
                    .position(x: figure.midX, y: figure.midY)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Only the model itself reacts to touches: the rest of the screen stays usable.
            .contentShape(guideInCard ? Path(roundedRect: card, cornerRadius: 20) : Path(figure))
            .onTapGesture {
                if guideInCard { motion.expandModel() } else { motion.shrinkModel() }
            }
            .allowsHitTesting(motion.phase == .active)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(Text("Modèle du mouvement"))
        .accessibilityHint(guideInCard
            ? Text("Touchez pour l'agrandir devant vous")
            : Text("Touchez pour le ranger dans sa vignette"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if guideInCard { motion.expandModel() } else { motion.shrinkModel() }
        }
    }

    /// Where to move to fit in the guide outline, in one short line.
    private var placementHint: some View {
        Label {
            Text(placement.message)
        } icon: {
            Image(systemName: placement == .aligned ? "checkmark.circle.fill" : "figure.stand")
                .foregroundStyle(placement == .aligned ? .green : placement == .almost ? .yellow : .white)
        }
        .font(.headline)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(in: .capsule)
        .contentTransition(.opacity)
        .animation(.default, value: placement)
    }

    private func topCard(title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding()
        .glassEffect(in: .rect(cornerRadius: 24))
    }

    /// Body lost during the set and end-of-set messages, in the middle of the screen.
    @ViewBuilder
    private var statusCard: some View {
        if motion.phase == .finished, offersAnotherSet {
            VStack(spacing: 16) {
                card(systemImage: "checkmark.circle.fill", color: .green,
                     title: "Série terminée !",
                     detail: "\(motion.repCount) répétitions")
                HStack {
                    Button("Terminer", systemImage: "flag.checkered") {
                        onFinish(motion.result)
                    }
                    .buttonStyle(.glass)
                    Button("Une série de plus", systemImage: "arrow.clockwise") {
                        onAnotherSet?(motion.result)
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.extraLarge)
            }
        } else if motion.phase == .finished {
            VStack(spacing: 16) {
                card(systemImage: "checkmark.circle.fill", color: .green,
                     title: "Série terminée !",
                     detail: "\(motion.repCount) répétitions")
                VStack(spacing: 6) {
                    if let nextTitle {
                        Text("Ensuite : \(Text(nextTitle))")
                            .font(.headline)
                    }
                    Text(nextTitle == nil ? "Fin dans \(restRemaining) s" : "Reprise dans \(restRemaining) s")
                        .font(.subheadline)
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.default, value: restRemaining)
                    if exercise.allowsHandGestures {
                        Label("Pouce levé pour continuer tout de suite", systemImage: "hand.thumbsup.fill")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.center)
                .padding()
                .glassEffect(in: .rect(cornerRadius: 24))
                HStack {
                    Button("Recommencer", systemImage: "arrow.counterclockwise") {
                        motion.restart()
                    }
                    .buttonStyle(.glass)
                    Button("Continuer", systemImage: "arrow.right") {
                        onFinish(motion.result)
                    }
                    .buttonStyle(.glassProminent)
                }
                .controlSize(.extraLarge)
            }
        }
    }

    private func card(systemImage: String, color: Color, title: LocalizedStringKey, detail: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(.largeTitle))
                .foregroundStyle(color)
                .symbolEffect(.pulse, isActive: motion.phase != .finished)
            Text(title)
                .font(.title2.bold())
            Text(detail)
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(24)
        .glassEffect(in: .rect(cornerRadius: 32))
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }

    @ViewBuilder
    private func feedbackBanner(_ feedback: MotionSession.Feedback) -> some View {
        if let tier = feedback.tier {
            tierBanner(tier, id: feedback.id)
        } else {
            correctionBanner(feedback)
        }
    }

    /// "Bien", "Très bien" or "Parfait !", in the tier's color.
    private func tierBanner(_ tier: AmplitudeTier, id: UUID) -> some View {
        Label {
            Text(tier.message)
        } icon: {
            Image(systemName: "checkmark.circle.fill")
        }
        .font(.title3.bold())
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(tier.color.opacity(0.7)), in: .capsule)
        .symbolEffect(.bounce, value: id)
        .id(id)
        .transition(.scale(scale: 0.8).combined(with: .opacity))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(tier.message))
    }

    private func correctionBanner(_ feedback: MotionSession.Feedback) -> some View {
        Label {
            Text(feedback.message)
        } icon: {
            Image(systemName: feedback.isPositive ? "hand.thumbsup.fill" : "exclamationmark.triangle.fill")
        }
        .font(.title3.bold())
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint((feedback.isPositive ? Color.green : Color.orange).opacity(0.6)), in: .capsule)
        .id(feedback.id)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}
