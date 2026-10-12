import SwiftUI

/// Review screen after reading the sheet, also used to enter or edit the program by hand.
/// Nothing is saved until the patient confirms.
struct ProgramEditorView: View {
    @State var program: EditableProgram
    /// Shown above the form, e.g. to say the program was read from the photo.
    var notice: LocalizedStringKey?
    let onSave: (EditableProgram) -> Void

    var body: some View {
        Form {
            if let notice {
                Section {
                    Label(notice, systemImage: "checkmark.circle")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Fréquence") {
                Stepper("\(program.sessionsPerWeek) séances par semaine", value: $program.sessionsPerWeek, in: 1...14)
            }

            Section {
                ForEach($program.exercises) { $exercise in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Nom de l'exercice", text: $exercise.name)
                            .font(.headline)
                        Picker("Suivi", selection: $exercise.catalogID) {
                            Text("Caméra (squat)").tag(Optional(CatalogExercise.squat.id))
                            Text("Comptage manuel").tag(String?.none)
                        }
                        Stepper("\(exercise.sets) séries", value: $exercise.sets, in: 1...10)
                        Stepper("\(exercise.reps) répétitions", value: $exercise.reps, in: 1...50)
                    }
                    .padding(.vertical, 4)
                }
                .onDelete { program.exercises.remove(atOffsets: $0) }

                Button("Ajouter un exercice", systemImage: "plus") {
                    program.exercises.append(.init(name: "", catalogID: nil, sets: 3, reps: 10))
                }
            } header: {
                Text("Exercices")
            } footer: {
                Text("Vérifiez chaque exercice avant d'enregistrer : seul votre kiné décide du programme.")
            }
        }
        .navigationTitle("Mon programme")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer") { onSave(program) }
                    .disabled(!program.isValid)
            }
        }
    }
}
