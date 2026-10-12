import SwiftData
import SwiftUI

struct HistoryView: View {
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @Environment(\.modelContext) private var context

    var body: some View {
        List {
            ForEach(sessions) { session in
                VStack(alignment: .leading, spacing: 4) {
                    Text(session.date, format: .dateTime.weekday(.wide).day().month().hour().minute())
                        .font(.headline)
                    let done = session.results.map(\.completedReps).reduce(0, +)
                    let planned = session.results.map(\.plannedReps).reduce(0, +)
                    Text("\(done) répétitions sur \(planned)")
                    Text("Douleur : \(session.pain) sur 10")
                        .foregroundStyle(session.pain >= WeeklyReport.highPain ? .orange : .secondary)
                }
            }
            .onDelete { offsets in
                offsets.map { sessions[$0] }.forEach(context.delete)
            }
        }
        .overlay {
            if sessions.isEmpty {
                ContentUnavailableView("Aucune séance", systemImage: "calendar", description: Text("Vos séances apparaîtront ici."))
            }
        }
        .navigationTitle("Historique")
    }
}
