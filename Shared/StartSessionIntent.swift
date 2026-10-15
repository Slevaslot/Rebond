import AppIntents

/// "Démarrer ma séance": from Shortcuts, Spotlight, the Action button or Control Center.
/// Shared with the widget extension for the Control Center button; it always runs in the app, which sets
/// `handler` at launch.
struct StartSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "Démarrer ma séance"
    static let description = IntentDescription("Ouvre Rebond et lance la séance de votre programme.")
    static let supportedModes: IntentModes = .foreground

    /// What the app does to start the session; nil in the widget extension.
    @MainActor static var handler: (() -> Void)?

    @MainActor
    func perform() async throws -> some IntentResult {
        Self.handler?()
        return .result()
    }
}
