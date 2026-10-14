import SwiftData
import SwiftUI

/// The report of the last 7 days, sent to the physiotherapist only when the patient taps the share button.
struct ReportView: View {
    @Query(sort: \Session.date) private var sessions: [Session]
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""
    /// The name is asked the first time the report is sent, where it matters; the keyboard suggests it.
    @State private var askingName = false
    @State private var nameDraft = ""
    @State private var sharing: [URL]?

    private var data: [WeeklyReport.SessionData] { sessions.map(\.reportData) }
    private var sessionsPerWeek: Int { programs.first?.sessionsPerWeek ?? 3 }

    var body: some View {
        let report = WeeklyReport(sessions: data, sessionsPerWeek: sessionsPerWeek)
        List {
            Section {
                ReportSummary(report: report)
                    .padding(.vertical, 4)
            } footer: {
                Text("Le bilan reste sur votre iPhone tant que vous ne l'envoyez pas.")
            }
        }
        .navigationTitle("Bilan de la semaine")
        .navigationSubtitle(Text("Du \(report.start, format: .dateTime.day().month(.wide)) au \(report.end, format: .dateTime.day().month(.wide))"))
        .safeAreaBar(edge: .bottom) {
            Button {
                if patientName.trimmingCharacters(in: .whitespaces).isEmpty {
                    nameDraft = ""
                    askingName = true
                } else {
                    share(report)
                }
            } label: {
                Label("Envoyer à mon kiné", systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .alert("Votre nom", isPresented: $askingName) {
            TextField("Prénom et nom", text: $nameDraft)
                .textContentType(.name)
                .textInputAutocapitalization(.words)
            Button("Continuer") {
                patientName = nameDraft.trimmingCharacters(in: .whitespaces)
                share(report)
            }
            Button("Annuler", role: .cancel) {}
        } message: {
            Text("Il figure sur le bilan pour que votre kiné le reconnaisse.")
        }
        .sheet(isPresented: Binding(get: { sharing != nil }, set: { if !$0 { sharing = nil } })) {
            if let sharing {
                ShareSheet(items: sharing)
                    .presentationDetents([.medium, .large])
                    .ignoresSafeArea()
            }
        }
    }

    private func share(_ report: WeeklyReport) {
        let weeks = ProgressData(sessions: data, sessionsPerWeek: sessionsPerWeek, weeks: 4)
        let name = patientName.trimmingCharacters(in: .whitespaces)
        let transfer = ReportTransfer.current(sessions: sessions, program: programs.first)
        sharing = [ReportPDF.render(report, progress: weeks, patientName: name), transfer.write()].compactMap { $0 }
    }
}

/// The system share sheet, opened from a button (ShareLink can't be opened after a question).
struct ShareSheet: UIViewControllerRepresentable {
    let items: [URL]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Every saved session, most recent first.
struct HistoryView: View {
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]

    var body: some View {
        List(sessions) { session in
            Section {
                LabeledContent {
                    Text("\(session.pain) / 10")
                } label: {
                    Label("Douleur", systemImage: session.pain >= WeeklyReport.highPain ? "exclamationmark.triangle.fill" : "heart")
                        .foregroundStyle(session.pain >= WeeklyReport.highPain ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                }
                ForEach(session.orderedResults) { result in
                    ResultRow(result: result)
                }
            } header: {
                Text(session.date, format: .dateTime.weekday(.wide).day().month(.wide))
            }
        }
        .navigationTitle("Historique")
    }
}
