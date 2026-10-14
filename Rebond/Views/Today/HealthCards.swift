import Charts
import SwiftData
import SwiftUI

/// The follow-up part of the Résumé page, after Health: small cards side by side (colored title, value,
/// mini chart, chevron), then "Points clés" sentences. Each card opens its detail in a sheet.
struct FollowUpSection: View {
    let sessions: [Session]
    let sessionsPerWeek: Int

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

            Grid(horizontalSpacing: 14, verticalSpacing: 14) {
                GridRow {
                    TileCard(title: "Amplitude", color: .blue) {
                        detail = .amplitude
                    } content: {
                        if let last = progress.amplitude.last {
                            TileValue(value: "\(Int(last.value.rounded()))", unit: "%")
                            MiniLine(values: progress.amplitude.filter { $0.series == last.series }.map(\.value), color: .blue)
                        } else {
                            TileEmpty()
                        }
                    }
                    TileCard(title: "Douleur", color: .orange) {
                        detail = .pain
                    } content: {
                        if let last = progress.pain.last {
                            TileValue(value: "\(Int(last.value))", unit: "/ 10")
                            MiniBars(values: progress.pain.suffix(8).map(\.value), maximum: 10, color: .orange)
                        } else {
                            TileEmpty()
                        }
                    }
                }
                GridRow {
                    TileCard(title: "Bilan kiné", color: .indigo) {
                        detail = .report
                    } content: {
                        Image(systemName: "doc.richtext")
                            .font(.system(size: 34))
                            .foregroundStyle(.indigo)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("7 derniers jours")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    TileCard(title: "Historique", color: .teal) {
                        detail = .history
                    } content: {
                        TileValue(value: "\(sessions.count)", unit: sessions.count > 1 ? "séances" : "séance")
                        if let last = sessions.first {
                            Text(last.date, format: .relative(presentation: .named))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            let highlights = Highlights(progress: progress, sessions: data)
            if !highlights.items.isEmpty {
                Text("Points clés")
                    .font(.title2.bold())
                    .padding(.horizontal, 4)
                    .padding(.top, 10)
                ForEach(highlights.items) { item in
                    HighlightCard(item: item)
                }
            }
        }
        .sheet(item: $detail) { detail in
            NavigationStack {
                Group {
                    switch detail {
                    case .amplitude: MetricDetailView(metric: .amplitude, sessions: data, sessionsPerWeek: sessionsPerWeek)
                    case .pain: MetricDetailView(metric: .pain, sessions: data, sessionsPerWeek: sessionsPerWeek)
                    case .report: ReportView()
                    case .history: HistoryView()
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

// MARK: - Tiles

/// A small Health tile: colored title with a chevron, then its content. The whole tile opens the detail.
private struct TileCard<Content: View>: View {
    let title: LocalizedStringKey
    let color: Color
    let action: () -> Void
    @ViewBuilder let content: Content

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(color)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
                content
            }
            .padding()
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
            .contentShape(.rect(cornerRadius: 26))
        }
        .buttonStyle(.plain)
    }
}

private struct TileValue: View {
    let value: String
    let unit: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(unit)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct TileEmpty: View {
    var body: some View {
        Text("Pas encore de mesure")
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }
}

private struct MiniLine: View {
    let values: [Double]
    let color: Color

    var body: some View {
        Chart(Array(values.suffix(10).enumerated()), id: \.offset) { item in
            LineMark(x: .value("n", item.offset), y: .value("v", item.element))
                .interpolationMethod(.monotone)
                .foregroundStyle(color)
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

private struct MiniBars: View {
    let values: [Double]
    let maximum: Double
    let color: Color

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            BarMark(x: .value("n", item.offset), y: .value("v", max(item.element, 0.3)))
                .foregroundStyle(item.offset == values.count - 1 ? color : Color(.tertiaryLabel))
                .clipShape(.rect(cornerRadius: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...maximum)
        .frame(height: 30)
        .accessibilityHidden(true)
    }
}

// MARK: - Highlights

/// Trend sentences, as Health's "Points clés".
struct Highlights {
    struct Item: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let symbol: String
        let color: Color
        let text: Text
    }

    var items: [Item] = []

    init(progress: ProgressData, sessions: [WeeklyReport.SessionData]) {
        // Amplitude: first and last measure of the main camera exercise.
        if let series = progress.amplitude.first?.series {
            let points = progress.amplitude.filter { $0.series == series }
            if let first = points.first, let last = points.last, points.count > 1 {
                let change = Int((last.value - first.value).rounded())
                if change != 0 {
                    items.append(Item(
                        title: "Amplitude", symbol: "arrow.up.right", color: .blue,
                        text: change > 0
                            ? Text("Votre amplitude au \(series.lowercased()) est passée de \(Int(first.value.rounded())) % à \(Int(last.value.rounded())) % de l'objectif.")
                            : Text("Votre amplitude au \(series.lowercased()) a baissé de \(abs(change)) points. Parlez-en à votre kiné si cela continue.")
                    ))
                }
            }
        }
        // Pain: average of the last 7 days against the 7 days before.
        let now = Date.now
        func average(from: Int, to: Int) -> Double? {
            let start = now.addingTimeInterval(-Double(from) * 86_400), end = now.addingTimeInterval(-Double(to) * 86_400)
            let pains = sessions.filter { $0.date > start && $0.date <= end }.map { Double($0.pain) }
            return pains.isEmpty ? nil : pains.reduce(0, +) / Double(pains.count)
        }
        if let recent = average(from: 7, to: 0), let before = average(from: 14, to: 7), abs(recent - before) >= 0.5 {
            let format = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(1))
            items.append(Item(
                title: "Douleur", symbol: recent < before ? "arrow.down.right" : "arrow.up.right", color: .orange,
                text: Text("Votre douleur moyenne est passée de \(before.formatted(format)) à \(recent.formatted(format)) sur 10 cette semaine.")
            ))
        }
        // Regularity: sessions in the last 7 days.
        let week = sessions.filter { $0.date > now.addingTimeInterval(-7 * 86_400) }.count
        if week > 0 {
            items.append(Item(
                title: "Régularité", symbol: "calendar", color: .green,
                text: Text("Vous avez fait \(week) séances ces 7 derniers jours.")
            ))
        }
    }
}

private struct HighlightCard: View {
    let item: Highlights.Item

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(item.title, systemImage: item.symbol)
                .font(.headline)
                .foregroundStyle(item.color)
            item.text
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 26))
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
