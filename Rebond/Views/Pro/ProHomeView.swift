import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The Kiné tab: the physiotherapist's workspace, laid out like the Accueil page (Health-style cards).
/// The week at a glance, prescribing a program by QR code, and the patients followed from the reports they send.
/// Free for up to `ProStore.freePatientLimit` patients; Rebond Pro follows as many as needed. Everything stays on this iPhone.
struct ProHomeView: View {
    @Environment(AppRouter.self) private var router
    @Environment(ProStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedPatient.updatedAt, order: .reverse) private var patients: [TrackedPatient]

    @State private var path: [UUID] = []
    @State private var prescribing: PrescribingItem?
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var importing = false
    @State private var importError = false
    @State private var removing: TrackedPatient?
    @State private var showingPatientSettings = false
    @State private var search = ""

    /// The patients with what the last report says, those needing attention first.
    private var followed: [(patient: TrackedPatient, overview: PatientOverview?)] {
        patients
            .map { patient in (patient, patient.transfer.map { PatientOverview(name: patient.name, transfer: $0) }) }
            .sorted { lhs, rhs in
                switch (lhs.1, rhs.1) {
                case let (left?, right?): left.comesBefore(right)
                case (.some, .none): true
                default: false
                }
            }
    }

    var body: some View {
        NavigationStack(path: $path) {
            // A plain iOS list, like Contacts: search, one row per patient, nothing else.
            List {
                Section {
                    PageHeader("Espace kiné") {
                        Menu {
                            Button("Prescrire un programme", systemImage: "qrcode") {
                                prescribing = PrescribingItem(program: EditableProgram())
                            }
                            Button("Importer un bilan", systemImage: "square.and.arrow.down") { importing = true }
                            Divider()
                            Button("Réglages de l'espace kiné", systemImage: "gearshape") { showingSettings = true }
                        } label: {
                            HeaderIcon(systemImage: "plus")
                        }
                        .accessibilityLabel("Ajouter")
                        ProfileButton { showingPatientSettings = true }
                    }
                    // The list's own margin already insets the rows: none more, so the title sits as on the other tabs.
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 6, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)

                    SearchField(text: $search)
                        .listRowInsets(EdgeInsets(top: 6, leading: 0, bottom: 10, trailing: 0))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                .listSectionSeparator(.hidden)

                let followed = followed.filter { search.isEmpty || $0.patient.name.localizedStandardContains(search) }
                Section {
                    if patients.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Aucun patient pour l'instant")
                                .font(.headline)
                            Button("Importer un bilan", systemImage: "square.and.arrow.down") { importing = true }
                            Button("Essayer avec des patients de démo", systemImage: "person.2") {
                                DemoData.loadPatients(into: context)
                            }
                        }
                        .padding(.vertical, 6)
                    } else {
                        ForEach(followed, id: \.patient.patientID) { item in
                            NavigationLink(value: item.patient.patientID) {
                                PatientRow(name: item.patient.name, overview: item.overview)
                            }
                            .swipeActions(edge: .trailing) {
                                Button("Arrêter le suivi", systemImage: "person.badge.minus", role: .destructive) { removing = item.patient }
                            }
                        }
                    }
                } footer: {
                    Button {
                        showingPaywall = true
                    } label: {
                        Text(store.hasPro ? "Rebond Pro · patients illimités"
                                          : "\(min(patients.count, ProStore.freePatientLimit)) / \(ProStore.freePatientLimit) patients gratuits")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                    .buttonStyle(.plain)
                    .disabled(store.hasPro)
                }
            }
            .listStyle(.insetGrouped)
            .contentMargins(.top, 0, for: .scrollContent)
            .scrollContentBackground(.hidden)
            .background(alignment: .top) {
                // Tinted top, fading into the page, like the Accueil page.
                LinearGradient(colors: [Color.accentColor.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 340)
                    .ignoresSafeArea()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Espace kiné")
            // Same top bar as the other tabs: the large title and its buttons in the page.
            .toolbarVisibility(.hidden, for: .navigationBar)
            .sheet(isPresented: $showingPatientSettings) { SettingsView() }
            .navigationDestination(for: UUID.self) { id in
                PatientDestination(patientID: id) { stopFollowing($0) }
            }
            .sheet(item: $prescribing) { item in
                PrescribeFlow(program: item.program)
            }
            .sheet(isPresented: $showingPaywall) { ProPaywall() }
            .sheet(isPresented: $showingSettings) { ProSettingsView() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.rebondReport, .json]) { result in
                guard case .success(let url) = result else { return }
                switch TrackedPatient.importReport(at: url, into: context, hasPro: store.hasPro) {
                case .imported(let id): path = [id]
                case .limitReached: showingPaywall = true
                case .invalid: importError = true
                }
            }
            .alert("Ce fichier n'est pas un bilan Rebond.", isPresented: $importError) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Choisissez le fichier « Bilan Rebond » envoyé par votre patient avec son PDF.")
            }
            .confirmationDialog(
                "Arrêter le suivi de \(removing?.name ?? "") ?",
                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                titleVisibility: .visible
            ) {
                Button("Arrêter le suivi", role: .destructive) {
                    if let removing { stopFollowing(removing) }
                }
            } message: {
                Text("Ses bilans sont effacés de cet iPhone. Il réapparaîtra s'il vous envoie un nouveau bilan.")
            }
        }
        // A report opened from another app shows its patient.
        .onChange(of: router.openedPatient, initial: true) {
            guard let id = router.openedPatient else { return }
            router.openedPatient = nil
            // After the tab is in place: pushing while it is being built can stall navigation.
            Task { path = [id] }
        }
    }

    /// Leaves the patient's page first, so it never shows a deleted patient.
    private func stopFollowing(_ patient: TrackedPatient) {
        removing = nil
        if path.contains(patient.patientID) {
            path.removeAll()
            Task {
                try? await Task.sleep(for: .milliseconds(600))
                context.delete(patient)
            }
        } else {
            withAnimation { context.delete(patient) }
        }
    }
}

