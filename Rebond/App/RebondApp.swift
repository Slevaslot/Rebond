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
        // Pause and next set from the Live Activity and Siri: the same path as the watch's buttons.
        ToggleSessionPauseIntent.handler = {
            PhoneWatchLink.shared.perform(.togglePause)
            // Paused without walking back to the phone: no need to suggest it any more.
            SiriPauseTip().invalidate(reason: .actionPerformed)
        }
        NextSetIntent.handler = { PhoneWatchLink.shared.perform(.nextSet) }
        // The hands-free controls of the session, made discoverable (TipKit).
        SessionTips.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(store)
                .task { await store.refresh() }
                // Widgets: the snapshot they read, and the link that opens today's session.
                .modifier(WidgetSync())
                .onOpenURL { url in
                    if DeepLink.isSession(url) { router.startWorkoutIfProgram() }
                }
        }
        .modelContainer(AppData.container)
    }
}
