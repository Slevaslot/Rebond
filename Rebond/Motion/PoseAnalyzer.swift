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
    let leftAnkle: CGPoint?
    let rightAnkle: CGPoint?

    /// Neck to hips distance: the body's scale in the image.
    var torsoLength: Double {
        hypot(neck.x - hips.x, neck.y - hips.y)
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
              let points = try? request.results?.first?.recognizedPoints(.all)
        else { return PoseFrame(skeleton: nil, measure: nil) }

        let visible = points.filter { $0.value.confidence >= minimumConfidence }
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

        var measure: PoseMeasure?
        if let hips = position(.root), let neck = position(.neck) {
            measure = PoseMeasure(
                hips: hips,
                neck: neck,
                leftAnkle: position(.leftAnkle),
                rightAnkle: position(.rightAnkle)
            )
        }
        return PoseFrame(skeleton: skeleton, measure: measure)
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
