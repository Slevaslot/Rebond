import AppIntents

/// Pause from the wrist with Siri ("Pause dans Rebond"), during a session the iPhone follows.
struct WatchPauseIntent: AppIntent {
    static let title: LocalizedStringResource = "Mettre en pause ou reprendre la série"
    static let description = IntentDescription("Met en pause la série en cours dans Rebond, ou la reprend.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WatchModel.shared.set != nil else {
            return .result(dialog: "Aucune série en cours. Lancez la séance sur votre iPhone.")
        }
        WatchModel.shared.togglePause()
        return .result(dialog: "C'est fait.")
    }
}

/// Next set from the wrist with Siri.
struct WatchNextSetIntent: AppIntent {
    static let title: LocalizedStringResource = "Passer à la série suivante"
    static let description = IntentDescription("Termine la série en cours dans Rebond et passe à la suivante.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard WatchModel.shared.set != nil else {
            return .result(dialog: "Aucune série en cours. Lancez la séance sur votre iPhone.")
        }
        WatchModel.shared.nextSet()
        return .result(dialog: "Série suivante.")
    }
}

/// Siri on the watch, without Siri AI (unavailable in the EU with watchOS 27): simple App Shortcuts.
struct RebondWatchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WeekProgressIntent(),
            phrases: [
                "Combien de séances cette semaine avec \(.applicationName)",
                "Ma régularité \(.applicationName)",
                "How many \(.applicationName) sessions this week",
            ],
            shortTitle: "Séances de la semaine",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: WatchPauseIntent(),
            phrases: [
                "Pause dans \(.applicationName)",
                "Reprendre dans \(.applicationName)",
            ],
            shortTitle: "Pause",
            systemImageName: "pause.fill"
        )
        AppShortcut(
            intent: WatchNextSetIntent(),
            phrases: [
                "Série suivante dans \(.applicationName)",
                "Next set in \(.applicationName)",
            ],
            shortTitle: "Série suivante",
            systemImageName: "forward.end.fill"
        )
    }
}
