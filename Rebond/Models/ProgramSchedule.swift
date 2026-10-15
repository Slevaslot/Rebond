import Foundation

/// The days of the programs, without SwiftData: tested on its own.
nonisolated enum ProgramSchedule {
    /// Calendar weekdays (1 is Sunday) in the order of a French week.
    static let mondayFirst = [2, 3, 4, 5, 6, 7, 1]

    /// The given days, Monday first and without repeats; or, without days, `sessionsPerWeek` sessions
    /// spread over the week, as the reminders always did.
    static func days(weekdays: [Int], sessionsPerWeek: Int) -> [Int] {
        guard !weekdays.isEmpty else { return ReminderScheduler.sessionDays(count: sessionsPerWeek) }
        let set = Set(weekdays)
        return mondayFirst.filter(set.contains)
    }

    /// The next day after `date` (not the same day) that is one of `days`.
    static func nextDay(after date: Date, in days: some Collection<Int>, calendar: Calendar = .current) -> Date? {
        guard !days.isEmpty else { return nil }
        for offset in 1...7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: date) else { continue }
            if days.contains(calendar.component(.weekday, from: day)) { return calendar.startOfDay(for: day) }
        }
        return nil
    }

    /// "lundi, mercredi et vendredi", or "tous les jours".
    static func describe(_ days: [Int], calendar: Calendar = .current) -> String {
        if Set(days).count >= 7 { return String(localized: "tous les jours") }
        let symbols = calendar.weekdaySymbols
        return mondayFirst.filter(days.contains).map { symbols[$0 - 1] }.formatted(.list(type: .and))
    }
}

extension Array where Element == Program {
    /// The programs planned on that day, oldest first so the order stays the same.
    func scheduled(on date: Date) -> [Program] {
        filter { $0.isScheduled(on: date) }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Every day with at least one session, for the reminders and the week's dots.
    var allDays: [Int] {
        ProgramSchedule.days(weekdays: flatMap(\.days), sessionsPerWeek: 0)
    }

    /// Sessions planned in a week, all programs together.
    var sessionsPerWeek: Int {
        isEmpty ? 0 : reduce(0) { $0 + $1.days.count }
    }

    /// The program to show first: the one of the day, otherwise the next one coming.
    func current(on date: Date = .now) -> Program? {
        if let today = scheduled(on: date).first { return today }
        let next = compactMap { program in
            ProgramSchedule.nextDay(after: date, in: program.days).map { (program, $0) }
        }
        return next.min { $0.1 < $1.1 }?.0 ?? first
    }
}
