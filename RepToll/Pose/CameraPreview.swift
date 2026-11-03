import AVFoundation
import SwiftUI
import RepTollKit

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

/// Draws the tracked joints over the aspect-filled camera preview. Bones stay calm white;
/// only joints with a problem get a red ring, so the overlay doesn't flash.
/// Reads the model itself so per-frame updates redraw only this view, not the whole camera screen.
struct SkeletonOverlay: View {
    let session: ExerciseSessionModel

    private static let bones: [(Joint, Joint)] = [
        (.leftShoulder, .rightShoulder), (.leftShoulder, .leftElbow), (.leftElbow, .leftWrist),
        (.rightShoulder, .rightElbow), (.rightElbow, .rightWrist), (.leftShoulder, .leftHip),
        (.rightShoulder, .rightHip), (.leftHip, .rightHip), (.leftHip, .leftKnee), (.leftKnee, .leftAnkle),
        (.rightHip, .rightKnee), (.rightKnee, .rightAnkle),
    ]

    var body: some View {
        let points = session.overlay, imageSize = session.imageSize, problems = session.problems
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
                context.stroke(path, with: .color(.white.opacity(0.75)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round))
            }
            for (joint, p) in points {
                let c = place(p)
                let dot = Path(ellipseIn: CGRect(x: c.x - 5, y: c.y - 5, width: 10, height: 10))
                context.fill(dot, with: .color(Theme.accent))
                if problems.contains(joint) {
                    let ring = Path(ellipseIn: CGRect(x: c.x - 11, y: c.y - 11, width: 22, height: 22))
                    context.stroke(ring, with: .color(Theme.danger), lineWidth: 3)
                }
            }
        }
        .allowsHitTesting(false)
    }
}
