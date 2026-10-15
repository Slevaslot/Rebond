import Foundation
import SwiftData
import Testing
@testable import Rebond

@Suite("Jours des programmes")
struct ProgramScheduleTests {
    private let calendar = Calendar(identifier: .gregorian)

    @Test func daysAreMondayFirstWithoutRepeats() {
        #expect(ProgramSchedule.days(weekdays: [1, 4, 2, 4], sessionsPerWeek: 0) == [2, 4, 1])
    }

    @Test func withoutDaysTheSessionsAreSpread() {
        #expect(ProgramSchedule.days(weekdays: [], sessionsPerWeek: 3) == [2, 4, 6])
    }

    @Test func nextDayIsAfterToday() throws {
        // Wednesday 14 October 2026.
        let wednesday = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 9)))
        let next = try #require(ProgramSchedule.nextDay(after: wednesday, in: [4, 6], calendar: calendar))
        #expect(calendar.component(.weekday, from: next) == 6)
        let nextWeek = try #require(ProgramSchedule.nextDay(after: wednesday, in: [4], calendar: calendar))
        #expect(calendar.dateComponents([.day], from: wednesday, to: nextWeek).day == 6)
    }

    @Test func editableProgramKeepsCountAndDaysTogether() {
        var program = EditableProgram()
        program.sessionsPerWeek = 2
        #expect(program.weekdays == [2, 5])
        program.weekdays = [3]
        #expect(program.sessionsPerWeek == 1)
        program.weekdays = []
        program.exercises = [.init(name: "Squat", catalogID: nil, sets: 1, reps: 1)]
        #expect(!program.isValid)
    }

    @Test func prescriptionCarriesDaysAndName() throws {
        var program = EditableProgram()
        program.name = "Genou"
        program.weekdays = [3, 5]
        program.exercises = [.init(name: "Squat", catalogID: "squat", sets: 3, reps: 12)]
        let url = try #require(ProgramTransfer(program, physiotherapist: "Claire").url)
        let received = try #require(ProgramTransfer(url: url)).editableProgram
        #expect(received.weekdays == [3, 5])
        #expect(received.name == "Genou")
    }

    @MainActor
    @Test func oneSeanceADay() throws {
        let container = try ModelContainer(for: Program.self, Session.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        var knee = EditableProgram()
        knee.weekdays = [2, 4, 6]
        knee.exercises = [.init(name: "Squat", catalogID: "squat", sets: 2, reps: 10)]
        let first = Program.add(knee, in: context)
        var back = EditableProgram()
        back.weekdays = [3, 4]
        back.exercises = [.init(name: "Gainage", catalogID: nil, sets: 2, reps: 10)]
        let second = Program.add(back, in: context)

        // Wednesday goes to the new séance.
        #expect(first.days == [2, 6])
        #expect(second.days == [3, 4])

        // Monday given back to the back séance from the week.
        second.toggle(2, in: context)
        #expect(first.days == [6])
        #expect(second.days == [2, 3, 4])

        // Resting on Friday: no séance keeps it.
        first.toggle(6, in: context)
        #expect(first.days.isEmpty)
        #expect([first, second].allDays == [2, 3, 4])
    }
}
