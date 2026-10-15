import SwiftUI
import WidgetKit

/// The complications of Rebond on the watch face and in the Smart Stack: the week's regularity and today's
/// session. Fed by the iPhone through the watch app (same snapshot as the iPhone widgets).
@main
struct RebondWatchWidgetsBundle: WidgetBundle {
    var body: some Widget {
        RegularityComplication()
        TodayComplication()
    }
}

/// Sessions done this week out of those planned by the physiotherapist.
struct RegularityComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchRegularity", provider: RebondProvider()) { entry in
            RegularityComplicationView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Régularité")
        .description("Vos séances de la semaine sur celles prévues par votre kiné.")
        .supportedFamilies([.accessoryCircular, .accessoryCorner])
    }
}

struct RegularityComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RebondEntry

    var body: some View {
        let week = entry.week
        switch family {
        case .accessoryCorner:
            Image(systemName: week.isComplete ? "checkmark" : "figure.cooldown")
                .font(.title2)
                .widgetAccentable()
                .widgetLabel {
                    Gauge(value: week.fraction) {
                        Text("Rebond")
                    } currentValueLabel: {
                        Text("\(week.done)/\(week.planned)")
                    }
                }
                .accessibilityLabel(Text("\(week.done) séances sur \(week.planned) cette semaine"))
        default:
            Gauge(value: week.fraction) {
                Image(systemName: "figure.cooldown")
            } currentValueLabel: {
                if week.isComplete {
                    Image(systemName: "checkmark").font(.title3.bold())
                } else {
                    Text("\(week.done)/\(week.planned)")
                        .font(.title3.bold())
                        .minimumScaleFactor(0.6)
                }
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .widgetAccentable()
            .accessibilityLabel(Text("Régularité"))
            .accessibilityValue(Text("\(week.done) séances sur \(week.planned) cette semaine"))
        }
    }
}

/// Today's session: what it holds, or that it is done. Shown in the Smart Stack while it is still to do.
struct TodayComplication: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WatchToday", provider: RebondProvider()) { entry in
            TodayComplicationView(entry: entry)
                .containerBackground(Color.accentColor.gradient, for: .widget)
        }
        .configurationDisplayName("Séance du jour")
        .description("Votre séance d'aujourd'hui et la semaine.")
        .supportedFamilies([.accessoryRectangular, .accessoryInline])
    }
}

struct TodayComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: RebondEntry

    var body: some View {
        let week = entry.week
        let snapshot = entry.snapshot
        switch family {
        case .accessoryInline:
            if !snapshot.hasProgram {
                Label("Rebond", systemImage: "figure.cooldown")
            } else {
                Label("\(week.done)/\(week.planned) séances", systemImage: "figure.cooldown")
            }
        default:
            VStack(alignment: .leading, spacing: 2) {
                Label("Rebond", systemImage: "figure.cooldown")
                    .font(.headline)
                    .widgetAccentable()
                if !snapshot.hasProgram {
                    Text("Créez votre programme sur l'iPhone")
                        .font(.footnote)
                } else if entry.doneToday {
                    Text("Séance faite, bravo !")
                    Text("\(week.done) sur \(week.planned) cette semaine")
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(snapshot.exercises.count) exercices · \(snapshot.estimatedMinutes) min")
                    Text("\(week.done) sur \(week.planned) cette semaine")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview("Séance du jour", as: .accessoryRectangular) {
    TodayComplication()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
}

#Preview("Régularité", as: .accessoryCircular) {
    RegularityComplication()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
}
