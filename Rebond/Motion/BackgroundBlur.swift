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

        var mask = CIImage(cvPixelBuffer: maskBuffer)
        mask = mask.transformed(by: CGAffineTransform(
            scaleX: camera.extent.width / mask.extent.width,
            y: camera.extent.height / mask.extent.height
        ))

        let blurred = camera.clampedToExtent()
            .applyingGaussianBlur(sigma: 25)
            .cropped(to: camera.extent)

        let blend = CIFilter.blendWithMask()
        blend.inputImage = camera
        blend.backgroundImage = blurred
        blend.maskImage = mask

        guard let output = blend.outputImage else { return nil }
        return context.createCGImage(output, from: camera.extent)
    }
}
