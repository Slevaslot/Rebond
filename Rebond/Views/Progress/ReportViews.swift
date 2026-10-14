import SwiftData
import SwiftUI

/// Sending the report of the last 7 days: first what the physiotherapist will receive, in the same cards as the
/// Accueil page, then the system share sheet, and a clear confirmation. Nothing leaves without the patient's tap.
struct ReportView: View {
    static let lastSentKey = "reportLastSent"

    @Query(sort: \Session.date) private var sessions: [Session]
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    @AppStorage(lastSentKey) private var lastSent: Double = 0
    /// The name is asked the first time the report is sent, where it matters; the keyboard suggests it.
    @State private var askingName = false
    @State private var nameDraft = ""
    /// Share right after the name is entered (first sending), or only save it (changing it).
    @State private var sendsAfterName = false
    @State private var sharing: [URL]?
    @State private var outcome: Outcome?
    @State private var showingDocument = false

    /// What happened in the share sheet.
    enum Outcome: Equatable {
        case sent
        /// Copied or saved to Files or Photos: still to pass on to the physiotherapist.
        case saved
    }

    private var data: [WeeklyReport.SessionData] { sessions.map(\.reportData) }
    private var sessionsPerWeek: Int { programs.first?.sessionsPerWeek ?? 3 }
    private var trimmedName: String { patientName.trimmingCharacters(in: .whitespaces) }

