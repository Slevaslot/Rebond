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

    /// Sessions planned in a week: the days with at least one exercise.
    var sessionsPerWeek: Int {
        allDays.count
    }

    /// The exercises of the day's session, in the order they were added.
    func exercises(on date: Date) -> [PlannedExercise] {
        scheduled(on: date).flatMap(\.orderedExercises)
    }

    /// The session to do: today's exercises, otherwise those of the next day with some.
    func sessionExercises(on date: Date = .now) -> [PlannedExercise] {
        let today = exercises(on: date)
        if !today.isEmpty { return today }
        guard let next = next(after: date)?.day else { return [] }
        return exercises(on: next)
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

/// A name for a program the patient didn't name, from what it works on: "Jambes", "Épaules et dos"…
nonisolated enum ProgramNaming {
    enum Area: CaseIterable {
        case legs, shoulders, trunk, flexibility

        var name: String {
            switch self {
            case .legs: String(localized: "Jambes")
            case .shoulders: String(localized: "Épaules")
            case .trunk: String(localized: "Dos")
            case .flexibility: String(localized: "Souplesse")
            }
        }
    }

    static func area(name: String, catalogID: String?) -> Area? {
        switch catalogID {
        case "squat", "sit-to-stand", "leg-raise", "hurdle-step", "forward-lunge", "side-lunge": return .legs
        case "lateral-raise", "shoulder-abduction", "scaption", "shoulder-rotation": return .shoulders
        default: break
        }
        let name = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let words: [(Area, [String])] = [
            (.flexibility, ["etirement", "stretch", "souplesse"]),
            (.trunk, ["gainage", "planche", "pont", "bassin", "dos", "abdo", "lombaire"]),
            (.shoulders, ["epaule", "bras", "coude", "poignet", "cervical"]),
            (.legs, ["squat", "fente", "genou", "jambe", "hanche", "cheville", "mollet", "assis", "marche", "escalier", "equilibre"]),
        ]
        return words.first { _, keys in keys.contains { name.contains($0) } }?.0
    }

    /// The one or two areas most worked on, or "Mon programme".
    static func suggestedName(for exercises: [(name: String, catalogID: String?)]) -> String {
        var counts: [Area: Int] = [:]
        for exercise in exercises {
            if let area = area(name: exercise.name, catalogID: exercise.catalogID) { counts[area, default: 0] += 1 }
        }
        let top = Area.allCases.filter { counts[$0] != nil }.sorted { counts[$0]! > counts[$1]! }.prefix(2)
        switch top.count {
        case 0: return String(localized: "Ma séance")
        case 1: return top[0].name
        default:
            let second = top[1].name
            return String(localized: "\(top[0].name) et \(second.prefix(1).lowercased() + second.dropFirst())")
        }
    }
}
