import AVFoundation
import Speech

/// Spoken commands during a set, for a patient standing away from the phone: "Pause", "Reprendre",
/// "Montre-moi". Recognition runs on the iPhone; nothing is recorded or sent.
///
/// Commands only do what they say (pausing an already paused set does nothing), so the coach saying
/// "Pause" or "On reprend" through the speaker can't flip the state back.
@Observable
final class VoiceCommands {
    enum Command {
        case pause
        case resume
        case showModel
    }

    private(set) var isListening = false
    var onCommand: ((Command) -> Void)?

    private let recognizer = SFSpeechRecognizer(locale: Locale.current) ?? SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
    private let engine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest? {
        didSet { buffers.request = request }
    }
    /// Where the microphone's buffers go, read from the audio thread.
    private let buffers = BufferRelay()
    private var task: SFSpeechRecognitionTask?
    /// A command is acted on once: the next words are read from a new recognition.
    private var lastCommandDate = Date.distantPast

    /// Both the microphone and speech recognition are allowed.
    static var isAuthorized: Bool {
        SFSpeechRecognizer.authorizationStatus() == .authorized
            && AVAudioApplication.shared.recordPermission == .granted
    }

    /// Asks for speech recognition, then the microphone. True when both are granted.
    static func requestAuthorization() async -> Bool {
        let speech = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) }
        }
        guard speech == .authorized else { return false }
        return await AVAudioApplication.requestRecordPermission()
    }

    func start() {
        guard !isListening, Self.isAuthorized, let recognizer, recognizer.isAvailable else { return }
        let session = AVAudioSession.sharedInstance()
        // The coach keeps talking through the speaker while the microphone listens.
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .duckOthers])
        try? session.setActive(true)

        let input = engine.inputNode
        // Echo cancellation: the coach's voice is not heard as a command.
        try? input.setVoiceProcessingEnabled(true)
        input.installTap(onBus: 0, bufferSize: 1024, format: input.outputFormat(forBus: 0), block: Self.tap(into: buffers))
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            return
        }
        isListening = true
        beginRecognition()
    }

    func stop() {
        guard isListening else { return }
        isListening = false
        task?.cancel()
        request?.endAudio()
        task = nil
        request = nil
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        // Back to the coach's own audio setup.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: .duckOthers)
    }

    private func beginRecognition() {
        guard isListening, let recognizer else { return }
        task?.cancel()
        request?.endAudio()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.taskHint = .confirmation
        request.contextualStrings = ["pause", "reprendre", "montre-moi"]
        self.request = request
        task = recognizer.recognitionTask(with: request, resultHandler: Self.resultHandler(for: self))
    }

    /// Called on the main actor with each new transcription.
    fileprivate func received(_ text: String?, isFinal: Bool, failed: Bool) {
        guard isListening else { return }
        if let text, let command = Self.command(in: text), Date.now.timeIntervalSince(lastCommandDate) > 1 {
            lastCommandDate = .now
            onCommand?(command)
            // Start over so the same words aren't read again.
            beginRecognition()
            return
        }
        if isFinal || failed {
            beginRecognition()
        }
    }

    /// The command in the last words heard, if any.
    nonisolated static func command(in text: String) -> Command? {
        let words = text
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .split(whereSeparator: { !$0.isLetter })
            .suffix(3)
        if words.contains(where: { $0 == "pause" || $0 == "stop" }) { return .pause }
        if words.contains(where: { $0.hasPrefix("repren") || $0.hasPrefix("continu") || $0 == "resume" }) { return .resume }
        if words.contains(where: { $0 == "montre" || $0 == "modele" || $0 == "show" }) { return .showModel }
        return nil
    }

    // The tap and the recognition results arrive on audio threads: these closures must not be main-actor ones.

    private nonisolated static func tap(into relay: BufferRelay) -> AVAudioNodeTapBlock {
        { buffer, _ in relay.append(buffer) }
    }

    private nonisolated static func resultHandler(for owner: VoiceCommands) -> (SFSpeechRecognitionResult?, Error?) -> Void {
        { [weak owner] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in owner?.received(text, isFinal: isFinal, failed: failed) }
        }
    }
}

/// Hands the microphone's buffers to the current recognition request, which changes after each command.
private nonisolated final class BufferRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var current: SFSpeechAudioBufferRecognitionRequest?

    var request: SFSpeechAudioBufferRecognitionRequest? {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        request?.append(buffer)
    }
}
