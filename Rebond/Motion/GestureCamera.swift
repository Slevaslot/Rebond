import AVFoundation
import Foundation
import Observation
import Synchronization

/// The front camera without any preview, only to see the patient's hand signs on the session's screens that
/// don't film them: the film of a filmed exercise, a held set. Each sign goes through `SessionRemote`, like
/// the buttons, Siri and the watch.
/// Starts only if camera access is already granted: these screens never ask for it.
@MainActor @Observable
final class GestureCamera {
    /// The last sign that did something, for a moment: the screen confirms it.
    private(set) var recognized: HandGesture?
    /// The camera is looking for signs.
    private(set) var isRunning = false
    /// The set is paused: any open hand of the patient resumes it.
    var isPaused = false {
        didSet { processor.isPaused.withLock { $0 = isPaused } }
    }

    @ObservationIgnored private let captureSession = AVCaptureSession()
    @ObservationIgnored private let processor = GestureFrameProcessor()
    @ObservationIgnored private let queue = DispatchQueue(label: "rebond.gestures")
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    @ObservationIgnored private var clearing: Task<Void, Never>?

    init() {
        processor.onGesture = { [weak self] gesture in
            Task { @MainActor [self] in self?.handle(gesture) }
        }
    }

    /// Camera access was granted before (by a set filmed by the camera, or the scan).
    static var isAuthorized: Bool {
        AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    }

    func start() {
        guard Self.isAuthorized, !isRunning else { return }
        if captureSession.inputs.isEmpty {
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
                  let input = try? AVCaptureDeviceInput(device: camera)
            else { return }
            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(processor, queue: queue)

            captureSession.beginConfiguration()
            // As in the camera sets: hands are small at 2–3 m, 720p keeps them readable.
            if captureSession.canSetSessionPreset(.hd1280x720) { captureSession.sessionPreset = .hd1280x720 }
            if captureSession.canAddInput(input) { captureSession.addInput(input) }
            if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
            captureSession.commitConfiguration()

            // Upright frames whatever the phone orientation, so Vision sees a standing body.
            nonisolated(unsafe) let connection = output.connection(with: .video)
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { coordinator, _ in
                connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
            }
            rotationCoordinator = coordinator
        }
        nonisolated(unsafe) let session = captureSession
        queue.async { session.startRunning() }
        isRunning = true
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        clearing?.cancel()
        nonisolated(unsafe) let session = captureSession
        queue.async { session.stopRunning() }
    }

    private func handle(_ gesture: HandGesture) {
        guard isRunning else { return }
        let action = SessionRemote.shared.send(SessionCommand(gesture), from: .gesture)
        if case .ignored = action { return }
        recognized = gesture
        clearing?.cancel()
        clearing = Task {
            try? await Task.sleep(for: .seconds(1.5))
            if !Task.isCancelled { recognized = nil }
        }
    }
}

/// Receives the frames on the camera's queue, about 10 times per second: the body, then the signs.
/// Its state is only touched on that queue.
nonisolated final class GestureFrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onGesture: (@Sendable (HandGesture) -> Void)?
    /// Set from the main thread.
    let isPaused = Mutex(false)

    private let analyzer = PoseAnalyzer()
    private var gestures = HandGestureDetector()
    private var motion = BodyMotion()
    private var lastAnalysisTime = CMTime.zero
    /// 10 analyses per second are enough for signs held more than half a second.
    private let minAnalysisInterval = CMTime(value: 1, timescale: 10)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let time = sampleBuffer.presentationTimeStamp
        guard time - lastAnalysisTime >= minAnalysisInterval else { return }
        lastAnalysisTime = time
        let frame = analyzer.analyze(pixelBuffer)
        let isMoving = motion.update(frame.measure)
        if let gesture = gestures.process(pixelBuffer, body: frame.skeleton, isMoving: isMoving,
                                          isPaused: isPaused.withLock { $0 }) {
            onGesture?(gesture)
        }
    }
}

/// Whether the body itself moves (walking, a repetition), from the neck and the hips: not the arms,
/// which make the signs.
nonisolated struct BodyMotion {
    private var previous: [CGPoint?] = []
    /// Smoothed displacement per analysis, in torso lengths.
    private(set) var speed = 0.0
    /// Above this, at 10 analyses per second (a fifth of a torso per second), the body moves.
    static let threshold = 0.02

    mutating func update(_ measure: PoseMeasure?) -> Bool {
        guard let measure, measure.torsoLength > 0 else {
            // Not seen: the patient may be close to the phone. Start again when seen.
            previous = []
            speed = 0
            return false
        }
        let points: [CGPoint?] = [measure.neck, measure.hips]
        defer { previous = points }
        guard previous.count == points.count else { return false }
        let moves = zip(previous, points).compactMap { before, now -> Double? in
            guard let before, let now else { return nil }
            return hypot(now.x - before.x, now.y - before.y) / measure.torsoLength
        }
        guard !moves.isEmpty else { return speed > Self.threshold }
        let move = moves.reduce(0, +) / Double(moves.count)
        speed = speed * 0.6 + move * 0.4
        return speed > Self.threshold
    }
}
