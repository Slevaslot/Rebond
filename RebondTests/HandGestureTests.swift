import CoreGraphics
import Foundation
import Testing
import Vision
@testable import Rebond

/// Synthetic hands, in pixels, origin top-left: the wrist at the given point, fingers pointing up, palm 50 px
/// (wrist to the base of the middle finger), about a sixth of the torso as seen from 2–3 m.
enum SyntheticHand {
    enum Finger { case stretched, folded }
    enum Thumb {
        /// Pointing up above the fist.
        case up
        /// Folded over the fingers.
        case tucked
        /// Away from the hand, to the side: an open palm.
        case out
        /// Its tip against the index tip.
        case touchingIndex
    }

    typealias Joint = VNHumanHandPoseObservation.JointName

    static func make(at wrist: CGPoint, index: Finger, middle: Finger, ring: Finger, little: Finger, thumb: Thumb) -> HandGestureDetector.Hand {
        var hand: HandGestureDetector.Hand = [.wrist: wrist]
        func put(_ joint: Joint, _ x: Double, _ y: Double) {
            hand[joint] = CGPoint(x: wrist.x + x, y: wrist.y + y)
        }
        let fingers: [(Finger, base: CGPoint, Joint, Joint, Joint, Joint)] = [
            (index, CGPoint(x: -20, y: -48), .indexMCP, .indexPIP, .indexDIP, .indexTip),
            (middle, CGPoint(x: 0, y: -50), .middleMCP, .middlePIP, .middleDIP, .middleTip),
            (ring, CGPoint(x: 16, y: -47), .ringMCP, .ringPIP, .ringDIP, .ringTip),
            (little, CGPoint(x: 30, y: -40), .littleMCP, .littlePIP, .littleDIP, .littleTip),
        ]
        for (shape, base, mcp, pip, dip, tip) in fingers {
            put(mcp, base.x, base.y)
            switch shape {
            case .stretched:
                put(pip, base.x, base.y - 25)
                put(dip, base.x, base.y - 40)
                put(tip, base.x, base.y - 52)
            case .folded:
                put(pip, base.x, base.y - 18)
                put(dip, base.x, base.y - 6)
                put(tip, base.x, base.y + 6)
            }
        }
        put(.thumbCMC, -12, -12)
        switch thumb {
        case .up:
            put(.thumbMP, -26, -30)
            put(.thumbIP, -30, -58)
            put(.thumbTip, -30, -88)
        case .tucked:
            put(.thumbMP, -22, -28)
            put(.thumbIP, -14, -40)
            put(.thumbTip, -2, -42)
        case .out:
            put(.thumbMP, -32, -24)
            put(.thumbIP, -46, -34)
            put(.thumbTip, -58, -42)
        case .touchingIndex:
            let indexTip = hand[.indexTip]!
            put(.thumbMP, -32, -40)
            put(.thumbIP, -30, -70)
            hand[.thumbTip] = CGPoint(x: indexTip.x - 3, y: indexTip.y + 4)
        }
        return hand
    }

    static func thumbsUp(at wrist: CGPoint) -> HandGestureDetector.Hand {
        make(at: wrist, index: .folded, middle: .folded, ring: .folded, little: .folded, thumb: .up)
    }

    static func fist(at wrist: CGPoint) -> HandGestureDetector.Hand {
        make(at: wrist, index: .folded, middle: .folded, ring: .folded, little: .folded, thumb: .tucked)
    }

    static func openPalm(at wrist: CGPoint) -> HandGestureDetector.Hand {
        make(at: wrist, index: .stretched, middle: .stretched, ring: .stretched, little: .stretched, thumb: .out)
    }

    static func victory(at wrist: CGPoint) -> HandGestureDetector.Hand {
        make(at: wrist, index: .stretched, middle: .stretched, ring: .folded, little: .folded, thumb: .tucked)
    }

