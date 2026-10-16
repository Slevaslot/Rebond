import SwiftData
import SwiftUI

/// The alert of the Accueil page: the last session was painful (pain at or above the high-pain threshold).
struct AlertsGroup: View {
    let sessions: [Session]
    let onReport: () -> Void

    static let dismissedKey = "dismissedPainAlert"
    @AppStorage(dismissedKey) private var painDismissed: Double = 0

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
        if let painful {
            AlertRow(
                symbol: "bandage.fill",
                color: .orange,
                title: Text("Douleur de \(painful.pain) sur 10"),
                detail: Text(painful.date, format: .dateTime.day().month()),
                message: Text("Faites une pause et prévenez votre kiné."),
                action: onReport,
                onDismiss: {
                    withAnimation(.spring(response: 0.45, dampingFraction: 0.8)) {
                        painDismissed = painful.date.timeIntervalSinceReferenceDate
                    }
                }
            )
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
    let detail: Text
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
                            detail
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
