import Foundation

/// The sets, repetitions, rest and progression of a filmed exercise, by rules from what was MEASURED (the duration
/// of a repetition, how big the movement is, both sides or one), never from its name. Deterministic.
/// The physiotherapist adjusts them; Rebond never changes a program by itself.
nonisolated struct SessionPlan: Codable, Sendable, Equatable {
    var sets: Int
    var reps: Int
    /// Seconds of rest between sets.
    var rest: Int
    /// Seconds per repetition, as filmed: the pace to keep.
    var tempo: Double
    /// One set per side, for a movement done with one side.
    var perSide: Bool
    /// Week by week, the repetitions to aim for (the first week first).
    var progression: [Int]
}

nonisolated enum SessionPlanner {
    /// Bounds of every plan: what a rehabilitation session at home stays within.
    static let repsRange = 6...15
    static let setsRange = 2...4

    static func plan(for m: MovementMeasurement) -> SessionPlan {
        let tempo = m.repDuration > 0 ? m.repDuration : 2
        // Slow movements (holds at the end, big amplitudes): fewer repetitions; quick ones: more.
        let reps = clamp(Int((20 / max(tempo, 1)).rounded()), repsRange)
        // A big movement of the whole body (hips going down) tires more: one set fewer.
        let bodyWeight = m.position == .mixed && m.range(.hipsHeight) > 0.25
        let sets = clamp(bodyWeight ? 2 : 3, setsRange)
        let rest = bodyWeight ? 60 : 30
        // +2 repetitions a week up to the top of the range, over four weeks.
        let progression = (0..<4).map { clamp(reps + $0 * 2, repsRange) }
        return SessionPlan(sets: sets, reps: reps, rest: rest, tempo: tempo, perSide: m.side != .both,
                           progression: progression)
    }

    private static func clamp(_ value: Int, _ range: ClosedRange<Int>) -> Int {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
