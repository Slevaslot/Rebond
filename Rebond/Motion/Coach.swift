import AVFoundation

/// Spoken instructions: the patient stands 2–3 m away and can't always read the screen.
final class Coach {
    /// The voice turned off by the patient stays off, for every set and session.
    static let mutedKey = "coachMuted"

    var isMuted = UserDefaults.standard.bool(forKey: Coach.mutedKey)

    private let synthesizer = AVSpeechSynthesizer()
    private let voice = Coach.bestVoice()

    init() {
        // Audible even with the silent switch on; the patient's music is lowered while the coach talks.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: .duckOthers)
    }

    /// How a new sentence gets along with the one being said. The coach never cuts itself off mid-word
    /// unless the patient asked for something (pause, resume): being interrupted sounds abrupt.
    enum Urgency {
        /// A tip or a placement hint: dropped if the coach is already talking, the screen still shows it.
        case optional
        /// A count or the end of the set: said once the current sentence ends.
        case queued
        /// The answer to the patient's own action: said right away.
        case immediate
    }

    func say(_ text: LocalizedStringResource, urgency: Urgency = .queued) {
        say(String(localized: text), urgency: urgency)
    }

    func say(_ text: String, urgency: Urgency = .queued) {
        guard !isMuted else { return }
        switch urgency {
        case .optional:
            guard !synthesizer.isSpeaking else { return }
        case .queued:
            break
        case .immediate:
            synthesizer.stopSpeaking(at: .word)
        }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        // A calm voice: a little slower, lower and quieter than the system default, with a short breath before.
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.9
        utterance.pitchMultiplier = 0.95
        utterance.volume = 0.8
        utterance.preUtteranceDelay = 0.15
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
