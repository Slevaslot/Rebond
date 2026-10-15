import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// At the physiotherapist's: the iPhone films the patient doing each exercise right, one take per exercise.
/// The iPhone stands where it will at home, the patient faces it; the physiotherapist starts and stops.
/// Only films: the séance screen analyzes the videos.
struct RecordMovementView: View {
    /// Several takes in a row, one per exercise; otherwise one take (to replace an exercise's video).
    var allowsSeveral = true
    let onFinish: ([URL]) -> Void

    private enum Stage: Equatable {
        case ready
        case countdown(Int)
        case recording
        /// A take is saved: next one, or done.
        case saved
        case failed
    }

    @Environment(\.dismiss) private var dismiss
    @State private var camera = ReferenceCamera()
    @State private var stage = Stage.ready
    @State private var takes: [URL] = []
    @State private var recordingStart = Date.now
    @State private var coach = Coach()
    /// Long enough for five slow repetitions; the physiotherapist usually stops before.
    private static let maximumDuration = 60.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()
                .opacity(stage == .saved ? 0.4 : 1)
            if case .countdown(let seconds) = stage {
                Text("\(seconds)")
                    .font(.system(size: 140, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .shadow(radius: 12)
            }
        }
        .overlay(alignment: .top) { topCard.padding() }
        .overlay(alignment: .bottom) { controls.padding() }
        .overlay(alignment: .topLeading) {
            if stage == .ready || stage == .saved || stage == .failed {
                Button(takes.isEmpty ? "Annuler" : "Terminé", systemImage: "xmark") { finish() }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 44, height: 44)
                    .glassEffect(in: .circle)
                    .padding()
                    .padding(.top, 60)
            }
        }
        .animation(.smooth, value: stage)
        .task { await camera.start() }
        .onDisappear { camera.stop() }
        .task(id: stage == .recording) {
            // Stops on its own after a minute.
            guard stage == .recording else { return }
            try? await Task.sleep(for: .seconds(Self.maximumDuration))
            if stage == .recording { await stopRecording() }
        }
    }

    @ViewBuilder
    private var topCard: some View {
        switch stage {
        case .ready:
            card(title: takes.isEmpty ? "Filmez un exercice" : "Exercice suivant",
                 detail: "Posez l'iPhone debout à 2 ou 3 mètres, comme pour vos séances. Restez immobile au début, puis faites 3 à 5 répétitions bien faites avec votre kiné.")
        case .countdown:
            card(title: "Mettez-vous en position de départ", detail: "Restez immobile")
        case .recording:
            TimelineView(.periodic(from: recordingStart, by: 1)) { timeline in
                Label {
                    Text(Duration.seconds(timeline.date.timeIntervalSince(recordingStart)),
                         format: .time(pattern: .minuteSecond))
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "record.circle.fill").foregroundStyle(.red)
                }
                .font(.headline)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .glassEffect(in: .capsule)
            }
            .padding(.top, 56)
        case .saved:
            card(title: "^[\(takes.count) exercice filmé](inflect: true)",
                 detail: "Filmez l'exercice suivant, ou terminez : Rebond analyse les vidéos.")
        case .failed:
            card(title: "La vidéo n'a pas pu être enregistrée", detail: "Réessayez.")
        }
    }

    private func card(title: LocalizedStringResource, detail: LocalizedStringResource) -> some View {
        VStack(spacing: 6) {
            Text(title).font(.headline)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding()
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 26))
        .padding(.top, 56)
    }

    @ViewBuilder
    private var controls: some View {
        switch stage {
        case .ready, .failed:
            recordButton
        case .countdown:
            EmptyView()
        case .recording:
            ZStack {
                Button { Task { await stopRecording() } } label: {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(.red)
                        .frame(width: 34, height: 34)
                        .frame(width: 66, height: 66)
                        .padding(6)
                        .overlay(Circle().stroke(.white, lineWidth: 5))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Arrêter de filmer"))
                Button("Recommencer", systemImage: "arrow.counterclockwise") { Task { await restartRecording() } }
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                    .frame(width: 56, height: 56)
                    .glassEffect(in: .circle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 24)
            }
        case .saved:
            VStack(spacing: 12) {
                Button { startCountdown() } label: {
                    Label("Filmer l'exercice suivant", systemImage: "video.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                Button { redoLastTake() } label: {
                    Label("Refilmer cet exercice", systemImage: "arrow.counterclockwise")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                Button { finish() } label: {
                    Text("Terminé")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
            }
        }
    }

    private var recordButton: some View {
        Button { startCountdown() } label: {
            Circle()
                .fill(.red)
                .frame(width: 66, height: 66)
                .padding(6)
                .overlay(Circle().stroke(.white, lineWidth: 5))
        }
        .buttonStyle(.plain)
        .disabled(camera.isUnavailable)
        .accessibilityLabel(Text("Commencer à filmer"))
    }

    /// Five seconds to walk to the place and stand still, the last three said aloud.
    private func startCountdown() {
        Task {
            for seconds in [5, 4, 3, 2, 1] {
                stage = .countdown(seconds)
                if seconds <= 3 { coach.say("\(seconds)") }
                try? await Task.sleep(for: .seconds(1))
            }
            camera.startRecording()
            recordingStart = .now
            stage = .recording
            coach.say("Restez immobile")
            try? await Task.sleep(for: .seconds(1.5))
            if stage == .recording { coach.say("Allez-y, faites trois à cinq répétitions") }
        }
    }

    private func stopRecording() async {
        guard let video = await camera.stopRecording() else {
            stage = .failed
            return
        }
        coach.say("C'est noté")
        takes.append(video)
        if allowsSeveral {
            stage = .saved
        } else {
            finish()
        }
    }

    /// Throws the take being filmed away and films it again, after the countdown.
    private func restartRecording() async {
        if let video = await camera.stopRecording() { try? FileManager.default.removeItem(at: video) }
        startCountdown()
    }

    /// Throws the last saved take away and films that exercise again.
    private func redoLastTake() {
        if let video = takes.popLast() { try? FileManager.default.removeItem(at: video) }
        startCountdown()
    }

    private func finish() {
        onFinish(takes)
        dismiss()
    }
}

/// A video picked in Photos, copied where Rebond can read it.
struct PickedMovie: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let copy = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).\(received.file.pathExtension)")
            try FileManager.default.copyItem(at: received.file, to: copy)
            return PickedMovie(url: copy)
        }
    }
}

