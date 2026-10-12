import CoreGraphics
import CoreVideo
import Vision
import simd

/// 2D joints to draw over the camera feed.
nonisolated struct PoseSkeleton: Sendable {
    /// Normalized positions, origin top-left.
    let points: [VNHumanBodyPoseObservation.JointName: CGPoint]
    /// Size of the analyzed image, to place the points over the preview.
    let imageSize: CGSize
}

/// What the rep counter needs from one frame.
nonisolated struct PoseMeasure: Sendable {
    /// Tracked joint angle, in degrees.
    let angle: Double
    /// Torso angle from vertical, in degrees.
    let torsoLean: Double
}

/// Detects the body in a camera frame.
nonisolated struct PoseAnalyzer {
    let exercise: CatalogExercise
    /// Orientation of the frames. Camera frames are already upright.
    var orientation = CGImagePropertyOrientation.up

    /// 2D joints below this confidence are not drawn.
    private let minimumConfidence: Float = 0.3

    /// Fast 2D detection, used to draw the skeleton and know if someone is in frame.
    func skeleton(in pixelBuffer: CVPixelBuffer) -> PoseSkeleton? {
        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        guard (try? handler.perform([request])) != nil,
              let points = try? request.results?.first?.recognizedPoints(.all)
        else { return nil }

        let visible = points
            .filter { $0.value.confidence >= minimumConfidence }
            .mapValues { CGPoint(x: $0.location.x, y: 1 - $0.location.y) }
        guard visible.count >= 4 else { return nil }

        return PoseSkeleton(points: visible, imageSize: uprightSize(of: pixelBuffer))
    }

    /// Slower 3D detection, used to measure the movement.
    /// Works facing the camera or sideways, even when the feet are hidden.
    func measure(in pixelBuffer: CVPixelBuffer) -> PoseMeasure? {
        let request = VNDetectHumanBodyPose3DRequest()
        let request2D = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: orientation)
        guard (try? handler.perform([request, request2D])) != nil,
              let observation = request.results?.first
        else { return nil }

        func position(_ joint: VNHumanBodyPose3DObservation.JointName) -> simd_float3? {
            guard let point = try? observation.recognizedPoint(joint) else { return nil }
            let translation = point.position.columns.3
            return simd_float3(translation.x, translation.y, translation.z)
        }

        let angles = exercise.joints.compactMap { joints -> Double? in
            guard let first = position(joints.first),
                  let vertex = position(joints.vertex),
                  let last = position(joints.last)
            else { return nil }
            return Self.angle(at: vertex, from: first, to: last)
        }
        // Vision sometimes folds one leg too much: keep the most open angle.
        guard let angle = angles.max() else { return nil }

        // The 3D torso stays upright in Vision's model: measure the lean in the image instead.
        // Visible when standing sideways, close to 0 when facing the camera.
        var torsoLean = 0.0
        if let points = try? request2D.results?.first?.recognizedPoints(.torso),
           let neck = points[.neck], let root = points[.root],
           neck.confidence >= minimumConfidence, root.confidence >= minimumConfidence {
            let size = uprightSize(of: pixelBuffer)
            let dx = abs(neck.location.x - root.location.x) * size.width
            let dy = (neck.location.y - root.location.y) * size.height
            torsoLean = atan2(dx, dy) * 180 / .pi
        }
        return PoseMeasure(angle: angle, torsoLean: torsoLean)
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

    /// Angle in degrees at `vertex` between the segments to `a` and `b`.
    static func angle(at vertex: simd_float3, from a: simd_float3, to b: simd_float3) -> Double {
        let v1 = a - vertex
        let v2 = b - vertex
        let lengths = simd_length(v1) * simd_length(v2)
        guard lengths > 0 else { return 0 }
        let cosine = Double(simd_dot(v1, v2) / lengths)
        return acos(max(-1, min(1, cosine))) * 180 / .pi
    }
}
