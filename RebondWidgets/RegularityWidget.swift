import SwiftUI
import WidgetKit

/// Lock Screen ring: sessions done this week out of those planned by the physiotherapist. A tap goes to
/// today's session, "Créer un programme" while there is none, otherwise the Accueil page.
struct RegularityWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeekRegularity", provider: RebondProvider()) { entry in
            RegularityView(entry: entry)
                .containerBackground(.clear, for: .widget)
                .widgetURL(entry.url)
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
            if !entry.snapshot.hasProgram {
                // No "0/0": nothing planned yet, a tap creates the program.
                Image(systemName: "plus")
                    .font(.title3.bold())
            } else if week.isComplete {
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
        .accessibilityValue(entry.snapshot.hasProgram
            ? Text("\(week.done) séances sur \(week.planned) cette semaine")
            : Text("Aucun programme. Touchez pour créer le vôtre."))
    }
}

#Preview("Anneau", as: .accessoryCircular) {
    RegularityWidget()
} timeline: {
    RebondEntry(date: .now, snapshot: .sample)
    RebondEntry(date: .now, snapshot: .sampleDoneToday)
    RebondEntry(date: .now, snapshot: .empty)
}
