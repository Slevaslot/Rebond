import Foundation
import UserNotifications

/// Keys of the reminder settings, shared by the views.
enum ReminderSettings {
    static let enabledKey = "remindersEnabled"
    static let hourKey = "reminderHour"
    static let defaultHour = 18
}

/// Local notifications only: a reminder on session days, and one each Sunday to send the report.
/// Interruption level "active", never "time sensitive" (HIG: Managing notifications).
enum ReminderScheduler {
    private static let sessionPrefix = "session-"
    private static let reportID = "weekly-report"

    /// Asks for permission, then schedules the reminders. Returns whether they are on.
    static func enable(sessionsPerWeek: Int, hour: Int = ReminderSettings.defaultHour) async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        guard granted else { return false }
        await schedule(sessionsPerWeek: sessionsPerWeek, hour: hour)
        return true
    }

    /// Moves the session reminders to the new frequency after the program changed, when they are on.
    /// Asks nothing: without the setting turned on, nothing is scheduled.
    static func refreshIfEnabled(sessionsPerWeek: Int) async {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ReminderSettings.enabledKey) else { return }
        let hour = defaults.object(forKey: ReminderSettings.hourKey) as? Int ?? ReminderSettings.defaultHour
        await schedule(sessionsPerWeek: sessionsPerWeek, hour: hour)
    }

    static func disable() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }

    static func schedule(sessionsPerWeek: Int, hour: Int) async {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()

        for weekday in sessionDays(count: sessionsPerWeek) {
            let content = UNMutableNotificationContent()
            content.title = String(localized: "C'est l'heure de votre séance")
            content.body = String(localized: "Quelques minutes d'exercices, guidés par Rebond.")
            content.sound = .default
            content.interruptionLevel = .active
            var date = DateComponents()
            date.weekday = weekday
            date.hour = hour
            let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
            try? await center.add(UNNotificationRequest(identifier: "\(sessionPrefix)\(weekday)", content: content, trigger: trigger))
        }

        let report = UNMutableNotificationContent()
        report.title = String(localized: "Votre bilan de la semaine est prêt")
        report.body = String(localized: "Envoyez-le à votre kiné pour qu'il suive vos progrès.")
        report.interruptionLevel = .passive
        var sunday = DateComponents()
        sunday.weekday = 1
        sunday.hour = hour
        let trigger = UNCalendarNotificationTrigger(dateMatching: sunday, repeats: true)
        try? await center.add(UNNotificationRequest(identifier: reportID, content: report, trigger: trigger))
    }

    /// Session days spread over the week, Monday first (Calendar weekdays: 1 is Sunday).
    nonisolated static func sessionDays(count: Int) -> [Int] {
        let monday = [2, 3, 4, 5, 6, 7, 1]
        switch count {
        case ..<1: return []
        case 1: return [2]
        case 2: return [2, 5]
        case 3: return [2, 4, 6]
        case 4: return [2, 3, 5, 6]
        case 5: return [2, 3, 4, 5, 6]
        default: return Array(monday.prefix(min(count, 7)))
        }
    }
}
