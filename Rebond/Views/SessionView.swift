import SwiftUI

/// Guided session: camera feed with the repetition counter and corrections on top.
struct SessionView: View {
    let exercise: CatalogExercise
    let targetReps: Int

    @State private var motion: MotionSession
    @Environment(\.dismiss) private var dismiss

    init(exercise: CatalogExercise, targetReps: Int) {
        self.exercise = exercise
        self.targetReps = targetReps
        _motion = State(initialValue: MotionSession(exercise: exercise))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if motion.cameraUnavailable {
                ContentUnavailableView(
                    "Caméra indisponible",
                    systemImage: "video.slash",
                    description: Text("Autorisez l'accès à la caméra dans Réglages pour que Rebond suive vos mouvements.")
                )
            } else {
                CameraPreview(session: motion.captureSession, camera: motion.camera)
                    .ignoresSafeArea()
            }
        }
        .overlay(alignment: .top) {
            if !motion.cameraUnavailable {
                status
                    .padding()
                    .glassEffect(in: .rect(cornerRadius: 24))
                    .padding()
            }
        }
        .overlay(alignment: .bottom) {
            Button("Terminer") { dismiss() }
                .buttonStyle(.glass)
                .controlSize(.extraLarge)
                .padding()
        }
        .navigationTitle(Text(exercise.name))
        .navigationBarTitleDisplayMode(.inline)
        .task { await motion.start() }
        .onDisappear { motion.stop() }
        .sensoryFeedback(.success, trigger: motion.repCount)
        .sensoryFeedback(.warning, trigger: motion.incompleteCount)
    }

    private var status: some View {
        VStack(spacing: 8) {
            Text("\(motion.repCount) / \(targetReps)")
                .font(.largeTitle.bold())
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.default, value: motion.repCount)

            if motion.repCount >= targetReps {
                Text("Série terminée !")
            } else if !motion.bodyVisible {
                Text("Placez-vous de profil, le corps entier visible")
            } else if let correction = motion.lastCorrection {
                Text(correction)
            }

            if motion.incompleteCount > 0 {
                Text("Incomplètes : \(motion.incompleteCount)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.headline)
        .multilineTextAlignment(.center)
    }
}
