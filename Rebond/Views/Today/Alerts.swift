import SwiftData
import SwiftUI

/// An alert card in the style of Health's "Liste de vérification": a small gray header in capitals with a
/// close button, a separator, then a large colored symbol, a bold sentence, a gray explanation and one action.
struct AlertCard: View {
    let header: Text
    let symbol: String
    let color: Color
    let title: Text
    let message: Text
    let actionTitle: LocalizedStringKey
    let action: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                header
                    .textCase(.uppercase)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Masquer", systemImage: "xmark", action: onDismiss)
                    .labelStyle(.iconOnly)
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 30, height: 30)
                    .background(Color(.tertiarySystemFill), in: .circle)
                    .buttonStyle(.plain)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            HStack(alignment: .top, spacing: 16) {
                Image(systemName: symbol)
                    .font(.system(size: 34))
                    .foregroundStyle(color)
                    .symbolRenderingMode(.hierarchical)
                    .frame(width: 44)
                VStack(alignment: .leading, spacing: 6) {
                    title
                        .font(.title3.weight(.semibold))
                    message
                        .foregroundStyle(.secondary)
                    Button(actionTitle, action: action)
                        .font(.headline)
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.capsule)
                        .tint(color)
                        .padding(.top, 6)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
        }
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .transition(.asymmetric(insertion: .opacity.combined(with: .scale(scale: 0.96)), removal: .opacity))
    }
}

/// After a painful session: calm, never blocking, with a way to tell the physiotherapist.
struct PainAlertCard: View {
    let sessions: [Session]
    let onReport: () -> Void
    static let dismissedKey = "dismissedPainAlert"
    @AppStorage(dismissedKey) private var dismissed: Double = 0

    private var painful: Session? {
        guard let last = sessions.first,
              last.pain >= WeeklyReport.highPain,
              last.date.timeIntervalSinceReferenceDate > dismissed,
              last.date > Date.now.addingTimeInterval(-7 * 86_400)
        else { return nil }
        return last
    }

    var body: some View {
        if let painful {
            AlertCard(
                header: Text("Douleur · \(painful.date, format: .dateTime.day().month())"),
                symbol: "heart.text.square.fill",
                color: .orange,
                title: Text("Douleur de \(painful.pain) sur 10 à la dernière séance."),
                message: Text("Si elle est forte ou inhabituelle, faites une pause et parlez-en à votre kiné."),
                actionTitle: "Prévenir mon kiné",
                action: onReport,
                onDismiss: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        dismissed = painful.date.timeIntervalSinceReferenceDate
                    }
                }
            )
        }
    }
}

/// The physiotherapist changed the program (QR code or connected version): what changed, in one line.
struct ProgramChangeCard: View {
    let onShow: () -> Void
    @AppStorage(ProgramChange.dateKey) private var date: Double = 0
    @AppStorage(ProgramChange.byKey) private var by = ""
    @AppStorage(ProgramChange.summaryKey) private var summary = ""

    var body: some View {
        if date > 0 {
            AlertCard(
                header: Text("Programme · \(Date(timeIntervalSinceReferenceDate: date), format: .dateTime.day().month())"),
                symbol: "list.bullet.clipboard.fill",
                color: .blue,
                title: by.isEmpty ? Text("Votre kiné a modifié votre programme.") : Text("\(by) a modifié votre programme."),
                message: Text(summary),
                actionTitle: "Voir le programme",
                action: onShow,
                onDismiss: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) { date = 0 }
                }
            )
        }
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
