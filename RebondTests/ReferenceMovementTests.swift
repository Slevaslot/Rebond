import CoreGraphics
import Foundation
import Testing
import Vision
@testable import Rebond

/// Filmed movements: learning (starting position, repetitions, held positions, alternating sides) and counting at
/// home (missing joints, sides, noise), replayed without a camera, on synthetic bodies and on real recordings
/// (`Fixtures/references`, poses seen by Vision on the team's iPhone videos).
@Suite("Mouvements filmés")
struct ReferenceMovementTests {
    // MARK: Helpers

    /// A frame of a synthetic video: square images, so the points are the measure's, top-left.
    static func sample(_ m: PoseMeasure, at time: Double) -> ReferenceSample {
        var points: [VNHumanBodyPoseObservation.JointName: CGPoint] = [:]
        func put(_ joint: VNHumanBodyPoseObservation.JointName, _ p: CGPoint?) {
            if let p { points[joint] = CGPoint(x: p.x, y: 1 - p.y) }
        }
        put(.root, m.hips); put(.neck, m.neck); put(.leftHip, m.leftHip); put(.rightHip, m.rightHip)
        put(.leftKnee, m.leftKnee); put(.rightKnee, m.rightKnee); put(.leftAnkle, m.leftAnkle); put(.rightAnkle, m.rightAnkle)
        put(.leftShoulder, m.leftShoulder); put(.rightShoulder, m.rightShoulder); put(.leftElbow, m.leftElbow)
        put(.rightElbow, m.rightElbow); put(.leftWrist, m.leftWrist); put(.rightWrist, m.rightWrist)
        return ReferenceSample(time: time, measure: m, points: points, imageSize: CGSize(width: 1000, height: 1000))
    }

    /// A synthetic film: the arm angles go through the key points (angle left, angle right, seconds to get there),
    /// with a small regular tremor as Vision has.
    static func film(start: (Double, Double), _ keys: [(Double, Double, Double)]) -> [ReferenceSample] {
        var samples: [ReferenceSample] = []
        var time = 0.0
        var current = start
        func add(_ left: Double, _ right: Double) {
            let jitter = sin(time * 37) * 1.5
            samples.append(sample(Body.arms(left: left + jitter, right: right - jitter), at: time))
            time += 1 / 15
        }
        for (left, right, seconds) in keys {
            let frames = max(1, Int(seconds * 15))
            for i in 1...frames {
                let t = Double(i) / Double(frames)
                add(current.0 + (left - current.0) * t, current.1 + (right - current.1) * t)
            }
            current = (left, right)
        }
        return samples
    }

