import SwiftUI

/// Guided session: camera feed with the skeleton, repetition counter, depth gauge and corrections on top.
struct SessionView: View {
    let exercise: CatalogExercise
    /// Shown under the exercise name, e.g. "Série 1 sur 3".
    let setTitle: LocalizedStringKey
    let onFinish: (SetResult) -> Void

    @State private var motion: MotionSession
    @ScaledMetric private var ringSize = 64

    init(exercise: CatalogExercise, targetReps: Int, setTitle: LocalizedStringKey, onFinish: @escaping (SetResult) -> Void) {
        self.exercise = exercise
        self.setTitle = setTitle
        self.onFinish = onFinish
        _motion = State(initialValue: MotionSession(exercise: exercise, targetReps: targetReps))
    }

    var body: some View {
        ZStack {
            Color.black
            if motion.cameraUnavailable {
                ContentUnavailableView(
                    "Caméra indisponible",
                    systemImage: "video.slash",
                    description: motion.cameraAccessDenied
                        ? Text("Autorisez l'accès à la caméra dans Réglages pour que Rebond suive vos mouvements.")
                        : Text("Aucune caméra avant n'est disponible. Vous pouvez terminer la série.")
                )
            } else {
                CameraFrameView(frame: motion.liveFrame)
                if let skeleton = motion.skeleton {
                    SkeletonOverlay(
                        skeleton: skeleton,
                        highlightedJoints: exercise.highlightedJoints,
                        highlightColor: motion.depthProgress >= 1 ? .green : .yellow,
                        faultyJoints: motion.faultToHighlight?.bodyJoints ?? []
                    )
                }
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            if !motion.cameraUnavailable {
                counter.padding()
            }
        }
        .overlay(alignment: .trailing) {
            if motion.phase == .active && motion.bodyVisible {
                DepthGauge(progress: motion.depthProgress)
                    .containerRelativeFrame(.vertical) { height, _ in height * 0.4 }
                    .padding()
                    .transition(.opacity)
            }
        }
        .overlay {
            if !motion.cameraUnavailable {
                statusCard.padding()
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 16) {
                if let feedback = motion.feedback {
                    feedbackBanner(feedback)
                }
                if motion.phase != .finished {
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

    /// Placement, calibration and end-of-set messages, in the middle of the screen.
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
        } else if !motion.bodyVisible {
            card(systemImage: "figure.stand", color: .white,
                 title: "Placez-vous à 2–3 m",
                 detail: "Le corps entier visible, de face ou de profil")
        } else if motion.phase == .calibrating {
            card(systemImage: "figure.stand", color: .yellow,
                 title: "Restez debout, immobile",
                 detail: "Rebond mesure votre position de départ")
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
