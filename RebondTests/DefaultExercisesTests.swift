import Foundation
import SwiftData
import Testing
@testable import Rebond

@Suite("Default exercises")
struct DefaultExercisesTests {
    @MainActor
    @Test func addedOnceWithoutRepeats() throws {
        let container = try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let defaults = try #require(UserDefaults(suiteName: "DefaultExercisesTests-\(UUID())"))
        // Already there under the same name: not repeated.
        context.insert(LibraryExercise(catalogID: CatalogExercise.squat.id, name: String(localized: CatalogExercise.squat.name)))

        LibraryExercise.addDefaults(in: context, defaults: defaults)
        let first = try context.fetch(FetchDescriptor<LibraryExercise>())
        #expect(first.count == CatalogExercise.all.count)

        // Deleted by the patient: doesn't come back.
        context.delete(first[0])
        LibraryExercise.addDefaults(in: context, defaults: defaults)
        #expect(try context.fetch(FetchDescriptor<LibraryExercise>()).count == CatalogExercise.all.count - 1)
    }

    @Test func sameNameGetsANumber() {
        #expect(LibraryExercise.uniqueName("Squat", taken: []) == "Squat")
        #expect(LibraryExercise.uniqueName("Squat", taken: ["Squat"]) == "Squat 2")
        #expect(LibraryExercise.uniqueName("Squat", taken: ["Squat", "Squat 2"]) == "Squat 3")
    }

    @MainActor
    @Test func exerciseMatchesItsOwnCopyInAProgram() {
        let filmed = LibraryExercise(catalogID: "reference-1", name: "Squat")
        #expect(filmed.matches(PlannedExercise(catalogID: "reference-1", name: "Squat", sets: 3, reps: 10, order: 0)))
        // Rebond's squat, same name: another exercise.
        #expect(!filmed.matches(PlannedExercise(catalogID: "squat", name: "Squat", sets: 3, reps: 10, order: 0)))
    }

    @MainActor
    @Test func groupsFollowTheMovement() {
        let rebond = LibraryExercise(catalogID: "squat", name: "Squat")
        let byHand = LibraryExercise(catalogID: nil, name: "Pont fessier")
        let groups = LibraryExercise.grouped([byHand, rebond]).map(\.group)
        #expect(groups == [.rebond, .withoutCamera])
        #expect(LibraryExercise.grouped([rebond], keepingWithoutCamera: true).map(\.group) == [.rebond, .withoutCamera])
    }
}
