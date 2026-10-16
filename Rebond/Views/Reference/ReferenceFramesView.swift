import AVKit
import SwiftUI

/// The clearest repetition of a filmed movement, image by image: played in a loop, or following the patient
/// (`progress` 0 at rest, 1 at the end of the movement), so the video moves as they move.
struct ReferenceFramesView: View {
    let movement: ReferenceMovement
    /// Following the patient; nil plays the repetition in a loop.
    var progress: Double?
    var contentMode: ContentMode = .fill

    @State private var frames: [UIImage] = []
    @State private var loopStart = Date.now
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if frames.isEmpty {
                Color.black
            } else if let progress {
                image(frames[index(for: progress)])
            } else {
                TimelineView(.animation(paused: reduceMotion)) { timeline in
                    image(frames[loopIndex(at: timeline.date)])
                }
            }
        }
        .task(id: "\(movement.id)-\(movement.revision ?? 0)") {
            let id = movement.id, count = movement.frameCount
            frames = await Task.detached(priority: .userInitiated) {
                (0..<count).compactMap { UIImage(contentsOfFile: ReferenceStore.frameURL(id, $0).path(percentEncoded: false)) }
            }.value
        }
        .accessibilityElement()
        .accessibilityLabel(Text("Vidéo du mouvement filmé chez votre kiné"))
    }

    private func image(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: contentMode)
    }

    /// The images from rest to the end of the movement: the way back looks like the way there.
    private func index(for progress: Double) -> Int {
        let peak = min(movement.peakFrame, frames.count - 1)
        return min(peak, max(0, Int((progress * Double(peak)).rounded())))
    }

    /// At the video's pace, with a short pause at rest between repetitions.
    private func loopIndex(at date: Date) -> Int {
        let position = Int(max(0, date.timeIntervalSince(loopStart)) * 15) % (frames.count + 8)
        return position < frames.count ? position : 0
    }
}

/// The whole video filmed at the physiotherapist's, to watch again.
struct ReferenceVideoSheet: View {
    let movement: ReferenceMovement
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            VideoPlayer(player: player)
                .ignoresSafeArea(edges: .bottom)
                .background(Color.black)
                .navigationTitle(movement.name)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    Button("Fermer", systemImage: "xmark", role: .close) { dismiss() }
                }
        }
        .onAppear {
            let player = AVPlayer(url: ReferenceStore.videoURL(movement.id))
            self.player = player
            player.play()
        }
        .onDisappear { player?.pause() }
    }
}

/// Before a filmed exercise: the patient's own video from the physiotherapist's, full screen and with its sound
/// (the physiotherapist's advice), as the example to follow. Then "Je suis prêt".
struct ReferenceExampleView: View {
    let movement: ReferenceMovement
    let setTitle: LocalizedStringKey
    /// The other side of an exercise done on both: the film shown as in a mirror.
    var isMirrored = false
    let onReady: () -> Void

    @State private var player: AVQueuePlayer?
    @State private var looper: AVPlayerLooper?
    /// The patient may already stand back from the phone: a thumbs up goes on, without walking back.
    @State private var gestures = GestureCamera()
    @Environment(\.skipRequest) private var skipRequest

    var body: some View {
        ZStack {
            Color.black
            if let player {
                PlayerLayerView(player: player)
                    .scaleEffect(x: isMirrored ? -1 : 1, y: 1)
            }
        }
        .ignoresSafeArea()
        .overlay(alignment: .top) {
            VStack(spacing: 6) {
                Text("Regardez l'exemple").font(.headline)
                Text("Votre mouvement, filmé chez votre kiné. Vous allez le refaire de la même façon.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .multilineTextAlignment(.center)
            .padding()
            .frame(maxWidth: .infinity)
            .glassEffect(in: .rect(cornerRadius: 26))
            .padding()
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 12) {
                if gestures.isRunning {
                    GestureLegend(items: [
                        .init(gesture: .thumbsUp, title: "Je suis prêt"),
                        .init(gesture: .crossedArms, title: "Bras croisés : terminer"),
                    ], recognized: gestures.recognized)
                }
                Button(action: onReady) {
                    Text("Je suis prêt")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
            }
            .padding()
        }
        .navigationTitle(movement.name)
        .navigationSubtitle(Text(setTitle))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let item = AVPlayerItem(url: ReferenceStore.videoURL(movement.id))
            let player = AVQueuePlayer()
            looper = AVPlayerLooper(player: player, templateItem: item)
            self.player = player
            try? AVAudioSession.sharedInstance().setCategory(.playback)
            player.play()
            gestures.start()
        }
        .onDisappear {
            player?.pause()
            looper = nil
            gestures.stop()
        }
        .sessionScreen(.example)
        // A thumbs up, Siri, the watch or the Passer menu: the patient is ready.
        .onChange(of: skipRequest) { if skipRequest != nil { onReady() } }
    }
}

/// A video without controls, filling its frame.
private struct PlayerLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerView {
        let view = PlayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerView, context: Context) {
        uiView.playerLayer.player = player
    }

    final class PlayerView: UIView {
        override class var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}