/// A patient's page, found by identifier with its own query, so it follows a report imported a moment ago.
private struct PatientDestination: View {
    let onStopFollowing: (TrackedPatient) -> Void
    @Query private var matches: [TrackedPatient]

    init(patientID: UUID, onStopFollowing: @escaping (TrackedPatient) -> Void) {
        self.onStopFollowing = onStopFollowing
        _matches = Query(filter: #Predicate<TrackedPatient> { $0.patientID == patientID })
    }

    var body: some View {
        if let patient = matches.first {
            PatientDetailView(patient: patient) { onStopFollowing(patient) }
        } else {
            ContentUnavailableView("Patient introuvable", systemImage: "person.crop.circle.badge.questionmark")
        }
    }
}

/// A program being composed, before it becomes a QR code.
struct PrescribingItem: Identifiable {
    let id = UUID()
    let program: EditableProgram
}

// MARK: - Rows

/// A search field in the page, like the system's: the page has no navigation bar to hold one.
private struct SearchField: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Rechercher", text: $text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button("Effacer", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 40)
        .background(Color(.tertiarySystemFill), in: .capsule)
    }
}

/// One patient: initials, name, when the last report came, and an orange dot when the pain was strong.
private struct PatientRow: View {
    let name: String
    let overview: PatientOverview?

    private var detail: String {
        guard let overview else { return String(localized: "Bilan illisible") }
        let when = switch overview.daysSinceReport {
        case 0: String(localized: "Bilan aujourd'hui")
        case 1: String(localized: "Bilan hier")
        default: String(localized: "Bilan il y a \(overview.daysSinceReport) j")
        }
        if overview.attention == .highPain, let pain = overview.lastPain {
            return when + " · " + String(localized: "douleur \(pain)/10")
        }
        return when
    }

    var body: some View {
        HStack(spacing: 12) {
            InitialsBadge(name: name, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.body.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if overview?.attention == .highPain {
                Circle()
                    .fill(.orange)
                    .frame(width: 10, height: 10)
                    .accessibilityLabel(Text("Douleur forte"))
            }
        }
        .padding(.vertical, 2)
    }
}
