import HealthKit
import SwiftUI
import WatchKit

/// Rebond on the Apple Watch: the set in progress on the wrist while the iPhone counts with its camera.
@main
struct RebondWatchApp: App {
    @WKApplicationDelegateAdaptor private var delegate: WatchAppDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(WatchModel.shared)
        }
    }
}

final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        WatchModel.shared.activate()
    }

    /// The iPhone started a session and opened the app (`HKHealthStore.startWatchApp`).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        WatchModel.shared.activate()
        WatchModel.shared.phoneStartedSession()
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let task = task as? WKWatchConnectivityRefreshBackgroundTask {
                WatchModel.shared.activate()
                WatchModel.shared.handle(task)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
