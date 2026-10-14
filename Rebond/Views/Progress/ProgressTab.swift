import SwiftData
import SwiftUI

/// Progress: the report for the physiotherapist, the charts, and the history. Standard list and Swift Charts.
struct ProgressTab: View {
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]

    private var sessionsPerWeek: Int { programs.first?.sessionsPerWeek ?? 3 }

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView {
                        Label("Pas encore de séance", systemImage: "chart.line.uptrend.xyaxis")
                    } description: {
                        Text("Vos progrès apparaîtront ici après votre première séance.")
                    }
                } else {
                    content
                }
            }
            .navigationTitle("Progrès")
            .navigationSubtitle(sessions.isEmpty ? Text("") : Text("6 dernières semaines"))
        }
    }

    private var content: some View {
        let data = ProgressData(sessions: sessions.map(\.reportData), sessionsPerWeek: sessionsPerWeek)
        let week = WeekProgress(sessions: sessions, sessionsPerWeek: sessionsPerWeek)

        return List {
            Section {
                NavigationLink {
                    ReportView()
                } label: {
                    Label("Bilan pour mon kiné", systemImage: "doc.richtext")
                        .font(.headline)
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(week.summary)
                        .font(.headline)
                    RegularityChart(data: data)
                        .frame(height: 160)
                }
                .padding(.vertical, 4)
            } header: {
                Text("Régularité")
            }

            if !data.amplitude.isEmpty {
                Section {
                    AmplitudeChart(data: data)
                        .frame(height: 200)
                        .padding(.vertical, 4)
                } header: {
                    Text("Amplitude")
                } footer: {
                    Text("Meilleure répétition de chaque séance, mesurée par la caméra : 100 % correspond à l'objectif du mouvement.")
                }
            }
            Section("Douleur") {
                PainChart(data: data)
                    .frame(height: 160)
                    .padding(.vertical, 4)
            }

            Section {
                NavigationLink {
                    HistoryView()
                } label: {
                    Label("Historique des séances", systemImage: "calendar")
                }
            }
        }
    }
}

/// The report of the last 7 days, sent to the physiotherapist only when the patient taps the share button.
struct ReportView: View {
    @Query(sort: \Session.date) private var sessions: [Session]
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @State private var files: [URL] = []
    @AppStorage(PatientIdentity.nameKey) private var patientName = ""

    private var data: [WeeklyReport.SessionData] { sessions.map(\.reportData) }
    private var sessionsPerWeek: Int { programs.first?.sessionsPerWeek ?? 3 }

    var body: some View {
        let report = WeeklyReport(sessions: data, sessionsPerWeek: sessionsPerWeek)
        List {
            Section {
                TextField("Votre nom", text: $patientName)
                    .textContentType(.name)
            } footer: {
                Text("Affiché sur le bilan, pour que votre kiné le reconnaisse.")
            }
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
            if !files.isEmpty {
                ShareLink(items: files, subject: Text("Mon bilan Rebond")) {
                    Label("Envoyer à mon kiné", systemImage: "paperplane.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.extraLarge)
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
        .task(id: "\(sessions.count)\(patientName)") {
            let weeks = ProgressData(sessions: data, sessionsPerWeek: sessionsPerWeek, weeks: 4)
            let name = patientName.trimmingCharacters(in: .whitespaces)
            let transfer = ReportTransfer.current(sessions: sessions, program: programs.first)
            files = [ReportPDF.render(report, progress: weeks, patientName: name), transfer.write()].compactMap { $0 }
        }
    }
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
