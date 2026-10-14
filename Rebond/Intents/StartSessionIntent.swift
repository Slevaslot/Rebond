import AppIntents

/// "Démarrer ma séance": from Shortcuts, Spotlight, the Action button or Control Center.
struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Démarrer ma séance"
    static let description = IntentDescription("Ouvre Rebond et lance la séance de votre programme.")
    static let supportedModes: IntentModes = .foreground

    @MainActor
    func perform() async throws -> some IntentResult {
        AppRouter.shared.startWorkout()
        return .result()
    }
}

struct RebondShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Démarrer ma séance \(.applicationName)",
                "Commencer ma séance \(.applicationName)",
                "Start my \(.applicationName) session",
            ],
            shortTitle: "Démarrer ma séance",
            systemImageName: "figure.cooldown"
        )
    }
}
