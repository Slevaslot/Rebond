import CoreGraphics
import CoreVideo
import Vision

/// Gestures to control the session from 2–3 m away, without touching the phone.
/// Both are made with one hand raised to shoulder height, the other one down.
nonisolated enum HandGesture: Sendable {
    /// Palm open toward the camera, held a moment: pause or resume.
    case openPalm
    /// Thumb and index together, then moving apart, as on a touch screen: open the model large.
    case spread
    /// Thumb and index apart, then coming together: put the model back in its card.
    case pinch
    /// Fist with the thumb up, held a moment: next set.
    case thumbsUp
}

/// Recognizes `HandGesture`s with Vision's hand pose.
/// A gesture only counts with one hand up at shoulder height: during a squat the hands stay lower, together at
/// chest height, and an exercise raising both arms is left out. Hands are only analyzed then, which also saves work.
nonisolated struct HandGestureDetector {
    /// Orientation of the frames. Camera frames are already upright.
    var orientation = CGImagePropertyOrientation.up

    /// A wrist this far below the shoulders, in torso lengths, still counts as raised: the elbow can stay bent.
    private let raisedMargin = 0.15
    private let minimumConfidence: Float = 0.3

    /// A hand shape held for a few frames in a row, then released before it can count again.
    private struct Hold {
        /// Frames needed, at 15 analyses per second.
        let frames: Int
        private var count = 0
        private var missed = 0
        private var used = false

        init(frames: Int) { self.frames = frames }

        /// True once, when the shape has been held long enough.
        mutating func update(_ seen: Bool) -> Bool {
            if seen {
                missed = 0
                count += 1
                if count >= frames, !used {
                    used = true
                    return true
                }
            } else {
                // A missed detection or two doesn't release the shape.
                missed += 1
                if missed >= 3 {
                    count = 0
                    used = false
                }
            }
            return false
        }

        /// Another gesture just used the hand: wait for it to be released.
        mutating func consume() {
            used = true
        }
    }

    /// About 1 s: a pause shouldn't come from a hand passing by.
    private var palm = Hold(frames: 15)
    /// About 0.4 s while paused: resuming is quicker than pausing.
    private var resume = Hold(frames: 6)
    private var wasPaused = false
    /// About 0.6 s as well: moving on to the next set is not undone easily.
    private var thumb = Hold(frames: 9)

    /// Gap between the thumb and index tips, in palm sizes: below, they touch; above, they are apart.
    private let closedGap = 0.35
    private let openGap = 0.8
    /// Recent gaps, about one second: a spread or pinch must happen within it.
    private var gaps: [Double] = []
    private let gapWindow = 15

    /// - Parameters:
    ///   - isMoving: The patient is in a repetition: an open hand is then part of the movement, not a pause.
    ///   - isPaused: Resuming must always be easy: any open hand of the patient, raised or not, one hand or two,
    ///     even standing close to the phone, held a shorter moment. A thumbs up resumes too.
    mutating func process(_ pixelBuffer: CVPixelBuffer, body: PoseSkeleton?, isMoving: Bool = false,
                          isPaused: Bool = false) -> HandGesture? {
        if isPaused {
            wasPaused = true
            let hands = anyHands(in: pixelBuffer, body: body)
            let open = hands.contains(where: Self.isOpenPalm) || hands.contains(where: Self.isThumbUp)
            gaps = []
            return resume.update(open) ? .openPalm : nil
        }
        if wasPaused {
            // Just resumed: the hand that resumed must come down before it can pause or skip again.
            wasPaused = false
            resume = Hold(frames: 6)
            palm.consume()
            thumb.consume()
        }
        let (hands, raisedArms) = raisedHands(in: pixelBuffer, body: body)
        let hand = raisedArms == 1 && hands.count == 1 && !isMoving ? hands[0] : nil

        if palm.update(hand.map(Self.isOpenPalm) ?? false) { return .openPalm }
        let isThumbUp = hand.map(Self.isThumbUp) ?? false
        if thumb.update(isThumbUp) { return .thumbsUp }
        // A thumb going up from a fist also opens the thumb-index gap: it isn't a spread.
        if isThumbUp {
            gaps = []
            return nil
        }

        guard let gap = hand.flatMap(Self.fingerGap) else {
            // A missed detection doesn't break the gesture, but the window still moves on.
            gaps = Array(gaps.dropFirst())
            return nil
        }
        defer { gaps = Array(gaps.suffix(gapWindow - 1)) }
        // Each position is held at least two frames, so a hand moving while talking doesn't count.
        let wasClosed = gaps.filter { $0 < closedGap }.count >= 2
        let wasOpen = gaps.filter { $0 > openGap }.count >= 2
        gaps.append(gap)
        let lastTwo = gaps.suffix(2)
        guard lastTwo.count == 2 else { return nil }
        if lastTwo.allSatisfy({ $0 > openGap }), wasClosed {
            gaps = []
            // The spread hand may look like an open palm: it must not pause right after.
            palm.consume()
            return .spread
        }
        if lastTwo.allSatisfy({ $0 < closedGap }), wasOpen {
            gaps = []
            return .pinch
        }
        return nil
    }

    /// The patient's hands that are raised above their shoulders, in pixels, origin top-left,
    /// and how many of their arms are raised.
    private func raisedHands(in pixelBuffer: CVPixelBuffer, body: PoseSkeleton?) -> ([[VNHumanHandPoseObservation.JointName: CGPoint]], Int) {
        guard let body else { return ([], 0) }
        let size = body.imageSize
        func pixels(_ point: CGPoint) -> CGPoint { CGPoint(x: point.x * size.width, y: point.y * size.height) }

        let shoulders = [body.points[.leftShoulder], body.points[.rightShoulder], body.points[.neck]].compactMap { $0 }
        guard let shoulderLine = shoulders.map(\.y).max(), let neck = body.points[.neck], let hips = body.points[.root] else { return ([], 0) }
        let raisedLine = shoulderLine + (hips.y - neck.y) * raisedMargin
        let raisedWrists = [body.points[.leftWrist], body.points[.rightWrist]].compactMap { $0 }.filter { $0.y < raisedLine }
        guard !raisedWrists.isEmpty else { return ([], 0) }

        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 4
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        guard (try? handler.perform([request])) != nil else { return ([], raisedWrists.count) }

        // Only hands at the patient's own raised wrists: not someone else's in the background.
        let torso = hypot(pixels(neck).x - pixels(hips).x, pixels(neck).y - pixels(hips).y)
        let hands: [[VNHumanHandPoseObservation.JointName: CGPoint]] = (request.results ?? []).compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            let hand = points.filter { $0.value.confidence >= minimumConfidence }
                .mapValues { pixels(CGPoint(x: $0.location.x, y: 1 - $0.location.y)) }
            guard let wrist = hand[.wrist] else { return nil }
            let atRaisedWrist = raisedWrists.contains {
                hypot(pixels($0).x - wrist.x, pixels($0).y - wrist.y) < torso * 0.4
            }
            return atRaisedWrist ? hand : nil
        }
        return (hands, raisedWrists.count)
    }

    /// The patient's hands wherever they are: near the body when it is seen, otherwise the largest ones in view
    /// (the patient stepped close to the phone).
    private func anyHands(in pixelBuffer: CVPixelBuffer, body: PoseSkeleton?) -> [[VNHumanHandPoseObservation.JointName: CGPoint]] {
        let request = VNDetectHumanHandPoseRequest()
        request.maximumHandCount = 4
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        guard (try? handler.perform([request])) != nil else { return [] }
        let size = body?.imageSize ?? CGSize(width: CVPixelBufferGetWidth(pixelBuffer), height: CVPixelBufferGetHeight(pixelBuffer))
        let hands: [[VNHumanHandPoseObservation.JointName: CGPoint]] = (request.results ?? []).compactMap { observation in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            let hand = points.filter { $0.value.confidence >= minimumConfidence }
                .mapValues { CGPoint(x: $0.location.x * size.width, y: (1 - $0.location.y) * size.height) }
            return hand[.wrist] == nil ? nil : hand
        }
        // With the body in view, only the hands at its wrists: not someone else's in the background.
        guard let body, let neck = body.points[.neck], let hips = body.points[.root] else { return hands }
        let wrists = [body.points[.leftWrist], body.points[.rightWrist]].compactMap { $0 }
            .map { CGPoint(x: $0.x * size.width, y: $0.y * size.height) }
        let torso = hypot((neck.x - hips.x) * size.width, (neck.y - hips.y) * size.height)
        guard !wrists.isEmpty, torso > 0 else { return hands }
        return hands.filter { hand in
            wrists.contains { hypot($0.x - hand[.wrist]!.x, $0.y - hand[.wrist]!.y) < torso * 0.5 }
        }
    }

    /// All four fingers stretched out and the thumb away from them.
    private static func isOpenPalm(_ hand: [VNHumanHandPoseObservation.JointName: CGPoint]) -> Bool {
        guard areStretched([(.indexTip, .indexPIP), (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP)], in: hand),
              let thumb = hand[.thumbTip], let index = hand[.indexMCP], let palm = palmSize(hand)
        else { return false }
        return hypot(thumb.x - index.x, thumb.y - index.y) > palm * 0.5
    }

    /// The four fingers folded into the palm, the thumb stretched upward.
    private static func isThumbUp(_ hand: [VNHumanHandPoseObservation.JointName: CGPoint]) -> Bool {
        guard let wrist = hand[.wrist], let thumb = hand[.thumbTip], let index = hand[.indexMCP], let palm = palmSize(hand)
        else { return false }
        let folded = [(VNHumanHandPoseObservation.JointName.indexTip, VNHumanHandPoseObservation.JointName.indexPIP),
                      (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP)]
            .filter { tip, pip in
                guard let tip = hand[tip], let pip = hand[pip] else { return false }
                return hypot(wrist.x - tip.x, wrist.y - tip.y) < hypot(wrist.x - pip.x, wrist.y - pip.y) * 1.05
            }
        // Pixels, origin top-left: up is a smaller y.
        return folded.count >= 3 && index.y - thumb.y > palm * 0.6
    }

    /// Gap between the thumb and index tips, in palm sizes.
    private static func fingerGap(_ hand: [VNHumanHandPoseObservation.JointName: CGPoint]) -> Double? {
        guard let thumb = hand[.thumbTip], let index = hand[.indexTip], let palm = palmSize(hand) else { return nil }
        return hypot(thumb.x - index.x, thumb.y - index.y) / palm
    }

    private static func areStretched(
        _ fingers: [(tip: VNHumanHandPoseObservation.JointName, pip: VNHumanHandPoseObservation.JointName)],
        in hand: [VNHumanHandPoseObservation.JointName: CGPoint]
    ) -> Bool {
        guard let wrist = hand[.wrist] else { return false }
        return fingers.allSatisfy { finger in
            guard let tip = hand[finger.tip], let pip = hand[finger.pip] else { return false }
            return hypot(wrist.x - tip.x, wrist.y - tip.y) > hypot(wrist.x - pip.x, wrist.y - pip.y) * 1.15
        }
    }

    /// Wrist to the base of the middle finger: the hand's scale in the image.
    private static func palmSize(_ hand: [VNHumanHandPoseObservation.JointName: CGPoint]) -> Double? {
        guard let wrist = hand[.wrist], let base = hand[.middleMCP] else { return nil }
        let size = hypot(wrist.x - base.x, wrist.y - base.y)
        return size > 0 ? size : nil
    }
}
