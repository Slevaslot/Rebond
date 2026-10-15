import SwiftUI
import WidgetKit

/// "Séance du jour": what is left to do today and the week's regularity. Opens the app on the session.
struct TodaySessionWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TodaySession", provider: RebondProvider()) { entry in
            TodaySessionView(entry: entry)
                .widgetURL(DeepLink.session)
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
            Label("Ajoutez votre programme", systemImage: "figure.cooldown")
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
            Image(systemName: entry.doneToday ? "checkmark.circle.fill" : "figure.cooldown")
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
}

private struct MediumView: View {
    let entry: RebondEntry

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            SmallView(entry: entry)
            if entry.snapshot.hasProgram {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(entry.snapshot.exercises.prefix(3).enumerated()), id: \.offset) { _, exercise in
                        ExerciseRow(exercise: exercise, done: entry.doneToday)
                    }
                    if entry.snapshot.exercises.count > 3 {
                        Text("+ ^[\(entry.snapshot.exercises.count - 3) exercice](inflect: true)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if !entry.doneToday {
                        Link(destination: DeepLink.session) {
                            Label("Commencer", systemImage: "play.fill")
                                .font(.subheadline.bold())
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                                .foregroundStyle(.white)
                                .background(Color.accentColor, in: .capsule)
                        }
                        .widgetAccentable()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

/// Today's session in a few words: to do (exercises, minutes), done, or no program yet.
private struct TodayStatus: View {
    let entry: RebondEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !entry.snapshot.hasProgram {
                Text("Votre programme")
                    .font(.headline)
                Text("Ajoutez celui de votre kiné dans Rebond.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if entry.doneToday {
                Text("Séance faite")
                    .font(.headline)
                Text("Aujourd'hui")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(entry.sessionTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
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
                .font(.footnote)
                .frame(width: 22, height: 22)
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
                Text("Ajoutez votre programme")
                    .font(.headline)
            } else if entry.doneToday {
                Text("Séance faite")
                    .font(.headline)
                Text(entry.week.isComplete ? "Objectif de la semaine atteint" : "\(entry.week.done) sur \(entry.week.planned) cette semaine")
                    .font(.caption)
            } else {
                Text(entry.sessionTitle)
                    .font(.headline)
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
}

#Preview("Écran verrouillé", as: .accessoryRectangular) {
    TodaySessionWidget()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
    RebondEntry(date: .now, snapshot: .sampleDoneToday)
}

extension WidgetSnapshot {
    static var sampleDoneToday: WidgetSnapshot {
        var snapshot = WidgetSnapshot.sample
        snapshot.sessionDates.insert(.now, at: 0)
        return snapshot
    }
}
