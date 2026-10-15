import Foundation
import SwiftData
import Testing
@testable import Rebond

@Suite("Widgets")
struct WidgetSnapshotTests {
    /// Weeks start on Monday, in Paris.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: "Europe/Paris")!
        return calendar
    }

    private func date(_ day: Int, _ hour: Int = 10) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
    }

    private func snapshot(sessions: [Date]) -> WidgetSnapshot {
        var snapshot = WidgetSnapshot.sample
        snapshot.sessionsPerWeek = 3
        snapshot.sessionDates = sessions
        return snapshot
    }

    @Test func todayIsDoneOnlyWithASessionThatDay() {
        // Thursday 15 October 2026.
        let snapshot = snapshot(sessions: [date(14, 18)])
        #expect(!snapshot.isDone(on: date(15), calendar: calendar))
        #expect(snapshot.isDone(on: date(14, 8), calendar: calendar))
    }

    @Test func weekCountsSessionsSinceMonday() {
        // Sunday 11 is last week; Monday 12 and Wednesday 14 are this week.
        let snapshot = snapshot(sessions: [date(14), date(12), date(11)])
        let week = snapshot.week(containing: date(15), calendar: calendar)
        #expect(week.done == 2)
        #expect(week.planned == 3)
        #expect(!week.isComplete)
        #expect(week.days.count == 7)
        #expect(week.days.map(\.done) == [true, false, true, false, false, false, false])
        #expect(abs(week.fraction - 2.0 / 3.0) < 0.001)
    }

    @Test func weekGoalReachedCapsTheRing() {
        let snapshot = snapshot(sessions: [date(12), date(13), date(14), date(15)])
        let week = snapshot.week(containing: date(15), calendar: calendar)
        #expect(week.isComplete)
        #expect(week.fraction == 1)
    }

    @Test func refreshesAtMidnight() {
        let next = WidgetSnapshot.nextRefresh(after: date(15, 22), calendar: calendar)
        #expect(next == calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 0)))
    }

    @Test func survivesTheFileFormat() throws {
        let snapshot = snapshot(sessions: [date(14)])
        let decoded = try JSONDecoder().decode(WidgetSnapshot.self, from: JSONEncoder().encode(snapshot))
        #expect(decoded == snapshot)
    }

    @MainActor
    @Test func builtFromTheProgramAndRecentSessions() throws {
        let container = try ModelContainer(for: Program.self, Session.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let program = Program(sessionsPerWeek: 4, exercises: [
            PlannedExercise(catalogID: nil, name: "Gainage", sets: 2, reps: 0, holdSeconds: 30, order: 1),
            PlannedExercise(catalogID: "squat", name: "Squat", sets: 3, reps: 10, order: 0),
        ])
        let now = Date.now
        let sessions = [
            Session(date: now.addingTimeInterval(-3600), pain: 2, results: []),
            Session(date: now.addingTimeInterval(-40 * 86_400), pain: 2, results: []),
        ]
        context.insert(program)
        sessions.forEach(context.insert)
        let snapshot = WidgetSnapshot(programs: [program], sessions: sessions, now: now)
        #expect(snapshot.hasProgram)
        #expect(snapshot.sessionsPerWeek == 4)
        #expect(snapshot.exercises.map(\.name) == ["Squat", "Gainage"])
        #expect(snapshot.exercises[1].holdSeconds == 30)
        #expect(snapshot.sessionDates.count == 1)
        #expect(WidgetSnapshot(programs: [], sessions: sessions) == .empty)
    }

    @MainActor
    @Test func gathersTheProgramsOfTheDay() throws {
        let container = try ModelContainer(for: Program.self, Session.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let now = Date.now
        let today = Calendar.current.component(.weekday, from: now)
        let otherDay = today % 7 + 1
        let knee = Program(createdAt: now.addingTimeInterval(-60), sessionsPerWeek: 2, exercises: [
            PlannedExercise(catalogID: "squat", name: "Squat", sets: 3, reps: 10, order: 0),
        ], weekdays: [today, otherDay])
        let back = Program(createdAt: now, sessionsPerWeek: 1, exercises: [
            PlannedExercise(catalogID: nil, name: "Gainage", sets: 2, reps: 0, holdSeconds: 30, order: 0),
        ], weekdays: [today])
        let paused = Program(sessionsPerWeek: 1, exercises: [
            PlannedExercise(catalogID: nil, name: "Étirement", sets: 1, reps: 5, order: 0),
        ], weekdays: [today])
        paused.isActive = false
        [knee, back, paused].forEach(context.insert)

        let snapshot = WidgetSnapshot(programs: [back, paused, knee], sessions: [], now: now)
        // Oldest program first; a program not followed is left out.
        #expect(snapshot.exercises.map(\.name) == ["Squat", "Gainage"])
        // Two different days in the week, whatever the number of programs.
        #expect(snapshot.sessionsPerWeek == 2)
    }

    @Test func restDayShowsTheNextSession() {
        var snapshot = WidgetSnapshot.sample
        snapshot.sessionDay = date(15)
        #expect(snapshot.hasSession(on: date(15), calendar: calendar))
        #expect(snapshot.sessionTitle(on: date(15), calendar: calendar) == "Séance du jour")
        #expect(!snapshot.hasSession(on: date(14), calendar: calendar))
        #expect(snapshot.sessionTitle(on: date(14), calendar: calendar) == "Prochaine séance demain")
        #expect(snapshot.sessionTitle(on: date(13), calendar: calendar).hasPrefix("Prochaine séance "))
    }
}
