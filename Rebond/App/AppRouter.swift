import Observation
import SwiftData
import SwiftUI

/// Where the app is: the selected tab, the session in progress, adding a program, and the patient opened in the
/// physiotherapist space.
/// Shared with the App Intents, which can start a session from Shortcuts or Spotlight.
@Observable
final class AppRouter {
    static let shared = AppRouter()

    enum AppTab: Hashable {
        case today
        case program
        /// The physiotherapist space, only shown when it is turned on.
        case physio
    }

    /// Ways to add a program: the physiotherapist's message, scanning the sheet, picking a photo of it, or typing it.
    enum ImportSource {
        case message
        case scan
        case photo
        case manual
    }

    /// The physiotherapist space is the first tab shown at launch while it is turned on.
    var tab: AppTab = AppRole.isPhysiotherapistEnabled ? .physio : .today
    var isWorkoutPresented = false
    var importSource: ImportSource?
    /// A followed patient to show in the physiotherapist space, after their report was opened.
    var openedPatient: UUID?

    /// The program of the session to start; nil for the program of the day.
    var workoutProgram: PersistentIdentifier?
    /// Set to do only this exercise of the program (its index in the program's order).
    var workoutExerciseIndex: Int?

    /// Starts a session: the program of the day by default, another program, or a single exercise of one.
    /// Stays on the current tab: the session covers the screen and comes back to it.
    func startWorkout(_ program: Program? = nil, exercise: Int? = nil) {
        workoutProgram = program?.persistentModelID
        workoutExerciseIndex = exercise
        isWorkoutPresented = true
    }

    /// Opens the physiotherapist space, on a patient's page when given.
    func openPhysioSpace(patient: UUID? = nil) {
        tab = .physio
        openedPatient = patient
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
