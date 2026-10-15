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
}
