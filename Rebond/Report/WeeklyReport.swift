import Foundation

/// What the physiotherapist receives each week: what was done, how well, and how painful it was.
struct WeeklyReport {
    /// Pain level from which a session is flagged in the report (to be validated with a physiotherapist).
    static let highPain = 7

    struct ExerciseLine: Identifiable {
        var id: String { name }
        let name: String
        let plannedReps: Int
        let completedReps: Int
        let incompleteReps: Int
        /// Amplitude of the first and last session of the week, in percent of the target depth.
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

    /// `exerciseOrder`: exercise names in program order (saved results don't keep their order).
    init(sessions allSessions: [Session], sessionsPerWeek: Int, exerciseOrder: [String] = [], end: Date = .now) {
        let start = Calendar.current.date(byAdding: .day, value: -7, to: end) ?? end
        let sessions = allSessions
            .filter { $0.date > start && $0.date <= end }
            .sorted { $0.date < $1.date }

        self.start = start
        self.end = end
        sessionsDone = sessions.count
        sessionsPlanned = sessionsPerWeek

        var names: [String] = []
        for result in sessions.flatMap(\.results) where !names.contains(result.exerciseName) {
            names.append(result.exerciseName)
        }
        names.sort { (exerciseOrder.firstIndex(of: $0) ?? .max, $0) < (exerciseOrder.firstIndex(of: $1) ?? .max, $1) }
        exercises = names.map { name in
            let results = sessions.flatMap(\.results).filter { $0.exerciseName == name }
            let amplitudes = results.compactMap(\.amplitude)
            return ExerciseLine(
                name: name,
                plannedReps: results.map(\.plannedReps).reduce(0, +),
                completedReps: results.map(\.completedReps).reduce(0, +),
                incompleteReps: results.map(\.incompleteReps).reduce(0, +),
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
