import Testing
import UIKit
import Vision
@testable import Rebond

/// The symbol of a filmed movement when Apple Intelligence can't choose it.
struct MovementSymbolTests {
    private func names(_ joints: VNHumanBodyPoseObservation.JointName...) -> [String] {
        joints.map(\.rawValue.rawValue)
    }

    @Test func ruleFollowsWhatMoves() {
        #expect(MovementSymbolPicker.rule(movingJoints: names(.leftHip, .leftKnee)) == .squat)
        #expect(MovementSymbolPicker.rule(movingJoints: names(.leftElbow)) == .armsRaise)
        #expect(MovementSymbolPicker.rule(movingJoints: names(.leftElbow, .rightKnee)) == .fullBody)
        #expect(MovementSymbolPicker.rule(movingJoints: names(.neck)) == .trunk)
    }

    @Test func everySymbolExists() {
        for symbol in MovementSymbol.allCases {
            #expect(UIImage(systemName: symbol.systemName) != nil, "\(symbol.systemName)")
        }
    }
}
