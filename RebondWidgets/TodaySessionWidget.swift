import SwiftUI
import WidgetKit

/// "Séance du jour": what is left to do today and the week's regularity. A tap goes where it says: today's
/// session, "Créer un programme" while there is none, otherwise the Accueil page.
struct TodaySessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySession", provider: RebondProvider()) { entry in
            TodaySessionView(entry: entry)
                .widgetURL(entry.url)
        }
        .configurationDisplayName("Séance du jour")
        .description("Votre séance du jour et vos séances de la semaine. Touchez pour commencer.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

struct TodaySessionView: View {
    let entry: RebondEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .accessoryRectangular:
            RectangularView(entry: entry)
                .containerBackground(.clear, for: .widget)
        case .accessoryInline:
            inline
                .containerBackground(.clear, for: .widget)
        case .systemMedium:
            MediumView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        default:
            SmallView(entry: entry)
                .containerBackground(for: .widget) { WidgetBackground() }
        }
    }

    @ViewBuilder private var inline: some View {
        if !entry.snapshot.hasProgram {
            Label("Créez votre programme", systemImage: "plus.circle")
        } else if entry.doneToday {
            Label("Séance faite · \(entry.week.done)/\(entry.week.planned)", systemImage: "checkmark.circle")
        } else {
            Label("\(entry.sessionTitle) · \(entry.snapshot.estimatedMinutes) min", systemImage: "figure.cooldown")
        }
    }
}

// MARK: - Home Screen

/// Tinted top fading into the background, like the Accueil page. Removed by the system in tinted
/// and clear modes.
private struct WidgetBackground: View {
    var body: some View {
        LinearGradient(colors: [Color.accentColor.opacity(0.28), Color(.systemBackground)], startPoint: .top, endPoint: .bottom)
    }
}

