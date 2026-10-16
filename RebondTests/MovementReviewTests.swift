import Testing
@testable import Rebond

@Suite("Review of a learned movement")
struct MovementReviewTests {
    private func review(isHold: Bool = false, repCount: Int = 4, holdSeconds: Int? = nil,
                        confidence: Double? = 0.9, reason: String? = "position du début de la vidéo",
                        swapped: Bool? = nil, alternates: Bool? = false) -> MovementReview {
        MovementReview(isHold: isHold, repCount: repCount, holdSeconds: holdSeconds, restConfidence: confidence,
                       restReason: reason, restSwapped: swapped, alternatesSides: alternates)
    }

    @Test func repetitionsShowTheirCountAndTheEndOfTheMovement() {
        let shown = review(repCount: 5)
        #expect(shown.found == .repetitions(5))
        #expect(shown.end == .endOfMovement)
    }

    @Test func aHeldPositionShowsHowLongToHoldIt() {
        let shown = review(isHold: true, repCount: 1, holdSeconds: 20)
        #expect(shown.found == .held(seconds: 20))
        #expect(shown.end == .hold(seconds: 20))
        #expect(review(isHold: true, holdSeconds: 0).end == .hold(seconds: nil))
        #expect(review(isHold: true, holdSeconds: nil).found == .held(seconds: nil))
    }

    @Test func anUnsureStartIsToCheckWithItsReason() {
        let shown = review(confidence: 0.3, reason: "  posture la plus proche de la station debout ")
        #expect(shown.needsChecking)
        #expect(shown.reason == "posture la plus proche de la station debout")
        #expect(!review(confidence: 0.5).needsChecking)
        #expect(!review(confidence: 0.9).needsChecking)
        #expect(review(reason: "").reason == nil)
    }

    @Test func aStartChosenByThePatientOrLearnedBeforeIsNotFlagged() {
        #expect(!review(confidence: 0.2, swapped: true).needsChecking)
        #expect(!review(confidence: nil, reason: nil).needsChecking)
    }

    @Test func swappingAsksForTheOppositeOfTheCurrentChoice() {
        #expect(review(swapped: nil).swapRequest)
        #expect(review(swapped: false).swapRequest)
        #expect(!review(swapped: true).swapRequest)
    }

    @Test func alternatingSidesAreSaid() {
        #expect(review(alternates: true).alternatesSides)
        #expect(!review(alternates: nil).alternatesSides)
    }
}
