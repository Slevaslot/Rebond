import AVFoundation
import Observation
import Synchronization

/// Runs the camera and exposes the live state of a guided session.
@Observable
final class MotionSession {
    enum Phase {
        /// Waiting for the patient to stand still so the resting position can be measured.
        case calibrating
        case active
        case finished
    }

    struct Feedback: Identifiable, Equatable {
        let id = UUID()
        let message: LocalizedStringResource
        let isPositive: Bool

        static func == (lhs: Feedback, rhs: Feedback) -> Bool { lhs.id == rhs.id }
    }

    let exercise: CatalogExercise
    let targetReps: Int
    let captureSession = AVCaptureSession()

    private(set) var camera: AVCaptureDevice?
    private(set) var cameraUnavailable = false
    private(set) var phase = Phase.calibrating
    private(set) var bodyVisible = false
    private(set) var skeleton: PoseSkeleton?
    /// 0 at rest, 1 when the target depth is reached.
    private(set) var depthProgress = 0.0
    private(set) var repCount = 0
    private(set) var incompleteCount = 0
    private(set) var feedback: Feedback?
    var isMuted = false {
        didSet { coach.isMuted = isMuted }
    }

    @ObservationIgnored private let coach = Coach()
    @ObservationIgnored private let processor: FrameProcessor
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "rebond.video")
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    /// Consecutive frames without a body, so a single missed detection doesn't flash the placement hint.
    @ObservationIgnored private var missedFrames = 0
    @ObservationIgnored private var feedbackDismissal: Task<Void, Never>?

    init(exercise: CatalogExercise, targetReps: Int) {
        self.exercise = exercise
        self.targetReps = targetReps
        processor = FrameProcessor(exercise: exercise)
        processor.onSkeleton = { [weak self] skeleton in
            Task { @MainActor [self] in self?.apply(skeleton) }
        }
        processor.onUpdate = { [weak self] update in
            Task { @MainActor [self] in self?.apply(update) }
        }
    }

    func start() async {
        guard captureSession.inputs.isEmpty else { return }
        guard await AVCaptureDevice.requestAccess(for: .video),
              let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera)
        else {
            cameraUnavailable = true
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(processor, queue: videoQueue)

        captureSession.beginConfiguration()
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
        captureSession.commitConfiguration()

        // Mirror the analyzed frames like the preview, so the skeleton lines up with the patient.
        nonisolated(unsafe) let connection = output.connection(with: .video)
        if let connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }

        // Keep frames upright whatever the phone orientation, so Vision sees a standing body.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelCapture, options: [.initial, .new]) { coordinator, _ in
            connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelCapture
        }
        rotationCoordinator = coordinator
        self.camera = camera

        nonisolated(unsafe) let session = captureSession
        videoQueue.async { session.startRunning() }
    }

    func stop() {
        nonisolated(unsafe) let session = captureSession
        videoQueue.async { session.stopRunning() }
    }

    private func apply(_ skeleton: PoseSkeleton?) {
        self.skeleton = skeleton
        if skeleton == nil {
            missedFrames += 1
            if missedFrames >= 8 { bodyVisible = false }
        } else {
            missedFrames = 0
            if !bodyVisible {
                bodyVisible = true
                if phase == .calibrating { coach.say("Restez debout, immobile") }
            }
        }
    }

    private func apply(_ update: CounterUpdate) {
        guard phase != .finished else { return }
        depthProgress = update.progress

        switch update.event {
        case .calibrated:
            phase = .active
            coach.say("C'est parti !")
        case .repCompleted(let result):
            repCount += 1
            if repCount >= targetReps {
                phase = .finished
                depthProgress = 0
                coach.say("\(repCount). Série terminée, bravo !")
            } else if let correction = result.correction {
                show(Feedback(message: correction.message, isPositive: false))
                coach.say("\(repCount). \(String(localized: correction.message))")
            } else {
                show(Feedback(message: "Bien !", isPositive: true))
                coach.say("\(repCount)")
            }
        case .repIncomplete:
            incompleteCount += 1
        case .correction(let correction):
            show(Feedback(message: correction.message, isPositive: false))
            coach.say(correction.message)
        case nil:
            break
        }
    }

    private func show(_ feedback: Feedback) {
        self.feedback = feedback
        feedbackDismissal?.cancel()
        feedbackDismissal = Task {
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            self.feedback = nil
        }
    }
}

/// Receives camera frames on the video queue and runs the analysis off the main thread.
/// The fast 2D skeleton runs on every frame; the slower 3D measure runs whenever the previous one is done.
nonisolated final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onSkeleton: (@Sendable (PoseSkeleton?) -> Void)?
    var onUpdate: (@Sendable (CounterUpdate) -> Void)?

    private let analyzer: PoseAnalyzer
    /// Only touched on `analysisQueue`.
    private var counter: RepCounter
    private let analysisQueue = DispatchQueue(label: "rebond.analysis")
    private let isMeasuring = Mutex(false)
    /// Only touched on the video queue.
    private var lastFrameTime = CMTime.zero
    /// 15 frames per second are enough to follow the movement.
    private let minFrameInterval = CMTime(value: 1, timescale: 15)

    init(exercise: CatalogExercise) {
        analyzer = PoseAnalyzer(exercise: exercise)
        counter = RepCounter(exercise: exercise)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = sampleBuffer.presentationTimeStamp
        guard time - lastFrameTime >= minFrameInterval,
              let pixelBuffer = sampleBuffer.imageBuffer
        else { return }
        lastFrameTime = time

        onSkeleton?(analyzer.skeleton(in: pixelBuffer))

        let wasMeasuring = isMeasuring.withLock { measuring in
            defer { measuring = true }
            return measuring
        }
        guard !wasMeasuring else { return }

        nonisolated(unsafe) let frame = pixelBuffer
        analysisQueue.async { [self] in
            if let measure = analyzer.measure(in: frame) {
                onUpdate?(counter.process(measure, at: time.seconds))
            }
            isMeasuring.withLock { $0 = false }
        }
    }
}
