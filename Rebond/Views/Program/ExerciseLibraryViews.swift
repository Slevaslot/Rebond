import SwiftData
import SwiftUI

/// "Ajouter un exercice": every way to add one to "Mes exercices", in the system's bubble.
/// Filmed at the physiotherapist's or done without the camera joins the list (Rebond's are already in it); the physiotherapist's sheet or message makes
/// a program with its exercises.
struct AddExerciseMenu<Label: View>: View {
    @ViewBuilder let label: Label
    /// Called with the new exercise, e.g. to tick it while creating a program.
    var onAdded: (LibraryExercise) -> Void = { _ in }
    /// Offers the physiotherapist's sheet or message (not while creating a program).
    var offersPhysiotherapist = true
    /// Once the exercise is saved, asks what next: add it to a program, or create one with it
    /// (not while creating a program, which ticks it instead).
    var offersProgram = true

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @State private var filming = false
    @State private var choosingWithoutCamera = false
    /// Saved while its sheet is still open; asked about once the sheet is gone.
    @State private var saved: LibraryExercise?
    @State private var created: LibraryExercise?

    var body: some View {
        Menu {
            Button("Filmer ou choisir une vidéo", systemImage: "video") { filming = true }
            Button("Sans caméra", systemImage: "hand.tap") { choosingWithoutCamera = true }
            if offersPhysiotherapist {
                Section("Feuille ou message du kiné") {
                    Button("Scanner la feuille", systemImage: "doc.viewfinder") { router.addProgram(from: .scan) }
                    Button("Photo de la feuille", systemImage: "photo") { router.addProgram(from: .photo) }
                    Button("Coller le message", systemImage: "text.bubble") { router.addProgram(from: .message) }
                }
            }
        } label: {
            label
        }
        .sheet(isPresented: $filming, onDismiss: askWhatNext) {
            FilmExerciseView { movement in
                add(LibraryExercise(catalogID: movement.catalogID, name: movement.name))
            }
        }
        .sheet(isPresented: $choosingWithoutCamera, onDismiss: askWhatNext) {
            WithoutCameraExercisePicker { catalogID, name, holdSeconds in
                add(LibraryExercise(catalogID: catalogID, name: name, holdSeconds: holdSeconds))
            }
        }
        // An exercise alone is not in any session yet: say so, and offer the program right away.
        .confirmationDialog("« \(created?.name ?? "") » est dans vos exercices.",
                            isPresented: Binding(get: { created != nil }, set: { if !$0 { created = nil } }),
                            titleVisibility: .visible, presenting: created) { exercise in
            ForEach(programs) { program in
                Button("Ajouter à « \(program.title) »") { exercise.append(to: program) }
            }
            Button("Créer un programme avec cet exercice") { router.newProgram(with: [exercise.name]) }
            Button("Non, juste l'exercice", role: .cancel) {}
        } message: { _ in
            Text("Vous pouvez déjà le faire seul (Accueil › Essayer un exercice). Ajoutez-le à un programme pour qu'il fasse partie de vos séances.")
        }
    }

    private func add(_ exercise: LibraryExercise) {
        context.insert(exercise)
        try? context.save()
        onAdded(exercise)
        if offersProgram { saved = exercise }
    }

    private func askWhatNext() {
        created = saved
        saved = nil
    }
}

/// An exercise done without the camera (counted by hand, or held). Rebond's exercises are in "Mes exercices" from
/// the start; only one the patient removed is offered again here.
struct WithoutCameraExercisePicker: View {
    let onChoose: (_ catalogID: String?, _ name: String, _ holdSeconds: Int?) -> Void
    @Environment(\.dismiss) private var dismiss
    @Query private var library: [LibraryExercise]
    @State private var naming: Bool?
    @State private var name = ""

