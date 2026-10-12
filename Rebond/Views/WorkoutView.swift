import SwiftData
import SwiftUI

/// A full session: every exercise of the program, set by set, then the pain level.
struct WorkoutView: View {
    let program: Program

    private struct Step {
        let exercise: PlannedExercise
        let set: Int
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var stepIndex = 0
    /// Results added up per exercise, in program order.
    @State private var results: [PersistentIdentifier: SetResult] = [:]

    private var steps: [Step] {
        program.orderedExercises.flatMap { exercise in
            (1...exercise.sets).map { Step(exercise: exercise, set: $0) }
        }
    }

    var body: some View {
        if stepIndex < steps.count {
            let step = steps[stepIndex]
            let setTitle: LocalizedStringKey = "Série \(step.set) sur \(step.exercise.sets)"
            Group {
                if let catalogExercise = step.exercise.catalogExercise {
                    SessionView(exercise: catalogExercise, targetReps: step.exercise.reps, setTitle: setTitle) {
                        finish(step, with: $0)
                    }
                } else {
                    ManualSetView(name: step.exercise.name, targetReps: step.exercise.reps, setTitle: setTitle) {
                        finish(step, with: $0)
                    }
                }
            }
            // A fresh screen (and camera analysis) for every set.
            .id(stepIndex)
        } else {
            PainView { pain in
                save(pain: pain)
                dismiss()
            }
        }
    }

    private func finish(_ step: Step, with result: SetResult) {
        var total = results[step.exercise.persistentModelID] ?? SetResult()
        total.completedReps += result.completedReps
        total.incompleteReps += result.incompleteReps
        if let amplitude = result.amplitude {
            total.amplitude = max(total.amplitude ?? 0, amplitude)
        }
        results[step.exercise.persistentModelID] = total
        stepIndex += 1
    }

    private func save(pain: Int) {
        let exerciseResults = program.orderedExercises.map { exercise in
            let result = results[exercise.persistentModelID] ?? SetResult()
            return ExerciseResult(
                exerciseName: exercise.name,
                catalogID: exercise.catalogID,
                plannedReps: exercise.sets * exercise.reps,
                completedReps: result.completedReps,
                incompleteReps: result.incompleteReps,
                amplitude: result.amplitude
            )
        }
        context.insert(Session(pain: pain, results: exerciseResults))
    }
}

/// An exercise the camera doesn't follow: the patient counts with the buttons.
struct ManualSetView: View {
    let name: String
    let targetReps: Int
    let setTitle: LocalizedStringKey
    let onFinish: (SetResult) -> Void

    @State private var count = 0

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 4) {
                Text(name)
                    .font(.title.bold())
                Text(setTitle)
                    .foregroundStyle(.secondary)
            }
            Text("\(count) / \(targetReps)")
                .font(.system(.largeTitle, design: .rounded).bold())
                .monospacedDigit()
                .contentTransition(.numericText())
            HStack(spacing: 24) {
                Button("Retirer une répétition", systemImage: "minus") { count = max(0, count - 1) }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .disabled(count == 0)
                Button("Ajouter une répétition", systemImage: "plus") { count += 1 }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.extraLarge)
            Text("Comptage manuel : cet exercice n'est pas suivi par la caméra.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Série terminée") { onFinish(SetResult(completedReps: count)) }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .animation(.default, value: count)
        .sensoryFeedback(.increase, trigger: count)
        .navigationTitle(name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// End of session: pain level from 0 to 10.
struct PainView: View {
    let onSave: (Int) -> Void

    @State private var pain = 0.0

    var body: some View {
        Form {
            Section {
                VStack(spacing: 12) {
                    Text("\(Int(pain))")
                        .font(.system(.largeTitle, design: .rounded).bold())
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Slider(value: $pain, in: 0...10, step: 1) {
                        Text("Douleur")
                    } minimumValueLabel: {
                        Text("0")
                    } maximumValueLabel: {
                        Text("10")
                    }
                    .accessibilityValue(Text("\(Int(pain)) sur 10"))
                }
                .padding(.vertical)
                .animation(.default, value: pain)
            } header: {
                Text("Quel est votre niveau de douleur ?")
            } footer: {
                Text("0 : aucune douleur. 10 : douleur maximale.")
            }

            if Int(pain) >= WeeklyReport.highPain {
                Section {
                    Label("Si la douleur est forte ou inhabituelle, faites une pause et parlez-en à votre kiné.", systemImage: "heart.text.square")
                }
            }

            Section {
                Button("Enregistrer la séance") { onSave(Int(pain)) }
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Fin de séance")
        .navigationBarBackButtonHidden()
    }
}
