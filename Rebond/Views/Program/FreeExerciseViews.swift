import SwiftUI

/// One exercise on its own, outside any program: pick it, choose how many, start.
struct FreeExerciseCard: View {
    @State private var choosing = false

    var body: some View {
        SummaryCard(title: Text("Faire un exercice"), systemImage: "figure.mixed.cardio", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: -6) {
                    ForEach(CatalogExercise.all.prefix(6)) { exercise in
                        Image(systemName: exercise.symbol)
                            .font(.system(size: 17))
                            .foregroundStyle(.tint)
                            .frame(width: 38, height: 38)
                            .background(Color(.tertiarySystemGroupedBackground), in: .circle)
                            .overlay(Circle().stroke(Color(.secondarySystemGroupedBackground), lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                Button {
                    choosing = true
                } label: {
                    Text("Choisir un exercice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
        .sheet(isPresented: $choosing) {
            FreeExercisePicker()
        }
    }
}

/// The exercises the camera follows, as Fitness shows its workouts: one large card each, its symbol in color,
/// a play button to start at once (1 × 10), the movement and the goal below.
private struct FreeExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @State private var path: [CatalogExercise.ID] = []

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(CatalogExercise.all) { exercise in
                        ExerciseStartCard(exercise: exercise,
                                          onStart: { start(exercise, sets: 1, reps: 10) },
                                          onOpen: { path.append(exercise.id) })
                    }
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
            .navigationDestination(for: CatalogExercise.ID.self) { id in
                if let exercise = CatalogExercise.find(id) {
                    FreeExerciseSetup(exercise: exercise) { sets, reps in start(exercise, sets: sets, reps: reps) }
                }
            }
        }
    }

    private func start(_ exercise: CatalogExercise, sets: Int, reps: Int) {
        let workout = WorkoutExercise(name: String(localized: exercise.name), catalogID: exercise.id,
                                      mode: .camera(catalogID: exercise.id), sets: sets, reps: reps)
        dismiss()
        // After the sheet is gone: the session covers the whole screen.
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            router.startExercise(workout)
        }
    }
}

/// One exercise, Fitness style: symbol and play button on top, the name in large type, two buttons below.
private struct ExerciseStartCard: View {
    let exercise: CatalogExercise
    let onStart: () -> Void
    let onOpen: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: exercise.symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .frame(height: 56, alignment: .topLeading)
                    .accessibilityHidden(true)
                Spacer()
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Commencer : \(exercise.name)"))
            }
            Text(exercise.name)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                cardButton(systemImage: "figure.stand", label: "Voir le mouvement")
                cardButton(systemImage: "target", label: "Choisir l'objectif", text: "1 × 10")
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 30))
    }

    private func cardButton(systemImage: String, label: LocalizedStringKey, text: String? = nil) -> some View {
        Button(action: onOpen) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                if let text { Text(text).monospacedDigit() }
            }
            .font(.headline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
    }
}

private struct FreeExerciseSetup: View {
    let exercise: CatalogExercise
    let onStart: (_ sets: Int, _ reps: Int) -> Void

    @State private var sets = 1
    @State private var reps = 10

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                MovementCard(catalog: exercise, symbol: exercise.symbol)
                VStack(spacing: 0) {
                    Stepper("^[\(sets) série](inflect: true)", value: $sets, in: 1...5)
                        .padding()
                    Divider().padding(.leading)
                    Stepper("^[\(reps) répétition](inflect: true)", value: $reps, in: 1...30)
                        .padding()
                }
                .font(.headline)
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
                Button {
                    onStart(sets, reps)
                } label: {
                    Label("Commencer", systemImage: "play.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(exercise.name))
        .navigationBarTitleDisplayMode(.inline)
    }
}
