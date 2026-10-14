import Charts
import SwiftData
import SwiftUI

/// The follow-up part of the Aujourd'hui page, after Health's "Points clés": one card per measure,
/// with a sentence, two values and a chart. Each card opens its detail in a sheet.
struct FollowUpSection: View {
    let sessions: [Session]
    let sessionsPerWeek: Int
    let week: WeekProgress

    enum Detail: String, Identifiable {
        case amplitude, pain, report, history
        var id: String { rawValue }
    }

    @State private var detail: Detail?

    private var data: [WeeklyReport.SessionData] { sessions.map(\.reportData) }

    var body: some View {
        let progress = ProgressData(sessions: data, sessionsPerWeek: sessionsPerWeek)
        VStack(alignment: .leading, spacing: 14) {
            Text("Suivi")
                .font(.title2.bold())
                .padding(.horizontal, 4)
                .padding(.top, 10)

            RegularityCard(week: week) { detail = .history }

            let amplitudes = progress.amplitude.last.map { last in progress.amplitude.filter { $0.series == last.series } } ?? []
            AmplitudeCard(points: Array(amplitudes.suffix(7))) { detail = .amplitude }

            PainCard(points: Array(progress.pain.suffix(7))) { detail = .pain }

            // A plain row, like Health's "Afficher toutes les données Santé".
            Button { detail = .report } label: {
                HStack(spacing: 14) {
                    Image(systemName: "paperplane.fill")
                        .font(.title2)
                        .foregroundStyle(.indigo)
                        .frame(width: 32)
                    Text("Envoyer le bilan à mon kiné")
                        .font(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
                .contentShape(.rect(cornerRadius: 26))
            }
            .buttonStyle(.plain)
        }
        .sheet(item: $detail) { detail in
            NavigationStack {
                Group {
                    switch detail {
                    case .amplitude: MetricDetailView(metric: .amplitude, sessions: data, sessionsPerWeek: sessionsPerWeek)
                    case .pain: MetricDetailView(metric: .pain, sessions: data, sessionsPerWeek: sessionsPerWeek)
                    case .report: ReportView()
                    case .history: HistoryView(sessionsPerWeek: sessionsPerWeek)
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Fermer", systemImage: "xmark", role: .close) { self.detail = nil }
                    }
                }
            }
        }
    }
}

// MARK: - Insight cards

/// A card like Health's "Points clés": colored title, one sentence saying what happens,
/// then two values side by side and a chart. The whole card opens the detail.
private struct InsightCard<Legend: View, ChartContent: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let color: Color
    let sentence: Text
    let action: () -> Void
    @ViewBuilder let legend: Legend
    @ViewBuilder let chart: ChartContent

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label(title, systemImage: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(color)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                sentence
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                HStack(alignment: .top, spacing: 0) {
                    legend
                }
                chart
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
        }
        .buttonStyle(.plain)
    }
}

/// One value of the legend: a dot and a label in its color, then the value and its unit.
private struct LegendValue: View {
    let label: LocalizedStringKey
    let value: String
    let unit: LocalizedStringKey
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(label).lineLimit(1)
            } icon: {
                Circle().fill(color).frame(width: 9, height: 9)
            }
            .labelStyle(DotLabelStyle())
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color == .gray ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color == .gray ? AnyShapeStyle(.secondary) : AnyShapeStyle(color))
                Text(unit)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DotLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) {
            configuration.icon
            configuration.title
        }
    }
}

/// This week, day by day, against the program's goal.
private struct RegularityCard: View {
    let week: WeekProgress
    let action: () -> Void

    private var sentence: Text {
        if week.done >= week.planned { return Text("Objectif de la semaine atteint, bravo.") }
        if week.done == 0 { return Text("Aucune séance cette semaine pour l'instant.") }
        return Text("Vous avez fait ^[\(week.done) séance](inflect: true) sur \(week.planned) cette semaine.")
    }

