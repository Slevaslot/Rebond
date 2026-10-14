import CoreImage.CIFilterBuiltins
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// The physiotherapist space: prescribe a program by QR code, and follow the patients from their reports.
/// Free for up to `ProStore.freePatientLimit` patients; Rebond Pro follows as many as needed.
struct ProHomeView: View {
    @Environment(ProStore.self) private var store
    @Environment(\.modelContext) private var context
    @Query(sort: \TrackedPatient.updatedAt, order: .reverse) private var patients: [TrackedPatient]
    @AppStorage(AppRole.key) private var role = AppRole.patient.rawValue
    @AppStorage(PatientIdentity.physiotherapistNameKey) private var physiotherapistName = ""

    @State private var prescribing: EditableProgram?
    @State private var prescription: PrescriptionItem?
    @State private var showingPaywall = false
    @State private var showingSettings = false
    @State private var importing = false
    @State private var importError = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        prescribing = EditableProgram()
                    } label: {
                        Label("Prescrire un programme", systemImage: "qrcode")
                            .font(.headline)
                    }
                } footer: {
                    Text("Votre patient scanne le QR code avec son iPhone : le programme s'ouvre dans Rebond.")
                }

                Section {
                    if patients.isEmpty {
                        Text("Ouvrez avec Rebond le bilan envoyé par votre patient pour le suivre ici.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(patients) { patient in
                        NavigationLink {
                            PatientDetailView(patient: patient)
                        } label: {
                            PatientRow(patient: patient)
                        }
                    }
                    .onDelete { offsets in
                        for index in offsets { context.delete(patients[index]) }
                    }
                    Button("Importer un bilan", systemImage: "square.and.arrow.down") { importing = true }
                } header: {
                    Text("Mes patients")
                } footer: {
                    if !store.hasPro {
                        Text("Offre gratuite : \(min(patients.count, ProStore.freePatientLimit)) patients suivis sur \(ProStore.freePatientLimit). Rebond Pro : patients illimités.")
                    }
                }

                if !store.hasPro {
                    Section {
                        Button("Passer à Rebond Pro", systemImage: "infinity") { showingPaywall = true }
                    }
                }

                #if DEBUG
                ConnectedSection(showingPaywall: $showingPaywall)
                #endif
            }
            .navigationTitle("Espace kiné")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Réglages", systemImage: "gearshape") { showingSettings = true }
                        Button("Mode patient", systemImage: "person.crop.circle") { role = AppRole.patient.rawValue }
                    } label: {
                        Label("Plus", systemImage: "ellipsis")
                    }
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { prescribing != nil },
                set: { if !$0 { prescribing = nil } }
            )) {
                if let prescribing {
                    ProgramEditorView(program: prescribing, title: "Nouveau programme") { program in
                        self.prescribing = nil
                        prescription = PrescriptionItem(transfer: ProgramTransfer(program, physiotherapist: physiotherapistName))
                    }
                }
            }
            .sheet(item: $prescription) { item in
                PrescriptionView(transfer: item.transfer)
            }
            .sheet(isPresented: $showingPaywall) { ProPaywall() }
            .sheet(isPresented: $showingSettings) { ProSettingsView() }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.rebondReport, .json]) { result in
                guard case .success(let url) = result else { return }
                switch ProHomeView.importReport(at: url, into: context, hasPro: store.hasPro) {
                case .invalid: importError = true
                case .limitReached: showingPaywall = true
                case .imported: break
                }
            }
            .alert("Ce fichier n'est pas un bilan Rebond.", isPresented: $importError) {}
        }
    }

    enum ImportResult {
        case imported
        case limitReached
        case invalid
    }

    /// Reads a `.rebond` report shared by a patient. A new patient beyond the free limit isn't added.
    @discardableResult
    static func importReport(at url: URL, into context: ModelContext, hasPro: Bool) -> ImportResult {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url),
              let reception = try? TrackedPatient.receive(data, in: context, canAddNew: TrackedPatient.canAddNew(in: context, hasPro: hasPro))
        else { return .invalid }
        if case .limitReached = reception { return .limitReached }
        return .imported
    }
}

