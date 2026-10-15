import Foundation

// Compiled into both the app and the widget extension (folder `Shared/`).

/// The App Group shared by the app and its widgets. Nothing in it leaves the iPhone.
nonisolated enum SharedContainer {
    static let appGroup = "group.com.rebond.app"

    /// Nil when the App Group is missing from the entitlements (misconfigured signing).
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
}

/// Links that open the app from a widget or a Live Activity.
nonisolated enum DeepLink {
    static let scheme = "rebond"
    /// Opens the app on today's session, ready to start.
    static let session = URL(string: "rebond://seance")!

    static func isSession(_ url: URL) -> Bool {
        url.scheme == scheme && url.host() == session.host()
    }
}
