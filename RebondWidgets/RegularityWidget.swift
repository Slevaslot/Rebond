import SwiftUI
import WidgetKit

/// Lock Screen ring: sessions done this week out of those planned by the physiotherapist.
struct RegularityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekRegularity", provider: RebondProvider()) { entry in
            RegularityView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(DeepLink.session)
        }
        .configurationDisplayName("Régularité")
        .description("Vos séances de la semaine sur celles prévues par votre kiné.")
        .supportedFamilies([.accessoryCircular])
    }
}

struct RegularityView: View {
    let entry: RebondEntry

    var body: some View {
        let week = entry.week
        Gauge(value: week.fraction) {
            Image(systemName: "figure.cooldown")
        } currentValueLabel: {
            if week.isComplete {
                Image(systemName: "checkmark")
                    .font(.title3.bold())
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

#Preview("Anneau", as: .accessoryCircular) {
    RegularityWidget()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
    RebondEntry(date: .now, snapshot: .sampleDoneToday)
}
