import SwiftData
import SwiftUI

/// The program as a week of sessions: which days, what was done, the exercises, and where to change them.
/// Same Health-style cards as the Séance page.
struct ProgramTab: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.modelContext) private var context
    @Query(sort: \Program.createdAt, order: .reverse) private var programs: [Program]
    @Query(sort: \Session.date, order: .reverse) private var sessions: [Session]
    @State private var editing: EditableProgram?

    var body: some View {
        NavigationStack {
            Group {
                if let program = programs.first {
                    content(program)
                } else {
                    ContentUnavailableView {
                        Label("Aucun programme", systemImage: "calendar")
                    } description: {
                        Text("Scannez la feuille de votre kiné pour créer votre programme.")
                    } actions: {
                        Button("Scanner ma feuille") { router.addProgram(from: .scan) }
                            .buttonStyle(.borderedProminent)
                            .buttonBorderShape(.capsule)
                        Button("Saisir à la main") { router.addProgram(from: .manual) }
                    }
                }
            }
            .navigationTitle("Programme")
            .navigationDestination(isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } })) {
                if let editing {
                    ProgramEditorView(program: editing) { saved in
                        Program.replaceAll(with: saved, in: context)
                        self.editing = nil
                    }
                }
            }
        }
    }

    private func content(_ program: Program) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ProgramCard(title: "Cette semaine", trailing: Text("\(program.sessionsPerWeek) séances")) {
                    VStack(spacing: 0) {
                        let days = PlannedWeek(sessions: sessions, sessionsPerWeek: program.sessionsPerWeek).days
                        ForEach(Array(days.enumerated()), id: \.element.date) { index, day in
                            if index > 0 { Divider() }
                            WeekDayRow(day: day, minutes: program.estimatedMinutes)
                        }
                    }
                }

                ProgramCard(title: "Exercices", trailing: Text("\(program.exercises.count)")) {
                    VStack(spacing: 0) {
                        ForEach(Array(program.orderedExercises.enumerated()), id: \.element.id) { index, exercise in
                            if index > 0 { Divider().padding(.leading, 54) }
                            ProgramExerciseRow(exercise: exercise)
                        }
                    }
                }

                HStack(spacing: 12) {
                    Button {
                        editing = EditableProgram(program)
                    } label: {
                        Label("Modifier", systemImage: "pencil").frame(maxWidth: .infinity)
                    }
                    Button {
                        router.addProgram(from: .scan)
                    } label: {
                        Label("Scanner", systemImage: "doc.viewfinder").frame(maxWidth: .infinity)
                    }
                }
                .lineLimit(1)
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.large)

                Text("Programme du \(program.createdAt, format: .dateTime.day().month(.wide)). Seul votre kiné décide de le changer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// The week's session days (spread like the reminders), each done, today, missed or to come.
struct PlannedWeek {
    enum Status { case done, today, missed, upcoming }

    struct Day {
        let date: Date
        let status: Status
    }

    let days: [Day]

    init(sessions: [Session], sessionsPerWeek: Int, now: Date = .now) {
        let calendar = Calendar.current
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { days = []; return }
        let weekDays = (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: week.start) }
        let planned = Set(ReminderScheduler.sessionDays(count: sessionsPerWeek))
        let doneDays = weekDays.filter { day in sessions.contains { calendar.isDate($0.date, inSameDayAs: day) } }
        // Planned days, plus any other day with a session done.
        days = weekDays.compactMap { day in
            let isDone = doneDays.contains(day)
            guard planned.contains(calendar.component(.weekday, from: day)) || isDone else { return nil }
            let status: Status = if isDone { .done }
                else if calendar.isDateInToday(day) { .today }
                else if day < now { .missed }
                else { .upcoming }
            return Day(date: day, status: status)
        }
    }
}

private struct WeekDayRow: View {
    let day: PlannedWeek.Day
    let minutes: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(day.date, format: .dateTime.weekday(.wide).day().month())
                    .font(.headline)
                    .foregroundStyle(day.status == .today ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(minutes) min")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }

    private var symbol: String {
        switch day.status {
        case .done: "checkmark.circle.fill"
        case .today: "circle.dotted.circle"
        case .missed: "minus.circle"
        case .upcoming: "circle"
        }
    }

    private var color: AnyShapeStyle {
        switch day.status {
        case .done: AnyShapeStyle(.green)
        case .today: AnyShapeStyle(.tint)
        case .missed, .upcoming: AnyShapeStyle(.tertiary)
        }
    }

    private var label: LocalizedStringKey {
        switch day.status {
        case .done: "Faite"
        case .today: "Aujourd'hui"
        case .missed: "Non faite"
        case .upcoming: "Prévue"
        }
    }
}

private struct ProgramExerciseRow: View {
    let exercise: PlannedExercise

    var body: some View {
        HStack(spacing: 12) {
            Group {
                if let catalog = exercise.catalogExercise {
                    ExerciseIcon(exercise: catalog).padding(8)
                } else {
                    Image(systemName: exercise.symbol).font(.title3)
                }
            }
            .foregroundStyle(.tint)
            .frame(width: 42, height: 42)
            .background(Color(.tertiarySystemGroupedBackground), in: .circle)
            VStack(alignment: .leading, spacing: 2) {
                Text(exercise.name).font(.headline)
                Text(exercise.prescriptionDetail).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: exercise.trackingSymbol)
                .foregroundStyle(.secondary)
                .accessibilityLabel(exercise.trackingLabel)
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }
}

/// A card with a section-style header, like Health's.
private struct ProgramCard<Content: View>: View {
    let title: LocalizedStringKey
    let trailing: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .textCase(.uppercase)
                    .font(.title3.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                trailing
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
    }
}
