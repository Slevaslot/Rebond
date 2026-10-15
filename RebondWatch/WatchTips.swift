import SwiftUI
import TipKit

/// Double Tap, made discoverable (TipKit): the patient's hands are busy with the exercise.
enum WatchTips {
    /// Called once at launch.
    static func configure() {
        #if DEBUG
        // Demo and simulator: `-RebondResetTips` shows the tip again, `-RebondShowAllTips` whatever its rules.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-RebondResetTips") { try? Tips.resetDatastore() }
        if arguments.contains("-RebondShowAllTips") { Tips.showAllTipsForTesting() }
        #endif
        try? Tips.configure([.displayFrequency(.immediate)])
    }
}

/// Shown on the set once the iPhone counts (the placement and the calibration are over), while it can be paused.
/// Once. A title only: the set must stay visible on the small screen.
struct DoubleTapTip: Tip {
    var title: Text {
        Text("Pincez deux fois pour mettre en pause")
    }

    var image: Image? {
        Image(systemName: "hand.pinch.fill")
    }

    var options: [any TipOption] {
        MaxDisplayCount(1)
    }
}
