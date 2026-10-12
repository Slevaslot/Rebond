import SwiftData
import SwiftUI

@main struct RebondApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [Program.self, Session.self])
    }
}
