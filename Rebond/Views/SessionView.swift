import SwiftUI

/// Guided session: camera feed with the skeleton, repetition counter, depth gauge and corrections on top.
struct SessionView: View {
    let exercise: CatalogExercise
    /// Shown under the exercise name, e.g. "Série 1 sur 3".
    let setTitle: LocalizedStringKey
    let onFinish: (SetResult) -> Void

    @State private var motion: MotionSession
    @State private var placement = GuidePlacement.notVisible
    @ScaledMetric private var ringSize = 64
    @ScaledMetric private var cardWidth = 84
    @ScaledMetric private var pauseIconSize = 72
    /// The guide's card, as the patient placed and sized it.
    @State private var cardOffset = CGSize.zero
    @State private var cardScale = 1.0
    @GestureState private var drag = CGSize.zero
    @GestureState private var pinch = 1.0

    init(exercise: CatalogExercise, targetReps: Int, setTitle: LocalizedStringKey, onFinish: @escaping (SetResult) -> Void) {
        self.exercise = exercise
        self.setTitle = setTitle
        self.onFinish = onFinish
        _motion = State(initialValue: MotionSession(exercise: exercise, targetReps: targetReps))
    }

    var body: some View {
        ZStack {
            Color.black
            if !motion.cameraUnavailable {
                // While the guide demonstrates, the camera fades back: it is not the patient's turn yet.
                // Watching the demonstration or paused: the whole picture is blurred like the background.
                CameraFrameView(frame: motion.liveFrame)
                    .blur(radius: isWatching || motion.isPaused ? 12 : 0)
                if isWatching || motion.isPaused {
                    Color.black.opacity(0.3)
                }
                if let skeleton = motion.skeleton, !isWatching, !motion.isPaused {
                    SkeletonOverlay(
                        skeleton: skeleton,
                        highlightedJoints: exercise.highlightedJoints,
                        highlightColor: motion.depthProgress >= 1 ? .green : .yellow,
                        faultyJoints: motion.faultToHighlight?.bodyJoints ?? []
                    )
                }
            }
            if showsPlacementGuide {
                MovementGuide(exercise: exercise, skeleton: motion.skeleton, isDemonstrating: false) { placement in
                    self.placement = placement
                    motion.updatePlacement(placement)
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            Group {
                if motion.cameraUnavailable {
                    topCard(title: "Caméra indisponible", detail: motion.cameraAccessDenied
                        ? "Autorisez l'accès à la caméra dans Réglages pour que Rebond suive vos mouvements."
                        : "Aucune caméra avant n'est disponible. Vous pouvez terminer la série.")
                } else if motion.phase == .calibrating || motion.isLost {
                    placementHint
                } else if motion.phase == .demonstrating {
                    topCard(title: "Regardez d'abord le mouvement", detail: "Restez immobile, vous commencerez après")
                } else if !motion.isPaused {
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
            if motion.phase == .active, motion.bodyVisible, !motion.isPaused, !motion.isLost {
                DepthGauge(progress: motion.depthProgress)
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
                    // During setup the guide outline needs the space; the back button is still there.
                    if motion.phase == .active || motion.cameraUnavailable {
                        Button("Terminer la série") { onFinish(motion.result) }
                            .buttonStyle(.glass)
                            .controlSize(.extraLarge)
                    }
                }
                .padding()
                .animation(.spring(duration: 0.35), value: motion.feedback)
            }
        }
        .navigationTitle(Text(exercise.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if motion.phase == .active {
                    Button(motion.isPaused ? "Reprendre" : "Pause",
                           systemImage: motion.isPaused ? "play.fill" : "pause.fill") {
                        motion.togglePause()
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Recommencer", systemImage: "arrow.counterclockwise") {
                    motion.restart()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(motion.isMuted ? "Activer la voix" : "Couper la voix",
                       systemImage: motion.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    motion.isMuted.toggle()
                }
            }
        }
        .task { await motion.start() }
        .onDisappear { motion.stop() }
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
                Text(exercise.name)
                    .font(.headline)
                Text(setTitle)
                    .font(.subheadline)
                Text("sur \(motion.targetReps) répétitions")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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

    /// The first demonstration, before the set: the patient watches, the camera fades back.
    private var isWatching: Bool {
        motion.phase == .demonstrating && motion.guideDisplay == .large
    }

    /// Before the set: the large guide, to get in place.
    /// Before the set, and during it when the camera lost the patient.
    private var showsPlacementGuide: Bool {
        motion.phase == .calibrating || motion.isLost
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

    /// Card size limits, as a multiple of its base size. Pinching open past the largest opens it full screen.
    private let cardScales = 0.8...3.2

    /// The model card: full screen to watch the movement, or a card the patient can move and resize.
    private func floatingGuideFrame(in size: CGSize) -> CGRect {
        guard guideInCard else { return CGRect(origin: .zero, size: size) }
        let scale = min(max(cardScale * pinch, cardScales.lowerBound), cardScales.upperBound)
        let width = cardWidth * scale
        let height = width * 1.5
        let margin = 16.0
        var center = CGPoint(
            x: margin + width / 2 + cardOffset.width + drag.width,
            y: size.height / 2 + cardOffset.height + drag.height
        )
        center.x = min(max(center.x, width / 2 + margin), size.width - width / 2 - margin)
        center.y = min(max(center.y, height / 2 + margin * 4), size.height - height / 2 - margin * 4)
        return CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)
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
    /// In the card: drag to move, pinch to resize, pinch wide open or double-tap to open it large in front of
    /// the patient, without pausing. Large: tap or pinch closed to put it back in its card.
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
            .frame(width: geometry.size.width, height: geometry.size.height)
            // Only the model itself reacts to touches: the rest of the screen stays usable.
            .contentShape(guideInCard ? Path(roundedRect: card, cornerRadius: 20) : Path(figure))
            .gesture(cardGestures, isEnabled: guideInCard && motion.phase == .active)
            .onTapGesture(count: 2) {
                if guideInCard { motion.expandModel() }
            }
            .onTapGesture {
                if !guideInCard { motion.shrinkModel() }
            }
            .gesture(
                MagnifyGesture().onEnded { value in
                    if value.magnification < 0.8 { motion.shrinkModel() }
                },
                isEnabled: !guideInCard && motion.phase == .active
            )
            .allowsHitTesting(motion.phase == .active)
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(Text("Modèle du mouvement"))
        .accessibilityHint(guideInCard
            ? Text("Touchez deux fois pour l'agrandir devant vous, faites glisser pour le déplacer")
            : Text("Touchez pour le ranger dans sa vignette"))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            if guideInCard { motion.expandModel() } else { motion.shrinkModel() }
        }
    }

    private var cardGestures: some Gesture {
        DragGesture()
            .updating($drag) { value, state, _ in state = value.translation }
            .onEnded { value in
                cardOffset.width += value.translation.width
                cardOffset.height += value.translation.height
            }
            .simultaneously(with: MagnifyGesture()
                .updating($pinch) { value, state, _ in state = value.magnification }
                .onEnded { value in
                    let scale = cardScale * value.magnification
                    if scale > cardScales.upperBound {
                        motion.expandModel()
                    } else {
                        cardScale = min(max(scale, cardScales.lowerBound), cardScales.upperBound)
                    }
                })
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
        if motion.phase == .finished {
            VStack(spacing: 16) {
                card(systemImage: "checkmark.circle.fill", color: .green,
                     title: "Série terminée !",
                     detail: "\(motion.repCount) répétitions")
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

    private func feedbackBanner(_ feedback: MotionSession.Feedback) -> some View {
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
