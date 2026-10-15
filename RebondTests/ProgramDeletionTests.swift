import Foundation
import SwiftData
import Testing
@testable import Rebond

@Suite("Program deletion")
struct ProgramDeletionTests {
    @MainActor
    @Test func deletingOneProgramKeepsTheOthers() throws {
        let container = try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        DemoData.load(into: context)
        try context.save()
        let programs = try context.fetch(FetchDescriptor<Program>(sortBy: [SortDescriptor(\.createdAt)]))
        #expect(programs.count == 2)

        context.delete(programs[0])
        try context.save()

        let left = try context.fetch(FetchDescriptor<Program>())
        #expect(left.map(\.title) == [programs[1].title])
        #expect(left.first?.exercises.count == 2)
    }
}
