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

/// The exercises the camera follows, then the chosen one with its movement and how many to do.
private struct FreeExercisePicker: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(CatalogExercise.all) { exercise in
                NavigationLink {
                    FreeExerciseSetup(exercise: exercise) { dismiss() }
                } label: {
                    Label { Text(exercise.name) } icon: { Image(systemName: exercise.symbol).foregroundStyle(.tint) }
                }
            }
            .navigationTitle("Faire un exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
    }
}

private struct FreeExerciseSetup: View {
    let exercise: CatalogExercise
    let onStart: () -> Void

    @Environment(AppRouter.self) private var router
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
                    let workout = WorkoutExercise(name: String(localized: exercise.name), catalogID: exercise.id,
                                                  mode: .camera(catalogID: exercise.id), sets: sets, reps: reps)
                    onStart()
                    // After the sheet is gone: the session covers the whole screen.
                    Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        router.startExercise(workout)
                    }
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
