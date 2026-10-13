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
                CameraFrameView(frame: motion.liveFrame)
                    .blur(radius: isWatching ? 24 : 0)
                if isWatching {
                    Color.black.opacity(0.5)
                }
                if let skeleton = motion.skeleton, !isWatching {
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
                } else if motion.phase == .calibrating {
                    placementHint
                } else if motion.phase == .demonstrating {
                    topCard(title: "Regardez d'abord le mouvement", detail: "Restez immobile, vous commencerez après")
                } else {
                    counter
                }
            }
            .padding()
        }
        .overlay {
            if showsFloatingGuide {
                floatingGuide
            }
        }
        .animation(.spring(response: 0.7, dampingFraction: 0.8), value: motion.guideDisplay)
        .overlay(alignment: .trailing) {
            if motion.phase == .active && motion.bodyVisible {
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
        .navigationTitle(Text(exercise.name))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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

    /// The guide shows the movement: the patient watches before starting. Clear again once it moves to its card.
    private var isWatching: Bool {
        motion.phase == .demonstrating && motion.guideDisplay == .large
    }

    /// Before the set: the large guide, to get in place.
    private var showsPlacementGuide: Bool {
        motion.phase == .calibrating
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

    /// Frame of the floating guide: over the patient while demonstrating, otherwise its card,
    /// which the patient can move and resize.
    private func floatingGuideFrame(in size: CGSize) -> CGRect {
        let padding = 8.0
        if !guideInCard {
            // Same place and size as the guide used to get in place, so it starts exactly there.
            let figure = MovementGuide(exercise: exercise, skeleton: motion.skeleton, isDemonstrating: false).figureBox(in: size)
            let height = figure.height / 0.9 + padding * 2
            let width = height * 0.65
            return CGRect(x: figure.midX - width / 2, y: figure.midY - height / 2, width: width, height: height)
        }
        let scale = min(max(cardScale * pinch, 0.8), 3.2)
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

    /// The model: drag it anywhere, pinch to resize, tap to switch between small and large.
    private var floatingGuide: some View {
        GeometryReader { geometry in
            let frame = floatingGuideFrame(in: geometry.size)
            MovementGuide(
                exercise: exercise,
                skeleton: nil,
                isDemonstrating: true,
                demonstrationStart: motion.demonstrationStart,
                isCompact: true
            )
            .padding(8)
            .background {
                Color.clear
                    .glassEffect(in: .rect(cornerRadius: 20))
                    .opacity(guideInCard ? 1 : 0)
            }
            .contentShape(.rect(cornerRadius: 20))
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .onTapGesture {
                guard guideInCard else { return }
                withAnimation(.spring(duration: 0.4)) { cardScale = cardScale > 1.5 ? 1 : 2.6 }
            }
            .gesture(
                DragGesture()
                    .updating($drag) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        cardOffset.width += value.translation.width
                        cardOffset.height += value.translation.height
                    }
                    .simultaneously(with: MagnifyGesture()
                        .updating($pinch) { value, state, _ in state = value.magnification }
                        .onEnded { value in cardScale = min(max(cardScale * value.magnification, 0.8), 3.2) }),
                isEnabled: guideInCard
            )
            .accessibilityElement()
            .accessibilityLabel(Text("Modèle du mouvement"))
            .accessibilityHint(Text("Touchez pour agrandir ou réduire, faites glisser pour déplacer"))
            .accessibilityAddTraits(.isButton)
        }
        .ignoresSafeArea()
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
        } else if motion.phase == .active, !motion.bodyVisible {
            card(systemImage: "figure.stand", color: .white,
                 title: "Placez-vous à 2–3 m",
                 detail: "Le corps entier visible, de face ou de profil")
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
