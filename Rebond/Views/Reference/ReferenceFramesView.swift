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
        .task(id: movement.id) {
            let id = movement.id, count = movement.frameCount
            frames = await Task.detached(priority: .userInitiated) {
                (0..<count).compactMap { UIImage(contentsOfFile: ReferenceStore.frameURL(id, $0).path()) }
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
