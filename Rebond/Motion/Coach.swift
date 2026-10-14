import AVFoundation

/// Spoken instructions: the patient stands 2–3 m away and can't always read the screen.
final class Coach {
    var isMuted = false

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = Coach.bestVoice()

    init() {
        // Audible even with the silent switch on; the patient's music is lowered while the coach talks.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: .duckOthers)
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

    /// The most natural installed voice in the interface language.
    /// Premium and enhanced voices sound much better than the default one; the user downloads them in
    /// Réglages > Accessibilité > Contenu énoncé > Voix.
    private static func bestVoice() -> AVSpeechSynthesisVoice? {
        let language = Bundle.main.preferredLocalizations.first ?? "fr"
        let preferredCode = AVSpeechSynthesisVoice.currentLanguageCode()
        let voices = AVSpeechSynthesisVoice.speechVoices().filter {
            $0.language.hasPrefix(language) && !$0.voiceTraits.contains(.isNoveltyVoice)
        }
        let best = voices.max { a, b in
            if a.quality != b.quality { return a.quality.rawValue < b.quality.rawValue }
            // Same quality: prefer the user's own region (fr-FR over fr-CA for a French user).
            return a.language != preferredCode && b.language == preferredCode
        }
        return best ?? AVSpeechSynthesisVoice(language: language)
    }
}
