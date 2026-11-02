import AVFoundation
import CoreGraphics
import QuartzCore
import UnscrollKit
import Vision

/// One processed camera frame: detector input plus 2D points for the on-screen skeleton.
struct PoseSample: Sendable {
    var frame: PoseFrame
    /// Normalized image coordinates, origin top-left, in the (mirrored, portrait) camera buffer.
    var overlay: [UnscrollKit.Joint: CGPoint]
    var imageSize: CGSize
}

/// Front camera → Vision body pose. Runs on its own queues and streams results.
/// 3D pose gives joint angles in meters; 2D pose gives per-joint confidence and overlay points.
/// If 3D pose fails (older devices, simulator), angles fall back to aspect-corrected 2D.
nonisolated final class PosePipeline: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    let session = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "unscroll.camera.session")
    private let videoQueue = DispatchQueue(label: "unscroll.camera.video", qos: .userInitiated)
    private let request2D = VNDetectHumanBodyPoseRequest()
    private let request3D = VNDetectHumanBodyPose3DRequest()
    private var use3D = true
    private var isConfigured = false
    private var continuation: AsyncStream<PoseSample>.Continuation?

    private static let joints2D: [UnscrollKit.Joint: VNHumanBodyPoseObservation.JointName] = [
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    private static let joints3D: [UnscrollKit.Joint: VNHumanBodyPose3DObservation.JointName] = [
        .leftShoulder: .leftShoulder, .rightShoulder: .rightShoulder,
        .leftElbow: .leftElbow, .rightElbow: .rightElbow,
        .leftWrist: .leftWrist, .rightWrist: .rightWrist,
        .leftHip: .leftHip, .rightHip: .rightHip,
        .leftKnee: .leftKnee, .rightKnee: .rightKnee,
        .leftAnkle: .leftAnkle, .rightAnkle: .rightAnkle,
    ]

    /// Call once before `start()`.
    func samples() -> AsyncStream<PoseSample> {
        let (stream, continuation) = AsyncStream.makeStream(of: PoseSample.self, bufferingPolicy: .bufferingNewest(2))
        videoQueue.sync { self.continuation = continuation }
        return stream
    }

    func start() {
        sessionQueue.async { [self] in
            if !isConfigured { configure() }
            if !session.isRunning { session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async { [self] in
            if session.isRunning { session.stopRunning() }
        }
        videoQueue.async { [self] in
            continuation?.finish()
            continuation = nil
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
        output.setSampleBufferDelegate(self, queue: videoQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        if let connection = output.connection(with: .video) {
            if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            if connection.isVideoMirroringSupported {
                connection.automaticallyAdjustsVideoMirroring = false
                connection.isVideoMirrored = true
            }
        }
        isConfigured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let continuation, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
        let width = CVPixelBufferGetWidth(pixelBuffer), height = CVPixelBufferGetHeight(pixelBuffer)
        let started = CACurrentMediaTime()

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do {
            try handler.perform(use3D ? [request2D, request3D] : [request2D])
        } catch {
            // 3D pose isn't available everywhere; keep going with 2D only.
            if use3D { use3D = false }
            return
        }

        var points: [UnscrollKit.Joint: PosePoint] = [:]
        var overlay: [UnscrollKit.Joint: CGPoint] = [:]
        if let body = request2D.results?.first {
            let body3D = use3D ? request3D.results?.first : nil
            let aspect = Double(width) / Double(max(height, 1))
            for joint in UnscrollKit.Joint.allCases {
                guard let name = Self.joints2D[joint],
                      let p = try? body.recognizedPoint(name), p.confidence > 0 else { continue }
                overlay[joint] = CGPoint(x: p.location.x, y: 1 - p.location.y)
                var position = SIMD3(Double(p.location.x) * aspect, Double(p.location.y), 0)
                if let body3D, let name3D = Self.joints3D[joint],
                   let p3 = try? body3D.recognizedPoint(name3D) {
                    let t = p3.position.columns.3
                    position = SIMD3(Double(t.x), Double(t.y), Double(t.z))
                }
                points[joint] = PosePoint(position: position, confidence: Double(p.confidence))
            }
        }

        let frame = PoseFrame(timestamp: timestamp, processingTime: CACurrentMediaTime() - started, points: points)
        continuation.yield(PoseSample(frame: frame, overlay: overlay, imageSize: CGSize(width: width, height: height)))
    }
}
