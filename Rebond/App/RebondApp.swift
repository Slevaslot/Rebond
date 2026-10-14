import SwiftData
import SwiftUI

@main struct RebondApp: App {
    @State private var router = AppRouter.shared
    @State private var store = ProStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
                .environment(store)
                .task { await store.refresh() }
        }
        .modelContainer(for: [Program.self, Session.self, TrackedPatient.self])
    }
}
