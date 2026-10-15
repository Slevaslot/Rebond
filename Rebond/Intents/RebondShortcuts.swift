import AppIntents

extension AppRouter {
    /// Starts the session from outside the app (widget, Shortcuts, Spotlight). Without a program yet,
    /// shows the Accueil page, which explains how to add one, rather than an empty session.
    func startWorkoutIfProgram() {
        if WidgetSnapshot.load()?.hasProgram == false {
            tab = .today
        } else {
            startWorkout()
        }
    }
}

/// Phrases for Shortcuts, Spotlight and Siri. They work without Siri AI (unavailable in the EU with iOS 27):
/// they are simple App Shortcuts, also offered in Spotlight and the Shortcuts app.
struct RebondShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartSessionIntent(),
            phrases: [
                "Commencer ma séance avec \(.applicationName)",
                "Démarrer ma séance \(.applicationName)",
                "Commencer ma séance \(.applicationName)",
                "Lancer ma séance \(.applicationName)",
                "Faire mes exercices avec \(.applicationName)",
                "Start my \(.applicationName) session",
            ],
            shortTitle: "Démarrer ma séance",
            systemImageName: "figure.cooldown"
        )
        AppShortcut(
            intent: WeekProgressIntent(),
            phrases: [
                "Combien de séances cette semaine avec \(.applicationName)",
                "Mes séances de la semaine \(.applicationName)",
                "Ma régularité \(.applicationName)",
                "How many \(.applicationName) sessions this week",
            ],
            shortTitle: "Séances de la semaine",
            systemImageName: "chart.bar"
        )
        AppShortcut(
            intent: StartSeanceIntent(),
            phrases: [
                "Commencer \(\.$target) avec \(.applicationName)",
                "Lancer \(\.$target) avec \(.applicationName)",
            ],
            shortTitle: "Commencer une séance",
            systemImageName: "figure.mixed.cardio"
        )
    }
}
