import SwiftUI
import AVFoundation

/// AVCaptureVideoPreviewLayer를 호스팅하는 카메라 실시간 프리뷰.
struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.session = session
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            // layerClass를 위처럼 지정했으므로 항상 캐스팅 성공.
            layer as! AVCaptureVideoPreviewLayer
        }
    }
}
