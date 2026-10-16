import Foundation
import SwiftData
import Testing
@testable import Rebond

@Suite("Espace kiné")
struct PhysioSpaceTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func session(daysAgo: Double, pain: Int, reps: Int = 20, amplitude: Double? = nil) -> WeeklyReport.SessionData {
        WeeklyReport.SessionData(date: now.addingTimeInterval(-daysAgo * 86_400), pain: pain, results: [
            .init(name: "Squat", order: 0, plannedReps: 20, completedReps: reps, incompleteReps: 20 - reps,
                  plannedSeconds: 0, heldSeconds: 0, amplitude: amplitude),
        ])
    }

    private func transfer(_ sessions: [WeeklyReport.SessionData], daysAgo: Double = 0, perWeek: Int = 3) -> ReportTransfer {
        ReportTransfer(patientID: UUID(), patientName: "Martine", generatedAt: now.addingTimeInterval(-daysAgo * 86_400),
                       sessionsPerWeek: perWeek, sessions: sessions)
    }

    @Test func summarizesTheReportWeek() {
        let overview = PatientOverview(name: "Martine", transfer: transfer([
            session(daysAgo: 12, pain: 6, reps: 10, amplitude: 60),
            session(daysAgo: 5, pain: 4, reps: 18, amplitude: 80),
            session(daysAgo: 2, pain: 3, reps: 20, amplitude: 95),
        ]), now: now)
        #expect(overview.sessionsDone == 2)
        #expect(overview.regularity == 2.0 / 3.0)
        #expect(overview.lastPain == 3)
        #expect(overview.completedReps == 38)
        #expect(overview.incompleteReps == 2)
        #expect(overview.plannedReps == 40)
        #expect(overview.amplitude == 95)
        #expect(overview.attention == .none)
    }

    @Test func highPainComesFirst() {
        let painful = PatientOverview(name: "A", transfer: transfer([session(daysAgo: 1, pain: 8)], daysAgo: 0), now: now)
        let fewSessions = PatientOverview(name: "B", transfer: transfer([session(daysAgo: 1, pain: 2)], daysAgo: 0), now: now)
        let stale = PatientOverview(name: "C", transfer: transfer([session(daysAgo: 12, pain: 2), session(daysAgo: 11, pain: 2)],
                                                                  daysAgo: 10, perWeek: 2), now: now)
        #expect(painful.attention == .highPain)
        #expect(painful.painfulSessions == 1)
        #expect(fewSessions.attention == .fewSessions)
        #expect(stale.attention == .staleReport)
        #expect(stale.daysSinceReport == 10)
        let sorted = [stale, fewSessions, painful].sorted { $0.comesBefore($1) }
        #expect(sorted.map(\.name) == ["A", "B", "C"])
    }

    @Test func noAmplitudeWithoutCameraMeasure() {
        let overview = PatientOverview(name: "A", transfer: transfer([session(daysAgo: 1, pain: 2)]), now: now)
        #expect(overview.amplitude == nil)
    }

    @Test @MainActor func freeOfferStopsAtTheLimit() throws {
        let container = try ModelContainer(for: TrackedPatient.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        for _ in 0..<ProPlan.freePatientLimit {
            let data = try transfer([session(daysAgo: 1, pain: 2)]).encoded()
            guard case .imported = TrackedPatient.importReport(data, into: context, patientLimit: ProPlan.freePatientLimit) else {
                Issue.record("A patient within the free offer should be imported")
                return
            }
        }
        let extra = try transfer([session(daysAgo: 1, pain: 2)]).encoded()
        #expect(TrackedPatient.importReport(extra, into: context, patientLimit: ProPlan.freePatientLimit) == .limitReached)
        #expect(TrackedPatient.importReport(Data("{}".utf8), into: context, patientLimit: nil) == .invalid)
        if case .imported = TrackedPatient.importReport(extra, into: context, patientLimit: nil) {} else {
            Issue.record("Rebond Cabinet follows unlimited patients")
        }
        #expect(try context.fetchCount(FetchDescriptor<TrackedPatient>()) == ProPlan.freePatientLimit + 1)
    }

    @Test @MainActor func demoPatientsAreLoadedOnce() throws {
        let container = try ModelContainer(for: TrackedPatient.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        DemoData.loadPatients(into: container.mainContext)
        DemoData.loadPatients(into: container.mainContext)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<TrackedPatient>()) == 3)
    }
}
