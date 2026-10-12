import AVFoundation
import Observation

/// Runs the camera and exposes the live state of a guided session.
@Observable
final class MotionSession {
    let exercise: CatalogExercise
    let captureSession = AVCaptureSession()

    private(set) var camera: AVCaptureDevice?
    private(set) var cameraUnavailable = false
    private(set) var bodyVisible = false
    private(set) var repCount = 0
    private(set) var incompleteCount = 0
    private(set) var lastCorrection: LocalizedStringResource?

    @ObservationIgnored private let processor: FrameProcessor
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "rebond.video")
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?

    init(exercise: CatalogExercise) {
        self.exercise = exercise
        processor = FrameProcessor(exercise: exercise)
        processor.onResult = { [weak self] result in
            Task { @MainActor [self] in self?.apply(result) }
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

        // Keep frames upright whatever the phone orientation, so Vision sees a standing body.
        let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: nil)
        nonisolated(unsafe) let connection = output.connection(with: .video)
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

    private func apply(_ result: FrameResult) {
        bodyVisible = result.bodyVisible
        switch result.event {
        case .repCompleted:
            repCount += 1
            lastCorrection = nil
        case .repIncomplete:
            incompleteCount += 1
        case .correction(let text):
            lastCorrection = text
        case nil:
            break
        }
    }
}

nonisolated struct FrameResult: Sendable {
    let bodyVisible: Bool
    let event: RepEvent?
}

/// Receives camera frames on the video queue and runs the analysis off the main thread.
/// Its mutable state is only touched from that queue.
nonisolated final class FrameProcessor: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    var onResult: (@Sendable (FrameResult) -> Void)?

    private let analyzer: PoseAnalyzer
    private var counter: RepCounter
    private var lastFrameTime = CMTime.zero
    /// 15 frames per second are enough for counting.
    private let minFrameInterval = CMTime(value: 1, timescale: 15)

    init(exercise: CatalogExercise) {
        analyzer = PoseAnalyzer(exercise: exercise)
        counter = RepCounter(exercise: exercise)
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let time = sampleBuffer.presentationTimeStamp
        guard time - lastFrameTime >= minFrameInterval else { return }
        lastFrameTime = time

        guard let angle = analyzer.angle(in: sampleBuffer) else {
            onResult?(FrameResult(bodyVisible: false, event: nil))
            return
        }
        onResult?(FrameResult(bodyVisible: true, event: counter.process(angle: angle)))
    }
}
