import AVFoundation
import Observation
import Synchronization

/// What one set produced, saved in the session.
nonisolated struct SetResult: Sendable {
    var completedReps = 0
    var incompleteReps = 0
    /// Deepest repetition, in percent of the target depth. Nil when nothing was completed.
    var amplitude: Double?
}

/// Latest camera image to display, kept apart from `MotionSession`
/// so only the camera view redraws at the camera's frame rate.
@Observable
final class LiveFrame {
    var image: CGImage?
}

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
    let liveFrame = LiveFrame()

    private(set) var cameraUnavailable = false
    /// Access was refused, as opposed to a device without a front camera.
    private(set) var cameraAccessDenied = false
    private(set) var phase = Phase.calibrating
    private(set) var bodyVisible = false
    private(set) var skeleton: PoseSkeleton?
    /// 0 at rest, 1 when the target depth is reached.
    private(set) var depthProgress = 0.0
    private(set) var repCount = 0
    private(set) var incompleteCount = 0
    /// Deepest completed repetition, in torso lengths.
    private(set) var bestDepth = 0.0
    private(set) var feedback: Feedback?
    /// Fault to show in red on the body: the live posture problem, or the last rejected movement for a moment.
    private(set) var faultToHighlight: Correction?
    var isMuted = false {
        didSet { coach.isMuted = isMuted }
    }

    @ObservationIgnored private let captureSession = AVCaptureSession()
    @ObservationIgnored private let coach = Coach()
    @ObservationIgnored private let processor: FrameProcessor
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "rebond.video")
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    /// Consecutive frames without a body, so a single missed detection doesn't flash the placement hint.
    @ObservationIgnored private var missedFrames = 0
    @ObservationIgnored private var feedbackDismissal: Task<Void, Never>?
    @ObservationIgnored private var heldFault: Correction?
    @ObservationIgnored private var heldFaultRelease: Task<Void, Never>?
    /// "Plus lentement" is said at most once every few repetitions, so it doesn't become noise.
    @ObservationIgnored private var lastTempoReminder = -10
    private let tempoReminderInterval = 3

    init(exercise: CatalogExercise, targetReps: Int) {
        self.exercise = exercise
        self.targetReps = targetReps
        processor = FrameProcessor(exercise: exercise)
        processor.onImage = { [weak self] image in
            Task { @MainActor [self] in self?.liveFrame.image = image }
        }
        processor.onAnalysis = { [weak self] skeleton, update in
            Task { @MainActor [self] in self?.apply(skeleton, update) }
        }
    }

    func start() async {
        guard captureSession.inputs.isEmpty else { return }
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            cameraAccessDenied = true
            cameraUnavailable = true
            return
        }
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: camera)
        else {
            cameraUnavailable = true
            return
        }

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(processor, queue: videoQueue)

        captureSession.beginConfiguration()
        // 720p is plenty for the analysis and keeps the background blur fast.
        if captureSession.canSetSessionPreset(.hd1280x720) { captureSession.sessionPreset = .hd1280x720 }
        if captureSession.canAddInput(input) { captureSession.addInput(input) }
        if captureSession.canAddOutput(output) { captureSession.addOutput(output) }
        captureSession.commitConfiguration()

        // Mirror the frames like a mirror: the patient sees themselves as they move.
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

        nonisolated(unsafe) let session = captureSession
        videoQueue.async { session.startRunning() }
    }

    func stop() {
        nonisolated(unsafe) let session = captureSession
        videoQueue.async { session.stopRunning() }
    }

    var result: SetResult {
        SetResult(
            completedReps: repCount,
            incompleteReps: incompleteCount,
            amplitude: repCount > 0 ? bestDepth / exercise.targetDepth * 100 : nil
        )
    }

    /// Starts the set over, measuring the resting position again.
    func restart() {
        processor.resetCounter()
        phase = .calibrating
        depthProgress = 0
        repCount = 0
        incompleteCount = 0
        bestDepth = 0
        feedbackDismissal?.cancel()
        feedback = nil
        heldFault = nil
        faultToHighlight = nil
        lastTempoReminder = -10
        coach.say("Restez debout, immobile")
    }

    private func apply(_ skeleton: PoseSkeleton?, _ update: CounterUpdate) {
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

        guard phase != .finished else { return }
        depthProgress = update.progress
        faultToHighlight = update.posture ?? heldFault

        switch update.event {
        case .calibrated:
            phase = .active
            coach.say("C'est parti !")
        case .repCompleted(let result):
            repCount += 1
            bestDepth = max(bestDepth, result.depth)
            if repCount >= targetReps {
                phase = .finished
                depthProgress = 0
                coach.say("\(repCount). Série terminée, bravo !")
            } else if result.tooFast {
                if repCount - lastTempoReminder >= tempoReminderInterval {
                    lastTempoReminder = repCount
                    show(Feedback(message: Correction.slowDown.message, isPositive: false))
                    coach.say("\(repCount). \(String(localized: Correction.slowDown.message))")
                } else {
                    coach.say("\(repCount)")
                }
            } else {
                show(Feedback(message: "Bien !", isPositive: true))
                coach.say("\(repCount)")
            }
        case .repIncomplete:
            incompleteCount += 1
        case .bottomReached:
            coach.say("Remontez")
        case .correction(let correction):
            show(Feedback(message: correction.message, isPositive: false))
            coach.say(correction.message)
            hold(correction)
        case nil:
            break
        }
    }

    /// Keeps a rejected movement's fault highlighted for a moment, so the patient sees what went wrong.
    private func hold(_ fault: Correction) {
        heldFault = fault
        faultToHighlight = fault
        heldFaultRelease?.cancel()
        heldFaultRelease = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self.heldFault = nil
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

/// Receives camera frames on the video queue: blurs the background of every frame for display,
/// and analyzes the pose 15 times per second. Its state is only touched on that queue.
nonisolated final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onImage: (@Sendable (CGImage?) -> Void)?
    var onAnalysis: (@Sendable (PoseSkeleton?, CounterUpdate) -> Void)?

    private let exercise: CatalogExercise
    private let analyzer = PoseAnalyzer()
    private let blur = BackgroundBlur()
    private var counter: RepCounter
    private var lastAnalysisTime = CMTime.zero
    /// 15 analyses per second are enough to follow the movement.
    private let minAnalysisInterval = CMTime(value: 1, timescale: 15)

    init(exercise: CatalogExercise) {
        self.exercise = exercise
        counter = RepCounter(exercise: exercise)
    }

    /// Called from the main thread: the counter itself is replaced on the video queue, at the next analysis.
    func resetCounter() {
        resetRequested.withLock { $0 = true }
    }

    private let resetRequested = Mutex(false)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }
        onImage?(blur.apply(to: pixelBuffer))

        let time = sampleBuffer.presentationTimeStamp
        guard time - lastAnalysisTime >= minAnalysisInterval else { return }
        lastAnalysisTime = time

        if resetRequested.withLock({ requested in defer { requested = false }; return requested }) {
            counter = RepCounter(exercise: exercise)
        }
        let frame = analyzer.analyze(pixelBuffer)
        let update = counter.process(frame.measure, at: time.seconds)
        onAnalysis?(frame.skeleton, update)
    }
}
