import SwiftData
import SwiftUI

/// One exercise on its own, outside any program: pick it, choose how many, start.
struct FreeExerciseCard: View {
    @State private var choosing = false

    var body: some View {
        SummaryCard(title: Text("Essayer un exercice"), systemImage: "figure.mixed.cardio", color: .accentColor) {
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

/// Three groups, as Fitness shows its workouts: the movements the patient filmed, Rebond's, then the ones done
/// without the camera. One large card each, its symbol in color, a play button to start, the movement and the goal
/// set right in the card.
private struct FreeExercisePicker: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router
    @Query(sort: \LibraryExercise.createdAt) private var library: [LibraryExercise]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let filmed = library.filter { $0.catalogExercise?.reference != nil }
                    if !filmed.isEmpty {
                        header("Mes exercices filmés")
                        ForEach(filmed) { exercise in card(exercise) }
                    }
                    header("Exercices Rebond")
                    ForEach(CatalogExercise.all) { exercise in
                        ExerciseStartCard(name: String(localized: exercise.name), catalog: exercise,
                                          holdSeconds: nil, symbol: exercise.symbol) { reps in
                            start(WorkoutExercise(name: String(localized: exercise.name), catalogID: exercise.id,
                                                  mode: .camera(catalogID: exercise.id), sets: 1, reps: reps))
                        }
                    }
                    // Counted by hand or held: the patient's own, the camera doesn't follow them.
                    let withoutCamera = library.filter { $0.catalogExercise == nil }
                    if !withoutCamera.isEmpty {
                        header("Sans caméra")
                        ForEach(withoutCamera) { exercise in card(exercise) }
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

    private func header(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.title3.bold())
            .padding(.top, 10)
            .accessibilityAddTraits(.isHeader)
    }

    private func card(_ exercise: LibraryExercise) -> some View {
        ExerciseStartCard(name: exercise.name, catalog: exercise.catalogExercise, holdSeconds: exercise.holdSeconds,
                          symbol: exercise.planned.figureSymbol) { reps in
            start(exercise.workoutExercise(reps: reps))
        }
    }

    private func start(_ workout: WorkoutExercise) {
        dismiss()
        // After the sheet is gone: the session covers the whole screen.
        Task {
            try? await Task.sleep(for: .seconds(0.4))
            router.startExercise(workout)
        }
    }
}

/// One exercise, Fitness style and nothing more: symbol and play button, the name in large type, what the
/// play button starts. Tapping the card shows the movement in it.
private struct ExerciseStartCard: View {
    let name: String
    /// Followed by the camera: Rebond's or filmed. Nil when counted by hand or held.
    let catalog: CatalogExercise?
    let holdSeconds: Int?
    let symbol: String
    let onStart: (_ reps: Int) -> Void

    @State private var showsMovement = false
    @State private var reps = 10
    @State private var choosingReps = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: symbol)
                    .contentShape(.rect)
                    .onTapGesture { toggleMovement() }
                    .font(.system(size: 44))
                    .foregroundStyle(.tint)
                    .frame(height: 56, alignment: .topLeading)
                    .accessibilityHidden(true)
                Spacer()
                Button { onStart(reps) } label: {
                    Image(systemName: "play.fill")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Commencer : \(name)"))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(.title.bold())
                    .fixedSize(horizontal: false, vertical: true)
                    .contentShape(.rect)
                    .onTapGesture { toggleMovement() }
                if let holdSeconds {
                    Text("Tenir \(holdSeconds) s")
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .padding(.top, 4)
                } else {
                    // The number of repetitions, on the iPhone's wheel unfolded in the card; the play button starts with it.
                    Button {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { choosingReps.toggle() }
                    } label: {
                        HStack(spacing: 6) {
                            Text("^[\(reps) répétition](inflect: true)")
                                .monospacedDigit()
                                .contentTransition(.numericText())
                            Image(systemName: choosingReps ? "chevron.up" : "chevron.down")
                                .font(.caption.weight(.bold))
                        }
                        .font(.headline)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 40)
                        .background(Color.accentColor.opacity(0.15), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                    .accessibilityLabel(Text("Nombre de répétitions : \(reps)"))
                }
            }
            if choosingReps {
                Picker("Répétitions", selection: $reps) {
                    ForEach(1...50, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
            if showsMovement {
                MovementCard(catalog: catalog, symbol: symbol, height: 220)
                    .padding(.top, 4)
                    .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 30))
        .accessibilityAction(named: showsMovement ? Text("Masquer le mouvement") : Text("Voir le mouvement")) {
            showsMovement.toggle()
        }
    }

    /// Tapping the exercise (its symbol or name) shows its movement in the card.
    private func toggleMovement() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showsMovement.toggle() }
    }
}
