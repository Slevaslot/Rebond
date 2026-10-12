import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import Vision

/// Blurs everything but the person in a camera frame, so the patient's home stays private on screen.
/// Runs entirely on the device.
nonisolated final class BackgroundBlur {
    private let context = CIContext()
    private let request: VNGeneratePersonSegmentationRequest = {
        let request = VNGeneratePersonSegmentationRequest()
        // "balanced" keeps up with the camera; "accurate" is too slow for live video.
        request.qualityLevel = .balanced
        return request
    }()

    /// Returns the frame with a blurred background, or the frame unchanged if no person is found.
    func apply(to pixelBuffer: CVPixelBuffer) -> CGImage? {
        let camera = CIImage(cvPixelBuffer: pixelBuffer)
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)

        guard (try? handler.perform([request])) != nil,
              let maskBuffer = request.results?.first?.pixelBuffer
        else { return context.createCGImage(camera, from: camera.extent) }

        // Widen the sharp area around the body (cheaper at the mask's small size),
        // then soften its edge so the blur doesn't hug the silhouette.
        let rawMask = CIImage(cvPixelBuffer: maskBuffer)
        let widen = CIFilter.morphologyMaximum()
        widen.inputImage = rawMask
        widen.radius = Float(rawMask.extent.width * 0.025)
        let mask = (widen.outputImage ?? rawMask)
            .transformed(by: CGAffineTransform(
                scaleX: camera.extent.width / rawMask.extent.width,
                y: camera.extent.height / rawMask.extent.height
            ))
            .clampedToExtent()
            .applyingGaussianBlur(sigma: camera.extent.width * 0.02)
            .cropped(to: camera.extent)

        let blurred = camera.clampedToExtent()
            .applyingGaussianBlur(sigma: 12)
            .cropped(to: camera.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = camera
        blend.backgroundImage = blurred
        blend.maskImage = mask

        guard let output = blend.outputImage else { return nil }
        return context.createCGImage(output, from: camera.extent)
    }
}
