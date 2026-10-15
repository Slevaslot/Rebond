import Foundation
import UserNotifications

/// The buttons of the session reminder: "Commencer maintenant" opens the session, "Dans 1 heure" reminds
/// again an hour later. Also shows the reminders while Rebond is open.
final class ReminderActions: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let sessionCategory = "session"
    nonisolated private static let startAction = "start"
    nonisolated private static let laterAction = "later"
    private static let shared = ReminderActions()

    static func register() {
        let center = UNUserNotificationCenter.current()
        let start = UNNotificationAction(identifier: startAction, title: String(localized: "Commencer maintenant"),
                                         options: .foreground, icon: .init(systemImageName: "play.fill"))
        let later = UNNotificationAction(identifier: laterAction, title: String(localized: "Dans 1 heure"),
                                         icon: .init(systemImageName: "clock"))
        center.setNotificationCategories([
            UNNotificationCategory(identifier: sessionCategory, actions: [start, later], intentIdentifiers: []),
        ])
        center.delegate = shared
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let isSession = response.notification.request.content.categoryIdentifier == Self.sessionCategory
        guard isSession else { return }
        switch action {
        case Self.startAction, UNNotificationDefaultActionIdentifier:
            await MainActor.run { AppRouter.shared.startWorkoutIfProgram() }
        case Self.laterAction:
            await ReminderScheduler.remindLater()
        default:
            break
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