    static func pinched(at wrist: CGPoint) -> HandGestureDetector.Hand {
        make(at: wrist, index: .stretched, middle: .stretched, ring: .stretched, little: .stretched, thumb: .touchingIndex)
    }

    /// Thumb and index, the other three fingers curled: how most people pinch or spread.
    static func pinchedCurled(at wrist: CGPoint) -> HandGestureDetector.Hand {
        make(at: wrist, index: .stretched, middle: .folded, ring: .folded, little: .folded, thumb: .touchingIndex)
    }

    static func spreadCurled(at wrist: CGPoint) -> HandGestureDetector.Hand {
        make(at: wrist, index: .stretched, middle: .folded, ring: .folded, little: .folded, thumb: .out)
    }
}

/// A body facing the camera, in pixels, origin top-left: torso 300 px (neck 400, hips 700).
/// The patient's left side is on the right of the image (as in a mirror).
enum SyntheticBody {
    typealias Joint = VNHumanBodyPoseObservation.JointName

    static let restLeft = CGPoint(x: 600, y: 720)
    static let restRight = CGPoint(x: 400, y: 720)
    /// In front of the chest, below the shoulders: a thumbs up as people do it.
    static let chestRight = CGPoint(x: 430, y: 490)
    /// Raised to shoulder height.
    static let raisedRight = CGPoint(x: 380, y: 360)
    static let raisedLeft = CGPoint(x: 620, y: 360)
    /// Just below the middle of the torso: the hand at the belly.
    static let bellyRight = CGPoint(x: 440, y: 580)

    static func make(leftWrist: CGPoint? = restLeft, rightWrist: CGPoint? = restRight,
                     leftElbow: CGPoint = CGPoint(x: 600, y: 560), rightElbow: CGPoint = CGPoint(x: 400, y: 560)) -> HandGestureDetector.Body {
        var body: HandGestureDetector.Body = [
            .neck: CGPoint(x: 500, y: 400), .root: CGPoint(x: 500, y: 700),
            .leftShoulder: CGPoint(x: 580, y: 400), .rightShoulder: CGPoint(x: 420, y: 400),
            .leftHip: CGPoint(x: 550, y: 700), .rightHip: CGPoint(x: 450, y: 700),
            .leftElbow: leftElbow, .rightElbow: rightElbow,
        ]
        body[.leftWrist] = leftWrist
        body[.rightWrist] = rightWrist
        return body
    }

    /// Forearms crossed in front of the chest: each wrist near the other elbow.
    static var crossedArms: HandGestureDetector.Body {
        make(leftWrist: CGPoint(x: 430, y: 500), rightWrist: CGPoint(x: 570, y: 510),
             leftElbow: CGPoint(x: 600, y: 540), rightElbow: CGPoint(x: 400, y: 540))
    }
}

@Suite("Signes de la main : géométrie")
struct HandShapeTests {
    let wrist = CGPoint(x: 400, y: 500)

    @Test func thumbsUpIsRecognized() {
        #expect(HandGestureDetector.isThumbUp(SyntheticHand.thumbsUp(at: wrist)))
        #expect(!HandGestureDetector.isTwoFingers(SyntheticHand.thumbsUp(at: wrist)))
        #expect(!HandGestureDetector.isOpenPalm(SyntheticHand.thumbsUp(at: wrist)))
    }

    @Test func aFistWithoutTheThumbIsNotAThumbsUp() {
        #expect(!HandGestureDetector.isThumbUp(SyntheticHand.fist(at: wrist)))
        #expect(HandGestureDetector.isFist(SyntheticHand.fist(at: wrist)))
    }

    @Test func anOpenPalmIsNotAThumbsUpNorAV() {
        let palm = SyntheticHand.openPalm(at: wrist)
        #expect(HandGestureDetector.isOpenPalm(palm))
        #expect(!HandGestureDetector.isThumbUp(palm))
        #expect(!HandGestureDetector.isTwoFingers(palm))
    }

