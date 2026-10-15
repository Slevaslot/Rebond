import AppIntents

// Compiled into the iPhone app and its widget extension (folder `Shared/`): the Live Activity draws the
// buttons, the app performs them (a `LiveActivityIntent` always runs in the app's process).

/// "Pause" from the Live Activity (Lock Screen, Dynamic Island, Smart Stack of the Apple Watch) or from Siri
/// ("Pause dans Rebond"): pauses or resumes the set in progress, like the button on screen or the open palm.
struct ToggleSessionPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mettre en pause ou reprendre la série"
    static let description = IntentDescription("Met en pause la série en cours dans Rebond, ou la reprend.")
    static let isDiscoverable = true

    /// What the app does; nil in the widget extension.
    @MainActor static var handler: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}

/// "Série suivante" from the Live Activity or from Siri: ends the set in progress with what was done, like the
/// Passer menu or the thumbs up.
struct NextSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Passer à la série suivante"
    static let description = IntentDescription("Termine la série en cours dans Rebond et passe à la suivante.")
    static let isDiscoverable = true

    @MainActor static var handler: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