// MARK: - Camera

/// The front camera, filming like a mirror, as during the sessions. No sound is recorded.
@Observable
final class ReferenceCamera: NSObject, AVCaptureFileOutputRecordingDelegate {
    @ObservationIgnored let session = AVCaptureSession()
    private(set) var isUnavailable = false
    @ObservationIgnored private let output = AVCaptureMovieFileOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "rebond.reference-camera")
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    @ObservationIgnored private var finished: CheckedContinuation<URL?, Never>?

    func start() async {
        guard session.inputs.isEmpty else { return }
        guard await AVCaptureDevice.requestAccess(for: .video),
              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera)
        else {
            isUnavailable = true
            return
        }
        session.beginConfiguration()
        if session.canSetSessionPreset(.hd1280x720) { session.sessionPreset = .hd1280x720 }
        if session.canAddInput(input) { session.addInput(input) }
        if session.canAddOutput(output) { session.addOutput(output) }
        session.commitConfiguration()

        nonisolated(unsafe) let connection = output.connection(with: .video)
        if let connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { coordinator, _ in
            connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        }
        rotationCoordinator = coordinator

        nonisolated(unsafe) let session = session
        queue.async { session.startRunning() }
    }

    func stop() {
        if output.isRecording { output.stopRecording() }
        nonisolated(unsafe) let session = session
        queue.async { session.stopRunning() }
    }

    func startRecording() {
        let url = URL.temporaryDirectory.appending(path: "\(UUID().uuidString).mov")
        output.startRecording(to: url, recordingDelegate: self)
    }

    /// The video, once written; nil if it failed.
    func stopRecording() async -> URL? {
        guard output.isRecording else { return nil }
        return await withCheckedContinuation { continuation in
            finished = continuation
            output.stopRecording()
        }
    }

    nonisolated func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo url: URL,
                                from connections: [AVCaptureConnection], error: Error?) {
        // Stopping normally also reports an "error" saying the recording finished successfully.
        let success = error == nil || ((error as NSError?)?.userInfo[AVErrorRecordingSuccessfullyFinishedKey] as? Bool ?? false)
        Task { @MainActor in
            finished?.resume(returning: success ? url : nil)
            finished = nil
        }
    }
}

/// What the camera sees, filling the screen.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
