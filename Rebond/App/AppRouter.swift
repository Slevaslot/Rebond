import Observation
import SwiftUI

/// Where the app is: the selected tab, the session in progress, and adding a program.
/// Shared with the App Intents, which can start a session from Shortcuts or Spotlight.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum AppTab: Hashable {
        case today
        case program
        case progress
    }

    /// Ways to add a program: scanning the sheet, picking a photo of it, or typing it.
    enum ImportSource {
        case scan
        case photo
        case manual
    }

    var tab = AppTab.today
    var isWorkoutPresented = false
    var importSource: ImportSource?

    func startWorkout() {
        tab = .today
        isWorkoutPresented = true
    }

    func addProgram(from source: ImportSource) {
        // Without the document scanner (simulator), pick a photo of the sheet instead.
        importSource = source == .scan && !DocumentScanner.isAvailable ? .photo : source
    }
}

/// Fixed addresses shown in the app and on the store page.
enum AppLinks {
    /// Privacy policy: required by App Store Connect, shown in the app and on the paywall.
    static let privacyPolicy = URL(string: "https://rebond.app/confidentialite")!
    /// Apple's standard license agreement, used for the subscription terms.
    static let terms = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}
