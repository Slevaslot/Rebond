import SwiftUI

/// One followed patient in the physiotherapist space, as a Health-style card: who, when they last reported,
/// what needs attention, then regularity, pain, repetitions and amplitude over the week of the report.
struct PatientCard: View {
    let name: String
    let overview: PatientOverview?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                InitialsBadge(name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.headline)
                    if let overview {
                        Text("Bilan du \(overview.reportDate, format: .dateTime.day().month(.wide))")
                            .font(.subheadline)
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
                AttentionLabel(overview: overview)
                Divider()
                PatientMetrics(overview: overview)
            } else {
                Label("Bilan illisible", systemImage: "doc.questionmark")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
        .contentShape(.rect(cornerRadius: 24))
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
                Label("Rien à signaler cette semaine", systemImage: "checkmark.circle")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.subheadline.weight(.semibold))
    }
}

/// Regularity, pain, repetitions and amplitude, two by two (one by one at the accessibility text sizes).
struct PatientMetrics: View {
    let overview: PatientOverview
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: columns),
                  alignment: .leading, spacing: 14) {
            MetricTile(title: "Régularité", symbol: "calendar", color: .teal,
                       value: "\(overview.sessionsDone)/\(overview.sessionsPlanned)", unit: "séances",
                       accessibilityValue: Text("\(overview.sessionsDone) séances sur \(overview.sessionsPlanned)"))
            if let pain = overview.lastPain {
                MetricTile(title: "Douleur", symbol: "bandage.fill", color: .orange,
                           value: "\(pain)", unit: "sur 10",
                           accessibilityValue: Text("\(pain) sur 10 à la dernière séance"))
            } else {
                MetricTile(title: "Douleur", symbol: "bandage.fill", color: .orange, value: "–", unit: "",
                           accessibilityValue: Text("Aucune séance"))
            }
            if overview.plannedReps > 0 {
                MetricTile(title: "Répétitions", symbol: "repeat", color: .purple,
                           value: "\(overview.completedReps)", unit: "sur \(overview.plannedReps)",
                           accessibilityValue: Text("\(overview.completedReps) sur \(overview.plannedReps), \(overview.incompleteReps) incomplètes"))
            } else {
                MetricTile(title: "Répétitions", symbol: "repeat", color: .purple, value: "–", unit: "",
                           accessibilityValue: Text("Aucune répétition prévue"))
            }
            if let amplitude = overview.amplitude {
                MetricTile(title: "Amplitude", symbol: "arrow.up.and.down", color: .blue,
                           value: "\(Int(amplitude.rounded()))", unit: "%",
                           accessibilityValue: Text("\(Int(amplitude.rounded())) % de l'objectif"))
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
            Label(title, systemImage: symbol)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
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
