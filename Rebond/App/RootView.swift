import PhotosUI
import SwiftData
import SwiftUI

/// The patient's two tabs (HIG: tabs are for navigation, never for actions), or the physiotherapist space.
/// Also opens what other apps hand over: a program prescribed by QR code, or a patient's report.
struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @AppStorage(AppRole.key) private var role = AppRole.patient.rawValue

    /// The program being reviewed before it is saved: read from a photo, typed, or prescribed.
    private struct Draft: Identifiable {
        enum Content {
            case photo(UIImage)
            case program(EditableProgram, notice: LocalizedStringKey?)
        }
        let id = UUID()
        let content: Content
    }

    @State private var draft: Draft?
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var savedProgram = 0
    @State private var openedReport: URL?
    /// Set while the program being reviewed comes from the physiotherapist.
    @State private var prescriber: String?
    @State private var showingPaywall = false

    var body: some View {
        @Bindable var router = router

        Group {
            if role == AppRole.physiotherapist.rawValue {
                ProHomeView()
            } else {
                patientTabs
            }
        }
        .sheet(item: $draft) { draft in
            NavigationStack {
                switch draft.content {
                case .photo(let image):
                    SheetReadingView(photo: image, onSave: save)
                case .program(let program, let notice):
                    ProgramEditorView(program: program, notice: notice, onSave: save)
                }
            }
            .interactiveDismissDisabled()
        }
        .onOpenURL(perform: open)
        .alert("Bilan d'un patient", isPresented: Binding(get: { openedReport != nil }, set: { if !$0 { openedReport = nil } })) {
            Button("Ouvrir l'espace kiné") {
                if let openedReport { importReport(openedReport) }
                role = AppRole.physiotherapist.rawValue
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Ce fichier est le bilan d'un patient. Il s'ouvre dans l'espace kiné de Rebond.")
        }
        .sheet(isPresented: $showingPaywall) { ProPaywall() }
        .sensoryFeedback(.success, trigger: savedProgram)
        #if DEBUG
        .modifier(ConnectedPatient())
        #endif
    }

    private func importReport(_ url: URL) {
        if case .limitReached = ProHomeView.importReport(at: url, into: context, hasPro: store.hasPro) {
            showingPaywall = true
        }
    }

    private var patientTabs: some View {
        @Bindable var router = router

        return TabView(selection: $router.tab) {
            Tab("Résumé", systemImage: "heart.text.square", value: .today) {
                TodayView()
            }
            Tab("Programme", systemImage: "calendar", value: .program) {
                ProgramTab()
            }
        }
        .tabBarMinimizeBehavior(.never)
        .fullScreenCover(isPresented: $router.isWorkoutPresented) {
            if let program = programs.first {
                WorkoutView(program: program)
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
    }

    /// A program link scanned from the physiotherapist's QR code, or a report file opened with Rebond.
    private func open(_ url: URL) {
        #if DEBUG
        if url.host() == "connecter" {
            role = AppRole.patient.rawValue
            Task { _ = await DemoServer.shared.link(from: url) }
            return
        }
        #endif
        if let transfer = ProgramTransfer(url: url) {
            role = AppRole.patient.rawValue
            prescriber = transfer.k ?? ""
            let notice: LocalizedStringKey = if let name = transfer.k {
                "Programme prescrit par \(name). Vérifiez-le puis enregistrez-le."
            } else {
                "Programme prescrit par votre kiné. Vérifiez-le puis enregistrez-le."
            }
            draft = Draft(content: .program(transfer.editableProgram, notice: notice))
        } else if url.isFileURL {
            if role == AppRole.physiotherapist.rawValue {
                importReport(url)
            } else {
                openedReport = url
            }
        }
    }

    private func save(_ program: EditableProgram) {
        // A program prescribed by the physiotherapist shows what changed on the Résumé page.
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

#if DEBUG
/// Patient side of the connected version (demo server): sends the report once linked, and offers the program
/// changed by the physiotherapist as soon as it arrives.
private struct ConnectedPatient: ViewModifier {
    @Environment(\.modelContext) private var context
    @State private var server = DemoServer.shared

    func body(content: Content) -> some View {
        content
            .task(id: server.isLinked) {
                guard server.isLinked else { return }
                await server.pushReport(context: context)
                while !Task.isCancelled {
                    await server.checkProgram()
                    try? await Task.sleep(for: .seconds(4))
                }
            }
            .sheet(isPresented: Binding(
                get: { server.pendingProgram != nil },
                set: { if !$0 { server.settlePendingProgram() } }
            )) {
                if let pending = server.pendingProgram {
                    NavigationStack {
                        ProgramEditorView(
                            program: pending.program.editableProgram,
                            notice: pending.program.k.map { "\($0) a modifié votre programme. Vérifiez-le puis enregistrez-le." }
                                ?? "Votre kiné a modifié votre programme. Vérifiez-le puis enregistrez-le."
                        ) { program in
                            let current = try? context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.createdAt, order: .reverse)])).first
                            ProgramChange.record(from: current, to: program, by: pending.program.k)
                            Program.replaceAll(with: program, in: context)
                            server.settlePendingProgram()
                            Task { await server.pushReport(context: context) }
                        }
                    }
                    .interactiveDismissDisabled()
                }
            }
    }
}
#endif
