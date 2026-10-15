import SwiftUI

/// One screen at a time, following the session on the iPhone.
struct ContentView: View {
    @Environment(WatchModel.self) private var model

    var body: some View {
        NavigationStack {
            Group {
                switch model.stage {
                case .idle:
                    TodayView(snapshot: model.snapshot)
                case .session:
                    if let set = model.set {
                        SetView(set: set)
                    } else {
                        WaitingView(title: "Placez-vous devant l'iPhone",
                                    detail: "La série apparaîtra ici.",
                                    systemImage: "figure.stand")
                    }
                case .painOnPhone:
                    WaitingView(title: "Séries terminées !",
                                detail: "Indiquez votre douleur sur l'iPhone.",
                                systemImage: "checkmark.circle.fill")
                case .finished(let summary):
                    SummaryView(summary: summary)
                }
            }
            .animation(.default, value: model.stage)
        }
    }
}

/// Before the session: what today holds, started on the iPhone.
struct TodayView: View {
    let snapshot: WidgetSnapshot

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if snapshot.hasProgram {
                    let week = snapshot.week(containing: .now)
                    if snapshot.isDone(on: .now) {
                        Label("Séance faite, bravo !", systemImage: "checkmark.seal.fill")
                            .font(.headline)
                            .foregroundStyle(.green)
                    } else {
                        Text(snapshot.sessionTitle(on: .now))
                            .font(.headline)
                        Text("\(snapshot.exercises.count) exercices · \(snapshot.estimatedMinutes) min")
                            .foregroundStyle(.secondary)
                    }
                    Gauge(value: week.fraction) {
                        Text("Cette semaine")
                    } currentValueLabel: {
                        Text("\(week.done) / \(week.planned)")
                    }
                    .gaugeStyle(.accessoryLinearCapacity)
                    .tint(.accentColor)
                    .accessibilityValue(Text("\(week.done) séances sur \(week.planned) cette semaine"))
                    Label("Lancez la séance sur votre iPhone : votre montre suivra vos séries.", systemImage: "iphone")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Créez votre programme sur l'iPhone.", systemImage: "iphone")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Rebond")
    }
}

/// A message while the iPhone does the work (placement, pain).
struct WaitingView: View {
    @Environment(WatchModel.self) private var model
    let title: LocalizedStringKey
    let detail: LocalizedStringKey
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .symbolEffect(.pulse)
            Text(title)
                .font(.headline)
            Text(detail)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HeartRateLabel(recorder: model.recorder)
            }
        }
    }
}

/// The session was saved on the iPhone.
struct SummaryView: View {
    @Environment(WatchModel.self) private var model
    let summary: WorkoutRecorder.Summary?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label("Séance terminée, bravo !", systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .foregroundStyle(.green)
                if let summary {
                    LabeledContent("Durée") {
                        Text(Duration.seconds(summary.duration), format: .time(pattern: .minuteSecond))
                    }
                    if let calories = summary.calories {
                        LabeledContent("Calories", value: "\(Int(calories.rounded())) kcal")
                    }
                    if let heartRate = summary.averageHeartRate {
                        LabeledContent("Cœur moyen", value: "\(Int(heartRate.rounded())) bpm")
                    }
                    Label("Enregistrée dans Santé", systemImage: "heart.fill")
                        .font(.footnote)
                        .foregroundStyle(.pink)
                }
                Button("OK") { model.dismissSummary() }
                    .padding(.top, 4)
            }
        }
        .navigationTitle("Rebond")
    }
}

/// The latest heart rate, while the workout runs.
struct HeartRateLabel: View {
    let recorder: WorkoutRecorder

    var body: some View {
        if let heartRate = recorder.heartRate {
            Label {
                Text(Int(heartRate.rounded()), format: .number)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } icon: {
                Image(systemName: "heart.fill")
                    .foregroundStyle(.pink)
                    .symbolEffect(.pulse)
            }
            .font(.footnote.weight(.semibold))
            .accessibilityLabel(Text("Fréquence cardiaque : \(Int(heartRate.rounded())) battements par minute"))
        }
    }
}
