import AVFoundation

/// Spoken instructions: the patient stands 2–3 m away and can't always read the screen.
final class Coach {
    var isMuted = false

    private let synthesizer = AVSpeechSynthesizer()
    /// Same language as the interface.
    private let voice = AVSpeechSynthesisVoice(language: Bundle.main.preferredLocalizations.first)

    init() {
        // Audible even with the silent switch on, and lowers music while speaking.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers])
    }

    func say(_ text: LocalizedStringResource) {
        say(String(localized: text))
    }

    func say(_ text: String) {
        guard !isMuted else { return }
        // The newest instruction wins: the patient needs the current state, not a backlog.
        synthesizer.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        synthesizer.speak(utterance)
    }
}
