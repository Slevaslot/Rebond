import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

/// Blurs everything but the patient in a camera frame, so their home stays private on screen.
/// Other people in view are blurred too. Runs entirely on the device.
nonisolated final class BackgroundBlur {
    private let context = CIContext()
    /// The patient's mask is computed every other frame, and reused in between to keep up with the camera.
    private var lastMask: CIImage?
    private var frameIndex = 0

    /// - Parameters:
    ///   - patient: where the patient is (their hips), normalized, origin top-left.
    ///     Without it, every person in view stays sharp.
    ///   - everything: blur the patient too (while watching the model or paused), in a single blur.
    func apply(to pixelBuffer: CVPixelBuffer, patient: CGPoint?, everything: Bool = false) -> CGImage? {
        let camera = CIImage(cvPixelBuffer: pixelBuffer)
        frameIndex += 1
        if frameIndex.isMultiple(of: 2) || lastMask == nil {
            lastMask = patientMask(in: pixelBuffer, patient: patient, size: camera.extent.size)
        }
        let blurred = camera.clampedToExtent()
            .applyingGaussianBlur(sigma: 12)
            .cropped(to: camera.extent)
        // Nobody in view yet, or nothing should be sharp: the whole picture is blurred.
        guard !everything, let mask = lastMask else { return context.createCGImage(blurred, from: camera.extent) }

        let blend = CIFilter.blendWithMask()
        blend.inputImage = camera
        blend.backgroundImage = blurred
        blend.maskImage = mask
        guard let output = blend.outputImage else { return nil }
        return context.createCGImage(output, from: camera.extent)
    }

    /// Mask of the patient alone, widened and softened so the blur doesn't hug the silhouette.
    private func patientMask(in pixelBuffer: CVPixelBuffer, patient: CGPoint?, size: CGSize) -> CIImage? {
        let request = VNGeneratePersonInstanceMaskRequest()
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        guard (try? handler.perform([request])) != nil,
              let observation = request.results?.first,
              !observation.allInstances.isEmpty
        else { return nil }

        var instances = observation.allInstances
        if let patient, let label = Self.label(at: patient, in: observation.instanceMask), label > 0 {
            instances = IndexSet(integer: label)
        }
        guard let maskBuffer = try? observation.generateScaledMaskForImage(forInstances: instances, from: handler)
        else { return nil }

        // Widen at a small size (cheaper), then scale back up and soften the edge.
        let rawMask = CIImage(cvPixelBuffer: maskBuffer)
        let reduction = 0.25
        let small = rawMask.transformed(by: CGAffineTransform(scaleX: reduction, y: reduction))
        let widen = CIFilter.morphologyMaximum()
        widen.inputImage = small
        widen.radius = Float(small.extent.width * 0.025)
        return (widen.outputImage ?? small)
            .transformed(by: CGAffineTransform(scaleX: size.width / small.extent.width, y: size.height / small.extent.height))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: size.width * 0.02)
            .cropped(to: CGRect(origin: .zero, size: size))
    }

    /// Person label (0 is the background) under a normalized point of the instance mask.
    private static func label(at point: CGPoint, in mask: CVPixelBuffer) -> Int? {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return nil }
        let width = CVPixelBufferGetWidth(mask), height = CVPixelBufferGetHeight(mask)
        let x = min(max(Int(point.x * Double(width)), 0), width - 1)
        let y = min(max(Int(point.y * Double(height)), 0), height - 1)
        let row = base.advanced(by: y * CVPixelBufferGetBytesPerRow(mask))
        return Int(row.load(fromByteOffset: x, as: UInt8.self))
    }
}