    private var removedRebond: [CatalogExercise] {
        let known = Set(library.compactMap(\.catalogID))
        return CatalogExercise.all.filter { !known.contains($0.id) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        name = ""
                        naming = false
                    } label: {
                        Label { Text("Compté à la main").foregroundStyle(.primary) } icon: { Image(systemName: "hand.tap") }
                    }
                    Button {
                        name = ""
                        naming = true
                    } label: {
                        Label { Text("Position tenue (gainage, étirement…)").foregroundStyle(.primary) } icon: { Image(systemName: "timer") }
                    }
                }
                if !removedRebond.isEmpty {
                    Section("Remettre un exercice Rebond") {
                        ForEach(removedRebond) { exercise in
                            Button {
                                choose(exercise.id, String(localized: exercise.name), nil)
                            } label: {
                                Label { Text(exercise.name).foregroundStyle(.primary) } icon: { Image(systemName: exercise.symbol) }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Sans caméra")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
            }
            .alert("Nom de l'exercice", isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
                TextField(naming == true ? "Ex. : Gainage" : "Ex. : Pont fessier", text: $name)
                    .textInputAutocapitalization(.sentences)
                Button("Ajouter") {
                    let trimmed = name.trimmingCharacters(in: .whitespaces)
                    let hold = naming == true
                    naming = nil
                    guard !trimmed.isEmpty else { return }
                    choose(nil, trimmed, hold ? EditableProgram.defaultHoldSeconds : nil)
                }
                Button("Annuler", role: .cancel) { naming = nil }
            }
        }
    }

    private func choose(_ catalogID: String?, _ name: String, _ holdSeconds: Int?) {
        onChoose(catalogID, name, holdSeconds)
        dismiss()
    }
}

/// An exercise of "Mes exercices" in a list: its picture and its name.
struct LibraryExerciseRow: View {
    let exercise: LibraryExercise
    var isSelected: Bool?

    var body: some View {
        HStack(spacing: 14) {
            ExerciseBadge(exercise: exercise.planned, size: 44)
            Text(exercise.name)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            if let isSelected {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected == true ? .isSelected : [])
    }
}

/// Ticking exercises of "Mes exercices", in the order they will be done. A new exercise can be added without leaving.
struct LibraryPickerView: View {
    var preselected: [String] = []
    var nextTitle: LocalizedStringKey = "Suivant"
    let onNext: ([EditableProgram.Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \LibraryExercise.createdAt) private var library: [LibraryExercise]
    /// Names of the ticked exercises, in order.
    @State private var selection: [String] = []
    @State private var addingWithoutCamera = false

    var body: some View {
        List {
            Section {
                AddExerciseMenu(label: {
                    Text("Ajouter un exercice")
                }, onAdded: { exercise in
                    withAnimation(.snappy) { selection.append(exercise.name) }
                }, offersPhysiotherapist: false, offersProgram: false)
            }
            // Three groups, as in "Choisir un exercice": filmed, Rebond's, then without the camera.
            let filmed = library.filter(\.isFilmed)
            if !filmed.isEmpty {
                Section("Mes exercices filmés") { rows(filmed) }
            }
            let rebond = library.filter(\.isRebond)
            if !rebond.isEmpty {
                Section("Exercices Rebond") { rows(rebond) }
            }
            Section {
                rows(library.filter { $0.catalogExercise == nil })
                Button("Compté à la main ou minuteur", systemImage: "plus") { addingWithoutCamera = true }
            } header: {
                Text("Sans caméra")
            } footer: {
                Text("Pour un exercice que la caméra ne suit pas : vous comptez vous-même, ou un minuteur pour une position tenue.")
            }
        }
        .sheet(isPresented: $addingWithoutCamera) {
            WithoutCameraExercisePicker { catalogID, name, holdSeconds in
                let exercise = LibraryExercise(catalogID: catalogID, name: name, holdSeconds: holdSeconds)
                context.insert(exercise)
                try? context.save()
                withAnimation(.snappy) { selection.append(exercise.name) }
            }
        }
        .navigationTitle("Choisir les exercices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(nextTitle) { onNext(chosen) }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
            }
        }
        .onAppear { if selection.isEmpty { selection = preselected } }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func rows(_ exercises: [LibraryExercise]) -> some View {
        ForEach(exercises) { exercise in
            Button {
                withAnimation(.snappy) {
                    if let index = selection.firstIndex(of: exercise.name) {
                        selection.remove(at: index)
                    } else {
                        selection.append(exercise.name)
                    }
                }
            } label: {
                LibraryExerciseRow(exercise: exercise, isSelected: selection.contains(exercise.name))
            }
            .buttonStyle(.plain)
        }
    }

    private var chosen: [EditableProgram.Exercise] {
        selection.compactMap { name in library.first { $0.name == name }?.editable }
    }
}

/// "Créer un programme": tick its exercises, set how many of each, then its days.
struct NewProgramFlow: View {
    var preselected: [String] = []
    let onSave: (EditableProgram) -> Void

    /// The program being set, once its exercises are ticked.
    private struct Step: Hashable {
        let id = UUID()
        let program: EditableProgram
        static func == (lhs: Step, rhs: Step) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    @State private var step: Step?