    @Test func aVIsNotAnOpenPalm() {
        let victory = SyntheticHand.victory(at: wrist)
        #expect(HandGestureDetector.isTwoFingers(victory))
        #expect(!HandGestureDetector.isOpenPalm(victory))
        #expect(!HandGestureDetector.isThumbUp(victory))
    }

    @Test func threeFingersUpIsNotAV() {
        let three = SyntheticHand.make(at: wrist, index: .stretched, middle: .stretched, ring: .stretched, little: .folded, thumb: .tucked)
        #expect(!HandGestureDetector.isTwoFingers(three))
        #expect(!HandGestureDetector.isOpenPalm(three))
    }

    @Test func thumbAgainstTheIndexIsNotAnOpenPalm() {
        #expect(!HandGestureDetector.isOpenPalm(SyntheticHand.pinched(at: wrist)))
    }

    @Test func aThumbsUpUpsideDownDoesNotCount() {
        // The same hand hanging down: the thumb is the lowest point.
        let hanging = SyntheticHand.thumbsUp(at: wrist).mapValues { CGPoint(x: $0.x, y: 2 * wrist.y - $0.y) }
        #expect(!HandGestureDetector.isThumbUp(hanging))
    }

    @Test func heightsOnTheBody() {
        let body = SyntheticBody.make()
        #expect(HandGestureDetector.height(of: SyntheticBody.restRight, in: body) == .low)
        #expect(HandGestureDetector.height(of: SyntheticBody.bellyRight, in: body) == .low)
        #expect(HandGestureDetector.height(of: SyntheticBody.chestRight, in: body) == .chest)
        #expect(HandGestureDetector.height(of: SyntheticBody.raisedRight, in: body) == .raised)
    }

    @Test func crossedArmsAreRecognized() {
        #expect(HandGestureDetector.areArmsCrossed(SyntheticBody.crossedArms))
    }

    @Test func oneArmAcrossTheChestIsNotCrossedArms() {
        let oneArm = SyntheticBody.make(leftWrist: CGPoint(x: 430, y: 500), leftElbow: CGPoint(x: 600, y: 540))
        #expect(!HandGestureDetector.areArmsCrossed(oneArm))
    }

    @Test func handsClaspedAtTheChestAreNotCrossedArms() {
        let clasped = SyntheticBody.make(leftWrist: CGPoint(x: 505, y: 480), rightWrist: CGPoint(x: 495, y: 480))
        #expect(!HandGestureDetector.areArmsCrossed(clasped))
        #expect(HandGestureDetector.areHandsTogether(clasped))
    }

    @Test func armsDownOrRaisedAreNotCrossed() {
        #expect(!HandGestureDetector.areArmsCrossed(SyntheticBody.make()))
        #expect(!HandGestureDetector.areArmsCrossed(SyntheticBody.make(leftWrist: SyntheticBody.raisedLeft, rightWrist: SyntheticBody.raisedRight)))
    }

    @Test func crossedWristsAboveTheHeadAreNotCrossedArms() {
        let overHead = SyntheticBody.make(leftWrist: CGPoint(x: 460, y: 200), rightWrist: CGPoint(x: 540, y: 200))
        #expect(!HandGestureDetector.areArmsCrossed(overHead))
    }

    @Test func onlyThePatientsHandsCount() {
        let body = SyntheticBody.make(rightWrist: SyntheticBody.chestRight)
        let own = SyntheticHand.thumbsUp(at: SyntheticBody.chestRight)
        let someoneElse = SyntheticHand.thumbsUp(at: CGPoint(x: 900, y: 450))
        #expect(HandGestureDetector.patientHands([own, someoneElse], body: body, lenient: false).count == 1)
        // Close to the phone, the body not seen: only while paused.
        #expect(HandGestureDetector.patientHands([own], body: nil, lenient: false).isEmpty)
        #expect(HandGestureDetector.patientHands([own], body: nil, lenient: true).count == 1)
    }
}

