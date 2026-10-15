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
    /// The programs the patient follows now.
    var active: [Program] { filter(\.isActive) }

    /// The followed programs planned on that day, oldest first so the order stays the same.
    func scheduled(on date: Date) -> [Program] {
        active.filter { $0.isScheduled(on: date) }.sorted { $0.createdAt < $1.createdAt }
    }

    /// Every day with at least one session of a followed program, for the reminders and the week's dots.
    var allDays: [Int] {
        ProgramSchedule.days(weekdays: active.flatMap(\.days), sessionsPerWeek: 0)
    }

    /// Sessions planned in a week, followed programs together.
    var sessionsPerWeek: Int {
        active.reduce(0) { $0 + $1.days.count }
    }

    /// The next session of a followed program after `date`: which program, which day.
    func next(after date: Date = .now) -> (program: Program, day: Date)? {
        active.compactMap { program in ProgramSchedule.nextDay(after: date, in: program.days).map { (program, $0) } }
            .min { $0.1 < $1.1 }
    }

    /// The program to show first: the one of the day, otherwise the next one coming.
    func current(on date: Date = .now) -> Program? {
        scheduled(on: date).first ?? next(after: date)?.program ?? active.first ?? first
    }
}
