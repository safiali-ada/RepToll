import AVFoundation
import SwiftUI
import UnscrollKit

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        view.backgroundColor = .black
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

        override func layoutSubviews() {
            super.layoutSubviews()
            if let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
        }
    }
}

/// Draws the tracked joints over the aspect-filled camera preview. Joints with form problems are red.
struct SkeletonOverlay: View {
    let points: [Joint: CGPoint]
    let imageSize: CGSize
    let problems: Set<Joint>

    private static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip), (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        Canvas { context, size in
            let scale = max(size.width / imageSize.width, size.height / imageSize.height)
            let drawn = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
            let offset = CGPoint(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2)
            func place(_ p: CGPoint) -> CGPoint {
                CGPoint(x: p.x * drawn.width + offset.x, y: p.y * drawn.height + offset.y)
            }

            for (a, b) in Self.bones {
                guard let pa = points[a], let pb = points[b] else { continue }
                var path = Path()
                path.move(to: place(pa))
                path.addLine(to: place(pb))
                let bad = problems.contains(a) || problems.contains(b)
                context.stroke(path, with: .color(bad ? Theme.danger : Theme.accent.opacity(0.85)),
                               style: StrokeStyle(lineWidth: 5, lineCap: .round))
            }
            for (joint, p) in points {
                let c = place(p)
                let dot = Path(ellipseIn: CGRect(x: c.x - 7, y: c.y - 7, width: 14, height: 14))
                context.fill(dot, with: .color(problems.contains(joint) ? Theme.danger : .white))
            }
        }
        .allowsHitTesting(false)
    }
}
