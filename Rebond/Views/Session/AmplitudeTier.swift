import SwiftUI

/// How far a counted repetition went, as a fraction of the exercise's target:
/// "Bien" from 70 %, "Très bien" from 85 %, "Parfait" at the target. Encouragement, never a judgement.
nonisolated enum AmplitudeTier: Int, Comparable, Sendable {
    case good = 1
    case veryGood = 2
    case perfect = 3

    /// Lowest amplitude (fraction of the target) of each tier.
    static let goodThreshold = 0.7
    static let veryGoodThreshold = 0.85
    static let perfectThreshold = 1.0

    /// The tier of a repetition. Under 70 % (when the counter still counts it) stays "Bien".
    init(amplitude: Double) {
        self = if amplitude >= Self.perfectThreshold { .perfect }
            else if amplitude >= Self.veryGoodThreshold { .veryGood }
            else { .good }
    }

    /// The tier reached so far during a movement, or nil before "Bien".
    init?(progress: Double) {
        guard progress >= Self.goodThreshold else { return nil }
        self.init(amplitude: progress)
    }

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    var message: LocalizedStringResource {
        switch self {
        case .good: "Bien"
        case .veryGood: "Très bien"
        case .perfect: "Parfait !"
        }
    }

    var color: Color {
        switch self {
        case .good: .blue
        case .veryGood: .teal
        case .perfect: .green
        }
    }
}
