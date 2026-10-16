import SwiftData
import SwiftUI
import TipKit

@main struct RebondApp: App {
    @State private var router = AppRouter.shared
    @State private var store = ProStore()

    init() {
        // The Control Center button, the Action button and Siri start the session through the router.
        StartSessionIntent.handler = { AppRouter.shared.startWorkoutIfProgram() }
        ReminderActions.register()
        // The Apple Watch: the set on the wrist during the session, today's session on the watch face.
        PhoneWatchLink.shared.activate()
        // The session's commands from Siri and the Live Activity: the same path as the buttons, the hand signs
        // and the watch (`SessionRemote`). Siri answers with what was really done, or why nothing was.
        ToggleSessionPauseIntent.handler = {
            // Paused without walking back to the phone: no need to suggest it any more.
            SiriPauseTip().invalidate(reason: .actionPerformed)
            return Self.answer(.togglePause)
        }
        NextSetIntent.handler = { Self.answer(.nextSet) }
        NextExerciseIntent.handler = { Self.answer(.nextExercise) }
        EndSessionIntent.handler = { Self.answer(.endSession) }
        EndSessionIntent.canEnd = {
            if case .endSession = SessionCommand.endSession.resolve(on: SessionRemote.shared.screen, from: .siri) {
                return true
            }
            return false
        }
        // The hands-free controls of the session, made discoverable (TipKit).
        SessionTips.configure()
    }

    /// Sends a command from Siri (or the Live Activity, which shares its intents) and says what it did.
    private static func answer(_ command: SessionCommand) -> LocalizedStringResource {
        let action = SessionRemote.shared.send(command, from: .siri)
        if case .ignored(let reason) = action { return reason }
        return action.confirmation ?? "C'est noté"
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(store)
                .task { await store.refresh() }
                // Filmed movements learned by an older analysis: learned again once, in the background.
                .task(priority: .background) { await ReferenceStore.upgradeOlderMovements() }
                // Widgets: the snapshot they read, and their links (today's session, a new program, Accueil).
                .modifier(WidgetSync())
                .onOpenURL { url in
                    if let destination = DeepLink.destination(of: url) { router.open(destination) }
                }
        }
        .modelContainer(AppData.container)
    }
}
