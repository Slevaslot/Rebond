import CoreGraphics
import CoreVideo
import Foundation
import Vision

/// Signs to control the session from 2–3 m away, without touching the phone. Each one is held still a moment,
/// and only while the body itself stands still: a hand moving through the shape during an exercise never counts.
nonisolated enum HandGesture: Sendable, Equatable, CaseIterable {
    /// Palm open toward the camera, one hand raised to shoulder height, held a moment: pause or resume.
    case openPalm
    /// Thumb and index together, then moving apart, as on a touch screen: open the model large.
    case spread
    /// Thumb and index apart, then coming together: put the model back in its card.
    case pinch
    /// Fist with the thumb up, at chest height or above, held a moment: next set (or go on, or confirm).
    case thumbsUp
    /// Index and middle finger up in a "V", held a moment: next exercise.
    case twoFingers
    /// Both forearms crossed in front of the chest, held a moment: end the session (asked again first).
    case crossedArms
}

/// Recognizes `HandGesture`s from Vision's hand pose and the body skeleton.
///
/// - Thumbs up and V: a hand clearly away from the hips (wrist above the middle of the torso), one hand or both.
/// - Open palm: one hand raised to about shoulder height, the other one lower.
/// - Crossed arms: the body pose alone, both wrists on the other side of the body, between shoulders and hips.
/// - Every sign is held with the wrist still, the body not moving; once used, the hand must come down (or change)
///   before any sign counts again. Pausing or resuming, whoever asked, also waits for the hand to come down.
/// - While paused, any hand of the patient counts, at any height, even standing close to the phone: resuming
///   (open palm) is quicker; a thumbs up stays "next", a V "next exercise", never a resume.
///
/// The geometry is in static functions, tested on synthetic points (`HandGestureTests`).
nonisolated struct HandGestureDetector {
    /// Points of a hand, in pixels, origin top-left.
    typealias Hand = [VNHumanHandPoseObservation.JointName: CGPoint]
    /// Points of a body, in pixels (the same unit on both axes), origin top-left.
    typealias Body = [VNHumanBodyPoseObservation.JointName: CGPoint]

    /// Orientation of the frames. Camera frames are already upright.
    var orientation = CGImagePropertyOrientation.up

    /// How long each sign is held, in seconds.
    static let palmHold = 0.9
    static let resumeHold = 0.4
    static let thumbHold = 0.6
    static let twoFingersHold = 0.8
    static let crossedArmsHold = 1.2
    /// A wrist moving more than this from where the sign started, in torso lengths, starts the hold again.
    static let stillness = 0.15
    /// The same without the body (paused, close to the phone), in palm sizes.
    static let handStillness = 0.8

    /// A wrist this far below the shoulders, in torso lengths, still counts as raised: the elbow can stay bent.
    static let raisedMargin = 0.15
    /// Above this fraction of the torso, from the neck down, a hand is clearly away from the hips.
    static let chestLine = 0.5

    private let minimumConfidence: Float = 0.3

    /// A sign seen held still long enough, once; then released before it can count again.
    private struct Hold {
        let duration: TimeInterval
        /// A detection missed this long doesn't release the sign.
        static let releaseDelay = 0.3
        private var start: TimeInterval?
        /// Where the sign started: it must stay about there.
        private(set) var anchor: CGPoint?
        private var lastSeen: TimeInterval?
        private var used = false

        init(duration: TimeInterval) { self.duration = duration }

        /// True once, when the sign has been held long enough at about the same place.
        /// - Parameter position: The sign's wrist, or nil when it isn't seen.
        mutating func update(_ position: CGPoint?, tolerance: Double, at time: TimeInterval) -> Bool {
            guard let position else {
                if let lastSeen, time - lastSeen <= Self.releaseDelay { return false }
                start = nil
                anchor = nil
                lastSeen = nil
                used = false
                return false
            }
            // The hand is going somewhere, not making a sign: start again from here.
            if let anchor, hypot(position.x - anchor.x, position.y - anchor.y) > tolerance { start = nil }
            if start == nil {
                start = time
                anchor = position
            }
            lastSeen = time
            guard !used, let start, time - start >= duration else { return false }
            used = true
            return true
        }

        /// Another sign just counted, or the pause changed: wait for this one to be released.
        mutating func consume(at time: TimeInterval) {
            used = true
            lastSeen = time
        }
    }

    private var palm = Hold(duration: palmHold)
    private var resume = Hold(duration: resumeHold)
    private var thumb = Hold(duration: thumbHold)
    private var twoFingers = Hold(duration: twoFingersHold)
    private var crossedArms = Hold(duration: crossedArmsHold)
    private var wasPaused = false

    /// Gap between the thumb and index tips, in palm sizes: below, they touch; above, they are apart.
    static let closedGap = 0.35
    static let openGap = 0.8
    /// Recent gaps: a spread or pinch must happen within about one second.
    private var gaps: [(time: TimeInterval, gap: Double)] = []
    private let gapWindow = 1.0

    /// - Parameters:
    ///   - isMoving: The body is really moving (a repetition, walking): no sign counts, except while paused.
    ///   - isPaused: Resuming must always be easy: any open hand of the patient, held a shorter moment.
    mutating func process(_ pixelBuffer: CVPixelBuffer, body: PoseSkeleton?, isMoving: Bool = false,
                          isPaused: Bool = false) -> HandGesture? {
        let time = ProcessInfo.processInfo.systemUptime
        let size = body?.imageSize ?? CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let points = body.map { skeleton in skeleton.points.mapValues { CGPoint(x: $0.x * size.width, y: $0.y * size.height) } }
        // Hands are only analyzed when one may be making a sign, which saves work during the exercise.
        let needsHands = isPaused || (points.map(Self.mayBeSigning) ?? false)
        let hands = needsHands ? Self.patientHands(detectHands(in: pixelBuffer, size: size), body: points, lenient: isPaused) : []
        return update(hands: hands, body: points, isMoving: isMoving, isPaused: isPaused, at: time)
    }

    /// The decision, from the patient's hands and body of one frame: what `process` does after Vision.
    mutating func update(hands: [Hand], body: Body?, isMoving: Bool, isPaused: Bool, at time: TimeInterval) -> HandGesture? {
        if isPaused != wasPaused {
            // Paused or resumed, by a sign, a button or Siri: the hand that did it must come down first,
            // or the palm that paused would resume a moment later.
            wasPaused = isPaused
            consumeAll(at: time)
        }
        let torso = body.flatMap(Self.torso)
        func tolerance(_ hand: Hand?) -> Double {
            if let torso { return torso.length * Self.stillness }
            return (hand.flatMap(Self.palmSize) ?? 0) * Self.handStillness
        }

        // Crossed arms: the body alone. Meanwhile the hands make no sign: the fists may look like thumbs up.
        let crossed = body.map(Self.areArmsCrossed) ?? false
        let crossing = crossed && !isMoving ? body.flatMap(Self.wristsMiddle) : nil
        if crossedArms.update(crossing, tolerance: tolerance(nil), at: time) { return fired(.crossedArms, at: time) }

        let signing: [Hand]
        if crossed {
            signing = []
        } else if isPaused {
            signing = hands
        } else if isMoving || (body.map(Self.areHandsTogether) ?? false) {
            // Moving, or both hands together (clasped at the chest during a squat): no sign.
            signing = []
        } else {
            signing = hands.filter { hand in
                guard let body, let wrist = hand[.wrist], let height = Self.height(of: wrist, in: body) else { return false }
                return height >= .chest
            }
        }

        // Open palm: resume while paused (any open hand), otherwise pause (one hand raised, the other lower).
        var raisedHand: Hand?
        if isPaused {
            let open = signing.first(where: Self.isOpenPalm)
            if resume.update(open?[.wrist], tolerance: .infinity, at: time) { return fired(.openPalm, at: time) }
        } else if let body {
            let raised = signing.filter { $0[.wrist].flatMap { Self.height(of: $0, in: body) } == .raised }
            let raisedArms = [body[.leftWrist], body[.rightWrist]].compactMap { $0 }
                .filter { Self.height(of: $0, in: body) == .raised }.count
            raisedHand = raisedArms == 1 && raised.count == 1 ? raised[0] : nil
            let open = raisedHand.flatMap { Self.isOpenPalm($0) ? $0[.wrist] : nil }
            if palm.update(open, tolerance: tolerance(raisedHand), at: time) { return fired(.openPalm, at: time) }
        } else {
            _ = palm.update(nil, tolerance: 0, at: time)
        }

        let thumbs = signing.filter(Self.isThumbUp)
        if thumb.update(Self.nearest(thumbs, to: thumb.anchor), tolerance: tolerance(thumbs.first), at: time) {
            return fired(.thumbsUp, at: time)
        }
        let victories = signing.filter(Self.isTwoFingers)
        if twoFingers.update(Self.nearest(victories, to: twoFingers.anchor), tolerance: tolerance(victories.first), at: time) {
            return fired(.twoFingers, at: time)
        }
        return spreadOrPinch(raisedHand, isOtherSign: !thumbs.isEmpty || !victories.isEmpty, at: time)
    }

    /// Spread and pinch, with the single raised hand: the thumb-index gap closing or opening within a second.
    private mutating func spreadOrPinch(_ hand: Hand?, isOtherSign: Bool, at time: TimeInterval) -> HandGesture? {
        gaps.removeAll { time - $0.time > gapWindow }
        // A thumb going up from a fist, or a V, also opens the thumb-index gap: it isn't a spread.
        if isOtherSign {
            gaps = []
            return nil
        }
        // A fist (and the moment it opens into a thumbs up or a V) isn't a pinch: no gap is measured.
        guard let hand, !Self.isFist(hand), let gap = Self.fingerGap(hand) else { return nil }
        // Each position is held at least two frames, so a hand moving while talking doesn't count.
        let wasClosed = gaps.filter { $0.gap < Self.closedGap }.count >= 2
        let wasOpen = gaps.filter { $0.gap > Self.openGap }.count >= 2
        gaps.append((time, gap))
        let lastTwo = gaps.suffix(2).map(\.gap)
        guard lastTwo.count == 2 else { return nil }
        if lastTwo.allSatisfy({ $0 > Self.openGap }), wasClosed {
            // The spread hand may look like an open palm: it must not pause right after.
            return fired(.spread, at: time)
        }
        if lastTwo.allSatisfy({ $0 < Self.closedGap }), wasOpen {
            return fired(.pinch, at: time)
        }
        return nil
    }

    /// A sign counted: every other one waits for the hand to come down.
    private mutating func fired(_ gesture: HandGesture, at time: TimeInterval) -> HandGesture {
        consumeAll(at: time)
        return gesture
    }

    private mutating func consumeAll(at time: TimeInterval) {
        palm.consume(at: time)
        resume.consume(at: time)
        thumb.consume(at: time)
        twoFingers.consume(at: time)
        crossedArms.consume(at: time)
        gaps = []
    }

    /// Vision's hands in a frame, in pixels, origin top-left.
    private func detectHands(in pixelBuffer: CVPixelBuffer, size: CGSize) -> [Hand] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 4
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        guard (try? handler.perform([request])) != nil else { return [] }
        return (request.results ?? []).compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            let hand = points.filter { $0.value.confidence >= minimumConfidence }
                .mapValues { CGPoint(x: $0.location.x * size.width, y: (1 - $0.location.y) * size.height) }
            return hand[.wrist] == nil ? nil : hand
        }
    }
}

