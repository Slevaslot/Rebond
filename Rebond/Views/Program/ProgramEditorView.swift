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
    var title: LocalizedStringKey = "Vérifier la séance"
    /// Shows a button to Settings under the notice (Apple Intelligence turned off).
    var opensSettings = false
    let onSave: (EditableProgram) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingPhoto = false
    /// The exercise whose wheels are open.
    @State private var expanded: EditableProgram.Exercise.ID?
    @State private var choosingExercise = false

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

            Section {
                DayPicker(days: $program.weekdays)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .onChange(of: program.weekdays) { program.sessionsPerWeekGuessed = false }
            } header: {
                Text("Jours")
            } footer: {
                GuessedValue(guessed: program.sessionsPerWeekGuessed) {
                    Text(program.weekdays.isEmpty
                         ? "Choisissez au moins un jour."
                         : "^[\(program.weekdays.count) séance](inflect: true) par semaine : \(ProgramSchedule.describe(program.weekdays)).")
                }
            }

            Section {
                ForEach($program.exercises) { $exercise in
                    ExerciseEditRow(
                        exercise: $exercise,
                        name: program.displayName(of: exercise),
                        isExpanded: expanded == exercise.id
                    ) {
                        withAnimation(.snappy) { expanded = expanded == exercise.id ? nil : exercise.id }
                    }
                }
                .onDelete { program.exercises.remove(atOffsets: $0) }
                .onMove { program.exercises.move(fromOffsets: $0, toOffset: $1) }

                Button("Ajouter un exercice", systemImage: "plus") { choosingExercise = true }
            } header: {
                Text("Exercices")
            }

            // Already named from what it works on: renaming is possible, never asked for.
            Section {
                TextField("Nom", text: $program.name, prompt: Text(program.suggestedName))
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
        .sheet(isPresented: $choosingExercise) {
            ExerciseChooser { exercise in
                program.exercises.append(exercise)
                withAnimation(.snappy) { expanded = exercise.id }
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

/// One exercise of the program: its symbol, its name, "3 × 10"; tapping it opens the iPhone's wheels
/// for the sets and the repetitions (or seconds) right in the list.
private struct ExerciseEditRow: View {
    @Binding var exercise: EditableProgram.Exercise
    /// Its name, or the one it will get.
    let name: String
    let isExpanded: Bool
    let onToggle: () -> Void

    private var symbol: String {
        if exercise.mode == .hold { return "figure.core.training" }
        return exercise.catalogID.flatMap(CatalogExercise.find)?.symbol ?? "figure.cooldown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(.tint)
                        .frame(width: 40, height: 40)
                        .background(Color.accentColor.opacity(0.12), in: .circle)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if !exercise.guessed.isEmpty {
                            Label("À vérifier", systemImage: "questionmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    Text(exercise.mode == .hold ? "\(exercise.sets) × \(exercise.holdSeconds) s" : "\(exercise.sets) × \(exercise.reps)")
                        .font(.headline)
                        .monospacedDigit()
                        .foregroundStyle(.tint)
                        .contentTransition(.numericText())
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)

            if isExpanded {
                HStack(spacing: 0) {
                    wheel("Séries", selection: $exercise.sets, values: Array(1...10)) { "\($0)" }
                    if exercise.mode == .hold {
                        wheel("Secondes", selection: $exercise.holdSeconds, values: Array(stride(from: 5, through: 300, by: 5))) { "\($0) s" }
                    } else {
                        wheel("Répétitions", selection: $exercise.reps, values: Array(1...50)) { "\($0)" }
                    }
                }
                .onChange(of: exercise.sets) { exercise.guessed.remove(.sets) }
                .onChange(of: exercise.reps) { exercise.guessed.remove(.reps) }
                .onChange(of: exercise.holdSeconds) { exercise.guessed.remove(.holdSeconds) }
                // Only an exercise Rebond doesn't know needs a name: the others carry their own.
                if exercise.catalogID.flatMap(CatalogExercise.find) == nil || exercise.mode == .hold {
                    TextField("Nom", text: $exercise.name, prompt: Text(name))
                        .textFieldStyle(.roundedBorder)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func wheel(_ title: LocalizedStringKey, selection: Binding<Int>, values: [Int], label: @escaping (Int) -> String) -> some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Picker(title, selection: selection) {
                ForEach(values, id: \.self) { Text(label($0)).tag($0) }
            }
            .pickerStyle(.wheel)
            .frame(height: 130)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Adding an exercise: the ones the camera follows, with their symbols, or another one counted or held.
private struct ExerciseChooser: View {
    let onChoose: (EditableProgram.Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    /// An exercise Rebond doesn't know, waiting for its name.
    @State private var naming: EditableProgram.Exercise?
    @State private var name = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Suivis par la caméra") {
                    ForEach(CatalogExercise.all) { catalog in
                        Button {
                            choose(EditableProgram.Exercise(name: "", catalogID: catalog.id,
                                                            sets: EditableProgram.defaultSets, reps: EditableProgram.defaultReps))
                        } label: {
                            Label { Text(catalog.name).foregroundStyle(.primary) } icon: { Image(systemName: catalog.symbol) }
                        }
                    }
                }
                Section("Autres") {
                    Button {
                        askName(EditableProgram.Exercise(name: "", catalogID: nil,
                                                         sets: EditableProgram.defaultSets, reps: EditableProgram.defaultReps))
                    } label: {
                        Label { Text("Autre exercice, compté à la main").foregroundStyle(.primary) } icon: { Image(systemName: "hand.tap") }
                    }
                    Button {
                        var exercise = EditableProgram.Exercise(name: "", catalogID: nil, sets: EditableProgram.defaultSets,
                                                                reps: EditableProgram.defaultReps)
                        exercise.mode = .hold
                        askName(exercise)
                    } label: {
                        Label { Text("Position tenue (gainage, étirement…)").foregroundStyle(.primary) } icon: { Image(systemName: "timer") }
                    }
                }
            }
            .navigationTitle("Ajouter un exercice")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Nom de l'exercice", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField(naming?.mode == .hold ? "Ex. : Gainage" : "Ex. : Pont fessier", text: $name)
                    .textInputAutocapitalization(.sentences)
                Button("Ajouter") {
                    if var exercise = naming {
                        exercise.name = name.trimmingCharacters(in: .whitespaces)
                        naming = nil
                        choose(exercise)
                    }
                }
                Button("Annuler", role: .cancel) { naming = nil }
            }
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
        }
    }

    private func askName(_ exercise: EditableProgram.Exercise) {
        name = ""
        naming = exercise
    }

    private func choose(_ exercise: EditableProgram.Exercise) {
        onChoose(exercise)
        dismiss()
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

/// The seven days, Monday first: tap a day to plan the program on it.
struct DayPicker: View {
    @Binding var days: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(ProgramSchedule.mondayFirst, id: \.self) { weekday in
                let selected = days.contains(weekday)
                Button {
                    days = ProgramSchedule.days(weekdays: selected ? days.filter { $0 != weekday } : days + [weekday],
                                                sessionsPerWeek: 0)
                } label: {
                    Text(Calendar.current.veryShortWeekdaySymbols[weekday - 1])
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .background(selected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(Color(.tertiarySystemFill)), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(Calendar.current.weekdaySymbols[weekday - 1]))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: days)
    }
}