    var body: some View {
        InsightCard(symbol: "calendar", title: "Régularité", color: .teal, sentence: sentence, action: action) {
            LegendValue(label: "Cette semaine", value: "\(week.done)", unit: week.done > 1 ? "séances" : "séance", color: .teal)
            LegendValue(label: "Objectif", value: "\(week.planned)", unit: week.planned > 1 ? "séances" : "séance", color: .gray)
        } chart: {
            HStack(spacing: 6) {
                ForEach(week.days, id: \.date) { day in
                    let isToday = Calendar.current.isDateInToday(day.date)
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(day.done ? AnyShapeStyle(Color.teal) : AnyShapeStyle(Color(.systemGray5)))
                            .frame(height: 30)
                            .overlay {
                                if day.done {
                                    Image(systemName: "checkmark")
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(.white)
                                }
                            }
                        Text(day.date, format: .dateTime.weekday(.narrow))
                            .font(.caption.weight(isToday ? .bold : .regular))
                            .foregroundStyle(isToday ? AnyShapeStyle(Color.teal) : AnyShapeStyle(.secondary))
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
        }
    }
}

/// The last measures of one exercise, against the target (100 %).
private struct AmplitudeCard: View {
    let points: [ProgressData.Point]
    let action: () -> Void

    private var sentence: Text {
        guard let last = points.last?.value else {
            return Text("Faites une séance suivie par la caméra pour mesurer votre mouvement.")
        }
        let trend = points.count > 1 ? last - points[0].value : 0
        if last >= 100 && trend >= 5 { return Text("Votre amplitude progresse et atteint l'objectif.") }
        if last >= 100 { return Text("Vous atteignez l'amplitude visée.") }
        if trend >= 5 { return Text("Votre amplitude progresse.") }
        if trend <= -5 { return Text("Votre amplitude baisse depuis quelques séances.") }
        return Text("Votre amplitude reste stable.")
    }

    var body: some View {
        InsightCard(symbol: "arrow.up.and.down", title: "Amplitude", color: .blue, sentence: sentence, action: action) {
            if let last = points.last {
                LegendValue(label: "\(last.series)", value: "\(Int(last.value.rounded()))", unit: "%", color: .blue)
                LegendValue(label: "Objectif", value: "100", unit: "%", color: .gray)
            }
        } chart: {
            if points.count > 1 {
                TrendChart(points: points, color: .blue, reference: 100, referenceLabel: "100 %",
                           domain: max(0, min(100, points.map(\.value).min() ?? 0) - 10)...max(105, (points.map(\.value).max() ?? 0) + 5))
            }
        }
    }
}

/// The pain of the last sessions, against the high-pain threshold.
private struct PainCard: View {
    let points: [ProgressData.Point]
    let action: () -> Void

    private var average: Double {
        points.isEmpty ? 0 : points.map(\.value).reduce(0, +) / Double(points.count)
    }

    private var sentence: Text {
        guard let last = points.last?.value else { return Text("Notez votre douleur à la fin de chaque séance.") }
        let trend = points.count > 1 ? last - points[0].value : 0
        if last >= Double(WeeklyReport.highPain) { return Text("Douleur forte à la dernière séance. Parlez-en à votre kiné.") }
        if trend <= -2 { return Text("Votre douleur diminue au fil des séances.") }
        if trend >= 2 { return Text("Votre douleur augmente depuis quelques séances.") }
        return Text("Votre douleur reste stable.")
    }

    var body: some View {
        InsightCard(symbol: "bandage.fill", title: "Douleur", color: .orange, sentence: sentence, action: action) {
            if let last = points.last {
                LegendValue(label: "Dernière séance", value: "\(Int(last.value))", unit: "sur 10", color: .orange)
                LegendValue(label: "Moyenne", value: average.formatted(.number.precision(.fractionLength(0...1))), unit: "sur 10", color: .gray)
            }
        } chart: {
            if points.count > 1 {
                TrendChart(points: points, color: .orange, reference: Double(WeeklyReport.highPain),
                           referenceLabel: "Seuil", domain: 0...10)
            }
        }
    }
}

/// Health's trend chart: a gray line with gray points, the last point in color,
/// a reference line labeled on the right, and the first and last dates below.
private struct TrendChart: View {
    let points: [ProgressData.Point]
    let color: Color
    let reference: Double
    let referenceLabel: LocalizedStringKey
    let domain: ClosedRange<Double>

    var body: some View {
        VStack(spacing: 6) {
            Chart {
                RuleMark(y: .value("Repère", reference))
                    .foregroundStyle(Color(.systemGray4))
                    .lineStyle(StrokeStyle(lineWidth: 1))
                    .annotation(position: .top, alignment: .leading, spacing: 2) {
                        Text(referenceLabel)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                ForEach(Array(points.enumerated()), id: \.offset) { index, point in
                    LineMark(x: .value("Séance", index), y: .value("Valeur", point.value))
                        .foregroundStyle(Color(.systemGray3))
                        .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                        .interpolationMethod(.monotone)
                    PointMark(x: .value("Séance", index), y: .value("Valeur", point.value))
                        .foregroundStyle(index == points.count - 1 ? color : Color(.systemGray3))
                        .symbolSize(index == points.count - 1 ? 150 : 50)
                }
            }
            .chartXScale(domain: -0.3...Double(points.count - 1) + 0.3)
            .chartYScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .frame(height: 130)
            HStack {
                if let first = points.first {
                    Text(first.date, format: .dateTime.day().month())
                }
                Spacer()
                if let last = points.last {
                    if Calendar.current.isDateInToday(last.date) {
                        Text("aujourd'hui")
                    } else {
                        Text(last.date, format: .dateTime.day().month())
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Detail sheet

/// A metric's detail, as in Health: period picker, average, large chart, explanation.
struct MetricDetailView: View {
    enum Metric { case amplitude, pain }
    enum Range: String, CaseIterable, Identifiable {
        case week = "S", month = "M", sixMonths = "6M"
        var id: String { rawValue }
        var days: Int { switch self { case .week: 7; case .month: 30; case .sixMonths: 182 } }
        var label: LocalizedStringKey { switch self { case .week: "Semaine"; case .month: "Mois"; case .sixMonths: "6 mois" } }
    }

    let metric: Metric
    let sessions: [WeeklyReport.SessionData]
    let sessionsPerWeek: Int
    @State private var range = Range.month

    var body: some View {
        let start = Date.now.addingTimeInterval(-Double(range.days) * 86_400)
        let kept = sessions.filter { $0.date >= start }
        let data = ProgressData(sessions: kept, sessionsPerWeek: sessionsPerWeek, weeks: max(1, range.days / 7))
        let values = metric == .amplitude ? data.amplitude.map(\.value) : data.pain.map(\.value)
        List {
            Section {
                Picker("Période", selection: $range) {
                    ForEach(Range.allCases) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("MOYENNE")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    if values.isEmpty {
                        Text("Pas de mesure sur cette période")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    } else {
                        let average = values.reduce(0, +) / Double(values.count)
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(metric == .amplitude ? "\(Int(average.rounded()))" : average.formatted(.number.precision(.fractionLength(1))))
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                            Text(metric == .amplitude ? "% de l'objectif" : "sur 10")
                                .font(.title3.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Group {
                        if metric == .amplitude { AmplitudeChart(data: data) } else { PainChart(data: data) }
                    }
                    .frame(height: 260)
                    .padding(.top, 8)
                }
                .padding(.vertical, 6)
            }
            Section("À propos") {
                Text(metric == .amplitude
                     ? "Meilleure répétition de chaque séance, mesurée par la caméra : 100 % correspond à l'objectif du mouvement fixé dans l'app. À titre indicatif."
                     : "Douleur indiquée à la fin de chaque séance, de 0 à 10. Au-delà de 7, la séance est signalée à votre kiné dans le bilan.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(metric == .amplitude ? "Amplitude" : "Douleur")
        .navigationBarTitleDisplayMode(.inline)
    }
}