// MARK: - Geometry

nonisolated extension HandGestureDetector {
    /// How high a point is on the body.
    enum Height: Int, Comparable {
        /// Below the middle of the torso: hands at rest, along the body.
        case low
        /// Between the middle of the torso and the shoulders.
        case chest
        /// At about shoulder height or above.
        case raised

        static func < (lhs: Height, rhs: Height) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    /// The torso of a body: Vision's neck and root, or the middles of the shoulders and the hips.
    struct Torso {
        let neck: CGPoint
        let root: CGPoint
        /// The lowest of the shoulders and the neck.
        let shoulderLine: Double

        var length: Double { hypot(root.x - neck.x, root.y - neck.y) }
    }

    static func torso(of body: Body) -> Torso? {
        func middle(_ a: VNHumanBodyPoseObservation.JointName, _ b: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = body[a], let q = body[b] else { return nil }
            return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        }
        guard let neck = body[.neck] ?? middle(.leftShoulder, .rightShoulder),
              let root = body[.root] ?? middle(.leftHip, .rightHip),
              root.y > neck.y
        else { return nil }
        let shoulderLine = [body[.leftShoulder], body[.rightShoulder], neck].compactMap { $0?.y }.max() ?? neck.y
        return Torso(neck: neck, root: root, shoulderLine: shoulderLine)
    }

    /// How high a point (a wrist) is on this body.
    static func height(of point: CGPoint, in body: Body) -> Height? {
        guard let torso = torso(of: body) else { return nil }
        if point.y < torso.shoulderLine + torso.length * raisedMargin { return .raised }
        if point.y < torso.neck.y + (torso.root.y - torso.neck.y) * chestLine { return .chest }
        return .low
    }

    /// A wrist of the body is high enough for a sign: the hands are worth analyzing.
    static func mayBeSigning(_ body: Body) -> Bool {
        [body[.leftWrist], body[.rightWrist]].compactMap { $0 }.contains { (height(of: $0, in: body) ?? .low) >= .chest }
    }

    /// Only the patient's own hands, at the wrists of their body: not someone else's in the background.
    /// - Parameter lenient: While paused, a little further from the wrists, and every hand when the body
    ///   isn't seen (the patient stepped close to the phone).
    static func patientHands(_ hands: [Hand], body: Body?, lenient: Bool) -> [Hand] {
        guard let body, let torso = torso(of: body) else { return lenient ? hands : [] }
        let wrists = [body[.leftWrist], body[.rightWrist]].compactMap { $0 }
        guard !wrists.isEmpty else { return lenient ? hands : [] }
        let reach = torso.length * (lenient ? 0.5 : 0.4)
        return hands.filter { hand in
            guard let wrist = hand[.wrist] else { return false }
            return wrists.contains { hypot($0.x - wrist.x, $0.y - wrist.y) < reach }
        }
    }

    /// All four fingers stretched out, the thumb away from them.
    static func isOpenPalm(_ hand: Hand) -> Bool {
        guard [Finger.index, .middle, .ring, .little].allSatisfy({ isStretched($0, in: hand) }),
              let thumb = hand[.thumbTip], let index = hand[.indexMCP], let palm = palmSize(hand),
              let gap = fingerGap(hand)
        else { return false }
        // Thumb touching the index: the start of a spread, not a palm.
        return hypot(thumb.x - index.x, thumb.y - index.y) > palm * 0.5 && gap > 0.6
    }

    /// At least three fingers folded into the palm, the thumb pointing up, its tip the highest point of the hand.
    static func isThumbUp(_ hand: Hand) -> Bool {
        guard let tip = hand[.thumbTip], let joint = hand[.thumbIP], let index = hand[.indexMCP], let palm = palmSize(hand)
        else { return false }
        let folded = [Finger.index, .middle, .ring, .little].filter { isFolded($0, in: hand) }.count
        // Pixels, origin top-left: up is a smaller y.
        guard folded >= 3, tip.y < joint.y, index.y - tip.y > palm * 0.6 else { return false }
        let fingerTips = [Finger.index, .middle, .ring, .little].compactMap { hand[$0.tip] }
        return fingerTips.allSatisfy { $0.y - tip.y > palm * 0.3 }
    }

    /// Index and middle finger stretched up, ring and little finger folded: a "V".
    static func isTwoFingers(_ hand: Hand) -> Bool {
        guard let wrist = hand[.wrist], let palm = palmSize(hand),
              isStretched(.index, in: hand), isStretched(.middle, in: hand),
              isFolded(.ring, in: hand), isFolded(.little, in: hand),
              let index = hand[.indexTip], let middle = hand[.middleTip]
        else { return false }
        return wrist.y - index.y > palm && wrist.y - middle.y > palm
    }

    /// The four fingers folded: a fist, with or without the thumb up.
    static func isFist(_ hand: Hand) -> Bool {
        [Finger.middle, .ring, .little].allSatisfy { isFolded($0, in: hand) }
    }

    /// Both forearms crossed in front of the chest: each wrist on the other side of the body's midline, between
    /// shoulders and hips, the elbows on their own side. One arm across the chest isn't enough.
    static func areArmsCrossed(_ body: Body) -> Bool {
        guard let torso = torso(of: body), torso.length > 0,
              let leftShoulder = body[.leftShoulder], let rightShoulder = body[.rightShoulder],
              let leftWrist = body[.leftWrist], let rightWrist = body[.rightWrist],
              // Facing the camera: the shoulders apart.
              abs(leftShoulder.x - rightShoulder.x) > torso.length * 0.3
        else { return false }
        let midline = (leftShoulder.x + rightShoulder.x) / 2
        let shoulders = (leftShoulder.y + rightShoulder.y) / 2
        let leftSide: Double = leftShoulder.x > midline ? 1 : -1
        func isAcross(_ wrist: CGPoint, side: Double) -> Bool {
            (wrist.x - midline) * -side > torso.length * 0.1
                && wrist.y > shoulders - torso.length * 0.2 && wrist.y < torso.root.y
        }
        func isOnItsSide(_ elbow: CGPoint?, side: Double) -> Bool {
            guard let elbow else { return true }
            return (elbow.x - midline) * side > -torso.length * 0.1
        }
        return isAcross(leftWrist, side: leftSide) && isAcross(rightWrist, side: -leftSide)
            && isOnItsSide(body[.leftElbow], side: leftSide) && isOnItsSide(body[.rightElbow], side: -leftSide)
    }

    /// Both wrists close together: hands clasped, or holding each other.
    static func areHandsTogether(_ body: Body) -> Bool {
        guard let torso = torso(of: body), let left = body[.leftWrist], let right = body[.rightWrist] else { return false }
        return hypot(left.x - right.x, left.y - right.y) < torso.length * 0.2
    }

    /// Gap between the thumb and index tips, in palm sizes.
    static func fingerGap(_ hand: Hand) -> Double? {
        guard let thumb = hand[.thumbTip], let index = hand[.indexTip], let palm = palmSize(hand) else { return nil }
        return hypot(thumb.x - index.x, thumb.y - index.y) / palm
    }

    /// Wrist to the base of the middle finger: the hand's scale in the image.
    static func palmSize(_ hand: Hand) -> Double? {
        guard let wrist = hand[.wrist], let base = hand[.middleMCP] else { return nil }
        let size = hypot(wrist.x - base.x, wrist.y - base.y)
        return size > 0 ? size : nil
    }

    enum Finger {
        case index, middle, ring, little

        var tip: VNHumanHandPoseObservation.JointName {
            switch self {
            case .index: .indexTip
            case .middle: .middleTip
            case .ring: .ringTip
            case .little: .littleTip
            }
        }

        var middleJoint: VNHumanHandPoseObservation.JointName {
            switch self {
            case .index: .indexPIP
            case .middle: .middlePIP
            case .ring: .ringPIP
            case .little: .littlePIP
            }
        }
    }

    /// The fingertip clearly further from the wrist than the finger's middle joint.
    static func isStretched(_ finger: Finger, in hand: Hand) -> Bool {
        guard let wrist = hand[.wrist], let tip = hand[finger.tip], let joint = hand[finger.middleJoint] else { return false }
        return hypot(wrist.x - tip.x, wrist.y - tip.y) > hypot(wrist.x - joint.x, wrist.y - joint.y) * 1.15
    }

    /// The fingertip back toward the palm, no further from the wrist than the finger's middle joint.
    static func isFolded(_ finger: Finger, in hand: Hand) -> Bool {
        guard let wrist = hand[.wrist], let tip = hand[finger.tip], let joint = hand[finger.middleJoint] else { return false }
        return hypot(wrist.x - tip.x, wrist.y - tip.y) < hypot(wrist.x - joint.x, wrist.y - joint.y) * 1.05
    }

    /// The middle of both wrists: where crossed arms are held.
    private static func wristsMiddle(_ body: Body) -> CGPoint? {
        guard let left = body[.leftWrist], let right = body[.rightWrist] else { return nil }
        return CGPoint(x: (left.x + right.x) / 2, y: (left.y + right.y) / 2)
    }

    /// The wrist of the hand making the sign: the one already held if there are two, otherwise the highest.
    private static func nearest(_ hands: [Hand], to anchor: CGPoint?) -> CGPoint? {
        let wrists = hands.compactMap { $0[.wrist] }
        guard let anchor else { return wrists.min { $0.y < $1.y } }
        return wrists.min { hypot($0.x - anchor.x, $0.y - anchor.y) < hypot($1.x - anchor.x, $1.y - anchor.y) }
    }
}
