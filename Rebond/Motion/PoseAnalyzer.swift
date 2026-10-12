import CoreMedia
import Foundation
import Vision

/// Detects the body in a camera frame and measures the exercise's tracked angle.
nonisolated struct PoseAnalyzer {
    let exercise: CatalogExercise

    /// Joints below this confidence are ignored.
    private let minimumConfidence: Float = 0.3

    /// Returns the tracked angle in degrees, or nil when the joints aren't reliably visible.
    func angle(in sampleBuffer: CMSampleBuffer) -> Double? {
        guard let pixelBuffer = sampleBuffer.imageBuffer else { return nil }

        let request = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              let points = try? observation.recognizedPoints(.all)
        else { return nil }

        // Vision returns normalized coordinates: scale them back to pixels so angles aren't distorted.
        let width = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let height = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        func position(_ point: VNRecognizedPoint) -> CGPoint {
            CGPoint(x: point.location.x * width, y: point.location.y * height)
        }

        let measures = exercise.joints.compactMap { joints -> (confidence: Float, angle: Double)? in
            guard let first = points[joints.first],
                  let vertex = points[joints.vertex],
                  let last = points[joints.last]
            else { return nil }
            let confidence = min(first.confidence, vertex.confidence, last.confidence)
            guard confidence >= minimumConfidence else { return nil }
            let angle = Self.angle(at: position(vertex), from: position(first), to: position(last))
            return (confidence, angle)
        }
        return measures.max { $0.confidence < $1.confidence }?.angle
    }

    /// Angle in degrees at `vertex` between the segments to `a` and `b`.
    static func angle(at vertex: CGPoint, from a: CGPoint, to b: CGPoint) -> Double {
        let v1 = CGVector(dx: a.x - vertex.x, dy: a.y - vertex.y)
        let v2 = CGVector(dx: b.x - vertex.x, dy: b.y - vertex.y)
        let lengths = hypot(v1.dx, v1.dy) * hypot(v2.dx, v2.dy)
        guard lengths > 0 else { return 0 }
        let cosine = Double((v1.dx * v2.dx + v1.dy * v2.dy) / lengths)
        return acos(max(-1, min(1, cosine))) * 180 / .pi
    }
}