@Suite("Signes de la main : tenue dans le temps")
struct HandGestureHoldTests {
    /// 15 analyses per second, as in a camera set.
    static let rate = 15.0

    /// Runs the detector for a while and returns every sign with the moment it counted.
    func run(_ detector: inout HandGestureDetector, from start: Double = 0, seconds: Double, rate: Double = rate,
             isMoving: Bool = false, isPaused: Bool = false,
             frame: (Double) -> ([HandGestureDetector.Hand], HandGestureDetector.Body?)) -> [(time: Double, gesture: HandGesture)] {
        var seen: [(time: Double, gesture: HandGesture)] = []
        for index in 0..<Int((seconds * rate).rounded()) {
            let time = start + Double(index) / rate
            let (hands, body) = frame(time - start)
            if let gesture = detector.update(hands: hands, body: body, isMoving: isMoving, isPaused: isPaused, at: time) {
                seen.append((time, gesture))
            }
        }
        return seen
    }

    func thumbAtChest(_: Double) -> ([HandGestureDetector.Hand], HandGestureDetector.Body?) {
        ([SyntheticHand.thumbsUp(at: SyntheticBody.chestRight)], SyntheticBody.make(rightWrist: SyntheticBody.chestRight))
    }

    @Test func thumbsUpAtChestHeightCountsOnceAfterAMoment() throws {
        var detector = HandGestureDetector()
        let seen = run(&detector, seconds: 3, frame: thumbAtChest)
        #expect(seen.map(\.gesture) == [.thumbsUp])
        let time = try #require(seen.first?.time)
        #expect(time >= HandGestureDetector.thumbHold - 0.01 && time < HandGestureDetector.thumbHold + 0.15)
    }

    @Test func thumbsUpWithBothHandsCounts() {
        var detector = HandGestureDetector()
        let left = CGPoint(x: 570, y: 490)
        let seen = run(&detector, seconds: 1.5) { _ in
            ([SyntheticHand.thumbsUp(at: SyntheticBody.chestRight), SyntheticHand.thumbsUp(at: left)],
             SyntheticBody.make(leftWrist: left, rightWrist: SyntheticBody.chestRight))
        }
        #expect(seen.map(\.gesture) == [.thumbsUp])
    }

    @Test func thumbsUpAtTheBellyDoesNotCount() {
        var detector = HandGestureDetector()
        let seen = run(&detector, seconds: 2) { _ in
            ([SyntheticHand.thumbsUp(at: SyntheticBody.bellyRight)], SyntheticBody.make(rightWrist: SyntheticBody.bellyRight))
        }
        #expect(seen.isEmpty)
    }

    @Test func aHandPassingByInTheShapeDoesNotCount() {
        var detector = HandGestureDetector()
        // The hand sweeps across the chest, about a torso per second, as in an exercise.
        let seen = run(&detector, seconds: 2) { time in
            let wrist = CGPoint(x: 300 + 300 * time, y: 490)
            return ([SyntheticHand.thumbsUp(at: wrist)], SyntheticBody.make(rightWrist: wrist))
        }
        #expect(seen.isEmpty)
    }

    @Test func noSignWhileTheBodyMoves() {
        var detector = HandGestureDetector()
        #expect(run(&detector, seconds: 2, isMoving: true, frame: thumbAtChest).isEmpty)
    }

    @Test func aShortSignDoesNotCount() {
        var detector = HandGestureDetector()
        let seen = run(&detector, seconds: 3) { time in
            time < 0.4 ? thumbAtChest(time) : ([SyntheticHand.fist(at: SyntheticBody.chestRight)], SyntheticBody.make(rightWrist: SyntheticBody.chestRight))
        }
        #expect(seen.isEmpty)
    }

    @Test func aSecondThumbsUpNeedsTheHandDownFirst() {
        var detector = HandGestureDetector()
        // Thumb up 1 s, hand down 0.5 s, thumb up again 1 s: two signs.
        let seen = run(&detector, seconds: 2.5) { time in
            (0.9..<1.4).contains(time) ? ([], SyntheticBody.make()) : thumbAtChest(time)
        }
        #expect(seen.map(\.gesture) == [.thumbsUp, .thumbsUp])
    }

