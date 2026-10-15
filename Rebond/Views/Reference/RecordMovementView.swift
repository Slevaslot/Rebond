import AVFoundation
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// At the physiotherapist's: the patient does the movement right, the iPhone films it, and Rebond learns it.
/// The iPhone stands where it will at home, the patient faces it; the physiotherapist starts and stops.
/// A video already filmed can be picked from Photos instead.
struct RecordMovementView: View {
    let onSave: (ReferenceMovement) -> Void

    private enum Stage: Equatable {
        case ready
        case countdown(Int)
        case recording
        case analyzing
        case review(UUID)
        case failed(LocalizedStringResource)
    }

    @Environment(\.dismiss) private var dismiss
    @State private var camera = ReferenceCamera()
    @State private var stage = Stage.ready
    @State private var movement: ReferenceMovement?
    @State private var name = ""
    @State private var recordingStart = Date.now
    @State private var pickedVideo: PhotosPickerItem?
    @State private var coach = Coach()
    /// Long enough for five slow repetitions; the physiotherapist usually stops before.
    private static let maximumDuration = 60.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch stage {
            case .ready, .countdown, .recording:
                CameraPreview(session: camera.session)
                    .ignoresSafeArea()
            case .analyzing, .failed:
                EmptyView()
            case .review:
                if let movement {
                    ReferenceFramesView(movement: movement, contentMode: .fit)
                        .ignoresSafeArea()
                }
            }
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
            if stage != .recording, stage != .analyzing {
                Button("Fermer", systemImage: "xmark") { cancel() }
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
        .onChange(of: pickedVideo) {
            guard let pickedVideo else { return }
            Task { await importVideo(pickedVideo) }
        }
        .task(id: stage == .recording) {
            // Stops on its own after a minute.
            guard stage == .recording else { return }
            try? await Task.sleep(for: .seconds(Self.maximumDuration))
            if stage == .recording { await stopRecording() }
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var topCard: some View {
        switch stage {
        case .ready:
            card(title: "Filmez le mouvement",
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
        case .analyzing:
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(.white)
                Text("Rebond apprend le mouvement…")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
            .padding(.top, 240)
        case .review:
            if let movement {
                card(title: "^[\(movement.repCount) répétition repérée](inflect: true)",
                     detail: "Pendant vos séances, cette vidéo avancera avec vous et Rebond comparera chaque répétition à celle-ci.")
            }
        case .failed(let reason):
            card(title: "Mouvement non reconnu", detail: reason)
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
        case .ready:
            VStack(spacing: 18) {
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
                PhotosPicker(selection: $pickedVideo, matching: .videos) {
                    Text("Choisir une vidéo")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        case .countdown:
            EmptyView()
        case .recording:
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
        case .analyzing:
            EmptyView()
        case .review:
            VStack(spacing: 12) {
                TextField("Nom de l'exercice", text: $name, prompt: Text("Nom de l'exercice, ex. : Fente arrière"))
                    .textInputAutocapitalization(.sentences)
                    .font(.headline)
                    .padding()
                    .glassEffect(in: .capsule)
                Button { save() } label: {
                    Text("Enregistrer l'exercice")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.extraLarge)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Filmer à nouveau") { retry() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
            }
        case .failed:
            Button { retry() } label: {
                Text("Filmer à nouveau")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.extraLarge)
        }
    }

    // MARK: Steps

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
            stage = .failed("La vidéo n'a pas pu être enregistrée. Réessayez.")
            return
        }
        coach.say("C'est noté")
        await learn(from: video, mirrored: false)
    }

    private func importVideo(_ item: PhotosPickerItem) async {
        stage = .analyzing
        guard let movie = try? await item.loadTransferable(type: PickedMovie.self) else {
            stage = .failed("Cette vidéo n'a pas pu être ouverte.")
            return
        }
        // Filmed by someone else, not like a mirror: turned over to look like the session's camera.
        await learn(from: movie.url, mirrored: true)
    }

    private func learn(from video: URL, mirrored: Bool) async {
        stage = .analyzing
        do {
            let learned = try await ReferenceStore.learn(from: video, name: "", mirrored: mirrored)
            movement = learned
            stage = .review(learned.id)
        } catch ReferenceError.noBody {
            stage = .failed("Rebond n'a pas bien vu le corps. Filmez de face, le corps entier dans l'image, pieds compris.")
        } catch {
            stage = .failed("Rebond n'a pas trouvé de mouvement répété. Restez immobile au début, puis faites 3 à 5 répétitions bien marquées.")
        }
    }

    private func save() {
        guard var movement else { return }
        movement.name = name.trimmingCharacters(in: .whitespaces)
        ReferenceStore.rename(movement.id, to: movement.name)
        self.movement = nil
        onSave(movement)
        dismiss()
    }

    private func retry() {
        if let movement { ReferenceStore.delete(movement.id) }
        movement = nil
        pickedVideo = nil
        stage = .ready
    }

    private func cancel() {
        if let movement { ReferenceStore.delete(movement.id) }
        dismiss()
    }
}

/// A video picked in Photos, copied where Rebond can read it.
private struct PickedMovie: Transferable {
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
