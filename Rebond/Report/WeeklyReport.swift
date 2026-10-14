import Foundation

/// What the physiotherapist receives each week: what was done, how well, and how painful it was.
/// Computed on the last 7 days, dates shown in full.
nonisolated struct WeeklyReport {
    /// Pain level from which a session is flagged in the report (to be validated with a physiotherapist).
    static let highPain = 7

    struct ExerciseLine: Identifiable {
        var id: String { name }
        let name: String
        let isHeld: Bool
        let plannedReps: Int
        let completedReps: Int
        let incompleteReps: Int
        let plannedSeconds: Int
        let heldSeconds: Int
        /// Best amplitude of the first and last session of the week, in percent of the target.
        let firstAmplitude: Double?
        let lastAmplitude: Double?
    }

    let start: Date
    let end: Date
    let sessionsDone: Int
    let sessionsPlanned: Int
    let exercises: [ExerciseLine]
    let averagePain: Double?
    let firstPain: Int?
    let lastPain: Int?
    let painfulSessionDates: [Date]

    struct SessionData {
        let date: Date
        let pain: Int
        let results: [ResultData]
    }

    struct ResultData {
        let name: String
        let order: Int
        let plannedReps: Int
        let completedReps: Int
        let incompleteReps: Int
        let plannedSeconds: Int
        let heldSeconds: Int
        let amplitude: Double?
    }

    init(sessions allSessions: [SessionData], sessionsPerWeek: Int, end: Date = .now) {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        let sessions = allSessions
            .filter { $0.date > start && $0.date <= end }
            .sorted { $0.date < $1.date }

        self.start = start
        self.end = end
        sessionsDone = sessions.count
        sessionsPlanned = sessionsPerWeek

        // Exercises in the order of the last session, which follows the program.
        let allResults = sessions.flatMap(\.results)
        var names: [String] = []
        for result in (sessions.last?.results ?? []).sorted(by: { $0.order < $1.order }) + allResults
        where !names.contains(result.name) {
            names.append(result.name)
        }
        exercises = names.map { name in
            let results = allResults.filter { $0.name == name }
            let amplitudes = results.compactMap(\.amplitude)
            return ExerciseLine(
                name: name,
                isHeld: results.contains { $0.plannedSeconds > 0 },
                plannedReps: results.map(\.plannedReps).reduce(0, +),
                completedReps: results.map(\.completedReps).reduce(0, +),
                incompleteReps: results.map(\.incompleteReps).reduce(0, +),
                plannedSeconds: results.map(\.plannedSeconds).reduce(0, +),
                heldSeconds: results.map(\.heldSeconds).reduce(0, +),
                firstAmplitude: amplitudes.first,
                lastAmplitude: amplitudes.count > 1 ? amplitudes.last : nil
            )
        }

        let pains = sessions.map(\.pain)
        averagePain = pains.isEmpty ? nil : Double(pains.reduce(0, +)) / Double(pains.count)
        firstPain = pains.first
        lastPain = pains.count > 1 ? pains.last : nil
        painfulSessionDates = sessions.filter { $0.pain >= Self.highPain }.map(\.date)
    }
}

extension WeeklyReport {
    init(sessions: [Session], sessionsPerWeek: Int, end: Date = .now) {
        self.init(sessions: sessions.map(\.reportData), sessionsPerWeek: sessionsPerWeek, end: end)
    }
}

extension Session {
    var reportData: WeeklyReport.SessionData {
        WeeklyReport.SessionData(date: date, pain: pain, results: results.map {
            WeeklyReport.ResultData(
                name: $0.exerciseName, order: $0.order,
                plannedReps: $0.plannedReps, completedReps: $0.completedReps, incompleteReps: $0.incompleteReps,
                plannedSeconds: $0.plannedSeconds, heldSeconds: $0.heldSeconds, amplitude: $0.amplitude
            )
        })
    }
}
