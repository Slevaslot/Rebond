import Foundation

// Compiled into both the app and the widget extension (folder `Shared/`).

/// The App Group shared by the app and its widgets. Nothing in it leaves the iPhone.
nonisolated enum SharedContainer {
    static let appGroup = "group.com.mwm.rebond"

    /// Nil when the App Group is missing from the entitlements (misconfigured signing).
    static var url: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }
}

/// Links that open the app from a widget or a Live Activity. The QR code of a prescription
/// (`rebond://programme?d=…`) is handled apart, by `ProgramTransfer`.
nonisolated enum DeepLink {
    static let scheme = "rebond"

    /// Where a link leads: the host of `rebond://<host>`.
    enum Destination: String, CaseIterable, Sendable {
        /// Today's session, ready to start.
        case session = "seance"
        /// "Créer un programme", while there is none yet.
        case newProgram = "nouveau-programme"
        /// The Accueil page: rest day, session already done.
        case home = "accueil"

        var url: URL { URL(string: "\(DeepLink.scheme)://\(rawValue)")! }
    }

    /// Opens the app on today's session, ready to start.
    static let session = Destination.session.url

    /// The destination of a widget link; nil for any other URL (prescription, report file).
    static func destination(of url: URL) -> Destination? {
        guard url.scheme == scheme, let host = url.host() else { return nil }
        return Destination(rawValue: host)
    }
}
