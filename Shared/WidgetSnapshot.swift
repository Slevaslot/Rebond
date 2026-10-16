import Foundation

// Compiled into both the app and the widget extension (folder `Shared/`).

/// What the widgets and the App Intents need to know, written by the app into the App Group each time the
/// program or the sessions change. A small file rather than the SwiftData store itself: the extension does
/// not depend on the models, and the store stays where it is (no migration of existing data).
/// Pure logic, tested without a screen.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    struct Exercise: Codable, Equatable, Sendable {
        let name: String
        /// SF Symbol of the exercise.
        let symbol: String
        let sets: Int
        let reps: Int
        /// Seconds per set for a held exercise, nil for repetitions.
        let holdSeconds: Int?
    }

    /// False until a program is saved.
    var hasProgram: Bool
    var sessionsPerWeek: Int
    var exercises: [Exercise]
    var estimatedMinutes: Int
    /// Dates of the recent sessions (the last few weeks), most recent first.
    var sessionDates: [Date]
    /// The day of `exercises`: today, or the next day with a session on a rest day. Nil in older files.
    var sessionDay: Date? = nil
    /// The days with a session, from the day the file was written and for `upcomingDays` days: the widgets
    /// stay right on the following days, even if the app is not opened. Nil in older files.
    var upcoming: [PlannedDay]? = nil

    /// A day with a session, and its exercises.
    struct PlannedDay: Codable, Equatable, Sendable {
        /// Start of the day.
        let day: Date
        let exercises: [Exercise]
        let estimatedMinutes: Int
    }

    static let empty = WidgetSnapshot(hasProgram: false, sessionsPerWeek: 0, exercises: [], estimatedMinutes: 0, sessionDates: [])

    /// Sessions kept in the file: enough for the current week, whatever the first weekday.
    static let keptDays = 14
    /// Days of `upcoming`: a week of timeline entries, each one finding its next session within a week.
    static let upcomingDays = 14

    // MARK: Derived values

    /// The snapshot as it reads on `date`: the session of that day, or the next one, taken from `upcoming`.
    /// Unchanged for older files, or past the days known.
    func resolved(on date: Date, calendar: Calendar = .current) -> WidgetSnapshot {
        let start = calendar.startOfDay(for: date)
        guard hasProgram, let next = upcoming?.first(where: { calendar.startOfDay(for: $0.day) >= start }) else { return self }
        var snapshot = self
        snapshot.exercises = next.exercises
        snapshot.estimatedMinutes = next.estimatedMinutes
        snapshot.sessionDay = next.day
        return snapshot
    }

    /// Where a tap leads on `date`, matching what the widget shows: creating a program while there is none,
    /// the session while today's is to do, otherwise the Accueil page (rest day, session done).
    /// To call on the snapshot resolved for that date.
    func destination(on date: Date, calendar: Calendar = .current) -> DeepLink.Destination {
        guard hasProgram else { return .newProgram }
        return hasSession(on: date, calendar: calendar) && !isDone(on: date, calendar: calendar) ? .session : .home
    }

    /// The exercises are the ones of `date` (always true for older files, without `sessionDay`).
    func hasSession(on date: Date, calendar: Calendar = .current) -> Bool {
        sessionDay.map { calendar.isDate($0, inSameDayAs: date) } ?? true
    }

    /// "Séance du jour" when the exercises are today's; "Prochaine séance demain", or "… mercredi", on a rest day.
    func sessionTitle(on date: Date, calendar: Calendar = .current) -> String {
        guard let sessionDay, !hasSession(on: date, calendar: calendar) else {
            return String(localized: "Séance du jour")
        }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: date), calendar.isDate(sessionDay, inSameDayAs: tomorrow) {
            return String(localized: "Prochaine séance demain")
        }
        return String(localized: "Prochaine séance \(sessionDay.formatted(.dateTime.weekday(.wide)))")
    }

    /// A session was saved that day.
    func isDone(on day: Date, calendar: Calendar = .current) -> Bool {
        sessionDates.contains { calendar.isDate($0, inSameDayAs: day) }
    }

    struct Week: Equatable, Sendable {
        let done: Int
        let planned: Int
        /// The seven days of the week, with whether a session was done that day.
        let days: [Day]

        struct Day: Equatable, Sendable {
            let date: Date
            let done: Bool
        }

        var isComplete: Bool { planned > 0 && done >= planned }
        /// 0 to 1, for the regularity ring.
        var fraction: Double { planned > 0 ? min(1, Double(done) / Double(planned)) : 0 }
    }

    /// Sessions done in the calendar week of `date` (same rule as the Aujourd'hui page).
    func week(containing date: Date, calendar: Calendar = .current) -> Week {
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        let done = sessionDates.filter { interval?.contains($0) ?? false }.count
        let days: [Week.Day] = (0..<7).compactMap { offset in
            guard let start = interval?.start, let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return Week.Day(date: day, done: isDone(on: day, calendar: calendar))
        }
        return Week(done: done, planned: sessionsPerWeek, days: days)
    }

    /// When what the widgets show changes by itself: the next midnight (today's session) and,
    /// through it, the start of a new week.
    static func nextRefresh(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(after: date, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime)
            ?? date.addingTimeInterval(24 * 3600)
    }

    /// `date`, then the next `days` midnights: the entries of a widget timeline.
    static func timelineDates(from date: Date, days: Int, calendar: Calendar = .current) -> [Date] {
        var dates = [date]
        for _ in 0..<days {
            dates.append(nextRefresh(after: dates[dates.count - 1], calendar: calendar))
        }
        return dates
    }

    // MARK: File in the App Group

    static let fileName = "widget-snapshot.json"

    private static var fileURL: URL? {
        SharedContainer.url?.appending(path: fileName)
    }

    /// The last snapshot written by the app, or nil if none (app never opened, App Group missing).
    static func load() -> WidgetSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Writes the snapshot. Returns false when nothing changed or the App Group is unavailable.
    @discardableResult
    func save() -> Bool {
        guard let fileURL = Self.fileURL, Self.load() != self,
              let data = try? JSONEncoder().encode(self)
        else { return false }
        return (try? data.write(to: fileURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])) != nil
    }
}

nonisolated extension WidgetSnapshot {
    /// Sample data for the widget gallery and the previews.
    static let sample = WidgetSnapshot(
        hasProgram: true,
        sessionsPerWeek: 3,
        exercises: [
            Exercise(name: "Squat", symbol: "figure.strengthtraining.functional", sets: 3, reps: 10, holdSeconds: nil),
            Exercise(name: "Élévation latérale des bras", symbol: "figure.arms.open", sets: 3, reps: 12, holdSeconds: nil),
            Exercise(name: "Gainage", symbol: "timer", sets: 3, reps: 0, holdSeconds: 30),
        ],
        estimatedMinutes: 12,
        sessionDates: [Date.now.addingTimeInterval(-2 * 86_400)]
    )
}
