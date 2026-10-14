import SwiftUI

/// Review screen after reading the sheet, also used to enter or edit the program by hand.
/// A standard list: tap an exercise to edit it, swipe to delete, drag to reorder.
/// Values the model didn't find are flagged "À vérifier". Nothing is saved until the patient confirms.
struct ProgramEditorView: View {
    @State var program: EditableProgram
    /// The sheet that was read, to compare with while checking.
    var photo: UIImage?
    /// Shown above the list, e.g. to say the program was read by Apple Intelligence.
    var notice: LocalizedStringKey?
    /// Symbol of the notice; by default Apple Intelligence for a sheet, the physiotherapist otherwise.
    var noticeSymbol: String?
    var title: LocalizedStringKey = "Vérifier le programme"
    /// Shows a button to Settings under the notice (Apple Intelligence turned off).
    var opensSettings = false
    let onSave: (EditableProgram) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingPhoto = false
    @State private var addedExercise: EditableProgram.Exercise.ID?

    var body: some View {
        List {
            if let notice {
                Section {
                    Label(notice, systemImage: noticeSymbol ?? (photo == nil ? "stethoscope" : "apple.intelligence"))
                    if program.hasGuesses {
                        Label("Les valeurs « À vérifier » ne figurent pas sur la feuille.", systemImage: "questionmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    if opensSettings {
                        Button("Ouvrir Réglages", systemImage: "gear") {
                            openURL(URL(string: UIApplication.openSettingsURLString)!)
                        }
                    }
                    if photo != nil {
                        Button("Revoir la feuille", systemImage: "doc.text.image") { showingPhoto = true }
                    }
                }
            }

            Section("Fréquence") {
                Stepper(value: $program.sessionsPerWeek, in: 1...14) {
                    GuessedValue(guessed: program.sessionsPerWeekGuessed) {
                        Text("\(program.sessionsPerWeek) séances par semaine")
                    }
                }
                .onChange(of: program.sessionsPerWeek) { program.sessionsPerWeekGuessed = false }
            }

            Section {
                ForEach($program.exercises) { $exercise in
                    NavigationLink {
                        ExerciseEditorView(exercise: $exercise)
                    } label: {
                        ExerciseDraftRow(exercise: exercise)
                    }
                }
                .onDelete { program.exercises.remove(atOffsets: $0) }
                .onMove { program.exercises.move(fromOffsets: $0, toOffset: $1) }

                Button("Ajouter un exercice", systemImage: "plus") {
                    let exercise = EditableProgram.Exercise(name: "", catalogID: nil, sets: EditableProgram.defaultSets, reps: EditableProgram.defaultReps)
                    program.exercises.append(exercise)
                    addedExercise = exercise.id
                }
            } header: {
                Text("Exercices")
            } footer: {
                Text("Seul votre kiné décide du programme.")
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", systemImage: "checkmark", role: .confirm) { onSave(program) }
                    .disabled(!program.isValid)
            }
        }
        .navigationDestination(item: $addedExercise) { id in
            if let index = program.exercises.firstIndex(where: { $0.id == id }) {
                ExerciseEditorView(exercise: $program.exercises[index])
            }
        }
        .sheet(isPresented: $showingPhoto) {
            if let photo {
                NavigationStack {
                    ScrollView([.horizontal, .vertical]) {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .containerRelativeFrame(.horizontal)
                    }
                    .navigationTitle("Feuille d'exercices")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        Button("Fermer", systemImage: "xmark", role: .close) { showingPhoto = false }
                    }
                }
            }
        }
    }
}

/// One exercise in the editor's list: its name, what to do, and a mark when something must be checked.
private struct ExerciseDraftRow: View {
    let exercise: EditableProgram.Exercise

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(exercise.name.isEmpty ? String(localized: "Nouvel exercice") : exercise.name)
                .font(.headline)
                .foregroundStyle(exercise.name.isEmpty ? .secondary : .primary)
            Group {
                if exercise.mode == .hold {
                    Text("\(exercise.sets) × \(exercise.holdSeconds) s")
                } else {
                    Text("\(exercise.sets) séries × \(exercise.reps)")
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            // How the session will follow it: a symbol and a word, as on the Programme page.
            Group {
                if exercise.mode == .hold {
                    Label("Minuteur", systemImage: "timer")
                } else if exercise.catalogID.flatMap(CatalogExercise.find) != nil {
                    Label("Suivi caméra", systemImage: "camera.viewfinder")
                        .foregroundStyle(.tint)
                } else {
                    Label("Comptage manuel", systemImage: "hand.tap")
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            if !exercise.guessed.isEmpty {
                Label("À vérifier", systemImage: "questionmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
    }
}

/// One exercise: its name, repetitions or a held position, how the camera follows it, sets and amount.
private struct ExerciseEditorView: View {
    @Binding var exercise: EditableProgram.Exercise

    var body: some View {
        Form {
            Section {
                TextField("Nom de l'exercice", text: $exercise.name)
                Picker("Type", selection: $exercise.mode) {
                    Text("Répétitions").tag(EditableProgram.Mode.reps)
                    Text("Maintien").tag(EditableProgram.Mode.hold)
                }
                .pickerStyle(.segmented)
            }

            if exercise.mode == .reps {
                Section {
                    Picker("Suivi", selection: $exercise.catalogID) {
                        ForEach(CatalogExercise.all) { catalog in
                            Text(catalog.name).tag(Optional(catalog.id))
                        }
                        Text("Comptage manuel").tag(String?.none)
                    }
                } footer: {
                    Text("La caméra compte les répétitions des exercices qu'elle connaît.")
                }
            }

            Section {
                Stepper(value: $exercise.sets, in: 1...10) {
                    GuessedValue(guessed: exercise.guessed.contains(.sets)) {
                        Text("\(exercise.sets) séries")
                    }
                }
                .onChange(of: exercise.sets) { exercise.guessed.remove(.sets) }
                if exercise.mode == .reps {
                    Stepper(value: $exercise.reps, in: 1...50) {
                        GuessedValue(guessed: exercise.guessed.contains(.reps)) {
                            Text("\(exercise.reps) répétitions")
                        }
                    }
                    .onChange(of: exercise.reps) { exercise.guessed.remove(.reps) }
                } else {
                    Stepper(value: $exercise.holdSeconds, in: 5...600, step: 5) {
                        GuessedValue(guessed: exercise.guessed.contains(.holdSeconds)) {
                            Text("\(exercise.holdSeconds) secondes")
                        }
                    }
                    .onChange(of: exercise.holdSeconds) { exercise.guessed.remove(.holdSeconds) }
                }
            }
        }
        .navigationTitle(exercise.name.isEmpty ? String(localized: "Nouvel exercice") : exercise.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A value with an "À vérifier" mark when it was filled in by default: an icon and a word, not only a color.
private struct GuessedValue<Content: View>: View {
    let guessed: Bool
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            content
            if guessed {
                Label("À vérifier", systemImage: "questionmark.circle.fill")
                    .font(.caption.bold())
                    .foregroundStyle(.orange)
            }
        }
    }
}
