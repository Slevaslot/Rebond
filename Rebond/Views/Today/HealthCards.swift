import Charts
import SwiftData
import SwiftUI

/// The follow-up part of the Résumé page, after Health: small cards side by side (colored title, value,
/// one per row with a mini chart and a chevron. Each card opens its detail in a sheet.
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

            // Régularité and the history are one card: this week at a glance, the sessions in the detail.
            Button { detail = .history } label: {
                WeekCard(week: week, showsChevron: true)
            }
            .buttonStyle(.plain)

            TileCard(title: "Amplitude", color: .blue, trailing: progress.amplitude.last.map { Text($0.series) }) {
                detail = .amplitude
            } value: {
                if let last = progress.amplitude.last {
                    TileValue(value: "\(Int(last.value.rounded()))", unit: "%")
                } else {
                    TileEmpty()
                }
            } chart: {
                if let last = progress.amplitude.last {
                    MiniLine(values: progress.amplitude.filter { $0.series == last.series }.map(\.value), color: .blue)
                }
            }
            TileCard(title: "Douleur", color: .orange, trailing: Text("Dernière séance")) {
                detail = .pain
            } value: {
                if let last = progress.pain.last {
                    TileValue(value: "\(Int(last.value))", unit: "/ 10")
                } else {
                    TileEmpty()
                }
            } chart: {
                MiniBars(values: progress.pain.suffix(8).map(\.value), maximum: 10, color: .orange)
            }

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

// MARK: - Tiles

/// A full-width Health card: colored title, a detail and a chevron, then the value with a small chart beside it.
/// The whole card opens the detail.
private struct TileCard<Value: View, ChartContent: View>: View {
    let title: LocalizedStringKey
    let color: Color
    let trailing: Text?
    let action: () -> Void
    @ViewBuilder let value: Value
    @ViewBuilder let chart: ChartContent

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(color)
                    Spacer()
                    if let trailing {
                        trailing
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                HStack(alignment: .bottom, spacing: 16) {
                    value
                    Spacer(minLength: 0)
                    chart
                        .frame(width: 130, height: 48)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
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
        .chartYScale(domain: (values.min() ?? 0) - 5 ... (values.max() ?? 1) + 5)
        .accessibilityHidden(true)
    }
}

private struct MiniBars: View {
    let values: [Double]
    let maximum: Double
    let color: Color
    /// Every bar in color; otherwise only the last one, as Health does for "today".
    var highlightAll = false

    var body: some View {
        Chart(Array(values.enumerated()), id: \.offset) { item in
            BarMark(x: .value("n", item.offset), y: .value("v", max(item.element, 0.3)))
                .foregroundStyle(highlightAll || item.offset == values.count - 1 ? color : Color(.tertiaryLabel))
                .clipShape(.rect(cornerRadius: 2))
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartYScale(domain: 0...maximum)
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
