import CoreGraphics
import CoreVideo
import Vision

/// 2D joints to draw over the camera feed.
nonisolated struct PoseSkeleton: Sendable {
    /// Normalized positions, origin top-left.
    let points: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// Size of the analyzed image, to place the points over the preview.
    let imageSize: CGSize
}

/// What the rep counter needs from one frame.
/// Positions use the image height as unit, origin bottom-left, so distances are comparable in x and y.
nonisolated struct PoseMeasure: Sendable {
    let hips: CGPoint
    let neck: CGPoint
    let leftHip: CGPoint?
    let rightHip: CGPoint?
    let leftKnee: CGPoint?
    let rightKnee: CGPoint?
    let leftAnkle: CGPoint?
    let rightAnkle: CGPoint?
    var leftShoulder: CGPoint? = nil
    var rightShoulder: CGPoint? = nil
    var leftElbow: CGPoint? = nil
    var rightElbow: CGPoint? = nil
    var leftWrist: CGPoint? = nil
    var rightWrist: CGPoint? = nil

    /// Neck to hips distance: the body's scale in the image.
    var torsoLength: Double {
        hypot(neck.x - hips.x, neck.y - hips.y)
    }

    /// Knee angle of each visible leg, in degrees: about 180 when the leg is straight.
    var kneeAngles: [Double] {
        [(leftHip, leftKnee, leftAnkle), (rightHip, rightKnee, rightAnkle)].compactMap { hip, knee, ankle in
            guard let hip, let knee, let ankle else { return nil }
            let a = CGVector(dx: hip.x - knee.x, dy: hip.y - knee.y)
            let b = CGVector(dx: ankle.x - knee.x, dy: ankle.y - knee.y)
            let lengths = hypot(a.dx, a.dy) * hypot(b.dx, b.dy)
            guard lengths > 0 else { return nil }
            let cosine = Double((a.dx * b.dx + a.dy * b.dy) / lengths)
            return acos(max(-1, min(1, cosine))) * 180 / .pi
        }
    }

    /// Height difference between both knees, in torso lengths. Large in a lunge, small in a squat.
    var kneeHeightGap: Double? {
        guard let leftKnee, let rightKnee, torsoLength > 0 else { return nil }
        return abs(leftKnee.y - rightKnee.y) / torsoLength
    }

    /// Distance between both ankles, in torso lengths.
    var stanceWidth: Double? {
        guard let leftAnkle, let rightAnkle, torsoLength > 0 else { return nil }
        return hypot(leftAnkle.x - rightAnkle.x, leftAnkle.y - rightAnkle.y) / torsoLength
    }

    /// Torso angle from vertical, in degrees. Visible when standing sideways, close to 0 when facing the camera.
    var torsoLean: Double {
        atan2(abs(neck.x - hips.x), neck.y - hips.y) * 180 / .pi
    }
}

nonisolated struct PoseFrame: Sendable {
    let skeleton: PoseSkeleton?
    /// Nil when the hips or the neck aren't reliably visible.
    let measure: PoseMeasure?
}

/// Detects the body in a camera frame with Vision's 2D body pose.
nonisolated struct PoseAnalyzer {
    /// Orientation of the frames. Camera frames are already upright.
    var orientation = CGImagePropertyOrientation.up

    /// Joints below this confidence are ignored.
    private let minimumConfidence: Float = 0.3

    func analyze(_ pixelBuffer: CVPixelBuffer) -> PoseFrame {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        guard (try? handler.perform([request])) != nil,
              let visible = patientPoints(in: request.results ?? [])
        else { return PoseFrame(skeleton: nil, measure: nil) }

        guard visible.count >= 4 else { return PoseFrame(skeleton: nil, measure: nil) }

        let size = uprightSize(of: pixelBuffer)
        let skeleton = PoseSkeleton(
            points: visible.mapValues { CGPoint(x: $0.location.x, y: 1 - $0.location.y) },
            imageSize: size
        )

        // Vision's normalized x is relative to the width: rescale it to the height unit.
        let aspect = size.width / size.height
        func position(_ joint: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            visible[joint].map { CGPoint(x: $0.location.x * aspect, y: $0.location.y) }
        }

        /// Vision's root and neck are the middles of the hips and of the shoulders. Their confidence drops
        /// sooner than the joints around them (arm across the body, loose clothes): rebuild them when needed,
        /// rather than losing the body.
        func middle(_ a: VNHumanBodyPoseObservation.JointName, _ b: VNHumanBodyPoseObservation.JointName) -> CGPoint? {
            guard let p = position(a), let q = position(b) else { return nil }
            return CGPoint(x: (p.x + q.x) / 2, y: (p.y + q.y) / 2)
        }

        var measure: PoseMeasure?
        if let hips = position(.root) ?? middle(.leftHip, .rightHip),
           let neck = position(.neck) ?? middle(.leftShoulder, .rightShoulder) {
            measure = PoseMeasure(
                hips: hips,
                neck: neck,
                leftHip: position(.leftHip),
                rightHip: position(.rightHip),
                leftKnee: position(.leftKnee),
                rightKnee: position(.rightKnee),
                leftAnkle: position(.leftAnkle),
                rightAnkle: position(.rightAnkle),
                leftShoulder: position(.leftShoulder),
                rightShoulder: position(.rightShoulder),
                leftElbow: position(.leftElbow),
                rightElbow: position(.rightElbow),
                leftWrist: position(.leftWrist),
                rightWrist: position(.rightWrist)
            )
        }
        return PoseFrame(skeleton: skeleton, measure: measure)
    }

    /// Several people can be in view (family, colleagues in the background): the patient is the one
    /// standing closest to the phone, so the largest on screen.
    private func patientPoints(in observations: [VNHumanBodyPoseObservation]) -> [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]? {
        let people = observations.compactMap { observation -> [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]? in
            guard let points = try? observation.recognizedPoints(.all) else { return nil }
            return points.filter { $0.value.confidence >= minimumConfidence }
        }
        return people.max { Self.area(of: $0) < Self.area(of: $1) }
    }

    private static func area(of points: [VNHumanBodyPoseObservation.JointName: VNRecognizedPoint]) -> Double {
        let xs = points.values.map(\.location.x), ys = points.values.map(\.location.y)
        guard let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() else { return 0 }
        return (maxX - minX) * (maxY - minY)
    }

    /// Image size once `orientation` is applied, matching Vision's normalized coordinates.
    private func uprightSize(of pixelBuffer: CVPixelBuffer) -> CGSize {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        switch orientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            return CGSize(width: height, height: width)
        default:
            return CGSize(width: width, height: height)
        }
    }
}
