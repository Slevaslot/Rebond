import Foundation
import Testing
@testable import Rebond

@Suite("Séance")
struct WorkoutPlanTests {
    private let exercises = [
        WorkoutExercise(name: "Squat", catalogID: "squat", mode: .camera(catalogID: "squat"), sets: 2, reps: 10),
        WorkoutExercise(name: "Gainage", catalogID: nil, mode: .hold(seconds: 30), sets: 1, reps: 0),
    ]

    @Test func oneStepPerSet() {
        let plan = WorkoutPlan(exercises: exercises)
        #expect(plan.steps.count == 3)
        #expect(plan.usesCamera)
        #expect(plan.currentStep?.set == 1)
    }

    @Test func addsUpSetsAndKeepsBestAmplitude() {
        var plan = WorkoutPlan(exercises: exercises)
        plan.record(SetResult(completedReps: 8, incompleteReps: 2, amplitude: 90))
        plan.record(SetResult(completedReps: 10, amplitude: 104))
        plan.record(SetResult(heldSeconds: 30))
        #expect(plan.isFinished)
        #expect(plan.tallies[0] == ExerciseTally(completedReps: 18, incompleteReps: 2, amplitude: 104, setsDone: 2))
        #expect(plan.tallies[1].heldSeconds == 30)
        #expect(!plan.nothingDone)
    }

    @Test func stoppingEarlyKeepsWhatWasDone() {
        var plan = WorkoutPlan(exercises: exercises)
        #expect(plan.nothingDone)
        plan.record(SetResult(completedReps: 5))
        plan.finishEarly()
        #expect(plan.isFinished)
        #expect(plan.summary.count == 2)
        #expect(plan.summary[1].tally.setsDone == 0)
    }
}

@Suite("Bilan hebdomadaire")
struct WeeklyReportTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(daysAgo: Double, pain: Int, reps: Int, amplitude: Double?) -> WeeklyReport.SessionData {
        WeeklyReport.SessionData(date: now.addingTimeInterval(-daysAgo * 86_400), pain: pain, results: [
            .init(name: "Squat", order: 0, plannedReps: 20, completedReps: reps, incompleteReps: 1,
                  plannedSeconds: 0, heldSeconds: 0, amplitude: amplitude),
            .init(name: "Gainage", order: 1, plannedReps: 0, completedReps: 0, incompleteReps: 0,
                  plannedSeconds: 60, heldSeconds: 45, amplitude: nil),
        ])
    }

    @Test func keepsTheLastSevenDays() {
        let report = WeeklyReport(sessions: [
            session(daysAgo: 10, pain: 2, reps: 20, amplitude: 70),
            session(daysAgo: 5, pain: 4, reps: 18, amplitude: 85),
            session(daysAgo: 3, pain: 8, reps: 12, amplitude: 80),
            session(daysAgo: 1, pain: 3, reps: 20, amplitude: 97),
        ], sessionsPerWeek: 3, end: now)

        #expect(report.sessionsDone == 3)
        #expect(report.exercises.map(\.name) == ["Squat", "Gainage"])
        let squat = report.exercises[0]
        #expect(squat.completedReps == 50)
        #expect(squat.plannedReps == 60)
        #expect(squat.firstAmplitude == 85)
        #expect(squat.lastAmplitude == 97)
        #expect(report.exercises[1].isHeld)
        #expect(report.exercises[1].heldSeconds == 135)
        #expect(report.painfulSessionDates.count == 1)
        #expect(report.sessionLines.map(\.pain) == [4, 8, 3])
        #expect(report.painfulSessions.map(\.pain) == [8])
        #expect(report.firstPain == 4)
        #expect(report.lastPain == 3)
    }

    @Test func emptyWeek() {
        let report = WeeklyReport(sessions: [session(daysAgo: 12, pain: 2, reps: 20, amplitude: nil)], sessionsPerWeek: 3, end: now)
        #expect(report.sessionsDone == 0)
        #expect(report.averagePain == nil)
        #expect(report.exercises.isEmpty)
    }
}

@Suite("Programme")
struct ProgramTests {
    @Test func catalogIDsAreUnique() {
        #expect(Set(CatalogExercise.all.map(\.id)).count == CatalogExercise.all.count)
        #expect(ExerciseKind.squat.catalogID == CatalogExercise.squat.id)
        #expect(ExerciseKind.lateralRaise.catalogID == CatalogExercise.lateralRaise.id)
        #expect(ExerciseKind.other.catalogID == nil)
    }

    @Test func reminderDaysSpreadOverTheWeek() {
        #expect(ReminderScheduler.sessionDays(count: 3) == [2, 4, 6])
        #expect(ReminderScheduler.sessionDays(count: 0).isEmpty)
        #expect(ReminderScheduler.sessionDays(count: 7).count == 7)
        #expect(ReminderScheduler.sessionDays(count: 14).count == 7)
    }

    @Test func editableProgramNeedsNamedExercises() {
        var program = EditableProgram()
        #expect(!program.isValid)
        program.exercises = [.init(name: "  ", catalogID: nil, sets: 3, reps: 10)]
        #expect(!program.isValid)
        program.exercises[0].name = "Pont fessier"
        #expect(program.isValid)
        #expect(!program.hasGuesses)
    }
}
