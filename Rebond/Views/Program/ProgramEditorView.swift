import PhotosUI
import SwiftUI

/// "Ma séance": the same screen to create a séance, whatever its source (videos from the physiotherapist's,
/// their sheet or message, exercises picked in the list), and to change it later.
/// Each exercise is a card: its video in a loop (or its symbol), its name, "3 × 10". Tapping it opens the wheels,
/// its name and its video. Swipe to delete, drag to reorder. "Continuer" asks when, then saves.
struct ProgramEditorView: View {
    /// What to do as soon as the screen opens, from the "Ajouter une séance" choices.
    enum Start {
        case videos([PhotosPickerItem])
        case recordings([URL])
        case chooseExercise
    }

    @State var program: EditableProgram
    /// The sheet that was read, to compare with while checking.
    var photo: UIImage?
    /// Shown above the list, e.g. to say the program was read by Apple Intelligence.
    var notice: LocalizedStringKey?
    /// Symbol of the notice; by default Apple Intelligence for a sheet, the physiotherapist otherwise.
    var noticeSymbol: String?
    var title: LocalizedStringKey = "Ma séance"
    /// Shows a button to Settings under the notice (Apple Intelligence turned off).
    var opensSettings = false
    /// The patient's videos: not for a prescription, which travels by QR code.
    var allowsVideos = true
    var start: Start?
    let onSave: (EditableProgram) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var showingPhoto = false
    /// The exercise whose wheels are open.
    @State private var expanded: EditableProgram.Exercise.ID?
    @State private var choosingExercise = false
    @State private var analyses: [EditableProgram.Exercise.ID: VideoAnalysis] = [:]
    @State private var pickingVideos = false
    @State private var pickedVideos: [PhotosPickerItem] = []
    @State private var filming = false
    @State private var filmed: [URL] = []
    /// The exercise whose video is being added or replaced; nil adds new exercises.
    @State private var videoTarget: EditableProgram.Exercise.ID?
    @State private var scheduling = false
    @State private var started = false