    var body: some View {
        let report = WeeklyReport(sessions: data, sessionsPerWeek: sessionsPerWeek)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ReportIntroCard(report: report, patientName: trimmedName,
                                onChangeName: { askName(thenSend: false) },
                                onShowDocument: { showingDocument = true })
                ReportRegularityCard(report: report)
                if !report.exercises.isEmpty {
                    ReportExercisesCard(report: report)
                }
                ReportPainCard(report: report)
                Label("Le bilan reste sur votre iPhone tant que vous ne l'envoyez pas. Vous choisissez à qui l'envoyer : rien ne part sans votre accord.",
                      systemImage: "lock.fill")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Envoyer à mon kiné")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            bottomBar(report)
        }
        .alert("Votre nom", isPresented: $askingName) {
            TextField("Prénom et nom", text: $nameDraft)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            Button(sendsAfterName ? "Continuer" : "Enregistrer") {
                let name = nameDraft.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                patientName = name
                if sendsAfterName { share(report) }
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Il figure sur le bilan pour que votre kiné le reconnaisse.")
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                ShareSheet(items: sharing) { activity, completed in
                    self.sharing = nil
                    guard completed else { return }
                    lastSent = Date.now.timeIntervalSinceReferenceDate
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        outcome = ShareSheet.isSaving(activity) ? .saved : .sent
                    }
                }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
            }
        }
        .sheet(isPresented: $showingDocument) {
            NavigationStack {
                ReportDocumentPreview(report: report,
                                      progress: ProgressData(sessions: data, sessionsPerWeek: sessionsPerWeek, weeks: 4),
                                      patientName: trimmedName)
                    .toolbar {
                        Button("Fermer", systemImage: "xmark", role: .close) { showingDocument = false }
                    }
            }
        }
        .sensoryFeedback(.success, trigger: outcome) { _, new in new != nil }
    }

    @ViewBuilder
    private func bottomBar(_ report: WeeklyReport) -> some View {
        VStack(spacing: 10) {
            if let outcome {
                SentConfirmation(outcome: outcome)
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))
            }
            Button {
                if trimmedName.isEmpty {
                    askName(thenSend: true)
                } else {
                    share(report)
                }
            } label: {
                Label(outcome == nil ? "Envoyer à mon kiné" : "Envoyer à nouveau", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            if outcome == nil, lastSent > 0 {
                let date = Date(timeIntervalSinceReferenceDate: lastSent)
                Text("Dernier envoi le \(date, format: .dateTime.day().month(.wide)) à \(date, format: .dateTime.hour().minute())")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

    private func askName(thenSend: Bool) {
        nameDraft = patientName
        sendsAfterName = thenSend
        askingName = true
    }

    /// Writes the PDF and the `.rebond` file on the iPhone, then opens the share sheet.
    private func share(_ report: WeeklyReport) {
        outcome = nil
        let weeks = ProgressData(sessions: data, sessionsPerWeek: sessionsPerWeek, weeks: 4)
        let transfer = ReportTransfer.current(sessions: sessions, program: programs.first)
        sharing = [ReportPDF.render(report, progress: weeks, patientName: trimmedName), transfer.write()].compactMap { $0 }
    }
}

/// What will be sent: the period, the name on the report, and the two files.
private struct ReportIntroCard: View {
    let report: WeeklyReport
    let patientName: String
    let onChangeName: () -> Void
    let onShowDocument: () -> Void

    var body: some View {
        SummaryCard(title: Text("Bilan des 7 derniers jours"), systemImage: "doc.text.fill", color: .accentColor) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Text("Du \(report.start, format: .dateTime.weekday(.wide).day().month(.wide)) au \(report.end, format: .dateTime.weekday(.wide).day().month(.wide).year())")
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text("Voici ce que votre kiné recevra : de quoi voir si vous avez pu faire vos exercices et comment ils se passent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Button(action: onChangeName) {
                    ReportRow(symbol: "person.crop.circle",
                              title: patientName.isEmpty ? Text("Votre nom") : Text(patientName),
                              detail: patientName.isEmpty ? Text("Demandé au moment de l'envoi") : Text("Nom inscrit sur le bilan"),
                              accessory: "pencil")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Modifier le nom inscrit sur le bilan")
                Button(action: onShowDocument) {
                    ReportRow(symbol: "doc.richtext",
                              title: Text("Un document PDF"),
                              detail: Text("Lisible sur tout ordinateur ou téléphone"),
                              accessory: "chevron.right")
                }
                .buttonStyle(.plain)
                .accessibilityHint("Afficher le document")
                ReportRow(symbol: "doc.badge.arrow.up",
                          title: Text("Un fichier Rebond"),
                          detail: Text("Pour que votre kiné suive vos progrès dans Rebond"),
                          accessory: nil)
            }
        }
    }
}

/// A line of the intro card: a symbol, two lines of text, and an optional trailing symbol.
private struct ReportRow: View {
    let symbol: String
    let title: Text
    let detail: Text
    let accessory: String?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                title.font(.headline)
                detail.font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let accessory {
                Image(systemName: accessory)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
        }
        .frame(minHeight: 44)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

/// Sessions done against the program's goal, with their dates.
private struct ReportRegularityCard: View {
    let report: WeeklyReport

    var body: some View {
        SummaryCard(title: Text("Régularité"), systemImage: "calendar", color: .teal) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                BigValue(value: "\(report.sessionsDone)",
                         unit: report.sessionsPlanned == 1 ? "sur 1 séance prévue" : "sur \(report.sessionsPlanned) séances prévues")
                    .accessibilityElement(children: .combine)
                if report.sessionLines.isEmpty {
                    Text("Aucune séance ces 7 derniers jours. Votre kiné le verra, sans jugement : cela l'aide à adapter votre programme.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    Text(report.sessionLines.map { $0.date.formatted(.dateTime.weekday(.wide).day().month()) }
                        .formatted(.list(type: .and)))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// Each exercise: repetitions done (and incomplete ones apart), held time, and amplitude in % of the target.
private struct ReportExercisesCard: View {
    let report: WeeklyReport

    var body: some View {
        SummaryCard(title: Text("Exercices"), systemImage: "figure.strengthtraining.functional", color: .blue) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(report.exercises.enumerated()), id: \.element.id) { index, line in
                    if index > 0 { Divider().padding(.vertical, 10) }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(line.name).font(.headline)
                        Group {
                            if line.isHeld {
                                Text("Maintien : \(line.heldSeconds) s sur \(line.plannedSeconds) s prévues")
                            } else {
                                Text("\(line.completedReps) répétitions sur \(line.plannedReps) prévues")
                                if line.incompleteReps > 0 {
                                    Text("\(line.incompleteReps) incomplètes, comptées à part")
                                }
                            }
                            if let first = line.firstAmplitude {
                                if let last = line.lastAmplitude {
                                    Text("Amplitude : \(Int(first.rounded())) % puis \(Int(last.rounded())) % de l'objectif")
                                } else {
                                    Text("Amplitude : \(Int(first.rounded())) % de l'objectif")
                                }
                            }
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .combine)
                }
                if report.exercises.contains(where: { $0.firstAmplitude != nil }) {
                    Text("L'amplitude est mesurée par la caméra, à titre indicatif : 100 % correspond à l'objectif du mouvement.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
            }
        }
    }
}

/// Pain after each session: the average, and the painful sessions flagged to the physiotherapist.
private struct ReportPainCard: View {
    let report: WeeklyReport

    var body: some View {
        SummaryCard(title: Text("Douleur"), systemImage: "bandage.fill", color: .orange) {
            EmptyView()
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                if let average = report.averagePain {
                    BigValue(value: average.formatted(.number.precision(.fractionLength(0...1))), unit: "sur 10 en moyenne")
                        .accessibilityElement(children: .combine)
                    if let first = report.firstPain, let last = report.lastPain {
                        Text("De \(first) à la première séance, \(last) à la dernière.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(report.painfulSessions) { session in
                        Label {
                            Text("\(session.pain) sur 10 le \(session.date, format: .dateTime.weekday(.wide).day().month()) : séance signalée à votre kiné")
                                .font(.subheadline.weight(.semibold))
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                } else {
                    Text("Pas de douleur notée ces 7 derniers jours.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// The confirmation after the share sheet: calm, with what to do next when the report was only saved.
private struct SentConfirmation: View {
    let outcome: ReportView.Outcome
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: outcome == .sent ? "checkmark.circle.fill" : "tray.and.arrow.down.fill")
                .font(.title)
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: appeared)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(outcome == .sent ? "Bilan envoyé" : "Bilan enregistré")
                    .font(.headline)
                Text(outcome == .sent
                     ? "Votre kiné pourra l'ouvrir dès réception."
                     : "Pensez à le transmettre à votre kiné.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 20))
        .accessibilityElement(children: .combine)
        .onAppear { appeared = true }
    }
}

/// The PDF as the physiotherapist will see it, scaled to the screen.
private struct ReportDocumentPreview: View {
    let report: WeeklyReport
    let progress: ProgressData
    let patientName: String

    var body: some View {
        GeometryReader { geometry in
            let scale = max(0.1, (geometry.size.width - 32) / ReportPage.width)
            ScrollView {
                ReportPage(report: report, progress: progress, patientName: patientName)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: ReportPage.width * scale, height: ReportPage.height * scale, alignment: .topLeading)
                    .clipShape(.rect(cornerRadius: 6))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 2)
                    .padding(16)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Document PDF")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The system share sheet, opened from a button: it can open right after the name question, and it tells
/// whether something was sent, which `ShareLink` doesn't.
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]
    var onComplete: (UIActivity.ActivityType?, Bool) -> Void = { _, _ in }

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: items, applicationActivities: nil)
        controller.completionWithItemsHandler = { activity, completed, _, _ in
            onComplete(activity, completed)
        }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

    /// Copying or saving keeps the report on the device: it still has to reach the physiotherapist.
    static func isSaving(_ activity: UIActivity.ActivityType?) -> Bool {
        guard let activity else { return false }
        return [.copyToPasteboard, .saveToCameraRoll, .addToReadingList].contains(activity)
            || activity.rawValue.localizedCaseInsensitiveContains("SaveToFiles")
    }
}

/// Every saved session, most recent first.
struct HistoryView: View {
    var sessionsPerWeek = 3
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    /// Sessions grouped by calendar week, newest first.
    private var weeks: [(start: Date, sessions: [Session])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: sessions) { calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        List {
            Section {
                RegularityChart(data: ProgressData(sessions: sessions.map(\.reportData), sessionsPerWeek: sessionsPerWeek))
                    .frame(height: 180)
                    .padding(.vertical, 6)
            }
            ForEach(weeks, id: \.start) { week in
                Section {
                    ForEach(week.sessions) { session in
                        DayRow(session: session)
                    }
                } header: {
                    WeekHeader(start: week.start, done: week.sessions.count, planned: sessionsPerWeek)
                }
            }
        }
        .navigationTitle("Régularité")
    }
}

/// "Cette semaine" or "Semaine du 6 oct.", with the count against the goal.
private struct WeekHeader: View {
    let start: Date
    let done: Int
    let planned: Int

    var body: some View {
        HStack {
            if Calendar.current.isDate(start, equalTo: .now, toGranularity: .weekOfYear) {
                Text("Cette semaine")
            } else {
                Text("Semaine du \(start, format: .dateTime.day().month())")
            }
            Spacer()
            Text("\(done) sur \(planned)")
                .foregroundStyle(done >= planned ? AnyShapeStyle(.teal) : AnyShapeStyle(.secondary))
        }
    }
}

/// One day: folded, the date and a short summary; unfolded, each exercise on one line.
private struct DayRow: View {
    let session: Session
    @State private var expanded = false

    private var isPainful: Bool { session.pain >= WeeklyReport.highPain }

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            ForEach(session.orderedResults) { result in
                CompactResultRow(result: result)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.teal)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.date, format: .dateTime.weekday(.wide).day().month())
                        .font(.headline)
                    Text("^[\(session.results.count) exercice](inflect: true)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Label {
                    Text("\(session.pain)")
                } icon: {
                    Image(systemName: "bandage.fill")
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(isPainful ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .accessibilityLabel(Text("Douleur \(session.pain) sur 10"))
            }
        }
    }
}

/// An exercise on one line: its name, what was done, and the amplitude when measured.
private struct CompactResultRow: View {
    let result: ExerciseResult

    private var complete: Bool {
        result.isHeld ? result.heldSeconds >= result.plannedSeconds : result.completedReps >= result.plannedReps
    }

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(result.exerciseName)
                if let amplitude = result.amplitude {
                    Text("Amplitude \(Int(amplitude.rounded())) %")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Group {
                if result.isHeld {
                    Text("\(result.heldSeconds) / \(result.plannedSeconds) s")
                } else {
                    Text("\(result.completedReps) / \(result.plannedReps)")
                }
            }
            .monospacedDigit()
            .foregroundStyle(complete ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            if complete {
                Image(systemName: "checkmark")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.teal)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
