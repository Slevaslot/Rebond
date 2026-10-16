import Foundation

/// What the review of a learned movement shows, decided from what was learned: what the film contained, how the
/// end image is named, and whether the patient should look closely at which position is the start.
nonisolated struct MovementReview: Equatable, Sendable {
    /// What was found in the film.
    enum Found: Equatable, Sendable {
        case repetitions(Int)
        /// A held position, and how long the film held it when known.
        case held(seconds: Int?)
    }

    /// The image opposite the start.
    enum End: Equatable, Sendable {
        /// "Arrivée": the end of the movement.
        case endOfMovement
        /// "Position à tenir · N s".
        case hold(seconds: Int?)
    }

    /// Below this, the analysis wasn't sure which position is the start.
    static let confidenceToCheck = 0.5

    let found: Found
    let end: End
    /// The analysis hesitated between the start and the end: shown as "À vérifier", with `reason`.
    let needsChecking: Bool
    /// How the start was chosen, in a few words; nil when the analysis didn't say.
    let reason: String?
    /// The movement goes to one side then the other.
    let alternatesSides: Bool
    /// What a tap on "Inverser départ et arrivée" asks for: the opposite of the current choice.
    let swapRequest: Bool

    init(isHold: Bool, repCount: Int, holdSeconds: Int?, restConfidence: Double?, restReason: String?,
         restSwapped: Bool?, alternatesSides: Bool?) {
        let seconds = holdSeconds.flatMap { $0 > 0 ? $0 : nil }
        found = isHold ? .held(seconds: seconds) : .repetitions(max(repCount, 0))
        end = isHold ? .hold(seconds: seconds) : .endOfMovement
        let trimmed = restReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        reason = trimmed.isEmpty ? nil : trimmed
        // The patient already chose the start: nothing left to check. Movements learned before the confidence
        // was measured aren't flagged either.
        needsChecking = restSwapped != true && (restConfidence ?? 1) < Self.confidenceToCheck
        self.alternatesSides = alternatesSides == true
        swapRequest = !(restSwapped ?? false)
    }

    init(_ movement: ReferenceMovement) {
        self.init(isHold: movement.isHold, repCount: movement.repCount, holdSeconds: movement.holdSeconds,
                  restConfidence: movement.restConfidence, restReason: movement.restReason,
                  restSwapped: movement.restSwapped, alternatesSides: movement.alternatesSides)
    }
}
