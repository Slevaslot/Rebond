import SwiftData
import SwiftUI

@main struct RebondApp: App {
    @State private var router = AppRouter.shared
    @State private var store = ProStore()

    init() {
        // The Control Center button, the Action button and Siri start the session through the router.
        StartSessionIntent.handler = { AppRouter.shared.startWorkoutIfProgram() }
        ReminderActions.register()
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
