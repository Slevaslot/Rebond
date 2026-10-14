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
