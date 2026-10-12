import SwiftData
import SwiftUI

/// The weekly report, sent to the physiotherapist only when the patient taps the share button.
struct ReportView: View {
    let program: Program

    @Query(sort: \Session.date) private var sessions: [Session]
    @State private var pdf: URL?

    private var report: WeeklyReport {
        WeeklyReport(sessions: sessions, sessionsPerWeek: program.sessionsPerWeek, exerciseOrder: program.orderedExercises.map(\.name))
    }

    var body: some View {
        ScrollView {
            ReportSummary(report: report)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Rapport de la semaine")
        .toolbar {
            if let pdf {
                ToolbarItem(placement: .primaryAction) {
                    ShareLink(item: pdf) {
                        Label("Envoyer à mon kiné", systemImage: "paperplane")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Le rapport reste sur votre iPhone tant que vous ne l'envoyez pas.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding()
        }
        .task(id: sessions.count) {
            pdf = ReportPDF.render(report)
        }
    }
}
