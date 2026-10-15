import SwiftUI

/// An exercise as a tile: its video at the end of the movement, or its pictogram on blue, and its name.
struct ExerciseTile: View {
    enum Content {
        case filmed(ReferenceMovement)
        case catalog(CatalogExercise)
        /// Done without the camera: counted by hand or held.
        case other(name: String, symbol: String)
        case add
    }

    let content: Content
    var isSelected = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            picture
                .frame(maxWidth: .infinity)
                .aspectRatio(3 / 4, contentMode: .fit)
                .clipShape(.rect(cornerRadius: 18))
                .overlay {
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 3 : 0)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                            .padding(6)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
        }
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var title: String {
        switch content {
        case .filmed(let movement): movement.name
        case .catalog(let exercise): String(localized: exercise.name)
        case .other(let name, _): name
        case .add: String(localized: "Nouvel exercice")
        }
    }

    @ViewBuilder
    private var picture: some View {
        switch content {
        case .filmed(let movement):
            ReferenceFramesView(movement: movement, progress: 1)
                .background(Color.black)
        case .catalog(let exercise):
            symbol(exercise.symbol)
        case .other(_, let symbol):
            self.symbol(symbol)
        case .add:
            Image(systemName: "plus")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.accentColor.opacity(0.12))
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 38))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.accentColor.gradient)
    }
}

/// Three tiles a row, the same grid everywhere.
struct ExerciseGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 14) {
            content
        }
    }
}

/// The first step of a séance: tick its exercises among "Mes exercices" and Rebond's, in the order they will
/// be done. A new exercise can be filmed without leaving. The physiotherapist's sheet or message fills it at once.
struct ExercisePickerView: View {
    var preselected: [String] = []
    var nextTitle: LocalizedStringKey = "Suivant"
    /// Offers the physiotherapist's sheet or message instead (only when creating a séance).
    var onPhysiotherapistSource: ((AppRouter.ImportSource) -> Void)?
    let onNext: ([EditableProgram.Exercise]) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(ExerciseLibrary.self) private var library
    /// Picked exercises, in order: catalog identifiers, or the identifiers of the ones done without camera.
    @State private var selection: [String] = []
    @State private var others: [EditableProgram.Exercise] = []
    @State private var creating = false
    @State private var naming: EditableProgram.Exercise?
    @State private var name = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let onPhysiotherapistSource {
                    physiotherapistCard(onPhysiotherapistSource)
                }

                title("Mes exercices")
                ExerciseGrid {
                    Button { creating = true } label: { ExerciseTile(content: .add) }
                        .buttonStyle(.plain)
                    ForEach(library.movements) { movement in
                        tile(.filmed(movement), id: movement.catalogID)
                    }
                }

                title("Exercices Rebond")
                ExerciseGrid {
                    ForEach(CatalogExercise.all) { exercise in
                        tile(.catalog(exercise), id: exercise.id)
                    }
                }

                title("Sans caméra")
                ExerciseGrid {
                    ForEach(others) { exercise in
                        tile(.other(name: exercise.name, symbol: exercise.mode == .hold ? "timer" : "hand.tap"),
                             id: exercise.id.uuidString)
                    }
                    Button { askName(hold: false) } label: {
                        ExerciseTile(content: .other(name: String(localized: "Compté à la main"), symbol: "hand.tap"))
                    }
                    .buttonStyle(.plain)
                    Button { askName(hold: true) } label: {
                        ExerciseTile(content: .other(name: String(localized: "Position tenue"), symbol: "timer"))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 90)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Choisir les exercices")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Button { onNext(chosen) } label: {
                Group {
                    if selection.isEmpty {
                        Text("Choisissez des exercices")
                    } else {
                        Text("\(Text(nextTitle)) (\(selection.count))")
                    }
                }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
            .disabled(selection.isEmpty)
            .padding()
        }
        .onAppear { if selection.isEmpty { selection = preselected } }
        .sheet(isPresented: $creating) {
            NewExerciseView { movement in
                withAnimation(.snappy) { selection.append(movement.catalogID) }
            }
        }
        .alert(naming?.mode == .hold ? "Position tenue" : "Exercice compté à la main",
               isPresented: Binding(get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField(naming?.mode == .hold ? "Ex. : Gainage" : "Ex. : Pont fessier", text: $name)
                .textInputAutocapitalization(.sentences)
            Button("Ajouter") {
                guard var exercise = naming else { return }
                exercise.name = name.trimmingCharacters(in: .whitespaces)
                naming = nil
                guard !exercise.name.isEmpty else { return }
                others.append(exercise)
                withAnimation(.snappy) { selection.append(exercise.id.uuidString) }
            }
            Button("Annuler", role: .cancel) { naming = nil }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }

    private func title(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 10)
    }

    private func tile(_ content: ExerciseTile.Content, id: String) -> some View {
        Button {
            withAnimation(.snappy) {
                if let index = selection.firstIndex(of: id) { selection.remove(at: index) } else { selection.append(id) }
            }
        } label: {
            ExerciseTile(content: content, isSelected: selection.contains(id))
        }
        .buttonStyle(.plain)
    }

    /// The physiotherapist's sheet or message: read, they make the séance's exercises at once.
    private func physiotherapistCard(_ open: @escaping (AppRouter.ImportSource) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Votre kiné vous a donné une feuille ou un message ?", systemImage: "doc.text")
                .font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                Button("Scanner") { open(.scan) }
                Button("Photo") { open(.photo) }
                Button("Message") { open(.message) }
            }
            .buttonStyle(.glass)
            .controlSize(.regular)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .padding(.top, 8)
    }

    private func askName(hold: Bool) {
        var exercise = EditableProgram.Exercise(name: "", catalogID: nil, sets: EditableProgram.defaultSets,
                                                reps: EditableProgram.defaultReps)
        if hold { exercise.mode = .hold }
        name = ""
        naming = exercise
    }

    /// The picked exercises, in the order they were picked, in 3 × 10.
    private var chosen: [EditableProgram.Exercise] {
        selection.compactMap { id in
            if let other = others.first(where: { $0.id.uuidString == id }) { return other }
            guard let exercise = CatalogExercise.find(id) else { return nil }
            return EditableProgram.Exercise(name: String(localized: exercise.name), catalogID: id,
                                            sets: EditableProgram.defaultSets, reps: EditableProgram.defaultReps)
        }
    }
}

/// A new séance: choose its exercises, set them, then when.
struct NewSessionFlow: View {
    var preselected: [String] = []
    let onPhysiotherapistSource: (AppRouter.ImportSource) -> Void
    let onSave: (EditableProgram) -> Void

    /// The séance being set, once its exercises are picked.
    private struct Step: Hashable {
        let id = UUID()
        let program: EditableProgram
        static func == (lhs: Step, rhs: Step) -> Bool { lhs.id == rhs.id }
        func hash(into hasher: inout Hasher) { hasher.combine(id) }
    }

    @State private var step: Step?

    var body: some View {
        NavigationStack {
            ExercisePickerView(preselected: preselected, onPhysiotherapistSource: onPhysiotherapistSource) { exercises in
                var program = EditableProgram()
                program.exercises = exercises
                step = Step(program: program)
            }
            .navigationDestination(item: $step) { step in
                ProgramEditorView(program: step.program, showsCancel: false, onSave: onSave)
            }
        }
        .interactiveDismissDisabled()
    }
}
