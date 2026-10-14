import Foundation

/// What the physiotherapist needs to see at a glance for one patient, from the last report received:
/// the week's regularity, the pain (sessions at or above the high-pain threshold), the repetitions and the amplitude.
/// Pure logic, covered by the tests.
nonisolated struct PatientOverview {
    /// What needs the physiotherapist's attention first. Ordered from the most to the least important.
    enum Attention: Int, Comparable {
        /// At least one session at or above `WeeklyReport.highPain` in the week.
        case highPain
        /// Fewer than half the planned sessions in the week.
        case fewSessions
        /// No report for more than `staleDays` days.
        case staleReport
        case none

        static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// A report older than this is flagged: the physiotherapist may ask the patient for a new one.
    static let staleDays = 8

    let name: String
    let reportDate: Date
    /// The 7 days before the report.
    let week: WeeklyReport
    /// Days between the report and now.
    let daysSinceReport: Int

    init(name: String, transfer: ReportTransfer, now: Date = .now) {
        self.name = name
        reportDate = transfer.generatedAt
        week = WeeklyReport(sessions: transfer.sessionData, sessionsPerWeek: transfer.sessionsPerWeek, end: transfer.generatedAt)
        let calendar = Calendar.current
        daysSinceReport = max(0, calendar.dateComponents([.day], from: calendar.startOfDay(for: transfer.generatedAt),
                                                          to: calendar.startOfDay(for: now)).day ?? 0)
    }

    var sessionsDone: Int { week.sessionsDone }
    var sessionsPlanned: Int { week.sessionsPlanned }

    /// Sessions done over planned, capped at 1.
    var regularity: Double {
        guard sessionsPlanned > 0 else { return 0 }
        return min(Double(sessionsDone) / Double(sessionsPlanned), 1)
    }

    var painfulSessions: Int { week.painfulSessionDates.count }

    /// Pain of the last session of the week.
    var lastPain: Int? { week.lastPain ?? week.firstPain }

    var completedReps: Int { week.exercises.map(\.completedReps).reduce(0, +) }
    var incompleteReps: Int { week.exercises.map(\.incompleteReps).reduce(0, +) }
    var plannedReps: Int { week.exercises.map(\.plannedReps).reduce(0, +) }

    /// Average of each camera-followed exercise's latest amplitude, in % of the target. Nil without a measure.
    var amplitude: Double? {
        let latest = week.exercises.compactMap { $0.lastAmplitude ?? $0.firstAmplitude }
        guard !latest.isEmpty else { return nil }
        return latest.reduce(0, +) / Double(latest.count)
    }

    var attention: Attention {
        if painfulSessions > 0 { return .highPain }
        if daysSinceReport > Self.staleDays { return .staleReport }
        if sessionsPlanned > 0, Double(sessionsDone) < Double(sessionsPlanned) / 2 { return .fewSessions }
        return .none
    }

    /// Order of the patient list: patients needing attention first, then the most recent reports.
    func comesBefore(_ other: PatientOverview) -> Bool {
        attention != other.attention ? attention < other.attention : reportDate > other.reportDate
    }
}
