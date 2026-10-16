import PhotosUI
import SwiftData
import SwiftUI

/// The tabs (HIG: tabs are for navigation, never for actions): Accueil and Programme for everyone, plus Kiné when the
/// physiotherapist space is turned on. Also opens what other apps hand over: a program prescribed by QR code,
/// or a patient's report.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query private var library: [LibraryExercise]
    @AppStorage(AppRole.key) private var role = AppRole.patient.rawValue
    /// The welcome screen is shown once, at first launch.
    @AppStorage(AppRole.welcomeSeenKey) private var welcomeSeen = false

    /// The program being reviewed before it is saved: read from a photo, typed, or prescribed.
    private struct Draft: Identifiable {
        enum Content {
            case message
            case photo(UIImage)
            case program(EditableProgram, notice: LocalizedStringKey?, start: ProgramEditorView.Start? = nil)
        }
        let id = UUID()
        let content: Content
    }

    @State private var draft: Draft?
    @State private var pickedPhoto: PhotosPickerItem?
    /// Videos just filmed, waiting for the camera to close to open their new séance.
    @State private var filmed: [URL] = []
    @State private var pickedVideos: [PhotosPickerItem] = []
    @State private var savedProgram = 0
    /// Set while the program being reviewed comes from the physiotherapist.
    @State private var prescriber: String?
    @State private var showingPaywall = false
    @State private var invalidReport = false

    @Namespace private var workoutTransition

    private var isPhysiotherapist: Bool { role == AppRole.physiotherapist.rawValue }

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.tab) {
            Tab("Accueil", systemImage: "house", value: .today) {
                TodayView()
                    .environment(\.workoutTransition, workoutTransition)
            }
            // Without a program, Accueil already offers to add one: a second tab would be the same page.
            // "Exercices": the exercises, and the programs made of them.
            if !programs.isEmpty || !library.isEmpty {
                Tab("Exercices", systemImage: "figure.mixed.cardio", value: .program) {
                    ProgramTab()
                }
            }
            if isPhysiotherapist {
                Tab("Kiné", systemImage: "stethoscope", value: .physio) {
                    ProHomeView()
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
        // Wide screens (unfolded foldable, landscape): pages keep a readable width, centred.
        .readableWidth()
        // The last program deleted: its tab goes away, back to Accueil.
        .onChange(of: programs.isEmpty) {
            if programs.isEmpty, library.isEmpty, router.tab == .program { router.tab = .today }
        }
        // Turning the space off from Réglages leaves its tab.
        // "Mes exercices" also lists the exercises of the programs saved before it existed.
        .task {
            LibraryExercise.addDefaults(in: context)
            LibraryExercise.addMissing(programs.flatMap(\.orderedExercises), in: context)
            // Following a program or not is gone: a program without days is simply not in the day's session.
            for program in programs where !program.isActive { program.isActive = true }
        }
        .onChange(of: role) {
            if !isPhysiotherapist, router.tab == .physio { router.tab = .today }
        }
        .fullScreenCover(isPresented: Binding(get: { !welcomeSeen }, set: { if !$0 { welcomeSeen = true } })) {
            WelcomeView { chosen in
                role = chosen.rawValue
                if chosen == .physiotherapist { router.openPhysioSpace() }
                welcomeSeen = true
            }
            .interactiveDismissDisabled()
        }
        .fullScreenCover(isPresented: $router.isWorkoutPresented) {
            if let free = router.freeExercise {
                WorkoutView(exercises: [free], offersMoreSets: true, isTrial: true)
            } else if let program = router.workoutProgram.flatMap({ id in programs.first { $0.persistentModelID == id } }) {
                WorkoutView(program: program, onlyExercise: router.workoutExerciseIndex)
            } else {
                // The day's session: the exercises of every program planned today (or on the next day with one).
                WorkoutView(exercises: programs.sessionExercises().map(\.workoutExercise))
                    // The session grows out of the Commencer button.
                    .navigationTransition(.zoom(sourceID: WorkoutTransition.sourceID, in: workoutTransition))
            }
        }
        .fullScreenCover(isPresented: Binding(
            get: { router.importSource == .scan },
            set: { if !$0 { router.importSource = nil } }
        )) {
            DocumentScanner { image in
                router.importSource = nil
                if let image { draft = Draft(content: .photo(image)) }
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(isPresented: Binding(
            get: { router.importSource == .film },
            set: { if !$0 { router.importSource = nil } }
        ), onDismiss: {
            // Once the camera is gone: the new séance, its videos being analyzed.
            guard !filmed.isEmpty else { return }
            draft = Draft(content: .program(EditableProgram(), notice: nil, start: .recordings(filmed)))
            filmed = []
        }) {
            RecordMovementView { filmed = $0 }
        }
        .photosPicker(
            isPresented: Binding(
                get: { router.importSource == .videos },
                set: { if !$0 { router.importSource = nil } }
            ),
            selection: $pickedVideos,
            matching: .videos
        )
        .onChange(of: pickedVideos) {
            guard !pickedVideos.isEmpty else { return }
            draft = Draft(content: .program(EditableProgram(), notice: nil, start: .videos(pickedVideos)))
            pickedVideos = []
        }
        .sheet(item: $router.programCreation) { creation in
            NewProgramFlow(preselected: creation.preselected) { program in
                router.programCreation = nil
                save(program)
            }
        }
        .photosPicker(
            isPresented: Binding(
                get: { router.importSource == .photo },
                set: { if !$0 { router.importSource = nil } }
            ),
            selection: $pickedPhoto,
            matching: .images
        )
        .onChange(of: router.importSource) {
            if router.importSource == .manual {
                router.importSource = nil
                draft = Draft(content: .program(EditableProgram(), notice: nil, start: .chooseExercise))
            } else if router.importSource == .message {
                router.importSource = nil
                draft = Draft(content: .message)
            }
        }
        .onChange(of: pickedPhoto) {
            guard let pickedPhoto else { return }
            Task {
                if let data = try? await pickedPhoto.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                    draft = Draft(content: .photo(image))
                }
                self.pickedPhoto = nil
            }
        }
        .sheet(item: $draft) { draft in
            NavigationStack {
                switch draft.content {
                case .message:
                    MessageReadingView(onSave: save)
                case .photo(let image):
                    SheetReadingView(photo: image, onSave: save)
                case .program(let program, let notice, let start):
                    ProgramEditorView(program: program, notice: notice, start: start, onSave: save)
                }
            }
            .interactiveDismissDisabled()
        }
        .onOpenURL(perform: open)
        .sheet(isPresented: $showingPaywall) { ProPaywall(followed: TrackedPatient.countedPatients(in: context)) }
        .alert("Ce fichier n'est pas un bilan Rebond.", isPresented: $invalidReport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Demandez à votre patient de vous renvoyer le fichier « Bilan Rebond » joint à son PDF.")
        }
        .sensoryFeedback(.success, trigger: savedProgram)
    }

    /// A program link scanned from the physiotherapist's QR code, or a report file opened with Rebond.
    private func open(_ url: URL) {
        // Opened from a QR code or a report: what to do is clear, no welcome screen over it.
        welcomeSeen = true
        if let transfer = ProgramTransfer(url: url) {
            prescriber = transfer.k ?? ""
            let notice: LocalizedStringKey = if let name = transfer.k {
                "Séance prescrite par \(name). Vérifiez-la puis enregistrez-la."
            } else {
                "Séance prescrite par votre kiné. Vérifiez-la puis enregistrez-la."
            }
            draft = Draft(content: .program(transfer.editableProgram, notice: notice))
        } else if url.isFileURL {
            openReport(url)
        }
    }

    /// A patient's report only makes sense in the physiotherapist space: opening one turns it on and shows the patient.
    private func openReport(_ url: URL) {
        let result = TrackedPatient.importReport(at: url, into: context, patientLimit: store.patientLimit)
        if result == .invalid {
            invalidReport = true
            return
        }
        role = AppRole.physiotherapist.rawValue
        switch result {
        case .imported(let id):
            router.openPhysioSpace(patient: id)
        case .limitReached:
            router.openPhysioSpace()
            showingPaywall = true
        case .invalid:
            break
        }
    }

    /// A new program joins the others. A physiotherapist's new prescription replaces their previous one
    /// (same physiotherapist, same name).
    private func save(_ program: EditableProgram) {
        if let prescriber {
            let name = prescriber.isEmpty ? nil : prescriber
            let previous = name.flatMap { name in
                programs.first { $0.prescriber == name && $0.name == program.name.trimmingCharacters(in: .whitespaces) }
            }
            if let previous {
                previous.update(with: program, in: context)
                LibraryExercise.addMissing(previous.orderedExercises, in: context)
            } else {
                Program.add(program, prescriber: name, in: context)
            }
            self.prescriber = nil
        } else {
            Program.add(program, in: context)
        }
        draft = nil
        savedProgram += 1
        router.tab = .program
    }
}

/// The zoom from the Commencer button to the session.
enum WorkoutTransition {
    static let sourceID = "startWorkout"
}

extension EnvironmentValues {
    @Entry var workoutTransition: Namespace.ID?
}
