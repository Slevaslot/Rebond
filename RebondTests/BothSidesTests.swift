import Foundation
import SwiftData
import Testing
@testable import Rebond

@Suite("Des deux côtés")
struct BothSidesTests {
    /// Filmed on the left leg: the left side first, then the right one, mirrored.
    private let leftLeg = WorkoutExercise(name: "Fente", catalogID: "filmed", mode: .camera(catalogID: "filmed"),
                                          sets: 2, reps: 8, bothSides: true, firstSide: .left)

    @Test func eachSetOnBothSides() {
        let plan = WorkoutPlan(exercises: [leftLeg])
        #expect(plan.steps.map(\.set) == [1, 1, 2, 2])
        #expect(plan.steps.map(\.side) == [.left, .right, .left, .right])
        #expect(plan.steps.map(\.isMirrored) == [false, true, false, true])
    }

    @Test func oneSideInMirror() {
        // Filmed on the left leg, done on the right one only: named, shown in mirror, every set.
        var mirrored = leftLeg
        mirrored.bothSides = false
        mirrored.mirrored = true
        var plan = WorkoutPlan(exercises: [mirrored])
        #expect(plan.steps.map(\.side) == [.right, .right])
        #expect(plan.steps.allSatisfy { $0.isMirrored })
        plan.record(SetResult(completedReps: 8))
        plan.addSet()
        #expect(plan.steps.last?.isMirrored == true)
        // As filmed: no side named, nothing mirrored.
        var asFilmed = leftLeg
        asFilmed.bothSides = false
        #expect(WorkoutPlan(exercises: [asFilmed]).steps.allSatisfy { !$0.isMirrored && $0.side == nil })
    }

    @Test func bothSidesAddUp() {
        var plan = WorkoutPlan(exercises: [leftLeg])
        for reps in [8, 7, 8, 6] { plan.record(SetResult(completedReps: reps)) }
        #expect(plan.isFinished)
        #expect(plan.tallies[0].completedReps == 29)
        #expect(leftLeg.sideCount == 2)
    }

    @Test func oneMoreSetKeepsBothSides() {
        let single = WorkoutExercise(name: "Fente", catalogID: "filmed", mode: .camera(catalogID: "filmed"),
                                     sets: 1, reps: 8, bothSides: true, firstSide: .right)
        var plan = WorkoutPlan(exercises: [single])
        plan.record(SetResult(completedReps: 8))
        plan.record(SetResult(completedReps: 8))
        plan.addSet()
        #expect(plan.steps.count == 4)
        #expect(plan.currentStep?.set == 2)
        #expect(plan.currentStep?.side == .right)
    }

    @Test func oneSideByDefault() {
        let squat = WorkoutExercise(name: "Squat", catalogID: "squat", mode: .camera(catalogID: "squat"), sets: 2, reps: 10)
        let plan = WorkoutPlan(exercises: [squat])
        #expect(plan.steps.count == 2)
        #expect(plan.steps.allSatisfy { $0.side == nil && !$0.isMirrored })
    }

    @Test func survivesTheQRCode() throws {
        var program = EditableProgram()
        program.exercises = [
            .init(name: "Fente", catalogID: nil, sets: 3, reps: 8, bothSides: true),
            .init(name: "Squat", catalogID: "squat", sets: 3, reps: 10),
        ]
        let transfer = ProgramTransfer(program, physiotherapist: nil)
        let url = try #require(transfer.url)
        let read = try #require(ProgramTransfer(url: url)).editableProgram
        #expect(read.exercises.map(\.bothSides) == [true, false])
    }

    @MainActor
    @Test func savedWithTheProgram() throws {
        let container = try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        var editable = EditableProgram()
        editable.exercises = [.init(name: "Pont fessier", catalogID: nil, sets: 2, reps: 12, bothSides: true)]
        let program = Program.add(editable, in: context)
        let exercise = try #require(program.orderedExercises.first)
        #expect(exercise.bothSides)
        #expect(exercise.workoutExercise.sideCount == 2)
        #expect(EditableProgram(program).exercises.first?.bothSides == true)
        // Twice the sets: the session takes longer.
        #expect(program.estimatedMinutes > [PlannedExercise(catalogID: nil, name: "x", sets: 2, reps: 12, order: 0)].estimatedMinutes)
    }
}
