import SwiftData
import SwiftUI

/// The alerts of the Résumé page, grouped in one compact card: one row each, newest first.
struct AlertsGroup: View {
    let sessions: [Session]
    let onReport: () -> Void
    let onShowProgram: () -> Void

    static let dismissedKey = "dismissedPainAlert"
    @AppStorage(dismissedKey) private var painDismissed: Double = 0
    @AppStorage(ProgramChange.dateKey) private var changeDate: Double = 0
    @AppStorage(ProgramChange.byKey) private var changeBy = ""
    @AppStorage(ProgramChange.summaryKey) private var changeSummary = ""

    /// The last session, when it was painful and its alert wasn't closed.
    private var painful: Session? {
        guard let last = sessions.first,
              last.pain >= WeeklyReport.highPain,
              last.date.timeIntervalSinceReferenceDate > painDismissed,
              last.date > Date.now.addingTimeInterval(-7 * 86_400)
        else { return nil }
        return last
    }

    var body: some View {
        let painful = painful
        if changeDate > 0 || painful != nil {
            VStack(spacing: 0) {
                if changeDate > 0 {
                    AlertRow(
                        symbol: "list.bullet.clipboard.fill",
                        color: .blue,
                        title: Text("Nouveau programme"),
                        date: Date(timeIntervalSinceReferenceDate: changeDate),
                        message: changeBy.isEmpty ? Text(changeSummary) : Text("\(changeBy) · \(changeSummary)"),
                        action: onShowProgram,
                        onDismiss: { withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { changeDate = 0 } }
                    )
                }
                if changeDate > 0, painful != nil {
                    Divider().padding(.leading, 62)
                }
                if let painful {
                    AlertRow(
                        symbol: "bandage.fill",
                        color: .orange,
                        title: Text("Douleur de \(painful.pain) sur 10"),
                        date: painful.date,
                        message: Text("Faites une pause et prévenez votre kiné."),
                        action: onReport,
                        onDismiss: {
                            withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                                painDismissed = painful.date.timeIntervalSinceReferenceDate
                            }
                        }
                    )
                }
            }
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
            .transition(.opacity.combined(with: .scale(scale: 0.97)))
        }
    }
}

/// One alert: a colored symbol, a bold line with its date, a gray line, and a small close button.
/// The row opens the action.
private struct AlertRow: View {
    let symbol: String
    let color: Color
    let title: Text
    let date: Date
    let message: Text
    let action: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: action) {
                HStack(spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(color)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            title.font(.headline)
                            Text(date, format: .dateTime.day().month())
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .lineLimit(1)
                        message
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Button("Masquer", systemImage: "xmark", action: onDismiss)
                .labelStyle(.iconOnly)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 26)
                .background(Color(.tertiarySystemFill), in: .circle)
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

/// Remembers the last change made by the physiotherapist, to show it on the Résumé page.
enum ProgramChange {
    static let dateKey = "programChangeDate"
    static let byKey = "programChangeBy"
    static let summaryKey = "programChangeSummary"

    static func record(from old: Program?, to new: EditableProgram, by name: String?) {
        let defaults = UserDefaults.standard
        defaults.set(Date.now.timeIntervalSinceReferenceDate, forKey: dateKey)
        defaults.set(name ?? "", forKey: byKey)
        defaults.set(describe(from: old.map(EditableProgram.init), to: new), forKey: summaryKey)
    }

    /// The most useful difference, in one short sentence.
    static func describe(from old: EditableProgram?, to new: EditableProgram) -> String {
        func amount(_ e: EditableProgram.Exercise) -> String {
            e.mode == .hold ? "\(e.sets) × \(e.holdSeconds) s" : "\(e.sets) × \(e.reps)"
        }
        guard let old else { return String(localized: "\(new.exercises.count) exercices, \(new.sessionsPerWeek) séances par semaine.") }
        var changes: [String] = []
        for exercise in new.exercises {
            if let before = old.exercises.first(where: { $0.name == exercise.name }) {
                if amount(before) != amount(exercise) {
                    changes.append(String(localized: "\(exercise.name) : \(amount(exercise)) au lieu de \(amount(before))"))
                }
            } else {
                changes.append(String(localized: "Nouvel exercice : \(exercise.name)"))
            }
        }
        for exercise in old.exercises where !new.exercises.contains(where: { $0.name == exercise.name }) {
            changes.append(String(localized: "\(exercise.name) retiré"))
        }
        if old.sessionsPerWeek != new.sessionsPerWeek {
            changes.append(String(localized: "\(new.sessionsPerWeek) séances par semaine au lieu de \(old.sessionsPerWeek)"))
        }
        guard let first = changes.first else { return String(localized: "Votre programme a été vérifié par votre kiné.") }
        return changes.count == 1 ? first + "." : first + String(localized: ", et \(changes.count - 1) autres changements.")
    }
}