    @Test func clappedHandsAtTheChestMakeNoSign() {
        var detector = HandGestureDetector()
        let left = CGPoint(x: 445, y: 490)
        let seen = run(&detector, seconds: 2) { _ in
            ([SyntheticHand.thumbsUp(at: SyntheticBody.chestRight), SyntheticHand.thumbsUp(at: left)],
             SyntheticBody.make(leftWrist: left, rightWrist: SyntheticBody.chestRight))
        }
        #expect(seen.isEmpty)
    }

    @Test func openPalmRaisedPausesAfterItsHold() throws {
        var detector = HandGestureDetector()
        let seen = run(&detector, seconds: 2) { _ in
            ([SyntheticHand.openPalm(at: SyntheticBody.raisedRight)], SyntheticBody.make(rightWrist: SyntheticBody.raisedRight))
        }
        #expect(seen.map(\.gesture) == [.openPalm])
        let time = try #require(seen.first?.time)
        #expect(time >= HandGestureDetector.palmHold - 0.01)
    }

    @Test func openPalmAtChestHeightOrWithBothArmsUpDoesNotPause() {
        var detector = HandGestureDetector()
        let atChest = run(&detector, seconds: 2) { _ in
            ([SyntheticHand.openPalm(at: SyntheticBody.chestRight)], SyntheticBody.make(rightWrist: SyntheticBody.chestRight))
        }
        #expect(atChest.isEmpty)
        var other = HandGestureDetector()
        let bothArms = run(&other, seconds: 2) { _ in
            ([SyntheticHand.openPalm(at: SyntheticBody.raisedRight), SyntheticHand.openPalm(at: SyntheticBody.raisedLeft)],
             SyntheticBody.make(leftWrist: SyntheticBody.raisedLeft, rightWrist: SyntheticBody.raisedRight))
        }
        #expect(bothArms.isEmpty)
    }

    @Test func theVCountsAsNextExercise() throws {
        var detector = HandGestureDetector()
        let seen = run(&detector, seconds: 2) { _ in
            ([SyntheticHand.victory(at: SyntheticBody.chestRight)], SyntheticBody.make(rightWrist: SyntheticBody.chestRight))
        }
        #expect(seen.map(\.gesture) == [.twoFingers])
        let time = try #require(seen.first?.time)
        #expect(time >= HandGestureDetector.twoFingersHold - 0.01)
    }

    @Test func crossedArmsEndAfterTheirHold() throws {
        var detector = HandGestureDetector()
        // The fists may look like thumbs up meanwhile: only the crossed arms count.
        let body = SyntheticBody.crossedArms
        let seen = run(&detector, seconds: 2.5) { _ in
            ([SyntheticHand.thumbsUp(at: body[.leftWrist]!), SyntheticHand.thumbsUp(at: body[.rightWrist]!)], body)
        }
        #expect(seen.map(\.gesture) == [.crossedArms])
        let time = try #require(seen.first?.time)
        #expect(time >= HandGestureDetector.crossedArmsHold - 0.01)
    }

    @Test func crossedArmsWhileMovingOrOneArmOnlyDoNothing() {
        var detector = HandGestureDetector()
        #expect(run(&detector, seconds: 2.5, isMoving: true) { _ in ([], SyntheticBody.crossedArms) }.isEmpty)
        var other = HandGestureDetector()
        let oneArm = SyntheticBody.make(leftWrist: CGPoint(x: 430, y: 500), leftElbow: CGPoint(x: 600, y: 540))
        #expect(run(&other, seconds: 2.5) { _ in ([], oneArm) }.isEmpty)
    }

