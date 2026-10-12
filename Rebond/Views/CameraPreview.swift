import AVFoundation
import SwiftUI

/// Live camera feed, kept upright when the phone rotates.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    let camera: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {
        if let camera {
            view.followRotation(of: camera)
        }
    }

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
        private var rotationObservation: NSKeyValueObservation?

        func followRotation(of camera: AVCaptureDevice) {
            guard rotationCoordinator == nil else { return }
            let coordinator = AVCaptureDevice.RotationCoordinator(device: camera, previewLayer: previewLayer)
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                self?.previewLayer.connection?.videoRotationAngle = coordinator.videoRotationAngleForHorizonLevelPreview
            }
            rotationCoordinator = coordinator
        }
    }
}
