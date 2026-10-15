import SwiftData
import SwiftUI

/// Where an exercise of "Mes exercices" opens.
struct LibraryRoute: Hashable {
    let id: UUID
}

/// One exercise of "Mes exercices": its video, do it now, the séances it is in, and rename, replace or delete it.
struct LibraryExerciseView: View {
    let id: UUID

    @Environment(AppRouter.self) private var router
    @Environment(ExerciseLibrary.self) private var library
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @State private var reps = 10
    @State private var choosingReps = false
    @State private var showingVideo = false
    @State private var renaming = false
    @State private var newName = ""
    @State private var replacing = false
    @State private var confirmingDelete = false

    private var movement: ReferenceMovement? {
        library.movements.first { $0.id == id }
    }

    var body: some View {
        if let movement {
            content(movement)
        } else {
            ContentUnavailableView("Exercice introuvable", systemImage: "questionmark.circle")
        }
    }

    private func content(_ movement: ReferenceMovement) -> some View {
        let using = programs.filter { $0.exercises.contains { $0.catalogID == movement.catalogID } }
        let others = programs.filter { program in !using.contains { $0.id == program.id } }
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ReferenceFramesView(movement: movement)
                    .frame(maxWidth: .infinity)
                    .frame(height: 420)
                    .background(Color.black)
                    .clipShape(.rect(cornerRadius: 26))
                    .overlay(alignment: .bottomTrailing) {
                        Button("Vidéo complète", systemImage: "play.fill") { showingVideo = true }
                            .font(.subheadline.weight(.semibold))
                            .buttonStyle(.glass)
                            .padding(12)
                    }

                doNow(movement)

                // The séances it is in, and adding it to one.
                VStack(alignment: .leading, spacing: 0) {
                    Text("Séances")
                        .font(.headline)
                        .padding()
                    ForEach(using) { program in
                        Divider().padding(.leading)
                        Label(program.title, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal)
                    }
                    Divider().padding(.leading)
                    Menu {
                        ForEach(others) { program in
                            Button(program.title) { program.append(catalogID: movement.catalogID, name: movement.name) }
                        }
                        Button("Nouvelle séance", systemImage: "plus") { router.newSession(with: [movement.catalogID]) }
                    } label: {
                        Label("Ajouter à une séance", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal)
                            .contentShape(.rect)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))

                VStack(spacing: 0) {
                    row("Renommer", symbol: "pencil") {
                        newName = movement.name
                        renaming = true
                    }
                    Divider().padding(.leading)
                    row("Remplacer la vidéo", symbol: "video.badge.plus") { replacing = true }
                    Divider().padding(.leading)
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        HStack {
                            Label("Supprimer l'exercice", systemImage: "trash")
                                .confirmationDialog("Supprimer « \(movement.name) » ?", isPresented: $confirmingDelete,
                                                    titleVisibility: .visible) {
                                    Button("Supprimer l'exercice", role: .destructive) {
                                        dismiss()
                                        library.delete(movement, in: context)
                                    }
                                } message: {
                                    Text(using.isEmpty
                                         ? "Sa vidéo est effacée de l'iPhone."
                                         : "Il est aussi retiré de \(using.count) séance(s). Sa vidéo est effacée de l'iPhone.")
                                }
                            Spacer(minLength: 0)
                        }
                        .frame(minHeight: 50)
                        .padding(.horizontal)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(movement.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingVideo) { ReferenceVideoSheet(movement: movement) }
        .sheet(isPresented: $replacing) { NewExerciseView(replacing: movement) { _ in } }
        .alert("Renommer l'exercice", isPresented: $renaming) {
            TextField("Nom", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Renommer") { library.rename(movement, to: newName, in: context) }
            Button("Annuler", role: .cancel) {}
        }
    }

    /// Do it right now, alone: how many repetitions on the iPhone's wheel, then start.
    private func doNow(_ movement: ReferenceMovement) -> some View {
        VStack(spacing: 12) {
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
            if choosingReps {
                Picker("Répétitions", selection: $reps) {
                    ForEach(1...50, id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.wheel)
                .frame(height: 150)
            }
            Button {
                router.startExercise(WorkoutExercise(name: movement.name, catalogID: movement.catalogID,
                                                     mode: .camera(catalogID: movement.catalogID), sets: 1, reps: reps))
            } label: {
                Label("Faire maintenant", systemImage: "play.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }

    private func row(_ title: LocalizedStringKey, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                .padding(.horizontal)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}

/// One of Rebond's exercises, done right away: the movement, how many, start.
struct CatalogExerciseSheet: View {
    let exercise: CatalogExercise

    @Environment(\.dismiss) private var dismiss
    @Environment(AppRouter.self) private var router

    var body: some View {
        NavigationStack {
            ScrollView {
                ExerciseStartCard(exercise: exercise) { sets, reps in
                    let workout = WorkoutExercise(name: String(localized: exercise.name), catalogID: exercise.id,
                                                  mode: .camera(catalogID: exercise.id), sets: sets, reps: reps)
                    dismiss()
                    // After the sheet is gone: the session covers the whole screen.
                    Task {
                        try? await Task.sleep(for: .seconds(0.4))
                        router.startExercise(workout)
                    }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Exercice")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
