import CoreGraphics
import Foundation
import Testing
@testable import Rebond

/// Synthetic bodies seen from the front, in the counters' units (image height, origin bottom-left).
enum Body {
    static let neck = CGPoint(x: 0.5, y: 0.8)
    static let hips = CGPoint(x: 0.5, y: 0.5)
    static let leftShoulder = CGPoint(x: 0.4, y: 0.78)
    static let rightShoulder = CGPoint(x: 0.6, y: 0.78)
    static let leftHip = CGPoint(x: 0.45, y: 0.5)
    static let rightHip = CGPoint(x: 0.55, y: 0.5)
    static let armLength = 0.25

    /// Standing, both arms raised sideways by the given angles (0 along the body).
    static func arms(left: Double, right: Double, elbowBend: Double = 0) -> PoseMeasure {
        func arm(shoulder: CGPoint, hip: CGPoint, angle: Double, outward: Double) -> (elbow: CGPoint, wrist: CGPoint) {
            // Direction from the shoulder to the hip, turned outward by the angle.
            let down = atan2(hip.y - shoulder.y, hip.x - shoulder.x)
            let direction = down + outward * angle * .pi / 180
            let elbow = CGPoint(x: shoulder.x + cos(direction) * armLength / 2, y: shoulder.y + sin(direction) * armLength / 2)
            let forearm = direction + outward * elbowBend * .pi / 180
            let wrist = CGPoint(x: elbow.x + cos(forearm) * armLength / 2, y: elbow.y + sin(forearm) * armLength / 2)
            return (elbow, wrist)
        }
        // Mirrored image: the left arm opens toward smaller x, so it turns clockwise from "down".
        let l = arm(shoulder: leftShoulder, hip: leftHip, angle: left, outward: -1)
        let r = arm(shoulder: rightShoulder, hip: rightHip, angle: right, outward: 1)
        return PoseMeasure(
            hips: hips, neck: neck, leftHip: leftHip, rightHip: rightHip,
            leftKnee: CGPoint(x: 0.45, y: 0.3), rightKnee: CGPoint(x: 0.55, y: 0.3),
            leftAnkle: CGPoint(x: 0.45, y: 0.1), rightAnkle: CGPoint(x: 0.55, y: 0.1),
            leftShoulder: leftShoulder, rightShoulder: rightShoulder,
            leftElbow: l.elbow, rightElbow: r.elbow, leftWrist: l.wrist, rightWrist: r.wrist
        )
    }

    /// Standing, hips lowered by `depth` torso lengths (the whole upper body moves down with them).
    static func squat(depth: Double) -> PoseMeasure {
        let drop = depth * (neck.y - hips.y)
        func down(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x, y: p.y - drop) }
        return PoseMeasure(
            hips: down(hips), neck: down(neck), leftHip: down(leftHip), rightHip: down(rightHip),
            leftKnee: CGPoint(x: 0.45, y: 0.3), rightKnee: CGPoint(x: 0.55, y: 0.3),
            leftAnkle: CGPoint(x: 0.45, y: 0.1), rightAnkle: CGPoint(x: 0.55, y: 0.1)
        )
    }
}

/// Feeds measures at 15 per second and collects the events.
struct Feeder<Counter: MovementCounter> {
    var counter: Counter
    var time = 0.0
    var events: [RepEvent] = []

    mutating func feed(_ measure: PoseMeasure, frames: Int = 1) {
        for _ in 0..<frames {
            time += 1.0 / 15
            if let event = counter.process(measure, at: time).event { events.append(event) }
        }
    }

    /// Moves smoothly from one value to another over `seconds`.
    mutating func move(from a: Double, to b: Double, seconds: Double, measure: (Double) -> PoseMeasure) {
        let frames = Int(seconds * 15)
        for i in 1...frames {
            feed(measure(a + (b - a) * Double(i) / Double(frames)))
        }
    }

    var completed: [RepResult] {
        events.compactMap { if case .repCompleted(let result) = $0 { result } else { nil } }
    }
    var incomplete: Int {
        events.filter { if case .repIncomplete = $0 { true } else { false } }.count
    }
    var corrections: [Correction] {
        events.compactMap { if case .correction(let correction) = $0 { correction } else { nil } }
    }
    var calibrated: Bool {
        events.contains { if case .calibrated = $0 { true } else { false } }
    }
}

@Suite("Élévation latérale des bras")
struct ArmRaiseCounterTests {
    private func calibrated() -> Feeder<ArmRaiseCounter> {
        var feeder = Feeder(counter: ArmRaiseCounter(targetAngle: 80))
        feeder.feed(Body.arms(left: 15, right: 15), frames: 10)
        return feeder
    }

    private func raise(_ feeder: inout Feeder<ArmRaiseCounter>, to angle: Double, seconds: Double = 1) {
        feeder.move(from: 15, to: angle, seconds: seconds) { Body.arms(left: $0, right: $0) }
        feeder.feed(Body.arms(left: angle, right: angle), frames: 3)
        feeder.move(from: angle, to: 15, seconds: seconds) { Body.arms(left: $0, right: $0) }
        feeder.feed(Body.arms(left: 15, right: 15), frames: 5)
    }