private struct SmallView: View {
    let entry: RebondEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .widgetAccentable()
            Spacer(minLength: 0)
            TodayStatus(entry: entry)
            Spacer(minLength: 0)
            if entry.snapshot.hasProgram {
                WeekDots(week: entry.week, today: entry.date)
                WeekCaption(week: entry.week)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var symbol: String {
        if !entry.snapshot.hasProgram { return "plus.circle.fill" }
        return entry.doneToday ? "checkmark.circle.fill" : "figure.cooldown"
    }
}

private struct MediumView: View {
    let entry: RebondEntry
    /// With the button below them, all the right column has room for.
    static let shownExercises = 2

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SmallView(entry: entry)
            if entry.snapshot.hasProgram {
                // Two exercises and the button fit the widget's height with its margins; more would push the
                // content past the edges.
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(entry.snapshot.exercises.prefix(Self.shownExercises).enumerated()), id: \.offset) { _, exercise in
                        ExerciseRow(exercise: exercise, done: entry.doneToday)
                    }
                    if entry.snapshot.exercises.count > Self.shownExercises {
                        Text("+ ^[\(entry.snapshot.exercises.count - Self.shownExercises) exercice](inflect: true)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    // Only while today's session is to do: on a rest day or once done, the widget opens Accueil.
                    if entry.destination == .session {
                        ActionCapsule(title: "Commencer", systemImage: "play.fill", destination: .session)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Ajoutez les exercices de votre kiné, puis vos jours de séance.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    ActionCapsule(title: "Créer un programme", systemImage: "plus", destination: .newProgram)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// The main action of the medium widget, as a filled capsule.
private struct ActionCapsule: View {
    let title: LocalizedStringKey
    let systemImage: String
    let destination: DeepLink.Destination

    var body: some View {
        Link(destination: destination.url) {
            Label(title, systemImage: systemImage)
                .font(.footnote.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .foregroundStyle(.white)
                .background(Color.accentColor, in: .capsule)
        }
        .widgetAccentable()
    }
}

/// Today's session in a few words: to do (exercises, minutes), done, or no program yet.
private struct TodayStatus: View {
    let entry: RebondEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !entry.snapshot.hasProgram {
                // What is missing, then what a tap does: the widget opens "Créer un programme".
                Text("Aucun programme")
                    .font(.headline)
                Text("Touchez pour créer le vôtre.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if entry.doneToday {
                Text("Séance faite")
                    .font(.headline)
                Text("Aujourd'hui")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                // "Prochaine séance mercredi" on a rest day: one line, smaller if needed.
                Text(entry.sessionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("^[\(entry.snapshot.exercises.count) exercice](inflect: true)")
                    .font(.headline)
                Text("Environ \(entry.snapshot.estimatedMinutes) min")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ExerciseRow: View {
    let exercise: WidgetSnapshot.Exercise
    let done: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: exercise.symbol)
                .font(.caption)
                .frame(width: 24, height: 24)
                .foregroundStyle(Color.accentColor)
                .background(Color.accentColor.opacity(0.15), in: .circle)
                .widgetAccentable()
            VStack(alignment: .leading, spacing: 0) {
                Text(exercise.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .strikethrough(done)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var detail: LocalizedStringKey {
        if let hold = exercise.holdSeconds { return "\(exercise.sets) × \(hold) s" }
        return "\(exercise.sets) × \(exercise.reps)"
    }
}

/// The seven days of the week: filled when a session was done, today outlined.
private struct WeekDots: View {
    let week: WidgetSnapshot.Week
    let today: Date

    var body: some View {
        HStack(spacing: 4) {
            ForEach(week.days, id: \.date) { day in
                Circle()
                    .fill(day.done ? Color.accentColor : Color.secondary.opacity(0.25))
                    .overlay {
                        if Calendar.current.isDate(day.date, inSameDayAs: today) {
                            Circle().strokeBorder(Color.primary.opacity(0.6), lineWidth: 1.5)
                        }
                    }
                    .frame(width: 10, height: 10)
                    .widgetAccentable(day.done)
            }
        }
        .accessibilityHidden(true)
    }
}

private struct WeekCaption: View {
    let week: WidgetSnapshot.Week

    var body: some View {
        Group {
            if week.isComplete {
                Text("Objectif de la semaine atteint")
            } else {
                Text("\(week.done) sur \(week.planned) cette semaine")
            }
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
    }
}

// MARK: - Lock Screen

/// "Prochaine séance": today's session if not done yet, otherwise the week so far.
private struct RectangularView: View {
    let entry: RebondEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Label("Rebond", systemImage: "figure.cooldown")
                .font(.caption.weight(.semibold))
                .widgetAccentable()
            if !entry.snapshot.hasProgram {
                Text("Aucun programme")
                    .font(.headline)
                Text("Touchez pour créer le vôtre.")
                    .font(.caption)
            } else if entry.doneToday {
                Text("Séance faite")
                    .font(.headline)
                Text(entry.week.isComplete ? "Objectif de la semaine atteint" : "\(entry.week.done) sur \(entry.week.planned) cette semaine")
                    .font(.caption)
            } else {
                Text(entry.sessionTitle)
                    .font(.headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Text("^[\(entry.snapshot.exercises.count) exercice](inflect: true) · \(entry.snapshot.estimatedMinutes) min")
                    .font(.caption)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Previews

#Preview("Petit", as: .systemSmall) {
    TodaySessionWidget()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
    RebondEntry(date: .now, snapshot: .sampleDoneToday)
    RebondEntry(date: .now, snapshot: .empty)
}

#Preview("Moyen", as: .systemMedium) {
    TodaySessionWidget()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
    RebondEntry(date: .now, snapshot: .sampleDoneToday)
    RebondEntry(date: .now, snapshot: .empty)
}

#Preview("Écran verrouillé", as: .accessoryRectangular) {
    TodaySessionWidget()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
    RebondEntry(date: .now, snapshot: .sampleDoneToday)
    RebondEntry(date: .now, snapshot: .empty)
}

extension WidgetSnapshot {
    static var sampleDoneToday: WidgetSnapshot {
        var snapshot = WidgetSnapshot.sample
        snapshot.sessionDates.insert(.now, at: 0)
        return snapshot
    }
}
