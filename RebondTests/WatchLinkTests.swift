import Foundation
import Testing
@testable import Rebond

@Suite("Apple Watch")
struct WatchLinkTests {
    private func set(_ count: Int, target: Int = 10, set: Int = 1, isHold: Bool = false, isPaused: Bool = false,
                     exercise: String = "Squat") -> WatchSetState {
        WatchSetState(exercise: exercise, symbol: "figure.strengthtraining.functional", set: set, totalSets: 3,
                      count: count, target: target, isHold: isHold, isPaused: isPaused, canPause: true)
    }

    // MARK: Haptics

    @Test func firstSetTapsAsANewSet() {
        #expect(WatchHaptic.feedback(from: nil, to: set(0)) == .newSet)
    }

    @Test func eachRepetitionTaps() {
        #expect(WatchHaptic.feedback(from: set(3), to: set(4)) == .repetition)
    }

    @Test func reachingTheTargetWinsOverTheRepetition() {
        #expect(WatchHaptic.feedback(from: set(9), to: set(10)) == .setComplete)
        // Past the target, each extra repetition is a plain tap again.
        #expect(WatchHaptic.feedback(from: set(10), to: set(11)) == .repetition)
    }

    @Test func nothingChangedNoTap() {
        #expect(WatchHaptic.feedback(from: set(4), to: set(4)) == nil)
        // A count going down (corrected by hand) is not worth a tap.
        #expect(WatchHaptic.feedback(from: set(4), to: set(3)) == nil)
    }

    @Test func pauseAndResume() {
        #expect(WatchHaptic.feedback(from: set(4), to: set(4, isPaused: true)) == .paused)
        #expect(WatchHaptic.feedback(from: set(4, isPaused: true), to: set(4)) == .resumed)
    }

    @Test func nextSetOrExerciseTapsAsANewSet() {
        #expect(WatchHaptic.feedback(from: set(10), to: set(0, set: 2)) == .newSet)
        #expect(WatchHaptic.feedback(from: set(10, set: 3), to: set(0, exercise: "Gainage")) == .newSet)
    }

    @Test func otherSideTapsAsANewSet() {
        var right = set(10), left = set(0)
        right.side = "côté droit"
        left.side = "côté gauche"
        #expect(WatchHaptic.feedback(from: right, to: left) == .newSet)
    }

    @Test func heldSetTapsEveryTenSeconds() {
        let held = { (seconds: Int) in set(seconds, target: 30, isHold: true) }
        #expect(WatchHaptic.feedback(from: held(8), to: held(9)) == nil)
        #expect(WatchHaptic.feedback(from: held(9), to: held(10)) == .repetition)
        #expect(WatchHaptic.feedback(from: held(29), to: held(30)) == .setComplete)
    }

    @Test func heldSetNotStartedIsWaiting() {
        #expect(set(0, target: 30, isHold: true, isPaused: true).isWaitingToStart)
        #expect(!set(12, target: 30, isHold: true, isPaused: true).isWaitingToStart)
    }

    // MARK: Messages

    @Test func messagesSurviveTheTrip() {
        let messages: [PhoneMessage] = [
            .sessionStarted(Date(timeIntervalSince1970: 1_000)), .set(set(4)), .setsFinished, .sessionEnded(saved: true),
        ]
        for message in messages {
            #expect(WatchCoding.decode(PhoneMessage.self, from: WatchCoding.encode(message)) == message)
        }
        for message in [WatchMessage.togglePause, .nextSet, .recordingWorkout] {
            #expect(WatchCoding.decode(WatchMessage.self, from: WatchCoding.encode(message)) == message)
        }
    }

    @Test func foreignPayloadIsIgnored() {
        #expect(WatchCoding.decode(PhoneMessage.self, from: ["other": 1]) == nil)
        #expect(WatchCoding.decode(PhoneMessage.self, from: [WatchCoding.key: Data("{}".utf8)]) == nil)
    }

    @Test func todaySessionReachesTheWatch() {
        #expect(WatchContext.decode(WatchContext.encode(.sample)) == .sample)
    }

    // MARK: Health

    @Test func watchRecordingMeansNoDuplicate() {
        #expect(HealthRecording.decide(watchRecorded: true, healthEnabled: true, duration: 600) == .watch)
        #expect(HealthRecording.decide(watchRecorded: true, healthEnabled: false, duration: 600) == .watch)
    }

    @Test func phoneRecordsWithoutWatch() {
        #expect(HealthRecording.decide(watchRecorded: false, healthEnabled: true, duration: 600) == .phone)
    }

    @Test func nothingWhenOffOrTooShort() {
        #expect(HealthRecording.decide(watchRecorded: false, healthEnabled: false, duration: 600) == .none)
        #expect(HealthRecording.decide(watchRecorded: false, healthEnabled: true, duration: 10) == .none)
    }
}
