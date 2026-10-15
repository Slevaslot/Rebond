import SwiftUI
import TipKit

/// The hands-free controls of the session, made discoverable with TipKit. One tip at a time, never during the
/// placement or the calibration: each one has its own screen and moment.
enum SessionTips {
    /// Called once at launch.
    static func configure() {
        #if DEBUG
        // Demo and simulator: `-RebondResetTips` shows the tips again from the start, `-RebondShowAllTips`
        // shows them whatever their rules.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-RebondResetTips") { try? Tips.resetDatastore() }
        if arguments.contains("-RebondShowAllTips") { Tips.showAllTipsForTesting() }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// "Dis Siri, pause dans Rebond": shown when the patient walked back to the phone to pause the set by touch,
/// from their second session on. Once.
struct SiriPauseTip: Tip {
    /// A session saved, donated by `WorkoutView`.
    static let sessionSaved = Tips.Event(id: "sessionSaved")

    var title: Text {
        Text("Mettez en pause à la voix")
    }

    var message: Text? {
        Text("Dites « Dis Siri, pause dans Rebond » pour mettre en pause sans revenir au téléphone.")
    }

    var image: Image? {
        Image(systemName: "waveform")
    }

    var rules: [Rule] {
        // The first session already has a lot to discover.
        #Rule(Self.sessionSaved) { $0.donations.count >= 1 }
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}

/// An Apple Watch is paired but Rebond isn't on it: shown in the summary at the end of the session, when no other
/// offer is shown there.
struct WatchAppTip: Tip {
    var title: Text {
        Text("Suivez vos séries sur votre Apple Watch")
    }

    var message: Text? {
        Text("Installez Rebond sur votre montre depuis l'app Watch : la série s'affiche à votre poignet, qui tapote à chaque répétition.")
    }

    var image: Image? {
        Image(systemName: "applewatch")
    }

    var options: [any TipOption] {
        MaxDisplayCount(2)
    }
}