    /// Paused with the hands down a moment, then the given frames.
    func paused(_ detector: inout HandGestureDetector, seconds: Double,
                frame: (Double) -> ([HandGestureDetector.Hand], HandGestureDetector.Body?)) -> [(time: Double, gesture: HandGesture)] {
        _ = run(&detector, seconds: 0.5, isPaused: true) { _ in ([], SyntheticBody.make()) }
        return run(&detector, from: 0.5, seconds: seconds, isPaused: true, frame: frame)
    }

    @Test func whilePausedAnyOpenHandResumesQuickly() throws {
        var detector = HandGestureDetector()
        // Low, along the body: still a resume.
        let seen = paused(&detector, seconds: 1.5) { _ in
            ([SyntheticHand.openPalm(at: SyntheticBody.restRight)], SyntheticBody.make())
        }
        #expect(seen.map(\.gesture) == [.openPalm])
        let time = try #require(seen.first?.time)
        #expect(time - 0.5 < HandGestureDetector.resumeHold + 0.1)
    }

    @Test func whilePausedAThumbsUpStaysNext() {
        var detector = HandGestureDetector()
        let seen = paused(&detector, seconds: 1.5, frame: thumbAtChest)
        #expect(seen.map(\.gesture) == [.thumbsUp])
    }

    @Test func whilePausedWithoutTheBodyAHandStillResumes() {
        var detector = HandGestureDetector()
        let seen = paused(&detector, seconds: 1.5) { _ in
            ([SyntheticHand.openPalm(at: CGPoint(x: 360, y: 640))], nil)
        }
        #expect(seen.map(\.gesture) == [.openPalm])
    }

    @Test func thePalmThatPausedDoesNotResumeRightAway() {
        var detector = HandGestureDetector()
        let palm: (Double) -> ([HandGestureDetector.Hand], HandGestureDetector.Body?) = { _ in
            ([SyntheticHand.openPalm(at: SyntheticBody.raisedRight)], SyntheticBody.make(rightWrist: SyntheticBody.raisedRight))
        }
        let paused = run(&detector, seconds: 1.2, frame: palm)
        #expect(paused.map(\.gesture) == [.openPalm])
        // Now paused, the hand still up for a while: no resume until it comes down.
        let stillUp = run(&detector, from: 1.2, seconds: 2, isPaused: true, frame: palm)
        #expect(stillUp.isEmpty)
        _ = run(&detector, from: 3.2, seconds: 0.6, isPaused: true) { _ in ([], SyntheticBody.make()) }
        let again = run(&detector, from: 3.8, seconds: 1, isPaused: true, frame: palm)
        #expect(again.map(\.gesture) == [.openPalm])
    }

    @Test func spreadStillWorks() {
        var detector = HandGestureDetector()
        let body = SyntheticBody.make(rightWrist: SyntheticBody.raisedRight)
        let seen = run(&detector, seconds: 0.6) { time in
            (time < 0.3 ? [SyntheticHand.pinched(at: SyntheticBody.raisedRight)] : [SyntheticHand.openPalm(at: SyntheticBody.raisedRight)], body)
        }
        #expect(seen.map(\.gesture) == [.spread])
    }

    @Test func pinchStillWorks() {
        var detector = HandGestureDetector()
        let body = SyntheticBody.make(rightWrist: SyntheticBody.raisedRight)
        let seen = run(&detector, seconds: 0.6) { time in
            (time < 0.3 ? [SyntheticHand.openPalm(at: SyntheticBody.raisedRight)] : [SyntheticHand.pinched(at: SyntheticBody.raisedRight)], body)
        }
        #expect(seen.map(\.gesture) == [.pinch])
    }