    var body: some View {
        NavigationStack {
            LibraryPickerView(preselected: preselected) { exercises in
                var program = EditableProgram()
                program.exercises = exercises
                step = Step(program: program)
            }
            .navigationDestination(item: $step) { step in
                ProgramEditorView(program: step.program, title: "Nouveau programme", showsCancel: false, onSave: onSave)
            }
        }
        .interactiveDismissDisabled()
    }
}

/// One exercise of "Mes exercices": the movement, do it now, the programs it is in, check the filmed movement,
/// rename or delete it.
struct LibraryExerciseView: View {
    let exercise: LibraryExercise

    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Program.createdAt) private var programs: [Program]
    @State private var reps = EditableProgram.defaultReps
    @State private var choosingReps = false
    /// A movement filmed on one side: which side to do now.
    @State private var sides = LibraryExercise.SideChoice.both
    @State private var renaming = false
    @State private var newName = ""
    @State private var confirmingDelete = false
    /// The filmed movement being checked ("Vérifier le mouvement").
    @State private var checking: ReferenceMovement?
    /// Bumped after a check: the movement may have been learned again, its images changed.
    @State private var movementRevision = 0

    var body: some View {
        let using = programs.filter { $0.exercises.contains { $0.name == exercise.name } }
        let others = programs.filter { program in !using.contains { $0.persistentModelID == program.persistentModelID } }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                MovementCard(catalog: exercise.catalogExercise, symbol: exercise.planned.figureSymbol)
                    .id(movementRevision)
                    .accessibilityLabel(Text("Mouvement : \(exercise.name)"))

                doNow

                VStack(alignment: .leading, spacing: 0) {
                    Text("Programmes")
                        .font(.headline)
                        .padding()
                    ForEach(using) { program in
                        Divider().padding(.leading)
                        Label(program.title, systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .padding(.horizontal)
                    }
                    Divider().padding(.leading)
                    Menu {
                        ForEach(others) { program in
                            Button(program.title) { exercise.append(to: program) }
                        }
                        Button("Nouveau programme") { router.newProgram(with: [exercise.name]) }
                    } label: {
                        Label("Ajouter à un programme", systemImage: "plus.circle")
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal)
                            .contentShape(.rect)
                    }
                }
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))

                VStack(spacing: 0) {
                    if let reference = exercise.catalogExercise?.reference {
                        Button { checking = reference } label: {
                            Label("Vérifier le mouvement", systemImage: "eye")
                                .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                                .padding(.horizontal)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        Divider().padding(.leading)
                    }
                    Button {
                        newName = exercise.name
                        renaming = true
                    } label: {
                        Label("Renommer", systemImage: "pencil")
                            .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
                            .padding(.horizontal)
                            .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    Divider().padding(.leading)
                    Button(role: .destructive) { confirmingDelete = true } label: {
                        HStack {
                            Label("Supprimer l'exercice", systemImage: "trash")
                                .confirmationDialog("Supprimer « \(exercise.name) » ?", isPresented: $confirmingDelete,
                                                    titleVisibility: .visible) {
                                    Button("Supprimer l'exercice", role: .destructive) {
                                        dismiss()
                                        context.delete(exercise)
                                    }
                                } message: {
                                    Text("Les programmes qui l'utilisent le gardent.")
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
        .navigationTitle(exercise.name)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $checking, onDismiss: { movementRevision += 1 }) { MovementCheckSheet(movement: $0) }
        .alert("Renommer l'exercice", isPresented: $renaming) {
            TextField("Nom", text: $newName)
                .textInputAutocapitalization(.sentences)
            Button("Renommer") { rename() }
            Button("Annuler", role: .cancel) {}
        }
    }

    /// Do it right now, alone: how many on the iPhone's wheel, then start.
    private var doNow: some View {
        VStack(spacing: 12) {
            if exercise.holdSeconds == nil {
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
            }
            if let filmed = exercise.filmedSide {
                // Filmed on one side: both, as filmed, or the other side with the film in mirror.
                Picker("Côté", selection: $sides) {
                    Text("Les deux").tag(LibraryExercise.SideChoice.both)
                    Text(filmed == .right ? "Droit" : "Gauche").tag(LibraryExercise.SideChoice.filmed)
                    Text(filmed == .right ? "Gauche (miroir)" : "Droit (miroir)").tag(LibraryExercise.SideChoice.mirrored)
                }
                .pickerStyle(.segmented)
                .accessibilityHint(Text("Le côté miroir montre la vidéo retournée et suit l'autre côté du corps."))
            }
            Button {
                router.startExercise(exercise.workoutExercise(reps: reps, sides: sides))
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

    private func rename() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed != exercise.name else { return }
        // The programs show it under the same name.
        for program in programs {
            for planned in program.exercises where planned.name == exercise.name { planned.name = trimmed }
        }
        if let id = exercise.catalogID.flatMap(ReferenceStore.id(fromCatalogID:)) { ReferenceStore.rename(id, to: trimmed) }
        exercise.name = trimmed
    }
}
