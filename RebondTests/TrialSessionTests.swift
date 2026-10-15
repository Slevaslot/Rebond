import Foundation
import SwiftData
import Testing
@testable import Rebond

@Suite("Exercise tried on its own")
struct TrialSessionTests {
    @MainActor
    @Test func isLeftOutOfTheProgramSessions() throws {
        let container = try ModelContainer(for: AppData.schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        context.insert(Session(pain: 2, results: []))
        context.insert(Session(pain: 3, results: [], isTrial: true))
        try context.save()

        let all = try context.fetch(FetchDescriptor<Session>())
        let program = try context.fetch(FetchDescriptor<Session>(predicate: Session.programSessions))
        #expect(all.count == 2)
        #expect(program.map(\.pain) == [2])
    }
}