    @Test func spreadAndPinchWithTheOtherFingersCurled() {
        let body = SyntheticBody.make(rightWrist: SyntheticBody.raisedRight)
        var detector = HandGestureDetector()
        let spread = run(&detector, seconds: 0.6) { time in
            ([time < 0.3 ? SyntheticHand.pinchedCurled(at: SyntheticBody.raisedRight) : SyntheticHand.spreadCurled(at: SyntheticBody.raisedRight)], body)
        }
        #expect(spread.map(\.gesture) == [.spread])
        var other = HandGestureDetector()
        let pinch = run(&other, seconds: 0.6) { time in
            ([time < 0.3 ? SyntheticHand.spreadCurled(at: SyntheticBody.raisedRight) : SyntheticHand.pinchedCurled(at: SyntheticBody.raisedRight)], body)
        }
        #expect(pinch.map(\.gesture) == [.pinch])
    }

    @Test func openPalmPausesWithTheThumbSeenCloseToTheIndex() {
        var palm = SyntheticHand.openPalm(at: SyntheticBody.raisedRight)
        // Vision put the thumb's tip close to the index (0.45 palm from its tip), not touching it.
        let indexTip = palm[.indexTip]!
        palm[.thumbTip] = CGPoint(x: indexTip.x - 22, y: indexTip.y + 2)
        #expect(HandGestureDetector.isOpenPalm(palm))
    }

    @Test func openPalmPausesDespiteASmallDrift() {
        var detector = HandGestureDetector()
        // The raised wrist drifts 60 px (0.2 torso) during the hold, as an arm held up does.
        let seen = run(&detector, seconds: 1.5) { time in
            let wrist = CGPoint(x: SyntheticBody.raisedRight.x + 60 * min(1, time), y: SyntheticBody.raisedRight.y)
            return ([SyntheticHand.openPalm(at: wrist)], SyntheticBody.make(rightWrist: wrist))
        }
        #expect(seen.map(\.gesture) == [.openPalm])
    }

    @Test(arguments: [false, true])
    func aThumbsUpOrAVFromAFistIsNotASpread(victory: Bool) {
        var detector = HandGestureDetector()
        let body = SyntheticBody.make(rightWrist: SyntheticBody.raisedRight)
        let seen = run(&detector, seconds: 2) { time in
            let sign = victory ? SyntheticHand.victory(at: SyntheticBody.raisedRight) : SyntheticHand.thumbsUp(at: SyntheticBody.raisedRight)
            return (time < 0.4 ? [SyntheticHand.fist(at: SyntheticBody.raisedRight)] : [sign], body)
        }
        #expect(seen.map(\.gesture) == [victory ? .twoFingers : .thumbsUp])
    }

    @Test func holdsAreInSecondsWhateverTheRate() throws {
        // 10 analyses per second, as on the screens without the session camera.
        var detector = HandGestureDetector()
        let seen = run(&detector, seconds: 2, rate: 10, frame: thumbAtChest)
        #expect(seen.map(\.gesture) == [.thumbsUp])
        let time = try #require(seen.first?.time)
        #expect(time >= HandGestureDetector.thumbHold - 0.01 && time < HandGestureDetector.thumbHold + 0.15)
    }
}

@Suite("Mouvement du corps")
struct BodyMotionTests {
    func measure(hipsY: Double) -> PoseMeasure {
        PoseMeasure(hips: CGPoint(x: 0.5, y: hipsY), neck: CGPoint(x: 0.5, y: hipsY + 0.3),
                    leftHip: nil, rightHip: nil, leftKnee: CGPoint(x: 0.45, y: 0.3), rightKnee: CGPoint(x: 0.55, y: 0.3),
                    leftAnkle: nil, rightAnkle: nil)
    }

    @Test func standingStillIsNotMoving() {
        var motion = BodyMotion()
        let moving = (0..<20).map { index in motion.update(measure(hipsY: 0.5 + (index.isMultiple(of: 2) ? 0.002 : -0.002))) }
        #expect(!moving.contains(true))
    }

    @Test func aSquatIsMoving() {
        var motion = BodyMotion()
        // Hips going down 0.15 in 1 s, at 10 analyses per second.
        let moving = (0..<10).map { index in motion.update(measure(hipsY: 0.5 - 0.015 * Double(index))) }
        #expect(moving.suffix(5).allSatisfy { $0 })
    }
}
