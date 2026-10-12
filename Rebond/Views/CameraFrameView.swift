import SwiftUI
import UIKit

/// Shows the processed camera frames (background blurred), filling the space like the camera app.
struct CameraFrameView: UIViewRepresentable {
    let frame: LiveFrame

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.layer.contentsGravity = .resizeAspectFill
        view.clipsToBounds = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        view.layer.contents = frame.image
    }
}
