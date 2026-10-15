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
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    let followed = followed
                    WeekOverviewCard(overviews: followed.compactMap(\.overview), patientCount: patients.count, hasPro: store.hasPro)
                    PrescribeCard { prescribing = PrescribingItem(program: EditableProgram()) }

                    patientsHeader
                    if followed.isEmpty {
                        EmptyPatientsCard(
                            onImport: { importing = true },
                            onDemo: { DemoData.loadPatients(into: context) }
                        )
                    } else {
                        ForEach(followed, id: \.patient.patientID) { item in
                            NavigationLink(value: item.patient.patientID) {
                                PatientCard(name: item.patient.name, overview: item.overview)
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Arrêter le suivi", systemImage: "person.badge.minus", role: .destructive) { removing = item.patient }
                            }
                            .accessibilityAction(named: "Arrêter le suivi") { removing = item.patient }
                        }
                    }

                    OfferCard(patientCount: patients.count, hasPro: store.hasPro) { showingPaywall = true }

                    Label("Les bilans restent sur cet iPhone : rien n'est envoyé à un serveur.", systemImage: "lock.shield")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.top, 4)
                }
                .padding(.horizontal)
                .padding(.bottom)
            }
            .background(alignment: .top) {
                // Tinted top, fading into the page, like the Accueil page.
                LinearGradient(colors: [Color.accentColor.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 340)
                    .ignoresSafeArea()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Espace kiné")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Réglages de l'espace kiné", systemImage: "gearshape") { showingSettings = true }
                }
            }
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

    private var patientsHeader: some View {
        HStack {
            Text("Mes patients")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button("Importer un bilan", systemImage: "square.and.arrow.down") { importing = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
        }
        .padding(.leading, 4)
        .padding(.top, 10)
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

// MARK: - Cards

/// The week at a glance: patients followed, patients needing attention, reports received in the last 7 days.
private struct WeekOverviewCard: View {
    let overviews: [PatientOverview]
    let patientCount: Int
    let hasPro: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let attention = overviews.filter { $0.attention != .none }.count
        let painful = overviews.filter { $0.attention == .highPain }.count
        let recent = overviews.filter { $0.daysSinceReport < 7 }.count
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                                                         : AnyLayout(HStackLayout(alignment: .top, spacing: 12))

        SummaryCard(title: Text("Cette semaine"), systemImage: nil, color: .accentColor, sectionHeader: true) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                layout {
                    MetricTile(title: "Patients", symbol: "person.2.fill", color: .accentColor,
                               value: "\(patientCount)", unit: hasPro ? "suivis" : "sur \(ProStore.freePatientLimit)",
                               accessibilityValue: Text("\(patientCount) patients suivis"))
                    MetricTile(title: "À regarder", symbol: "exclamationmark.circle.fill", color: .orange,
                               value: "\(attention)", unit: "",
                               accessibilityValue: Text("\(attention) patients à regarder"))
                    MetricTile(title: "Bilans reçus", symbol: "tray.and.arrow.down.fill", color: .teal,
                               value: "\(recent)", unit: "",
                               accessibilityValue: Text("\(recent) bilans reçus ces 7 derniers jours"))
                }
                if painful > 0 {
                    Label("^[\(painful) patient](inflect: true) avec une douleur forte cette semaine. C'est vous qui décidez de la suite.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else if patientCount > 0 {
                    Text("Aucune douleur forte signalée par vos patients cette semaine.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The main action: a new program, shown as a QR code.
private struct PrescribeCard: View {
    let onPrescribe: () -> Void

    var body: some View {
        SummaryCard(title: Text("Prescrire"), systemImage: "qrcode", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Text("Composez le programme : votre patient scanne le QR code avec son iPhone, sans feuille à recopier.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onPrescribe) {
                    Label("Prescrire un programme", systemImage: "plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
            }
        }
    }
}

/// No patient yet: how they arrive, and a way to try with demo patients.
private struct EmptyPatientsCard: View {
    let onImport: () -> Void
    let onDemo: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "person.2.badge.plus")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Aucun patient suivi pour l'instant")
                .font(.headline)
                .multilineTextAlignment(.center)
            Text("Votre patient envoie son bilan depuis Rebond (Accueil, « Envoyer à mon kiné »). Ouvrez le fichier « Bilan Rebond » avec Rebond : il apparaît ici.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Importer un bilan", systemImage: "square.and.arrow.down", action: onImport)
                .buttonStyle(.glass)
                .controlSize(.large)
            Button("Essayer avec des patients de démo", action: onDemo)
                .font(.subheadline)
                .frame(minHeight: 44)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }
}

/// The free offer's limit, and Rebond Pro.
private struct OfferCard: View {
    let patientCount: Int
    let hasPro: Bool
    let onUpgrade: () -> Void

    var body: some View {
        SummaryCard(title: Text("Rebond Pro"), systemImage: hasPro ? "checkmark.seal.fill" : "infinity", color: .accentColor) {
            EmptyView()
        } content: {
            if hasPro {
                Text("Patients illimités. Rebond reste gratuit pour vos patients.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    let used = min(patientCount, ProStore.freePatientLimit)
                    Text("Offre gratuite : \(used) patients suivis sur \(ProStore.freePatientLimit).")
                        .font(.subheadline.weight(.semibold))
                    ProgressView(value: Double(used), total: Double(ProStore.freePatientLimit))
                        .tint(.accentColor)
                        .accessibilityHidden(true)
                    Text("Avec Rebond Pro, suivez autant de patients que vous voulez. Rebond reste gratuit pour eux.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Découvrir Rebond Pro", action: onUpgrade)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                }
            }
        }
    }
}
