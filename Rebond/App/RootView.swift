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
    @AppStorage(AppRole.key) private var role = AppRole.patient.rawValue

    /// The program being reviewed before it is saved: read from a photo, typed, or prescribed.
    private struct Draft: Identifiable {
        enum Content {
            case message
            case photo(UIImage)
            case program(EditableProgram, notice: LocalizedStringKey?)
        }
        let id = UUID()
        let content: Content
    }

    @State private var draft: Draft?
    @State private var pickedPhoto: PhotosPickerItem?
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
            Tab("Programme", systemImage: "list.bullet.clipboard", value: .program) {
                ProgramTab()
            }
            if isPhysiotherapist {
                Tab("Kiné", systemImage: "stethoscope", value: .physio) {
                    ProHomeView()
                }
            }
        }
        .tabBarMinimizeBehavior(.never)
        // Turning the space off from Réglages leaves its tab.
        .onChange(of: role) {
            if !isPhysiotherapist, router.tab == .physio { router.tab = .today }
        }
        .fullScreenCover(isPresented: $router.isWorkoutPresented) {
            if let program = programs.first {
                WorkoutView(program: program)
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
                draft = Draft(content: .program(EditableProgram(), notice: nil))
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
                case .program(let program, let notice):
                    ProgramEditorView(program: program, notice: notice, onSave: save)
                }
            }
            .interactiveDismissDisabled()
        }
        .onOpenURL(perform: open)
        .sheet(isPresented: $showingPaywall) { ProPaywall() }
        .alert("Ce fichier n'est pas un bilan Rebond.", isPresented: $invalidReport) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Demandez à votre patient de vous renvoyer le fichier « Bilan Rebond » joint à son PDF.")
        }
        .sensoryFeedback(.success, trigger: savedProgram)
    }

    /// A program link scanned from the physiotherapist's QR code, or a report file opened with Rebond.
    private func open(_ url: URL) {
        if let transfer = ProgramTransfer(url: url) {
            prescriber = transfer.k ?? ""
            let notice: LocalizedStringKey = if let name = transfer.k {
                "Programme prescrit par \(name). Vérifiez-le puis enregistrez-le."
            } else {
                "Programme prescrit par votre kiné. Vérifiez-le puis enregistrez-le."
            }
            draft = Draft(content: .program(transfer.editableProgram, notice: notice))
        } else if url.isFileURL {
            openReport(url)
        }
    }

    /// A patient's report only makes sense in the physiotherapist space: opening one turns it on and shows the patient.
    private func openReport(_ url: URL) {
        let result = TrackedPatient.importReport(at: url, into: context, hasPro: store.hasPro)
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

    private func save(_ program: EditableProgram) {
        // A program prescribed by the physiotherapist shows what changed on the Aujourd'hui page.
        if let prescriber {
            ProgramChange.record(from: programs.first, to: program, by: prescriber.isEmpty ? nil : prescriber)
            self.prescriber = nil
        }
        Program.replaceAll(with: program, in: context)
        draft = nil
        savedProgram += 1
        router.tab = .today
    }
}

/// The zoom from the Commencer button to the session.
enum WorkoutTransition {
    static let sourceID = "startWorkout"
}

extension EnvironmentValues {
    @Entry var workoutTransition: Namespace.ID?
}
