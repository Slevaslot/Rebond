import Charts
import SwiftData
import SwiftUI

/// The follow-up part of the Aujourd'hui page, after Health: small cards side by side (colored title, value,
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

            TileCard(symbol: "calendar", title: "Régularité", color: .teal, trailing: Text("Cette semaine")) {
                detail = .history
            } value: {
                TileValue(value: "\(week.done)", unit: "sur \(week.planned) séances")
            } chart: {
                // One bar per day of the week: full and colored when a session was done.
                HealthBars(values: week.days.map { $0.done ? 1 : 0 }, maximum: 1, color: .teal,
                           highlighted: Set(week.days.indices.filter { week.days[$0].done }))
            }

            let amplitudes = progress.amplitude.last.map { last in progress.amplitude.filter { $0.series == last.series } } ?? []
            TileCard(symbol: "arrow.up.and.down", title: "Amplitude", color: .blue,
                     trailing: amplitudes.last.map { Text($0.date, format: .dateTime.day().month()) }) {
                detail = .amplitude
            } value: {
                if let last = amplitudes.last {
                    TileValue(value: "\(Int(last.value.rounded()))", unit: "% · \(last.series)")
                } else {
                    TileEmpty()
                }
            } chart: {
                let values = amplitudes.suffix(7).map(\.value)
                HealthBars(values: values, maximum: max(110, values.max() ?? 0), color: .blue, highlighted: [values.count - 1])
            }

            TileCard(symbol: "bandage.fill", title: "Douleur", color: .orange,
                     trailing: sessions.first.map { Text($0.date, format: .dateTime.day().month()) }) {
                detail = .pain
            } value: {
                if let last = progress.pain.last {
                    TileValue(value: "\(Int(last.value))", unit: "sur 10")
                } else {
                    TileEmpty()
                }
            } chart: {
                let values = progress.pain.suffix(7).map(\.value)
                HealthBars(values: values, maximum: 10, color: .orange, highlighted: [values.count - 1])
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

/// A card like Health's "Épinglés": colored symbol and title, a detail and a chevron in gray,
/// some air, then the value at bottom left and a few narrow bars at bottom right. The card opens the detail.
private struct TileCard<Value: View, ChartContent: View>: View {
    let symbol: String
    let title: LocalizedStringKey
    let color: Color
    let trailing: Text?
    let action: () -> Void
    @ViewBuilder let value: Value
    @ViewBuilder let chart: ChartContent

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Label(title, systemImage: symbol)
                        .font(.headline)
                        .foregroundStyle(color)
                    Spacer()
                    if let trailing {
                        trailing
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 34)
                HStack(alignment: .bottom) {
                    value
                    Spacer(minLength: 12)
                    chart
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
            .contentShape(.rect(cornerRadius: 24))
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
                .font(.system(size: 34, weight: .semibold))
                .monospacedDigit()
            Text(unit)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }
}

private struct TileEmpty: View {
    var body: some View {
        Text("Aucune donnée")
            .font(.title2.bold())
    }
}

/// Health's mini chart: a few narrow gray bars, rounded at the top, the highlighted ones in color.
private struct HealthBars: View {
    let values: [Double]
    let maximum: Double
    let color: Color
    let highlighted: Set<Int>
    private let height = 52.0

    var body: some View {
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                UnevenRoundedRectangle(topLeadingRadius: 2, topTrailingRadius: 2)
                    .fill(highlighted.contains(index) ? AnyShapeStyle(color) : AnyShapeStyle(Color(.systemGray3)))
                    .frame(width: 8, height: max(4, height * min(value / max(maximum, 0.001), 1)))
            }
        }
        .frame(height: height, alignment: .bottom)
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
