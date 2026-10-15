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
            // A list rather than a scroll view, for the system's swipe actions; it keeps the look of the cards.
            List {
                PageHeader("Espace kiné") {
                    Button { showingSettings = true } label: { HeaderIcon(systemImage: "gearshape") }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Réglages de l'espace kiné")
                    ProfileButton { showingPatientSettings = true }
                }
                .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 7, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                let followed = followed
                WeekOverviewCard(overviews: followed.compactMap(\.overview), patientCount: patients.count, hasPro: store.hasPro)
                    .pageRow()
                PrescribeCard { prescribing = PrescribingItem(program: EditableProgram()) }
                    .pageRow()

                patientsHeader.pageRow()
                if followed.isEmpty {
                    EmptyPatientsCard(
                        onImport: { importing = true },
                        onDemo: { DemoData.loadPatients(into: context) }
                    )
                    .pageRow()
                } else {
                    ForEach(followed, id: \.patient.patientID) { item in
                        Button { path.append(item.patient.patientID) } label: {
                            PatientCard(name: item.patient.name, overview: item.overview)
                        }
                        .buttonStyle(.plain)
                        // Like Mail: swipe to the left to stop following.
                        .swipeActions(edge: .trailing) {
                            Button("Arrêter le suivi", systemImage: "person.badge.minus", role: .destructive) { removing = item.patient }
                        }
                        .accessibilityAction(named: "Arrêter le suivi") { removing = item.patient }
                        .pageRow()
                    }
                }

                OfferCard(patientCount: patients.count, hasPro: store.hasPro) { showingPaywall = true }
                    .pageRow()
            }
            .listStyle(.plain)
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

    private var patientsHeader: some View {
        HStack {
            Text("Mes patients")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            Button { importing = true } label: { HeaderIcon(systemImage: "square.and.arrow.down") }
                .buttonStyle(.plain)
                .accessibilityLabel("Importer un bilan")
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

/// The week at a glance, like Accueil's cards: one sentence first, then patients, those to look at, reports received.
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

        SummaryCard(title: Text("Cette semaine"), systemImage: "calendar", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 14) {
                Group {
                    if patientCount == 0 {
                        Text("Vos patients apparaîtront ici avec leurs bilans.")
                    } else if painful > 0 {
                        Text("^[\(painful) patient](inflect: true) signale une douleur forte.")
                            .foregroundStyle(.orange)
                    } else if attention > 0 {
                        Text("^[\(attention) patient](inflect: true) à regarder.")
                    } else {
                        Text("Tout va bien pour vos patients.")
                    }
                }
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
                Divider()
                layout {
                    MetricTile(title: "Patients", symbol: "person.2.fill", color: .accentColor,
                               value: "\(patientCount)", unit: hasPro ? "suivis" : "sur \(ProStore.freePatientLimit)",
                               accessibilityValue: Text("\(patientCount) patients suivis"))
                    MetricTile(title: "À regarder", symbol: "exclamationmark.circle.fill", color: .orange,
                               value: "\(attention)", unit: "",
                               accessibilityValue: Text("\(attention) patients à regarder"))
                    MetricTile(title: "Bilans", symbol: "tray.and.arrow.down.fill", color: .teal,
                               value: "\(recent)", unit: "reçus",
                               accessibilityValue: Text("\(recent) bilans reçus ces 7 derniers jours"))
                }
            }
        }
    }
}

/// The main action, as the exercise cards: a large symbol, the action in large type, a round button.
private struct PrescribeCard: View {
    let onPrescribe: () -> Void

    var body: some View {
        Button(action: onPrescribe) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Image(systemName: "qrcode")
                        .font(.system(size: 40))
                        .foregroundStyle(.tint)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Color.accentColor, in: .circle)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prescrire un programme")
                        .font(.title.bold())
                    Text("Votre patient scanne le QR code avec son iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.accentColor.opacity(0.14), in: .rect(cornerRadius: 30))
            .contentShape(.rect(cornerRadius: 30))
        }
        .buttonStyle(.plain)
    }
}

/// No patient yet: where they come from, and demo patients to try.
private struct EmptyPatientsCard: View {
    let onImport: () -> Void
    let onDemo: () -> Void

    var body: some View {
        SummaryCard(title: Text("Aucun patient"), systemImage: "person.2", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ils apparaissent quand vous ouvrez leur bilan Rebond.")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: onImport) {
                    Label("Importer un bilan", systemImage: "square.and.arrow.down")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                Button("Essayer avec des patients de démo", action: onDemo)
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }
}

/// The free offer's limit, and Rebond Pro, in one short card.
private struct OfferCard: View {
    let patientCount: Int
    let hasPro: Bool
    let onUpgrade: () -> Void

    var body: some View {
        SummaryCard(title: Text("Rebond Pro"), systemImage: hasPro ? "checkmark.seal.fill" : "infinity", color: .accentColor) {
            EmptyView()
        } content: {
            if hasPro {
                Text("Patients illimités.")
                    .font(.title3.weight(.semibold))
            } else {
                let used = min(patientCount, ProStore.freePatientLimit)
                VStack(alignment: .leading, spacing: 12) {
                    BigValue(value: "\(used)", unit: "sur \(ProStore.freePatientLimit) patients gratuits")
                    ProgressView(value: Double(used), total: Double(ProStore.freePatientLimit))
                        .tint(.accentColor)
                        .accessibilityHidden(true)
                    Button(action: onUpgrade) {
                        Text("Passer à Rebond Pro")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
        }
    }
}
