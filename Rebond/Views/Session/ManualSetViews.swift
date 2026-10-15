import AVFoundation
import SwiftUI

/// An exercise the camera doesn't follow: the patient counts with the buttons.
/// Name and set in the navigation bar, standard glass buttons, the main action in the bottom bar.
struct ManualSetView: View {
    let name: String
    let targetReps: Int
    let setTitle: LocalizedStringKey
    let onFinish: (SetResult) -> Void

    @State private var count = 0
    @Environment(\.reportSetActivity) private var reportSetActivity
    @Environment(\.skipRequest) private var skipRequest

    var body: some View {
        VStack(spacing: 40) {
            Spacer()
            VStack(spacing: 4) {
                Text(count, format: .number)
                    .font(.system(size: 120, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text("sur \(targetReps) répétitions")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text("\(count) répétitions sur \(targetReps)"))
            GlassEffectContainer {
                HStack(spacing: 40) {
                    Button("Retirer une répétition", systemImage: "minus") { count = max(0, count - 1) }
                        .buttonStyle(.glass)
                        .disabled(count == 0)
                    Button("Ajouter une répétition", systemImage: "plus") { count += 1 }
                        .buttonStyle(.glassProminent)
                }
                .labelStyle(.iconOnly)
                .buttonBorderShape(.circle)
                .controlSize(.extraLarge)
                .font(.largeTitle)
            }
            Spacer()
            Label("Comptage manuel : cet exercice n'est pas suivi par la caméra.", systemImage: "hand.tap")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity)
        .safeAreaBar(edge: .bottom) {
            Button {
                onFinish(SetResult(completedReps: count))
            } label: {
                Text("Série terminée")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.extraLarge)
            .padding(.horizontal)
        }
        .animation(.default, value: count)
        .onChange(of: count) {
            if count > 0 { reportSetActivity() }
            WorkoutLiveActivity.shared.update(count: count)
        }
        .onChange(of: skipRequest) { if skipRequest != nil { onFinish(SetResult(completedReps: count)) } }
        .sensoryFeedback(.increase, trigger: count)
        .navigationTitle(name)
        .navigationSubtitle(Text(setTitle))
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// A held position (plank, stretch…): a timer the patient starts and can pause, with spoken cues.
struct HoldSetView: View {
    let name: String
    let targetSeconds: Int
    let setTitle: LocalizedStringKey
    let onFinish: (SetResult) -> Void

    private enum Phase { case ready, running, paused, done }

    @State private var phase = Phase.ready
    @State private var elapsed: TimeInterval = 0
    @State private var coach = Coach()
    @State private var muted = false
    @Environment(\.skipRequest) private var skipRequest
    @Environment(\.reportSetActivity) private var reportSetActivity

    private var remaining: Int { max(0, targetSeconds - Int(elapsed)) }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Text(Duration.seconds(remaining), format: .time(pattern: .minuteSecond))
                .font(.system(size: 96, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(countsDown: true))
                .accessibilityLabel(Text("\(remaining) secondes restantes"))
            ProgressView(value: min(1, elapsed / Double(targetSeconds)))
                .progressViewStyle(.linear)
                .padding(.horizontal, 32)
            Text(phase == .done ? "Terminé, bravo !" : "Tenez la position")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .safeAreaBar(edge: .bottom) {
            controls
                .controlSize(.extraLarge)
                .padding(.horizontal)
        }
        .animation(.default, value: remaining)
        .animation(.default, value: phase)
        .onChange(of: skipRequest) { if skipRequest != nil { onFinish(SetResult(heldSeconds: Int(elapsed))) } }
        .onChange(of: Int(elapsed)) { WorkoutLiveActivity.shared.update(count: Int(elapsed)) }
        .onChange(of: phase) { WorkoutLiveActivity.shared.setPaused(phase == .paused) }
        .navigationTitle(name)
        .navigationSubtitle(Text(setTitle))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(muted ? "Activer la voix" : "Couper la voix", systemImage: muted ? "speaker.slash.fill" : "speaker.wave.2.fill") {
                    muted.toggle()
                    coach.isMuted = muted
                }
            }
        }
        .task(id: phase) { await tick() }
        .onChange(of: phase) { if phase != .ready { reportSetActivity() } }
        .onAppear { try? AVAudioSession.sharedInstance().setActive(true) }
        .onDisappear { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
        .sensoryFeedback(.success, trigger: phase == .done)
    }

    /// One main action at a time, in the bottom bar; a second, quieter one when paused.
    @ViewBuilder
    private var controls: some View {
        switch phase {
        case .ready:
            Button {
                phase = .running
                coach.say("C'est parti, tenez la position")
            } label: {
                Label("Commencer", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        case .running:
            Button {
                phase = .paused
                coach.say("Pause")
            } label: {
                Label("Pause", systemImage: "pause.fill").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
        case .paused:
            GlassEffectContainer {
                VStack(spacing: 12) {
                    Button {
                        phase = .running
                        coach.say("On reprend")
                    } label: {
                        Label("Reprendre", systemImage: "play.fill").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent)
                    Button {
                        onFinish(SetResult(heldSeconds: Int(elapsed)))
                    } label: {
                        Label("Terminer la série", systemImage: "stop.fill").font(.headline).frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                }
            }
        case .done:
            Button {
                onFinish(SetResult(heldSeconds: targetSeconds))
            } label: {
                Label("Continuer", systemImage: "arrow.right").font(.headline).frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
        }
    }

    /// Counts while running; announces the last ten seconds and the end.
    private func tick() async {
        guard phase == .running else { return }
        var last = Date.now
        while phase == .running, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(200))
            let now = Date.now
            let before = remaining
            elapsed += now.timeIntervalSince(last)
            last = now
            if before > 10, remaining <= 10, targetSeconds > 15 {
                coach.say("Plus que 10 secondes")
            }
            if remaining == 0 {
                phase = .done
                coach.say("Terminé, bravo !")
            }
        }
    }
}