private struct PrescriptionItem: Identifiable {
    let id = UUID()
    let transfer: ProgramTransfer
}

/// The physiotherapist's name, demo data and privacy.
private struct ProSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(ProStore.self) private var store
    @AppStorage(PatientIdentity.physiotherapistNameKey) private var physiotherapistName = ""

    var body: some View {
        @Bindable var store = store

        NavigationStack {
            Form {
                Section {
                    TextField("Votre nom", text: $physiotherapistName)
                        .textContentType(.name)
                } footer: {
                    Text("Affiché à vos patients quand ils reçoivent un programme.")
                }
                Section {
                    Button("Charger des patients de démo") { DemoData.loadPatients(into: context) }
                    #if DEBUG
                    Toggle("Débloquer Pro (démo)", isOn: $store.demoUnlocked)
                    #endif
                    Link("Politique de confidentialité", destination: AppLinks.privacyPolicy)
                }
            }
            .navigationTitle("Réglages")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Fermer", systemImage: "xmark", role: .close) { dismiss() } }
        }
    }
}

/// One patient: when they last reported, and how their week went.
private struct PatientRow: View {
    let patient: TrackedPatient

    var body: some View {
        let transfer = patient.transfer
        let report = transfer.map { WeeklyReport(sessions: $0.sessionData, sessionsPerWeek: $0.sessionsPerWeek, end: $0.generatedAt) }
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(patient.name).font(.headline)
                if let report {
                    Text("\(report.sessionsDone) séances sur \(report.sessionsPlanned) · bilan du \(patient.updatedAt, format: .dateTime.day().month())")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            #if DEBUG
            if DemoServer.shared.connectedPatients.contains(patient.patientID) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(.tint)
                    .accessibilityLabel("Connecté")
            }
            #endif
            if let report, !report.painfulSessionDates.isEmpty {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Douleur forte signalée")
            }
        }
    }
}

/// The QR code of a prescribed program, to show to the patient or send as a link.
struct PrescriptionView: View {
    let transfer: ProgramTransfer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if let url = transfer.url {
                        QRCodeView(url: url)
                        Text("Votre patient scanne ce code avec l'appareil photo de son iPhone.")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(transfer.f) séances par semaine").font(.headline)
                        ForEach(Array(transfer.e.enumerated()), id: \.offset) { _, exercise in
                            if let hold = exercise.h {
                                Text("\(exercise.n) : \(exercise.s) × \(hold) s")
                            } else {
                                Text("\(exercise.n) : \(exercise.s) × \(exercise.r)")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding()
            }
            .navigationTitle("Programme prescrit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
                if let url = transfer.url {
                    ShareLink(item: url, subject: Text("Votre programme Rebond"), message: Text("Ouvrez ce lien sur votre iPhone pour retrouver votre programme dans Rebond."))
                }
            }
        }
    }
}

/// A link as a QR code, on white so any camera reads it.
struct QRCodeView: View {
    let url: URL