    @Test func measuresTheArmAngle() throws {
        let arms = try #require(ArmRaiseCounter.arms(in: Body.arms(left: 30, right: 85)))
        #expect(abs(arms.left.angle - 30) < 0.5)
        #expect(abs(arms.right.angle - 85) < 0.5)
        #expect(try #require(arms.left.elbow) > 179)
    }

    @Test func calibratesWithArmsDown() {
        #expect(calibrated().calibrated)
    }

    @Test func doesNotCalibrateWithArmsUp() {
        var feeder = Feeder(counter: ArmRaiseCounter(targetAngle: 80))
        feeder.feed(Body.arms(left: 70, right: 70), frames: 20)
        #expect(!feeder.calibrated)
    }

    @Test func countsFullRaises() throws {
        var feeder = calibrated()
        for _ in 0..<3 { raise(&feeder, to: 88) }
        #expect(feeder.completed.count == 3)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        #expect(amplitude > 1.05 && amplitude < 1.15)
        #expect(feeder.completed.allSatisfy { !$0.tooFast })
    }

    @Test func partialRaiseIsIncomplete() {
        var feeder = calibrated()
        // Under 70% of the 80° target (56°), above the 50° under which an attempt is ignored.
        raise(&feeder, to: 53)
        #expect(feeder.completed.isEmpty)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections == [.raiseHigher])
    }

    @Test func smallMovementIsIgnored() {
        var feeder = calibrated()
        raise(&feeder, to: 45)
        #expect(feeder.events.count == 1) // calibration only
    }

    @Test func oneArmOnlyIsRejected() {
        var feeder = calibrated()
        feeder.move(from: 15, to: 85, seconds: 1) { Body.arms(left: $0, right: 20) }
        feeder.move(from: 85, to: 15, seconds: 1) { Body.arms(left: $0, right: 20) }
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.raiseBothArms))
    }

    @Test func bentElbowsAreRejected() {
        var feeder = calibrated()
        feeder.move(from: 15, to: 85, seconds: 1) { Body.arms(left: $0, right: $0, elbowBend: 70) }
        feeder.move(from: 85, to: 15, seconds: 1) { Body.arms(left: $0, right: $0, elbowBend: 70) }
        #expect(feeder.completed.isEmpty)
        #expect(feeder.corrections.contains(.keepArmsStraight))
    }

    @Test func countsFromSeventyPercent() throws {
        var feeder = calibrated()
        raise(&feeder, to: 62)
        let result = try #require(feeder.completed.first)
        #expect(result.amplitude > 0.7 && result.amplitude < 0.8)
        #expect(AmplitudeTier(amplitude: result.amplitude) == .good)
        #expect(feeder.corrections.isEmpty)
    }

    @Test func fastRaiseIsFlagged() throws {
        var feeder = calibrated()
        raise(&feeder, to: 88, seconds: 0.4)
        #expect(try #require(feeder.completed.first).tooFast)
    }
}

@Suite("Squat")
struct SquatCounterTests {
    @Test func countsSquatsAndPartialOnes() throws {
        var feeder = Feeder(counter: RepCounter(targetDepth: 0.6))
        feeder.feed(Body.squat(depth: 0), frames: 10)
        #expect(feeder.calibrated)

        for _ in 0..<2 {
            feeder.move(from: 0, to: 0.7, seconds: 1) { Body.squat(depth: $0) }
            feeder.move(from: 0.7, to: 0, seconds: 1) { Body.squat(depth: $0) }
            feeder.feed(Body.squat(depth: 0), frames: 3)
        }
        #expect(feeder.completed.count == 2)
        let amplitude = try #require(feeder.completed.first?.amplitude)
        // The median over 3 frames softens the very bottom of the movement.
        #expect(amplitude > 1.0 && amplitude < 1.2)

        // Under 70% of the target (0.42): incomplete.
        feeder.move(from: 0, to: 0.36, seconds: 1) { Body.squat(depth: $0) }
        feeder.move(from: 0.36, to: 0, seconds: 1) { Body.squat(depth: $0) }
        feeder.feed(Body.squat(depth: 0), frames: 3)
        #expect(feeder.completed.count == 2)
        #expect(feeder.incomplete == 1)
        #expect(feeder.corrections.contains(.goLower))
    }

    @Test func countsFromSeventyPercentOfTheTarget() throws {
        var feeder = Feeder(counter: RepCounter(targetDepth: 0.6))
        feeder.feed(Body.squat(depth: 0), frames: 10)
        feeder.move(from: 0, to: 0.48, seconds: 1) { Body.squat(depth: $0) }
        let bottom = feeder.events.contains { if case .bottomReached = $0 { true } else { false } }
        #expect(bottom)
        feeder.move(from: 0.48, to: 0, seconds: 1) { Body.squat(depth: $0) }
        feeder.feed(Body.squat(depth: 0), frames: 3)
        let result = try #require(feeder.completed.first)
        #expect(result.amplitude > 0.7 && result.amplitude < 0.85)
        #expect(feeder.incomplete == 0)
    }
}
