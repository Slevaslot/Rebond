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
/// a play button to start, the movement and the goal set right in the card.
private struct FreeExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    ForEach(CatalogExercise.all) { exercise in
                        ExerciseStartCard(exercise: exercise) { sets, reps in start(exercise, sets: sets, reps: reps) }
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

/// One exercise, Fitness style: symbol and play button on top, the name in large type, then two buttons that
/// act in the card itself: show the movement, and choose the goal the play button starts with.
private struct ExerciseStartCard: View {
    let exercise: CatalogExercise
    let onStart: (_ sets: Int, _ reps: Int) -> Void

    @State private var sets = 1
    @State private var reps = 10
    @State private var showsMovement = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                Image(systemName: exercise.symbol)
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .frame(height: 56, alignment: .topLeading)
                    .accessibilityHidden(true)
                Spacer()
                Button { onStart(sets, reps) } label: {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Commencer : \(exercise.name), \(sets) × \(reps)"))
            }
            Text(exercise.name)
                .font(.title.bold())
                .fixedSize(horizontal: false, vertical: true)

            if showsMovement {
                MovementCard(catalog: exercise, symbol: exercise.symbol, height: 220)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }

            HStack(spacing: 12) {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showsMovement.toggle() }
                } label: {
                    Image(systemName: showsMovement ? "eye.slash" : "figure.stand")
                        .cardButtonLabel(selected: showsMovement)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(showsMovement ? "Masquer le mouvement" : "Voir le mouvement"))

                // The goal, chosen in place: the play button starts with it.
                Menu {
                    Picker("Séries", selection: $sets) {
                        ForEach(1...5, id: \.self) { Text("^[\($0) série](inflect: true)").tag($0) }
                    }
                    Picker("Répétitions", selection: $reps) {
                        ForEach([5, 8, 10, 12, 15, 20], id: \.self) { Text("^[\($0) répétition](inflect: true)").tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "target")
                        Text("\(sets) × \(reps)").monospacedDigit()
                    }
                    .cardButtonLabel(selected: false)
                }
                .accessibilityLabel(Text("Objectif : \(sets) séries de \(reps) répétitions"))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 30))
    }
}

private extension View {
    func cardButtonLabel(selected: Bool) -> some View {
        font(.headline)
            .foregroundStyle(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(Color.accentColor.opacity(selected ? 0.25 : 0.12), in: .rect(cornerRadius: 18))
            .contentShape(.rect(cornerRadius: 18))
    }
}
