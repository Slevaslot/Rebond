import CoreGraphics
import CoreVideo
import Vision

/// Gestures to control the session from 2–3 m away, without touching the phone.
nonisolated enum HandGesture: Sendable {
    /// One open hand raised, palm toward the camera, the other hand down: pause or resume.
    /// Both hands up is left out: some exercises raise both arms, palms forward.
    case openPalm
    /// Both hands pinching and moving apart, like zooming on Apple Vision Pro: open the model large.
    case pinchApart
    /// Both hands pinching and coming together: put the model back in its card.
    case pinchTogether
}

/// Recognizes `HandGesture`s with Vision's hand pose.
/// A gesture only counts with the hands raised above the shoulders: during a squat they stay at chest height,
/// so the exercise itself never triggers one. Hands are only analyzed then, which also saves work.
nonisolated struct HandGestureDetector {
    /// Orientation of the frames. Camera frames are already upright.
    var orientation = CGImagePropertyOrientation.up

    /// Frames in a row with the open palm before it counts (about 0.6 s at 15 analyses per second).
    private let palmHoldFrames = 9
    /// Change of distance between both pinches that zooms, as a ratio of the starting distance.
    private let zoomInRatio = 1.4
    private let zoomOutRatio = 0.7
    /// Frames without the gesture before it is considered released.
    private let releaseFrames = 4
    private let minimumConfidence: Float = 0.3

    private var palmFrames = 0
    /// The palm already triggered: the hand must go down or close before it can again.
    private var palmUsed = false
    private var pinchStartDistance: Double?
    private var pinchUsed = false
    private var framesWithoutPalm = 0
    private var framesWithoutPinch = 0

    mutating func process(_ pixelBuffer: CVPixelBuffer, body: PoseSkeleton?) -> HandGesture? {
        let (hands, raisedArms) = raisedHands(in: pixelBuffer, body: body)

        // Pause: a single raised arm, with the palm open, held.
        if raisedArms == 1, hands.count == 1, Self.isOpenPalm(hands[0]) {
            framesWithoutPalm = 0
            palmFrames += 1
            if palmFrames >= palmHoldFrames, !palmUsed {
                palmUsed = true
                return .openPalm
            }
        } else {
            framesWithoutPalm += 1
            if framesWithoutPalm >= releaseFrames {
                palmFrames = 0
                palmUsed = false
            }
        }

        // Zoom: two pinches moving apart or together.
        let pinches = hands.compactMap { Self.pinchPoint($0) }
        if pinches.count == 2 {
            framesWithoutPinch = 0
            let distance = hypot(pinches[0].x - pinches[1].x, pinches[0].y - pinches[1].y)
            guard let start = pinchStartDistance else {
                pinchStartDistance = distance
                return nil
            }
            guard !pinchUsed, start > 0 else { return nil }
            if distance / start > zoomInRatio {
                pinchUsed = true
                return .pinchApart
            }
            if distance / start < zoomOutRatio {
                pinchUsed = true
                return .pinchTogether
            }
        } else {
            framesWithoutPinch += 1
            if framesWithoutPinch >= releaseFrames {
                pinchStartDistance = nil
                pinchUsed = false
            }
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
        guard let shoulderLine = shoulders.map(\.y).min(), let neck = body.points[.neck], let hips = body.points[.root] else { return ([], 0) }
        let raisedWrists = [body.points[.leftWrist], body.points[.rightWrist]].compactMap { $0 }.filter { $0.y < shoulderLine }
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

    /// All four fingers stretched out and the thumb away from them.
    private static func isOpenPalm(_ hand: [VNHumanHandPoseObservation.JointName: CGPoint]) -> Bool {
        guard let wrist = hand[.wrist], let palm = palmSize(hand) else { return false }
        func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
        let fingers: [(tip: VNHumanHandPoseObservation.JointName, pip: VNHumanHandPoseObservation.JointName)] = [
            (.indexTip, .indexPIP), (.middleTip, .middlePIP), (.ringTip, .ringPIP), (.littleTip, .littlePIP),
        ]
        let stretched = fingers.allSatisfy { finger in
            guard let tip = hand[finger.tip], let pip = hand[finger.pip] else { return false }
            return distance(wrist, tip) > distance(wrist, pip) * 1.15
        }
        guard stretched, let thumb = hand[.thumbTip], let index = hand[.indexMCP] else { return false }
        return distance(thumb, index) > palm * 0.5
    }

    /// Where the thumb and the index touch, if they do.
    private static func pinchPoint(_ hand: [VNHumanHandPoseObservation.JointName: CGPoint]) -> CGPoint? {
        guard let thumb = hand[.thumbTip], let index = hand[.indexTip], let palm = palmSize(hand),
              hypot(thumb.x - index.x, thumb.y - index.y) < palm * 0.35
        else { return nil }
        return CGPoint(x: (thumb.x + index.x) / 2, y: (thumb.y + index.y) / 2)
    }

    /// Wrist to the base of the middle finger: the hand's scale in the image.
    private static func palmSize(_ hand: [VNHumanHandPoseObservation.JointName: CGPoint]) -> Double? {
        guard let wrist = hand[.wrist], let base = hand[.middleMCP] else { return nil }
        let size = hypot(wrist.x - base.x, wrist.y - base.y)
        return size > 0 ? size : nil
    }
}
