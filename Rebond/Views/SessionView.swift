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
    @ScaledMetric private var cornerGuideWidth = 84
    /// Lets the large guide shrink and slide into its corner.
    @Namespace private var guideSpace

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
            if showsLargeGuide {
                MovementGuide(
                    exercise: exercise,
                    skeleton: motion.skeleton,
                    isDemonstrating: motion.phase == .demonstrating || motion.phase == .active,
                    demonstrationStart: motion.demonstrationStart
                ) { placement in
                    self.placement = placement
                    motion.updatePlacement(placement)
                }
                // Demonstrating over the patient during the set: lighter, so their own body stays readable.
                .opacity(motion.phase == .active ? 0.6 : 1)
                .matchedGeometryEffect(id: "guide", in: guideSpace)
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
                } else if motion.phase == .countdown {
                    VStack(spacing: 12) {
                        Text("Prêt ?")
                            .font(.title2.bold())
                        Text(motion.countdownValue, format: .number)
                            .font(.system(.largeTitle, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .padding(28)
                            .glassEffect(in: .circle)
                            .animation(.default, value: motion.countdownValue)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text("Début dans \(motion.countdownValue) secondes"))
                } else {
                    counter
                }
            }
            .padding()
        }
        .overlay(alignment: .leading) {
            if showsCornerGuide {
                cornerGuide
                    .padding()
            }
        }
        .animation(.spring(duration: 0.5), value: motion.guideDisplay)
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

    /// The guide shows the movement and counts down: the patient watches before starting.
    private var isWatching: Bool {
        motion.phase == .demonstrating || motion.phase == .countdown
    }

    /// Large guide: to get in place before the set, then whenever it demonstrates the movement.
    private var showsLargeGuide: Bool {
        switch motion.phase {
        case .calibrating: true
        case .demonstrating, .active: motion.guideDisplay == .large
        case .countdown, .finished: false
        }
    }

    private var showsCornerGuide: Bool {
        switch motion.phase {
        case .demonstrating, .countdown, .active: motion.guideDisplay == .corner
        case .calibrating, .finished: false
        }
    }

    /// The movement in a loop, small in a corner during the set. A tap hides or shows it.
    @ViewBuilder
    private var cornerGuide: some View {
        Button {
            motion.showsCornerGuide.toggle()
        } label: {
            if motion.showsCornerGuide {
                MovementGuide(
                    exercise: exercise,
                    skeleton: nil,
                    isDemonstrating: motion.phase == .active,
                    demonstrationStart: motion.demonstrationStart,
                    isCompact: true
                )
                .frame(width: cornerGuideWidth, height: cornerGuideWidth * 1.5)
                .padding(8)
                .matchedGeometryEffect(id: "guide", in: guideSpace)
            } else {
                Image(systemName: "figure.strengthtraining.functional")
                    .font(.title2)
                    .padding(14)
            }
        }
        .buttonStyle(.plain)
        .glassEffect(in: .rect(cornerRadius: 20))
        .accessibilityLabel(motion.showsCornerGuide ? Text("Masquer le modèle") : Text("Afficher le modèle"))
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
