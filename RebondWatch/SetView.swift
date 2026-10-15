import SwiftUI
import TipKit

/// The set in progress, read at a glance during the movement: the count in a ring, the set, the heart rate,
/// and the two actions the patient can do without walking back to the iPhone.
struct SetView: View {
    @Environment(WatchModel.self) private var model
    let set: WatchSetState
    private let doubleTapTip = DoubleTapTip()
    /// The tip can still be shown (TipKit): it then takes the place of the set's line.
    @State private var doubleTapTipAvailable = false

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(.tint.opacity(0.25), lineWidth: 8)
                Circle()
                    .trim(from: 0, to: set.fraction)
                    .stroke(set.isSetComplete ? Color.green : Color.accentColor,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: set.count)
                VStack(spacing: 0) {
                    if set.isSetComplete {
                        Image(systemName: "checkmark")
                            .font(.title3.bold())
                            .foregroundStyle(.green)
                    }
                    Text(set.count, format: .number)
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.default, value: set.count)
                    Text(set.isHold ? "sur \(set.target) s" : "sur \(set.target)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .opacity(set.isPaused && !set.isWaitingToStart ? 0.4 : 1)
            .overlay {
                if set.isPaused, !set.isWaitingToStart {
                    Label("En pause", systemImage: "pause.fill")
                        .font(.headline)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityCount)

            if showsDoubleTapTip, doubleTapTipAvailable {
                TipView(doubleTapTip)
            } else {
                setLine
            }
        }
        .task {
            for await status in doubleTapTip.statusUpdates {
                doubleTapTipAvailable = status == .available
            }
        }
        .navigationTitle {
            Label(set.exercise, systemImage: set.symbol)
                .labelStyle(.titleOnly)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HeartRateLabel(recorder: model.recorder)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                // Double Tap (pinch twice) presses the main button: hands busy with the exercise, no need to
                // touch the screen.
                if set.canPause {
                    Button(pauseTitle, systemImage: set.isPaused ? "play.fill" : "pause.fill") {
                        model.togglePause()
                    }
                    .handGestureShortcut(.primaryAction, isEnabled: !set.isSetComplete)
                }
                Spacer()
                Button("Série suivante", systemImage: "forward.end.fill") {
                    model.nextSet()
                }
                .tint(set.isSetComplete ? .green : nil)
                .handGestureShortcut(.primaryAction, isEnabled: !set.canPause || set.isSetComplete)
            }
        }
        .disabled(!model.isPhoneReachable)
    }

    private var setLine: some View {
        Group {
            if set.isSetComplete {
                Text("Série terminée !")
            } else if let side = set.side {
                Text("Série \(set.set) sur \(set.totalSets) · \(side)")
            } else {
                Text("Série \(set.set) sur \(set.totalSets)")
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(set.isSetComplete ? .green : .secondary)
    }

    /// The iPhone counts (placement and calibration are over) and the set can be paused: the moment to learn
    /// Double Tap.
    private var showsDoubleTapTip: Bool {
        let set = self.set
        return set.canPause && !set.isPaused && !set.isSetComplete && set.count >= 2
    }

    private var pauseTitle: LocalizedStringKey {
        if set.isWaitingToStart { "Commencer" } else if set.isPaused { "Reprendre" } else { "Pause" }
    }

    private var accessibilityCount: Text {
        let base = set.isHold
            ? Text("\(set.count) secondes sur \(set.target)")
            : Text("\(set.count) répétitions sur \(set.target)")
        return set.isPaused ? Text("\(base), en pause") : base
    }
}

#Preview {
    NavigationStack {
        SetView(set: WatchSetState(exercise: "Squat", symbol: "figure.strengthtraining.functional", set: 2, totalSets: 3,
                                   count: 4, target: 10, isHold: false, isPaused: false, canPause: true))
    }
    .environment(WatchModel.shared)
}
