import Charts
import SwiftUI

/// Data for the progress charts: regularity per week, amplitude per camera exercise, pain per session.
nonisolated struct ProgressData {
    struct WeekCount: Identifiable {
        var id: Date { weekStart }
        let weekStart: Date
        let sessions: Int
    }

    struct Point: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
        let series: String
    }

    let weeks: [WeekCount]
    let amplitude: [Point]
    let pain: [Point]
    let sessionsPerWeek: Int

    init(sessions: [WeeklyReport.SessionData], sessionsPerWeek: Int, weeks count: Int = 6, now: Date = .now) {
        self.sessionsPerWeek = sessionsPerWeek
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        weeks = (0..<count).reversed().compactMap { offset in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek),
                  let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
            else { return nil }
            return WeekCount(weekStart: start, sessions: sessions.filter { $0.date >= start && $0.date < end }.count)
        }
        let sorted = sessions.sorted { $0.date < $1.date }
        amplitude = sorted.flatMap { session in
            session.results.compactMap { result in
                result.amplitude.map { Point(date: session.date, value: $0, series: result.name) }
            }
        }
        pain = sorted.map { Point(date: $0.date, value: Double($0.pain), series: "Douleur") }
    }
}

/// Sessions per week against the program's goal.
struct RegularityChart: View {
    let data: ProgressData

    var body: some View {
        Chart {
            ForEach(data.weeks) { week in
                BarMark(x: .value("Semaine", week.weekStart, unit: .weekOfYear), y: .value("Séances", week.sessions))
                    .foregroundStyle(week.sessions >= data.sessionsPerWeek ? Color.green : Color.accentColor)
            }
            RuleMark(y: .value("Objectif", data.sessionsPerWeek))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .foregroundStyle(.secondary)
                .annotation(position: .top, alignment: .leading) {
                    Text("Objectif : \(data.sessionsPerWeek)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .weekOfYear)) { _ in
                AxisValueLabel(format: .dateTime.day().month(.abbreviated))
            }
        }
        .accessibilityLabel("Séances par semaine")
    }
}

/// Usual amplitude per session (median of the measured repetitions), in percent of the target, for each exercise followed by the camera.
struct AmplitudeChart: View {
    let data: ProgressData

    var body: some View {
        Chart(data.amplitude) { point in
            LineMark(x: .value("Date", point.date, unit: .day), y: .value("Amplitude", point.value))
                .foregroundStyle(by: .value("Exercice", point.series))
                .symbol(by: .value("Exercice", point.series))
            RuleMark(y: .value("Objectif", 100))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.secondary)
        }
        .chartYScale(domain: 0...max(120, (data.amplitude.map(\.value).max() ?? 0) + 10))
        .chartYAxis {
            AxisMarks { value in
                AxisGridLine()
                AxisValueLabel { Text("\(value.as(Int.self) ?? 0) %") }
            }
        }
        .chartLegend(position: .bottom)
        .accessibilityLabel("Amplitude des mouvements, en pourcentage de l'objectif")
    }
}

/// Pain after each session, with the high-pain threshold.
struct PainChart: View {
    let data: ProgressData

    var body: some View {
        Chart {
            ForEach(data.pain) { point in
                LineMark(x: .value("Date", point.date, unit: .day), y: .value("Douleur", point.value))
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.orange)
                PointMark(x: .value("Date", point.date, unit: .day), y: .value("Douleur", point.value))
                    .foregroundStyle(.orange)
                    // A high-pain session stands out by its shape too, not only its colour.
                    .symbol(point.value >= Double(WeeklyReport.highPain) ? .triangle : .circle)
                    .symbolSize(point.value >= Double(WeeklyReport.highPain) ? 90 : 40)
            }
            RuleMark(y: .value("Douleur forte", WeeklyReport.highPain))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.orange.opacity(0.6))
                .annotation(position: .top, alignment: .leading) {
                    Text("Douleur forte (\(WeeklyReport.highPain))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
        }
        .chartYScale(domain: 0...10)
        .accessibilityLabel("Douleur après chaque séance, sur 10")
    }
}