    private var isAnalyzing: Bool {
        analyses.values.contains { if case .running = $0 { true } else { false } }
    }

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
                ForEach($program.exercises) { $exercise in
                    ExerciseCard(
                        exercise: $exercise,
                        name: program.displayName(of: exercise),
                        analysis: analyses[exercise.id],
                        isExpanded: expanded == exercise.id,
                        allowsVideos: allowsVideos,
                        onToggle: {
                            withAnimation(.snappy) { expanded = expanded == exercise.id ? nil : exercise.id }
                        },
                        onPickVideo: {
                            videoTarget = exercise.id
                            pickingVideos = true
                        },
                        onFilm: {
                            videoTarget = exercise.id
                            filming = true
                        }
                    )
                }
                .onDelete { offsets in
                    for index in offsets { analyses[program.exercises[index].id] = nil }
                    program.exercises.remove(atOffsets: offsets)
                }
                .onMove { program.exercises.move(fromOffsets: $0, toOffset: $1) }
            } footer: {
                if program.exercises.isEmpty {
                    Text("Ajoutez les exercices de votre séance.")
                }
            }

            Section {
                addMenu
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Annuler", systemImage: "xmark", role: .cancel) { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Continuer") { scheduling = true }
                    .fontWeight(.semibold)
                    .disabled(program.exercises.isEmpty || isAnalyzing || hasFailures)
            }
        }
        .navigationDestination(isPresented: $scheduling) {
            ScheduleStep(program: $program, asksReminder: allowsVideos) { saved in
                // The videos take the names given here, shown during the session.
                for exercise in saved.exercises {
                    if let id = exercise.catalogID.flatMap(ReferenceStore.id(fromCatalogID:)) {
                        ReferenceStore.rename(id, to: saved.displayName(of: exercise))
                    }
                }
                onSave(saved)
            }
        }
        .sheet(isPresented: $choosingExercise) {
            ExerciseChooser { exercise in
                program.exercises.append(exercise)
                withAnimation(.snappy) { expanded = exercise.id }
            }
        }
        .photosPicker(isPresented: $pickingVideos, selection: $pickedVideos,
                      maxSelectionCount: videoTarget == nil ? nil : 1, matching: .videos)
        .onChange(of: pickedVideos) {
            guard !pickedVideos.isEmpty else { return }
            let items = pickedVideos
            pickedVideos = []
            addVideos(items: items)
        }
        .fullScreenCover(isPresented: $filming, onDismiss: {
            let takes = filmed
            filmed = []
            addVideos(takes.map { ($0, false) })
        }) {
            RecordMovementView(allowsSeveral: videoTarget == nil) { filmed = $0 }
        }
        .task {
            guard !started else { return }
            started = true
            switch start {
            case .videos(let items): addVideos(items: items)
            case .recordings(let urls): addVideos(urls.map { ($0, false) })
            case .chooseExercise: choosingExercise = true
            case nil: break
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

    private var hasFailures: Bool {
        analyses.values.contains { if case .failed = $0 { true } else { false } }
    }

    /// The same ways as when creating the séance: the physiotherapist's videos, or an exercise of the list.
    private var addMenu: some View {
        Menu {
            if allowsVideos {
                Section("Vidéos de mon kiné") {
                    Button("Choisir mes vidéos", systemImage: "photo.on.rectangle") {
                        videoTarget = nil
                        pickingVideos = true
                    }
                    Button("Filmer", systemImage: "video") {
                        videoTarget = nil
                        filming = true
                    }
                }
            }
            Button("Choisir dans la liste", systemImage: "list.bullet") { choosingExercise = true }
        } label: {
            Label("Ajouter un exercice", systemImage: "plus")
        }
    }

    // MARK: Videos

    private func addVideos(items: [PhotosPickerItem]) {
        let target = videoTarget
        let ids = prepare(count: items.count, target: target)
        Task {
            for (item, id) in zip(items, ids) {
                guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
                    analyses[id] = .failed("Cette vidéo n'a pas pu être ouverte.")
                    continue
                }
                // Filmed with the Camera app, not like a mirror: turned over to look like the session's camera.
                await learn(movie.url, mirrored: true, for: id)
            }
        }
    }

    private func addVideos(_ videos: [(url: URL, mirrored: Bool)]) {
        guard !videos.isEmpty else { return }
        let ids = prepare(count: videos.count, target: videoTarget)
        Task {
            for (video, id) in zip(videos, ids) {
                await learn(video.url, mirrored: video.mirrored, for: id)
            }
        }
    }

    /// One card per new video, waiting for its analysis; or the exercise whose video is replaced.
    private func prepare(count: Int, target: EditableProgram.Exercise.ID?) -> [EditableProgram.Exercise.ID] {
        if let target {
            analyses[target] = .running
            return [target]
        }
        let new = (0..<count).map { _ in
            EditableProgram.Exercise(name: "", catalogID: nil, sets: EditableProgram.defaultSets, reps: EditableProgram.defaultReps)
        }
        program.exercises.append(contentsOf: new)
        for exercise in new { analyses[exercise.id] = .running }
        return new.map(\.id)
    }

    private func learn(_ video: URL, mirrored: Bool, for id: EditableProgram.Exercise.ID) async {
        do {
            let movement = try await ReferenceStore.learn(from: video, name: "", mirrored: mirrored)
            guard let index = program.exercises.firstIndex(where: { $0.id == id }) else {
                ReferenceStore.delete(movement.id)
                return
            }
            var exercise = program.exercises[index]
            exercise.catalogID = movement.catalogID
            exercise.mode = .reps
            if exercise.name.trimmingCharacters(in: .whitespaces).isEmpty {
                exercise.name = uniqueName(movement.name)
                // A new exercise: the sets and repetitions planned from what was measured.
                if let plan = movement.plan {
                    exercise.sets = plan.sets
                    exercise.reps = plan.reps
                }
            }
            program.exercises[index] = exercise
            analyses[id] = nil
        } catch ReferenceError.poorCapture(let advice) {
            analyses[id] = .failed("\(advice)")
        } catch ReferenceError.noBody {
            analyses[id] = .failed("Corps mal visible : filmez de face, le corps entier dans l'image.")
        } catch {
            analyses[id] = .failed("Aucun mouvement répété trouvé dans la vidéo.")
        }
    }

    /// "Jambes", then "Jambes 2": two exercises of the séance don't share a name.
    private func uniqueName(_ name: String) -> String {
        let names = Set(program.exercises.map { $0.name })
        guard names.contains(name) else { return name }
        var number = 2
        while names.contains("\(name) \(number)") { number += 1 }
        return "\(name) \(number)"
    }
}

/// A video being analyzed, or that couldn't be.
private enum VideoAnalysis {
    case running
    case failed(LocalizedStringResource)
}

private extension Optional where Wrapped == VideoAnalysis {
    var isRunning: Bool {
        if case .running = self { true } else { false }
    }

    var isFailed: Bool {
        if case .failed = self { true } else { false }
    }
}

/// When: the days, the reminder, and the séance's name (already given from its exercises).
private struct ScheduleStep: View {
    @Binding var program: EditableProgram
    let asksReminder: Bool
    let onSave: (EditableProgram) -> Void

    @AppStorage(ReminderSettings.enabledKey) private var remindersEnabled = false
    @AppStorage(ReminderSettings.hourKey) private var reminderHour = ReminderSettings.defaultHour

