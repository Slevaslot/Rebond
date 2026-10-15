import SwiftUI

/// One followed patient in the physiotherapist space, as a Health-style card: who, when they last reported,
/// what needs attention, then regularity, pain, repetitions and amplitude over the week of the report.
struct PatientCard: View {
    let name: String
    let overview: PatientOverview?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                InitialsBadge(name: name, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name)
                        .font(.headline)
                    if let overview {
                        AttentionLabel(overview: overview)
                    } else {
                        Label("Bilan illisible", systemImage: "doc.questionmark")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            if let overview {
                Text(overview.summaryLine)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
        .contentShape(.rect(cornerRadius: 26))
    }
}

/// What needs the physiotherapist's attention, with a symbol and words (never the color alone).
struct AttentionLabel: View {
    let overview: PatientOverview

    var body: some View {
        Group {
            switch overview.attention {
            case .highPain:
                Label("^[\(overview.painfulSessions) séance](inflect: true) avec une douleur forte", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            case .fewSessions:
                Label("\(overview.sessionsDone) séances sur \(overview.sessionsPlanned) prévues", systemImage: "calendar.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            case .staleReport:
                Label("Pas de nouveau bilan depuis \(overview.daysSinceReport) jours", systemImage: "clock.badge.exclamationmark")
                    .foregroundStyle(.secondary)
            case .none:
                Text("Rien à signaler")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline)
    }
}

/// Regularity, pain, repetitions and amplitude, two by two (one by one at the accessibility text sizes).
struct PatientMetrics: View {
    let overview: PatientOverview
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 2 : 4
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columns),
                  alignment: .leading, spacing: 14) {
            MetricTile(title: "Séances", symbol: "calendar", color: .teal,
                       value: "\(overview.sessionsDone)", unit: "/\(overview.sessionsPlanned)",
                       accessibilityValue: Text("\(overview.sessionsDone) séances sur \(overview.sessionsPlanned)"))
            if let pain = overview.lastPain {
                MetricTile(title: "Douleur", symbol: "bandage.fill", color: .orange,
                           value: "\(pain)", unit: "/10",
                           accessibilityValue: Text("\(pain) sur 10 à la dernière séance"))
            } else {
                MetricTile(title: "Douleur", symbol: "bandage.fill", color: .orange, value: "–", unit: "",
                           accessibilityValue: Text("Aucune séance"))
            }
            if overview.plannedReps > 0 {
                MetricTile(title: "Répétitions", symbol: "repeat", color: .purple,
                           value: "\(overview.completedReps)", unit: "/\(overview.plannedReps)",
                           accessibilityValue: Text("\(overview.completedReps) sur \(overview.plannedReps), \(overview.incompleteReps) incomplètes"))
            } else {
                MetricTile(title: "Répétitions", symbol: "repeat", color: .purple, value: "–", unit: "",
                           accessibilityValue: Text("Aucune répétition prévue"))
            }
            if let amplitude = overview.amplitude {
                // Past the goal, the physiotherapist reads 100 %: "101 %" looks like a measuring error.
                let shown = min(Int(amplitude.rounded()), 100)
                MetricTile(title: "Amplitude", symbol: "arrow.up.and.down", color: .blue,
                           value: "\(shown)", unit: "%",
                           accessibilityValue: Text(shown == 100 ? "Objectif atteint" : "\(shown) % de l'objectif"))
            } else {
                MetricTile(title: "Amplitude", symbol: "arrow.up.and.down", color: .blue, value: "–", unit: "",
                           accessibilityValue: Text("Pas de mesure"))
            }
        }
    }
}

/// A colored label, then a rounded value with its unit, as in Health.
struct MetricTile: View {
    let title: LocalizedStringKey
    let symbol: String
    let color: Color
    let value: String
    let unit: LocalizedStringKey
    let accessibilityValue: Text

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title2.weight(.semibold))
                    .fontDesign(.rounded)
                    .monospacedDigit()
                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(accessibilityValue)
    }
}

/// A patient's initials in a tinted circle.
struct InitialsBadge: View {
    let name: String
    var size: Double = 44

    private var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    var body: some View {
        Group {
            if initials.isEmpty {
                Image(systemName: "person.fill")
            } else {
                Text(initials)
            }
        }
        .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
        .foregroundStyle(.tint)
        .frame(width: size, height: size)
        .background(Color.accentColor.opacity(0.15), in: .circle)
        .accessibilityHidden(true)
    }
}

extension PatientOverview {
    /// "1 séance sur 3 · douleur 8/10 · amplitude 73 %": the week in one quiet line.
    var summaryLine: String {
        var parts = [String.inflected("^[\(sessionsDone) séance](inflect: true) sur \(sessionsPlanned)")]
        if let lastPain { parts.append(String(localized: "douleur \(lastPain)/10")) }
        if let amplitude { parts.append(String(localized: "amplitude \(min(Int(amplitude.rounded()), 100)) %")) }
        return parts.joined(separator: " · ")
    }
}
