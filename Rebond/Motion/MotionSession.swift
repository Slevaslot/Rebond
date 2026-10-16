import AVFoundation
import Observation
import Synchronization
import Vision

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
        /// Waiting for the patient to stand in the guide outline, still, so the resting position can be measured.
        case calibrating
        /// In place: the guide shows the movement once, then moves to its corner.
        case demonstrating
        case active
        case finished
    }

    /// Where the model is: large in front of the patient, or in its card during the set.
    enum GuideDisplay {
        case large
        case corner
    }

    /// One demonstration of the movement by the guide pictogram, in seconds.
    static let demonstrationDuration = 4.0

    struct Feedback: Identifiable, Equatable {
        let id = UUID()
        let message: LocalizedStringResource
        let isPositive: Bool
        /// For a counted repetition: how far it went.
        var tier: AmplitudeTier? = nil

        static func == (lhs: Feedback, rhs: Feedback) -> Bool { lhs.id == rhs.id }
    }

    let exercise: CatalogExercise
    let targetReps: Int
    /// The guide shows the movement before the set: only before the first set of an exercise.
    let showsDemonstration: Bool
    let liveFrame = LiveFrame()
    /// Called when the patient asks for the next set, with a thumbs up from where they stand.
    @ObservationIgnored var onNext: (() -> Void)?

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
    /// Each counted repetition's amplitude, as a fraction of the exercise's target.
    private(set) var amplitudes: [Double] = []
    private(set) var feedback: Feedback?
    private(set) var guideDisplay = GuideDisplay.large
    /// Paused from the screen or by a hand gesture: nothing is counted until the patient resumes.
    private(set) var isPaused = false
    /// The camera lost the patient during the set: the guide outline shows them where to stand again,
    /// and counting resumes once they are back in it.
    private(set) var isLost = false

    /// The patient opened the model large during the set: they watch the movement, the camera is blurred and
    /// nothing is counted. Once it goes back to its card, it's their turn.
    /// The first demonstration isn't watched this way: many start moving with it, and those repetitions count.
    var isWatching: Bool {
        phase == .active && guideDisplay == .large
    }
    /// When the current demonstration started, so the guide begins it standing.
    private(set) var demonstrationStart = Date.now
    /// Fault to show in red on the body: the live posture problem, or the last rejected movement for a moment.
    private(set) var faultToHighlight: Correction?
    /// Remembered from one set (and one session) to the next.
    var isMuted = UserDefaults.standard.bool(forKey: Coach.mutedKey) {
        didSet {
            coach.isMuted = isMuted
            UserDefaults.standard.set(isMuted, forKey: Coach.mutedKey)
        }
    }

    @ObservationIgnored private let captureSession = AVCaptureSession()
    @ObservationIgnored private let coach = Coach()
    @ObservationIgnored private let processor: FrameProcessor
    @ObservationIgnored private let videoQueue = DispatchQueue(label: "rebond.video")
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    /// Consecutive frames without the joints the exercise needs, so a short missed detection doesn't
    /// flash the placement hint.
    @ObservationIgnored private var missedFrames = 0
    /// Consecutive frames with them, to come back from "lost" only once the body is seen steadily.
    @ObservationIgnored private var followedFrames = 0
    /// Frames since Vision last returned a skeleton: the last one stays on screen for a moment.
    @ObservationIgnored private var framesWithoutSkeleton = 0
    /// About 0.8 s at 15 analyses per second without the exercise's joints: the body is no longer seen.
    private let framesBeforeHidden = 12
    /// About 0.5 s of the body seen steadily again: counting resumes, even if it isn't all in the outline.
    private let framesBeforeFound = 8
    /// About 0.4 s: the last skeleton stays drawn across short gaps of Vision.
    private let skeletonHoldFrames = 6
    /// Waits a moment before showing the outline again, so a short loss of the body doesn't flash it.
    @ObservationIgnored private var lostDelay: Task<Void, Never>?
    @ObservationIgnored private var feedbackDismissal: Task<Void, Never>?
    /// The resting position is measured and the patient stands in the guide: the demonstration can start.
    @ObservationIgnored private var isCalibrated = false
    @ObservationIgnored private var isInPlace = false
    @ObservationIgnored private var intro: Task<Void, Never>?
    @ObservationIgnored private var demonstration: Task<Void, Never>?
    /// A correction is spoken only when the same fault comes back, and long after the previous one;
    /// the screen still shows each.
    @ObservationIgnored private var lastSpokenCorrection = Date.distantPast
    @ObservationIgnored private var lastCorrection: Correction?
    private let correctionSpeechInterval = 15.0
    /// The return cue ("Remontez") is said on the first repetition only, then the patient knows it.
    private let returnCueRepetitions = 1
    @ObservationIgnored private var lastAnnouncement = ""
    @ObservationIgnored private var lastAnnouncementDate = Date.distantPast
    /// The placement hint waiting for the patient to settle, so moving into place doesn't trigger a stream of hints.
    @ObservationIgnored private var pendingAnnouncement = ""
    @ObservationIgnored private var announcementDelay: Task<Void, Never>?
    private let announcementSettleDelay = 1.2
    private let announcementInterval = 5.0
    @ObservationIgnored private var heldFault: Correction?
    @ObservationIgnored private var heldFaultRelease: Task<Void, Never>?
    /// "Prenez votre temps" is shown at most once every few repetitions, and said once per set.
    @ObservationIgnored private var lastTempoReminder = -10
    @ObservationIgnored private var hasSaidTempoReminder = false
    private let tempoReminderInterval = 3

    init(exercise: CatalogExercise, targetReps: Int, showsDemonstration: Bool = true) {
        self.exercise = exercise
        self.targetReps = targetReps
        self.showsDemonstration = showsDemonstration
        // A later set of the same exercise: the patient is already in place, no outline to fit again.
        isInPlace = !showsDemonstration
        processor = FrameProcessor(exercise: exercise)
        processor.onImage = { [weak self] image in
            Task { @MainActor [self] in self?.liveFrame.image = image }
        }
        processor.onAnalysis = { [weak self] skeleton, update, isFollowed in
            Task { @MainActor [self] in self?.apply(skeleton, update, isFollowed: isFollowed) }
        }
        processor.onGesture = { [weak self] gesture in
            Task { @MainActor [self] in self?.handle(gesture) }
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
        activateAudio()
    }

    func stop() {
        nonisolated(unsafe) let session = captureSession
        videoQueue.async { session.stopRunning() }
        deactivateAudio()
    }

    /// Pause at any moment, even before the set starts (getting in place, demonstration).
    func togglePause() {
        guard phase != .finished else { return }
        isPaused.toggle()
        processor.isPaused.withLock { $0 = isPaused }
        if isPaused {
            // The set resumes with the model in its card, as it normally is.
            demonstration?.cancel()
            if phase == .demonstrating { beginSet(announce: false) }
            if phase == .active { guideDisplay = .corner }
            lostDelay?.cancel()
        }
        coach.say(isPaused ? "Pause" : "On reprend", urgency: .immediate)
        if !isPaused { startDemonstrationIfReady() }
    }

    /// While the patient watches the model or pauses, the whole picture is blurred, in one blur with the background.
    func blurWholePicture(_ blurred: Bool) {
        processor.blursEverything.withLock { $0 = blurred }
    }

    /// Hand gestures, from where the patient stands: palm to pause, spread or pinch to open or close the model.
    private func handle(_ gesture: HandGesture) {
        switch gesture {
        case .openPalm: togglePause()
        case .spread: expandModel()
        case .pinch: shrinkModel()
        case .thumbsUp:
            // While paused, the detector reports any sign as the resume: a thumbs up never skips the set then.
            guard !isPaused else { return }
            onNext?()
        }
    }

    /// Spoken instructions need an active audio session; other audio is lowered while the coach talks.
    private func activateAudio() {
        try? AVAudioSession.sharedInstance().setActive(true)
    }

    private func deactivateAudio() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    var result: SetResult {
        SetResult(
            completedReps: repCount,
            incompleteReps: incompleteCount,
            amplitudes: amplitudes.map { $0 * 100 }
        )
    }

    /// Says a placement instruction once the patient has settled: the hint must stay the same for a moment,
    /// is not repeated, and waits a few seconds after the previous one.
    func announce(_ message: LocalizedStringResource) {
        let text = String(localized: message)
        guard text != pendingAnnouncement else { return }
        pendingAnnouncement = text
        announcementDelay?.cancel()
        let wait = max(announcementSettleDelay, announcementInterval - Date.now.timeIntervalSince(lastAnnouncementDate))
        announcementDelay = Task {
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled, phase == .calibrating || isLost, !isPaused, text != lastAnnouncement else { return }
            lastAnnouncement = text
            lastAnnouncementDate = .now
            coach.say(text)
        }
    }

    /// Where the patient stands compared with the guide outline, reported by the screen.
    func updatePlacement(_ placement: GuidePlacement) {
        isInPlace = placement == .aligned || placement == .almost
        if isLost, isInPlace {
            isLost = false
            coach.say("On reprend")
            return
        }
        announce(placement.message)
        startDemonstrationIfReady()
    }

    /// Once the patient is in place and still: the guide shows the movement once, large, over the camera,
    /// then moves to its corner. Counting already runs during the demonstration: a patient who starts with
    /// the model is counted, and the model steps aside as soon as they move.
    /// Later sets of the same exercise skip the demonstration.
    private func startDemonstrationIfReady() {
        guard phase == .calibrating, isCalibrated, isInPlace, !isPaused else { return }
        guard showsDemonstration else {
            beginSet(announce: true)
            return
        }
        phase = .demonstrating
        guideDisplay = .large
        demonstrationStart = .now
        coach.say("Voici le mouvement, faites-le avec le modèle")
        intro = Task {
            try? await Task.sleep(for: .seconds(Self.demonstrationDuration))
            guard !Task.isCancelled else { return }
            beginSet(announce: true)
        }
    }

    /// The set starts: the model goes to its card.
    private func beginSet(announce: Bool) {
        guard phase == .calibrating || phase == .demonstrating else { return }
        intro?.cancel()
        phase = .active
        guideDisplay = .corner
        demonstrationStart = .now
        if announce { coach.say("À vous") }
    }

    /// The patient opens the model large, in front of them, to follow it while doing the movement.
    func expandModel() {
        guard phase == .active, guideDisplay == .corner else { return }
        demonstration?.cancel()
        guideDisplay = .large
        depthProgress = 0
        demonstrationStart = .now
        coach.say("Regardez le mouvement", urgency: .immediate)
    }

    func shrinkModel() {
        guard phase == .active, guideDisplay == .large else { return }
        demonstration?.cancel()
        guideDisplay = .corner
        demonstrationStart = .now
        coach.say("À vous", urgency: .immediate)
    }

    /// The body has been missing for nearly a second: one more second, then the outline comes back.
    private func showOutlineIfStillLost() {
        lostDelay?.cancel()
        lostDelay = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled, phase == .active, !isPaused else { return }
            isLost = true
            depthProgress = 0
            lastAnnouncement = ""
            pendingAnnouncement = ""
            announce(GuidePlacement.notVisible.message)
        }
    }

    /// Starts the set over, measuring the resting position again.
    func restart() {
        processor.resetCounter()
        intro?.cancel()
        isPaused = false
        processor.isPaused.withLock { $0 = false }
        isLost = false
        lostDelay?.cancel()
        demonstration?.cancel()
        guideDisplay = .large
        isCalibrated = false
        phase = .calibrating
        depthProgress = 0
        repCount = 0
        incompleteCount = 0
        amplitudes = []
        feedbackDismissal?.cancel()
        feedback = nil
        heldFault = nil
        faultToHighlight = nil
        lastTempoReminder = -10
        hasSaidTempoReminder = false
        lastCorrection = nil
        lastAnnouncement = ""
        pendingAnnouncement = ""
        announcementDelay?.cancel()
        coach.say("Posez votre téléphone debout, reculez, puis placez-vous dans la silhouette", urgency: .immediate)
    }

    private func apply(_ skeleton: PoseSkeleton?, _ update: CounterUpdate, isFollowed: Bool) {
        if let skeleton {
            framesWithoutSkeleton = 0
            self.skeleton = skeleton
        } else {
            framesWithoutSkeleton += 1
            if framesWithoutSkeleton > skeletonHoldFrames { self.skeleton = nil }
        }

        if isFollowed {
            missedFrames = 0
            followedFrames += 1
            lostDelay?.cancel()
            if !bodyVisible { bodyVisible = true }
            // Back and seen steadily, maybe not whole (feet out of view): no need to fit the outline again.
            if isLost, followedFrames >= framesBeforeFound {
                isLost = false
                coach.say("On reprend")
            }
        } else {
            followedFrames = 0
            missedFrames += 1
            if missedFrames >= framesBeforeHidden, bodyVisible {
                bodyVisible = false
                if phase == .active { showOutlineIfStillLost() }
            }
        }

        guard phase != .finished else { return }
        if case .calibrated = update.event {
            isCalibrated = true
            startDemonstrationIfReady()
        }
        // Moving during the demonstration: the patient started with the model, it's their set now.
        if phase == .demonstrating, !isPaused, update.progress >= 0.3 || update.event.isRepetition {
            beginSet(announce: false)
        }
        // Nothing counts during a pause, while watching the model, nor until the patient is back in place.
        guard phase == .active, !isPaused, !isLost, !isWatching else { return }
        depthProgress = update.progress
        faultToHighlight = update.posture ?? heldFault

        switch update.event {
        case .calibrated:
            break
        case .repCompleted(let result):
            repCount += 1
            amplitudes.append(result.amplitude)
            if repCount >= targetReps {
                phase = .finished
                depthProgress = 0
                coach.say("\(repCount). Série terminée, bravo !")
            } else if result.tooFast {
                if repCount - lastTempoReminder >= tempoReminderInterval {
                    lastTempoReminder = repCount
                    show(Feedback(message: Correction.slowDown.message, isPositive: false))
                }
                if !hasSaidTempoReminder, repCount == lastTempoReminder {
                    hasSaidTempoReminder = true
                    coach.say("\(repCount). \(String(localized: Correction.slowDown.message))")
                } else {
                    coach.say("\(repCount)")
                }
            } else if exercise.reference != nil, let resemblance = result.resemblance {
                // A filmed movement: how close it was to the video, in percent.
                let percent = Int((resemblance * 100).rounded())
                let tier = AmplitudeTier(amplitude: min(1, resemblance / 0.9))
                show(Feedback(message: "\(percent) % comme sur la vidéo", isPositive: true, tier: tier))
                coach.say("\(repCount)")
            } else {
                let tier = AmplitudeTier(amplitude: result.amplitude)
                show(Feedback(message: tier.message, isPositive: true, tier: tier))
                coach.say("\(repCount)")
            }
        case .repIncomplete:
            incompleteCount += 1
        case .bottomReached:
            if repCount < returnCueRepetitions { coach.say(exercise.returnCue, urgency: .optional) }
        case .correction(let correction):
            show(Feedback(message: correction.message, isPositive: false))
            hold(correction)
            // A one-off fault isn't worth talking over the patient: only one that comes back is said.
            if correction == lastCorrection, Date.now.timeIntervalSince(lastSpokenCorrection) >= correctionSpeechInterval {
                lastSpokenCorrection = .now
                lastCorrection = nil
                coach.say(correction.message, urgency: .optional)
            } else {
                lastCorrection = correction
            }
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
    /// The skeleton, the counter's update, and whether the joints the exercise needs were seen.
    var onAnalysis: (@Sendable (PoseSkeleton?, CounterUpdate, Bool) -> Void)?
    var onGesture: (@Sendable (HandGesture) -> Void)?

    private let exercise: CatalogExercise
    private let analyzer = PoseAnalyzer()
    private var gestures = HandGestureDetector()
    private let blur = BackgroundBlur()
    /// Where the patient was last seen, normalized, origin top-left.
    private var patient: CGPoint?
    private var counter: any MovementCounter
    private var lastAnalysisTime = CMTime.zero
    /// 15 analyses per second are enough to follow the movement.
    private let minAnalysisInterval = CMTime(value: 1, timescale: 15)

    init(exercise: CatalogExercise) {
        self.exercise = exercise
        counter = exercise.makeCounter()
    }

    /// Called from the main thread: the counter itself is replaced on the video queue, at the next analysis.
    func resetCounter() {
        resetRequested.withLock { $0 = true }
    }

    private let resetRequested = Mutex(false)

    /// Set from the main thread: blur the patient too, not only the background.
    let blursEverything = Mutex(false)

    /// Set from the main thread: the set is paused, the detector waits for the sign to resume.
    let isPaused = Mutex(false)

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return }

        let time = sampleBuffer.presentationTimeStamp
        if time - lastAnalysisTime >= minAnalysisInterval {
            lastAnalysisTime = time
            if resetRequested.withLock({ requested in defer { requested = false }; return requested }) {
                counter = exercise.makeCounter()
            }
            let frame = analyzer.analyze(pixelBuffer)
            let update = counter.process(frame.measure, at: time.seconds)
            onAnalysis?(frame.skeleton, update, exercise.canFollow(frame.measure))
            // While paused, the sign to resume is always looked for, whatever the exercise.
            let paused = isPaused.withLock { $0 }
            if exercise.allowsHandGestures || paused,
               let gesture = gestures.process(pixelBuffer, body: frame.skeleton, isMoving: update.progress > 0.15,
                                              isPaused: paused) {
                onGesture?(gesture)
            }
            // The background blur keeps only this person sharp.
            patient = frame.skeleton.flatMap { $0.points[.root] ?? $0.points[.neck] } ?? patient
        }

        onImage?(blur.apply(to: pixelBuffer, patient: patient, everything: blursEverything.withLock { $0 }))
    }
}

private extension Optional where Wrapped == RepEvent {
    /// A repetition reached its target, or ended.
    var isRepetition: Bool {
        switch self {
        case .bottomReached, .repCompleted, .repIncomplete: true
        default: false
        }
    }
}