    var body: some View {
        List {
            Section {
                DayPicker(days: $program.weekdays)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    .onChange(of: program.weekdays) { program.sessionsPerWeekGuessed = false }
            } header: {
                Text("Jours")
            } footer: {
                Text(program.weekdays.isEmpty
                     ? "Choisissez au moins un jour."
                     : "^[\(program.weekdays.count) séance](inflect: true) par semaine : \(ProgramSchedule.describe(program.weekdays)).")
            }

            if asksReminder {
                Section {
                    Toggle("Me le rappeler", isOn: Binding(get: { remindersEnabled }, set: { turnReminders($0) }))
                    if remindersEnabled {
                        Picker("Heure", selection: $reminderHour) {
                            ForEach(6...22, id: \.self) { hour in
                                Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now) ?? .now,
                                     format: .dateTime.hour())
                                    .tag(hour)
                            }
                        }
                    }
                }
            }

            // Already named from what it works on: renaming is possible, never asked for.
            Section("Nom") {
                TextField("Nom", text: $program.name, prompt: Text(program.suggestedName))
            }
        }
        .navigationTitle("Quand ?")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Enregistrer", systemImage: "checkmark", role: .confirm) { onSave(program) }
                    .disabled(!program.isValid)
            }
        }
    }

    /// Asks for permission when turned on; the reminders then follow every séance's days.
    private func turnReminders(_ on: Bool) {
        if on {
            Task { remindersEnabled = await ReminderScheduler.enable(days: program.weekdays, hour: reminderHour) }
        } else {
            remindersEnabled = false
            ReminderScheduler.disable()
        }
    }
}

/// One exercise of the séance: its video in a loop or its symbol, its name, "3 × 10". Tapping it opens the
/// iPhone's wheels for the sets and the repetitions (or seconds), its name and its video.
private struct ExerciseCard: View {
    @Binding var exercise: EditableProgram.Exercise
    /// Its name, or the one it will get.
    let name: String
    let analysis: VideoAnalysis?
    let isExpanded: Bool
    let allowsVideos: Bool
    let onToggle: () -> Void
    let onPickVideo: () -> Void
    let onFilm: () -> Void

    private var catalog: CatalogExercise? {
        exercise.mode == .reps ? exercise.catalogID.flatMap(CatalogExercise.find) : nil
    }

    private var symbol: String {
        if exercise.mode == .hold { return "figure.core.training" }
        return catalog?.symbol ?? "figure.cooldown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button(action: onToggle) {
                HStack(spacing: 12) {
                    thumbnail
                    VStack(alignment: .leading, spacing: 3) {
                        Text(analysis.isRunning ? String(localized: "Analyse de la vidéo…") : name)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        if case .failed(let reason) = analysis {
                            Text(reason)
                                .font(.caption)
                                .foregroundStyle(.orange)
                        } else if !exercise.guessed.isEmpty {
                            Label("À vérifier", systemImage: "questionmark.circle.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.orange)
                        }
                    }
                    Spacer(minLength: 8)
                    if case .none = analysis {
                        Text(exercise.mode == .hold ? "\(exercise.sets) × \(exercise.holdSeconds) s" : "\(exercise.sets) × \(exercise.reps)")
                            .font(.headline)
                            .monospacedDigit()
                            .foregroundStyle(.tint)
                            .contentTransition(.numericText())
                    }
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(analysis.isRunning)

            if isExpanded, !analysis.isRunning {
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
                TextField("Nom", text: $exercise.name, prompt: Text(name))
                    .textFieldStyle(.roundedBorder)
                if allowsVideos, exercise.mode == .reps {
                    Menu {
                        Button("Choisir une vidéo", systemImage: "photo.on.rectangle", action: onPickVideo)
                        Button("Filmer", systemImage: "video", action: onFilm)
                    } label: {
                        Label(catalog?.reference == nil ? "Ajouter une vidéo" : "Remplacer la vidéo", systemImage: "video.badge.plus")
                            .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if analysis.isRunning {
            ProgressView()
                .frame(width: 52, height: 68)
                .background(Color(.tertiarySystemFill), in: .rect(cornerRadius: 12))
        } else {
            Image(systemName: analysis.isFailed ? "exclamationmark.triangle" : symbol)
                .font(.title3)
                .foregroundStyle(analysis.isFailed ? AnyShapeStyle(.orange) : AnyShapeStyle(.tint))
                .frame(width: 52, height: 68)
                .background(Color.accentColor.opacity(0.12), in: .rect(cornerRadius: 12))
        }
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
struct ExerciseChooser: View {
    let onChoose: (EditableProgram.Exercise) -> Void
    @Environment(\.dismiss) private var dismiss
    /// An exercise Rebond doesn't know, waiting for its name.
    @State private var naming: EditableProgram.Exercise?
    @State private var name = ""
    private let filmedMovements = ReferenceStore.all()

    var body: some View {
        NavigationStack {
            List {
                if !filmedMovements.isEmpty {
                Section("Vos vidéos") {
                    ForEach(filmedMovements) { movement in
                        Button {
                            choose(EditableProgram.Exercise(movement))
                        } label: {
                            Label { Text(movement.name).foregroundStyle(.primary) } icon: { Image(systemName: ReferenceMovement.symbol) }
                        }
                    }
                }
                }
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
