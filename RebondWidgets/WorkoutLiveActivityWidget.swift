import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

/// The set in progress on the Lock Screen and in the Dynamic Island: exercise, "4 / 10", "Série 2 sur 3".
/// Started and updated by the app (`Rebond/Workout/WorkoutLiveActivity.swift`). The small family also shows it
/// in the Apple Watch Smart Stack, without any watch app.
struct WorkoutLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: WorkoutActivityAttributes.self) { context in
            LockScreenView(state: context.state)
                .activityBackgroundTint(nil)
                .activitySystemActionForegroundColor(.accentColor)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ExerciseSymbol(symbol: state.symbol, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    CountText(state: state)
                        .font(.title.bold())
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(state.exercise)
                        .font(.headline)
                        .lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        ProgressView(value: state.fraction)
                            .tint(.accentColor)
                        SetText(state: state)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        SessionControls(state: state)
                    }
                }
            } compactLeading: {
                Image(systemName: state.symbol)
                    .foregroundStyle(Color.accentColor)
            } compactTrailing: {
                CountText(state: state, compact: true)
                    .font(.caption.bold())
            } minimal: {
                Gauge(value: state.fraction) {
                    Image(systemName: state.symbol)
                } currentValueLabel: {
                    Text("\(state.count)")
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .tint(.accentColor)
            }
            .keylineTint(.accentColor)
        }
        .supplementalActivityFamilies([.small])
    }
}

private struct LockScreenView: View {
    let state: WorkoutActivityAttributes.ContentState
    @Environment(\.activityFamily) private var family

    var body: some View {
        if family == .small {
            watchView
        } else {
            lockScreenView
        }
    }

    /// On the Apple Watch: the exercise and the count, large enough to read at arm's length.
    private var watchView: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: state.symbol)
                    .foregroundStyle(Color.accentColor)
                Text(state.exercise)
                    .font(.caption.bold())
                    .lineLimit(1)
            }
            CountText(state: state)
                .font(.system(size: 28, weight: .bold, design: .rounded))
            SetText(state: state)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .accessibilityElement(children: .combine)
    }

    private var lockScreenView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ExerciseSymbol(symbol: state.symbol, size: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text(state.exercise)
                        .font(.headline)
                        .lineLimit(1)
                    SetText(state: state)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                CountText(state: state)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
            }
            ProgressView(value: state.fraction)
                .tint(.accentColor)
            SessionControls(state: state)
        }
        .padding(16)
    }
}

/// Pause and next set without unlocking the iPhone: the same as the buttons of the session screen.
private struct SessionControls: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        HStack {
            if state.canPause {
                Button(intent: ToggleSessionPauseIntent()) {
                    Label(state.isPaused ? (state.count == 0 ? "Commencer" : "Reprendre") : "Pause",
                          systemImage: state.isPaused ? "play.fill" : "pause.fill")
                        .frame(maxWidth: .infinity)
                }
            }
            Button(intent: NextSetIntent()) {
                Label("Série suivante", systemImage: "forward.end.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .font(.subheadline.weight(.semibold))
        .buttonStyle(.bordered)
        .tint(.accentColor)
    }
}

private struct ExerciseSymbol: View {
    let symbol: String
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5))
            .foregroundStyle(Color.accentColor)
            .frame(width: size, height: size)
            .background(Color.accentColor.opacity(0.18), in: .circle)
    }
}

/// "4 / 10", or "18 / 30 s" for a hold.
private struct CountText: View {
    let state: WorkoutActivityAttributes.ContentState
    var compact = false

    var body: some View {
        Group {
            if state.isHold {
                Text(compact ? "\(state.count) s" : "\(state.count) / \(state.target) s")
            } else {
                Text(compact ? "\(state.count)/\(state.target)" : "\(state.count) / \(state.target)")
            }
        }
        .monospacedDigit()
        .contentTransition(.numericText(value: Double(state.count)))
    }
}

/// "Série 2 sur 3", or "En pause" (not before a held set's timer starts).
private struct SetText: View {
    let state: WorkoutActivityAttributes.ContentState

    var body: some View {
        if state.isPaused, state.count > 0 {
            Label("En pause", systemImage: "pause.fill")
        } else {
            Text("Série \(state.set) sur \(state.totalSets)")
        }
    }
}

// MARK: - Previews

private extension WorkoutActivityAttributes {
    static let preview = WorkoutActivityAttributes(startedAt: .now)
}

private extension WorkoutActivityAttributes.ContentState {
    static let squat = Self(exercise: "Squat", symbol: "figure.strengthtraining.functional", set: 2, totalSets: 3,
                            count: 4, target: 10, isHold: false, isPaused: false)
    static let plank = Self(exercise: "Gainage", symbol: "timer", set: 1, totalSets: 3,
                            count: 18, target: 30, isHold: true, isPaused: false)
    static let paused = Self(exercise: "Squat", symbol: "figure.strengthtraining.functional", set: 2, totalSets: 3,
                             count: 7, target: 10, isHold: false, isPaused: true)
}

#Preview("Écran verrouillé", as: .content, using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState.squat
    WorkoutActivityAttributes.ContentState.plank
    WorkoutActivityAttributes.ContentState.paused
}

#Preview("Dynamic Island", as: .dynamicIsland(.expanded), using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState.squat
}

#Preview("Dynamic Island compacte", as: .dynamicIsland(.compact), using: WorkoutActivityAttributes.preview) {
    WorkoutLiveActivityWidget()
} contentStates: {
    WorkoutActivityAttributes.ContentState.squat
}