    var body: some View {
        if let image = Self.qrCode(for: url.absoluteString) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 280)
                .padding()
                .background(.white, in: .rect(cornerRadius: 24))
                .accessibilityLabel("QR code")
        }
    }

    static func qrCode(for string: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage,
              let cgImage = CIContext().createCGImage(output, from: output.extent)
        else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

/// A patient's last report, the same summary and charts the patient sees, and their program to adjust.
struct PatientDetailView: View {
    let patient: TrackedPatient

    @AppStorage(PatientIdentity.physiotherapistNameKey) private var physiotherapistName = ""
    @State private var editing: EditableProgram?
    @State private var prescription: PrescriptionItem?
    @State private var sentByServer = false

    var body: some View {
        if let transfer = patient.transfer {
            let report = WeeklyReport(sessions: transfer.sessionData, sessionsPerWeek: transfer.sessionsPerWeek, end: transfer.generatedAt)
            let progress = ProgressData(sessions: transfer.sessionData, sessionsPerWeek: transfer.sessionsPerWeek, weeks: 6, now: transfer.generatedAt)
            List {
                Section {
                    Button("Modifier le programme", systemImage: "pencil") {
                        editing = transfer.program?.editableProgram ?? EditableProgram()
                    }
                    .font(.headline)
                }
                Section {
                    ReportSummary(report: report)
                        .padding(.vertical, 4)
                } header: {
                    Text("Du \(report.start, format: .dateTime.day().month(.wide)) au \(report.end, format: .dateTime.day().month(.wide))")
                }
                Section("Régularité") {
                    RegularityChart(data: progress).frame(height: 160)
                }
                if !progress.amplitude.isEmpty {
                    Section {
                        AmplitudeChart(data: progress).frame(height: 200)
                    } header: {
                        Text("Amplitude")
                    } footer: {
                        Text("Meilleure répétition de chaque séance, mesurée par la caméra du patient, à titre indicatif : 100 % correspond à l'objectif du mouvement.")
                    }
                }
                Section("Douleur") {
                    PainChart(data: progress).frame(height: 160)
                }
            }
            .navigationTitle(patient.name)
            .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let editing {
                    ProgramEditorView(program: editing, title: "Programme de \(patient.name)") { program in
                        self.editing = nil
                        send(ProgramTransfer(program, physiotherapist: physiotherapistName))
                    }
                }
            }
            .sheet(item: $prescription) { item in
                PrescriptionView(transfer: item.transfer)
            }
            .alert("Programme envoyé", isPresented: $sentByServer) {} message: {
                Text("Il s'affichera sur l'iPhone de \(patient.name) dans quelques secondes.")
            }
        } else {
            ContentUnavailableView("Bilan illisible", systemImage: "doc.questionmark")
        }
    }

    /// Connected patients receive the program directly (demo server); the others get a new QR code.
    private func send(_ program: ProgramTransfer) {
        #if DEBUG
        if DemoServer.shared.connectedPatients.contains(patient.patientID) {
            Task {
                if await DemoServer.shared.send(program, to: patient.patientID) {
                    sentByServer = true
                } else {
                    prescription = PrescriptionItem(transfer: program)
                }
            }
            return
        }
        #endif
        prescription = PrescriptionItem(transfer: program)
    }
}

#if DEBUG
/// The connected version of Rebond Pro, with the demo server: invite a patient, then their reports arrive
/// by themselves and program changes reach them directly. Development builds only.
private struct ConnectedSection: View {
    @Binding var showingPaywall: Bool

    @Environment(ProStore.self) private var store
    @Environment(\.modelContext) private var context
    @AppStorage(PatientIdentity.physiotherapistNameKey) private var physiotherapistName = ""
    @State private var server = DemoServer.shared
    @State private var inviting = false

    var body: some View {
        Section {
            TextField("Adresse du serveur", text: $server.serverURL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Inviter un patient", systemImage: "person.badge.plus") {
                guard store.hasPro else { showingPaywall = true; return }
                Task {
                    await server.registerIfNeeded(name: physiotherapistName)
                    inviting = server.kineID != nil
                }
            }
            .disabled(!server.isConfigured)
            if let error = server.lastError {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }
        } header: {
            Text("Version connectée (démo)")
        } footer: {
            Text("Prototype avec patients fictifs : bilans reçus automatiquement et programme modifié à distance. Lancez Server/server.py sur le Mac.")
        }
        .sheet(isPresented: $inviting) {
            NavigationStack {
                VStack(spacing: 24) {
                    if let url = server.invitation(name: physiotherapistName) {
                        QRCodeView(url: url)
                    }
                    Text("Le patient scanne ce code avec l'appareil photo de son iPhone : son Rebond est relié au vôtre.")
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .navigationTitle("Inviter un patient")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { Button("Fermer", systemImage: "xmark", role: .close) { inviting = false } }
            }
        }
        .task(id: server.kineID) {
            // The list follows the linked patients' reports by itself.
            while !Task.isCancelled, server.kineID != nil {
                await server.refreshPatients(into: context)
                try? await Task.sleep(for: .seconds(4))
            }
        }
    }
}
#endif