    static func recording(_ name: String) throws -> PoseRecording {
        let bundle = Bundle(for: BundleToken.self)
        let url = try #require(bundle.url(forResource: name, withExtension: "json")
            ?? bundle.url(forResource: name, withExtension: "json", subdirectory: "references"))
        return try JSONDecoder().decode(PoseRecording.self, from: Data(contentsOf: url))
    }

    static func movement(_ analysis: ReferenceAnalysis) -> ReferenceMovement {
        ReferenceMovement(id: UUID(), name: "Test", analysis: analysis, frameCount: 0, peakFrame: 0)
    }

    /// Both arms: 3 raises to 100°, each held at the top 3 s, only half a second down between them.
    static let raisesHeldAtTheTop: [(Double, Double, Double)] = [
        (20, 20, 1.5),
        (100, 100, 1), (100, 100, 3), (20, 20, 1), (20, 20, 0.5),
        (100, 100, 1), (100, 100, 3), (20, 20, 1), (20, 20, 0.5),
        (100, 100, 1), (100, 100, 3), (20, 20, 1), (20, 20, 1),
    ]

    // MARK: Learning: the starting position

    @Test func pauseAtTheTopDoesNotTurnTheMovementUpsideDown() throws {
        let analysis = try ReferenceAnalyzer.analyze(Self.film(start: (20, 20), Self.raisesHeldAtTheTop))
        #expect(analysis.repCount == 3)
        // The starting position is arms down: shoulder angle about 20° (in units of 60°).
        #expect(analysis.rest[2] < 0.6 && analysis.rest[3] < 0.6)
        // Raising the arms goes toward the target.
        #expect(analysis.axis[2] > 0 && analysis.axis[3] > 0)
        #expect(analysis.restConfidence > 0.5)
    }

    @Test func startingInTheMiddleOfTheMovementStillFindsArmsDown() throws {
        // The video starts arms half raised, moving, then the repetitions (each held up a long time).
        var keys: [(Double, Double, Double)] = [(60, 60, 0.3), (100, 100, 0.7), (100, 100, 3), (20, 20, 1)]
        keys += Self.raisesHeldAtTheTop.dropFirst()
        let analysis = try ReferenceAnalyzer.analyze(Self.film(start: (60, 60), keys))
        #expect(analysis.rest[2] < 0.6)
        #expect(analysis.repCount >= 3)
    }

    @Test func swappingTheStartTakesTheOtherEnd() throws {
        let samples = Self.film(start: (20, 20), Self.raisesHeldAtTheTop)
        let analysis = try ReferenceAnalyzer.analyze(samples, restChoice: .swapped)
        // Starting arms up, the movement brings them down.
        #expect(analysis.rest[2] > 1.4)
        #expect(analysis.axis[2] < 0)
        #expect(analysis.repCount >= 2)
    }

    @Test func alternatingArmsStartInTheMiddle() throws {
        let analysis = try ReferenceAnalyzer.analyze(Self.film(start: (20, 20), [
            (20, 20, 1.5),
            (110, 20, 1), (20, 20, 1), (20, 110, 1), (20, 20, 1),
            (110, 20, 1), (20, 20, 1), (20, 110, 1), (20, 20, 1.5),
        ]))
        #expect(analysis.alternatesSides)
        #expect(analysis.rest[2] < 0.6 && analysis.rest[3] < 0.6)
        // Each side counts: four raises.
        #expect(analysis.repCount == 4)
    }

    @Test func aHeldPositionIsLearnedAsAHold() throws {
        // Arms down, then raised to shoulder height and held 6 s.
        let analysis = try ReferenceAnalyzer.analyze(Self.film(start: (20, 20), [(20, 20, 1.5), (90, 90, 1.5), (90, 90, 6), (20, 20, 1)]))
        #expect(analysis.kind == .hold)
        #expect(analysis.holdSeconds == 10)
        #expect(analysis.rest[2] < 0.6)
    }

    @Test func standingStillIsNoMovement() {
        #expect(throws: ReferenceError.self) {
            try ReferenceAnalyzer.analyze(Self.film(start: (20, 20), [(20, 20, 6)]))
        }
    }

    // MARK: Learning: real films

    @Test func realArmRaiseStartsArmsDown() throws {
        let analysis = try ReferenceAnalyzer.analyze(Self.recording("film-elevation-bras").samples)
        #expect(analysis.repCount == 3)
        #expect(analysis.rest[2] < 0.7 && analysis.rest[3] < 0.7)
        #expect(analysis.axis[2] > 0.3 && analysis.axis[3] > 0.3)
        #expect(analysis.kind == .repetitions)
    }

    @Test func realSquatAfterRaisingTheArmsFindsTheSquats() throws {
        // Arms raised first (getting ready), then three squats arms up: the squats are the repetitions.
        let analysis = try ReferenceAnalyzer.analyze(Self.recording("film-squat-bras-leves").samples)
        #expect(analysis.repCount == 3)
        // The hips go down.
        #expect(analysis.axis[8] < -0.2)
    }

    @Test func realOneArmStartsAsAtTheStartOfTheVideo() throws {
        let analysis = try ReferenceAnalyzer.analyze(Self.recording("film-un-bras").samples)
        // The elbow starts open and folds.
        #expect(analysis.rest[0] > 1.5)
        #expect(analysis.axis[0] < -0.5)
        #expect(analysis.repCount >= 2)
        // The legs, out of view most of the video, aren't followed.
        #expect(analysis.featureMask[4] == false)
    }

    @Test func otherRealFilmsAreLearned() throws {
        for name in ["film-flexion-coudes", "film-jambe-tendue"] {
            let analysis = try ReferenceAnalyzer.analyze(Self.recording(name).samples)
            #expect(analysis.repCount >= 2, "\(name)")
        }
    }

    // MARK: Counting at home

    /// The real session of the arm raise that was counted 0 → 2 on the way up: one repetition per cycle now.
    @Test func realSessionCountsOneRepetitionPerCycle() throws {
        let movement = Self.movement(try ReferenceAnalyzer.analyze(Self.recording("film-elevation-bras").samples))
        var counter = ReferenceCounter(movement: movement)
        var reps = 0
        var tipsWhileMoving = 0
        var progressAt: [Double: Double] = [:]
        for sample in try Self.recording("seance-elevation-bras").samples {
            let update = counter.process(sample.measure, at: sample.time)
            if case .repCompleted = update.event { reps += 1 }
            if case .correction(let fault) = update.event, fault != .followReference, sample.time < 22 { tipsWhileMoving += 1 }
            progressAt[(sample.time * 10).rounded() / 10] = update.progress
        }
        // Five raises between 10 s and 22 s.
        #expect(reps == 5)
        #expect(tipsWhileMoving == 0)
        // The gauge is full arms up (11 s) and empty arms down (12.5 s).
        #expect((progressAt[11.0] ?? 0) > 0.9)
        #expect((progressAt[12.5] ?? 1) < 0.2)
    }

    private func armRaiseMovement() throws -> ReferenceMovement {
        Self.movement(try ReferenceAnalyzer.analyze(Self.film(start: (20, 20), [
            (20, 20, 1.5), (100, 100, 1), (20, 20, 1), (20, 20, 0.5), (100, 100, 1), (20, 20, 1), (20, 20, 0.5),
            (100, 100, 1), (20, 20, 1), (20, 20, 1),
        ])))
    }

    @Test func countsFullAndIncompleteRepetitions() throws {
        var feeder = Feeder(counter: ReferenceCounter(movement: try armRaiseMovement()))
        feeder.feed(Body.arms(left: 20, right: 20), frames: 12)
        #expect(feeder.calibrated)
        for _ in 0..<3 {
            feeder.move(from: 20, to: 100, seconds: 1) { Body.arms(left: $0, right: $0) }
            feeder.move(from: 100, to: 20, seconds: 1) { Body.arms(left: $0, right: $0) }
            feeder.feed(Body.arms(left: 20, right: 20), frames: 5)
        }
        #expect(feeder.completed.count == 3)
        // Halfway up only: incomplete, not counted.
        feeder.move(from: 20, to: 72, seconds: 1) { Body.arms(left: $0, right: $0) }
        feeder.move(from: 72, to: 20, seconds: 1) { Body.arms(left: $0, right: $0) }
        feeder.feed(Body.arms(left: 20, right: 20), frames: 5)
        #expect(feeder.completed.count == 3)
        #expect(feeder.incomplete == 1)
    }

    @Test func aRaiseCountsOnlyOnceBackDown() throws {
        var feeder = Feeder(counter: ReferenceCounter(movement: try armRaiseMovement()))
        feeder.feed(Body.arms(left: 20, right: 20), frames: 12)
        // Up and held: nothing counted yet.
        feeder.move(from: 20, to: 100, seconds: 1) { Body.arms(left: $0, right: $0) }
        feeder.feed(Body.arms(left: 100, right: 100), frames: 30)
        #expect(feeder.completed.isEmpty)
        feeder.move(from: 100, to: 20, seconds: 1) { Body.arms(left: $0, right: $0) }
        #expect(feeder.completed.count == 1)
    }

    @Test func detectionGlitchesAreNotRepetitions() throws {
        var feeder = Feeder(counter: ReferenceCounter(movement: try armRaiseMovement()))
        feeder.feed(Body.arms(left: 20, right: 20), frames: 12)
        // Vision puts the arms up on single frames.
        for _ in 0..<6 {
            feeder.feed(Body.arms(left: 20, right: 20), frames: 4)
            feeder.feed(Body.arms(left: 100, right: 100), frames: 1)
        }
        feeder.feed(Body.arms(left: 20, right: 20), frames: 10)
        #expect(feeder.completed.isEmpty)
    }

    @Test func missingWristsAreNotTakenForTheStart() throws {
        var counter = ReferenceCounter(movement: try armRaiseMovement())
        var time = 0.0
        func feed(_ m: PoseMeasure?) -> CounterUpdate {
            time += 1 / 15
            return counter.process(m, at: time)
        }
        for _ in 0..<12 { _ = feed(Body.arms(left: 20, right: 20)) }
        for i in 1...15 { _ = feed(Body.arms(left: 20 + 80 * Double(i) / 15, right: 20 + 80 * Double(i) / 15)) }
        // Arms up, the wrists and elbows unseen: no return to rest, no repetition, nothing measured.
        var up = Body.arms(left: 100, right: 100)
        up.leftWrist = nil; up.rightWrist = nil; up.leftElbow = nil; up.rightElbow = nil
        var events: [RepEvent] = []
        for _ in 0..<10 {
            let update = feed(up)
            #expect(update.isMeasured == false)
            if let event = update.event { events.append(event) }
        }
        #expect(!events.contains { if case .repCompleted = $0 { true } else { false } })
        // Only the wrists missing: the shoulder angle still tells the arms are up.
        var wristsOnly = Body.arms(left: 100, right: 100)
        wristsOnly.leftWrist = nil; wristsOnly.rightWrist = nil
        let update = feed(wristsOnly)
        #expect(update.isMeasured)
    }

    @Test func theBodyLostForASecondForgetsTheRepetition() throws {
        var feeder = Feeder(counter: ReferenceCounter(movement: try armRaiseMovement()))
        feeder.feed(Body.arms(left: 20, right: 20), frames: 12)
        feeder.move(from: 20, to: 100, seconds: 1) { Body.arms(left: $0, right: $0) }
        var counter = feeder.counter
        var time = feeder.time
        for _ in 0..<20 {
            time += 1 / 15
            _ = counter.process(nil, at: time)
        }
        feeder.counter = counter
        feeder.time = time
        feeder.feed(Body.arms(left: 20, right: 20), frames: 12)
        #expect(feeder.completed.isEmpty)
    }

    // MARK: Sides

    /// One arm filmed: the left one (as Vision names it), raised three times.
    private func leftArmMovement() throws -> ReferenceMovement {
        Self.movement(try ReferenceAnalyzer.analyze(Self.film(start: (20, 20), [
            (20, 20, 1.5), (110, 20, 1), (20, 20, 1), (20, 20, 0.5), (110, 20, 1), (20, 20, 1), (20, 20, 0.5),
            (110, 20, 1), (20, 20, 1), (20, 20, 1),
        ])))
    }

    private func raises(_ counter: ReferenceCounter, left: Bool) -> Feeder<ReferenceCounter> {
        var feeder = Feeder(counter: counter)
        feeder.feed(Body.arms(left: 20, right: 20), frames: 12)
        for _ in 0..<3 {
            feeder.move(from: 20, to: 110, seconds: 1) { left ? Body.arms(left: $0, right: 20) : Body.arms(left: 20, right: $0) }
            feeder.move(from: 110, to: 20, seconds: 1) { left ? Body.arms(left: $0, right: 20) : Body.arms(left: 20, right: $0) }
            feeder.feed(Body.arms(left: 20, right: 20), frames: 5)
        }
        return feeder
    }

    @Test func theFilmedSideIsTheOneCounted() throws {
        let movement = try leftArmMovement()
        #expect(movement.filmedSide == .left)
        #expect(raises(ReferenceCounter(movement: movement), left: true).completed.count == 3)
        // The other arm isn't counted as filmed, and the patient is told.
        let wrong = raises(ReferenceCounter(movement: movement), left: false)
        #expect(wrong.completed.isEmpty)
        #expect(wrong.corrections.contains(.useOtherSide))
    }

    @Test func theMirroredSideCountsTheOtherArm() throws {
        let movement = try leftArmMovement()
        #expect(raises(ReferenceCounter(movement: movement, side: .mirrored), left: false).completed.count == 3)
        #expect(raises(ReferenceCounter(movement: movement, side: .mirrored), left: true).completed.isEmpty)
        #expect(raises(ReferenceCounter(movement: movement, side: .either), left: false).completed.count == 3)
    }

    // MARK: Held position

    @Test func theHoldTimerRunsOnlyInThePosition() throws {
        let movement = Self.movement(try ReferenceAnalyzer.analyze(Self.film(start: (20, 20), [(20, 20, 1.5), (90, 90, 1.5), (90, 90, 6), (20, 20, 1)])))
        var counter = HoldCounter(movement: movement)
        var time = 0.0
        func feed(_ m: PoseMeasure?, frames: Int) -> CounterUpdate {
            var last = CounterUpdate(progress: 0, event: nil)
            for _ in 0..<frames {
                time += 1 / 15
                last = counter.process(m, at: time)
            }
            return last
        }
        #expect(feed(Body.arms(left: 20, right: 20), frames: 10).isHolding == false)
        #expect(feed(Body.arms(left: 90, right: 90), frames: 10).isHolding == true)
        // Arms dropping a little: still held; dropping a lot: the timer stops.
        #expect(feed(Body.arms(left: 80, right: 80), frames: 10).isHolding == true)
        #expect(feed(Body.arms(left: 40, right: 40), frames: 10).isHolding == false)
        // Not seen: the timer doesn't run on a guess.
        _ = feed(Body.arms(left: 90, right: 90), frames: 10)
        #expect(feed(nil, frames: 10).isHolding == false)
    }

    // MARK: Guide poses

    @Test func guidePosesAreCompleteAndPlausible() {
        typealias Joint = VNHumanBodyPoseObservation.JointName
        // The right arm unseen, the left wrist far away (a detection error).
        var measure = Body.arms(left: 20, right: 20)
        measure.rightElbow = nil
        measure.rightWrist = nil
        var sample = Self.sample(measure, at: 0)
        var points = sample.points
        points[.leftWrist] = CGPoint(x: 0.95, y: 0.02)
        sample = ReferenceSample(time: 0, measure: measure, points: points, imageSize: sample.imageSize)
        let poses = ReferenceAnalyzer.guidePoses(rest: [sample], target: [sample])
        for joint: Joint in [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist,
                             .leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .neck] {
            #expect(poses.rest[joint.rawValue.rawValue] != nil, "\(joint.rawValue.rawValue)")
        }
        // The left wrist is back near the body; the right arm mirrors the left one.
        let shoulder = poses.rest[Joint.leftShoulder.rawValue.rawValue]!, wrist = poses.rest[Joint.leftWrist.rawValue.rawValue]!
        #expect(hypot(wrist.x - shoulder.x, wrist.y - shoulder.y) < 0.6)
        let leftElbow = poses.rest[Joint.leftElbow.rawValue.rawValue]!, rightElbow = poses.rest[Joint.rightElbow.rawValue.rawValue]!
        #expect(abs(leftElbow.y - rightElbow.y) < 0.02)
        #expect(abs((leftElbow.x + rightElbow.x) / 2 - 0.5) < 0.05)
    }
}

private final class BundleToken {}
