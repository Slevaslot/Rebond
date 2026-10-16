import AppIntents

// Compiled into the iPhone app and its widget extension (folder `Shared/`): the Live Activity draws the
// buttons, the app performs them (a `LiveActivityIntent` always runs in the app's process). The app sets each
// `handler`: it sends the command to the session (`SessionRemote`) and returns what to say, from the real state
// of the session ("Série suivante", "Aucune séance en cours"…). Siri says it; the Live Activity ignores it.

/// Said when the app isn't there to answer (the widget extension never performs these intents).
private let noSession: LocalizedStringResource = "Aucune séance en cours"

/// "Pause" from the Live Activity (Lock Screen, Dynamic Island, Smart Stack of the Apple Watch) or from Siri
/// ("Pause dans Rebond"): pauses or resumes the set in progress, like the button on screen or the open palm.
struct ToggleSessionPauseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Mettre en pause ou reprendre la série"
    static let description = IntentDescription("Met en pause la série en cours dans Rebond, ou la reprend.")
    static let isDiscoverable = true

    /// What the app does, and what to answer; nil in the widget extension.
    @MainActor static var handler: (@MainActor () -> LocalizedStringResource)?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(Self.handler?() ?? noSession))
    }
}

/// "Série suivante" from the Live Activity or from Siri: ends the set in progress with what was done, like the
/// Passer menu or the thumbs up.
struct NextSetIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Passer à la série suivante"
    static let description = IntentDescription("Termine la série en cours dans Rebond et passe à la suivante.")
    static let isDiscoverable = true

    @MainActor static var handler: (@MainActor () -> LocalizedStringResource)?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(Self.handler?() ?? noSession))
    }
}

/// "Exercice suivant" from Siri: ends the set in progress and skips the exercise's other sets, like the Passer
/// menu or two fingers. On the last exercise, ends the session.
struct NextExerciseIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Passer à l'exercice suivant"
    static let description = IntentDescription("Termine l'exercice en cours dans Rebond et passe au suivant.")
    static let isDiscoverable = true

    @MainActor static var handler: (@MainActor () -> LocalizedStringResource)?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        .result(dialog: IntentDialog(Self.handler?() ?? noSession))
    }
}

/// "Terminer la séance" from Siri: ends the session, which goes on to the pain then the summary (nothing done is
/// lost), like crossed arms. Siri asks first, when a session is in progress.
struct EndSessionIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "Terminer la séance"
    static let description = IntentDescription("Termine la séance en cours dans Rebond : il reste à indiquer la douleur.")
    static let isDiscoverable = true

    /// A session is in progress and can be ended now; nil in the widget extension.
    @MainActor static var canEnd: (@MainActor () -> Bool)?
    @MainActor static var handler: (@MainActor () -> LocalizedStringResource)?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        if Self.canEnd?() == true {
            // Throws when the patient says no: the session goes on.
            try await requestConfirmation(dialog: "Terminer la séance ?")
        }
        return .result(dialog: IntentDialog(Self.handler?() ?? noSession))
    }
}
