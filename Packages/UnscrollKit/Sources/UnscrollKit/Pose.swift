import Foundation

/// The 12 body joints the detectors use. Names match Vision's `JointName`s.
public enum Joint: String, CaseIterable, Sendable, Hashable, Codable {
    case leftShoulder, rightShoulder
    case leftElbow, rightElbow
    case leftWrist, rightWrist
    case leftHip, rightHip
    case leftKnee, rightKnee
    case leftAnkle, rightAnkle
}

public struct PosePoint: Sendable, Equatable {
    /// Body-relative position. Meters when it comes from 3D pose, aspect-corrected image units for the 2D fallback.
    public var position: SIMD3<Double>
    /// Detection confidence in 0...1.
    public var confidence: Double

    public init(position: SIMD3<Double>, confidence: Double) {
        self.position = position
        self.confidence = confidence
    }
}

/// One analyzed camera frame.
public struct PoseFrame: Sendable {
    /// Seconds, monotonic (capture presentation time).
    public var timestamp: TimeInterval
    /// Time the pose model took on this frame.
    public var processingTime: TimeInterval
    public var points: [Joint: PosePoint]

    public init(timestamp: TimeInterval, processingTime: TimeInterval = 0, points: [Joint: PosePoint]) {
        self.timestamp = timestamp
        self.processingTime = processingTime
        self.points = points
    }

    public subscript(_ joint: Joint) -> PosePoint? { points[joint] }

    /// Joints that are missing or below `minConfidence`.
    public func weakJoints(_ required: Set<Joint>, minConfidence: Double) -> Set<Joint> {
        required.filter { (points[$0]?.confidence ?? 0) < minConfidence }
    }
}

public enum Geometry {
    /// Angle at `b` in degrees, formed by the segments b→a and b→c. Returns nil for degenerate input.
    public static func angle(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Double? {
        let u = a - b, v = c - b
        let lu = (u * u).sum().squareRoot(), lv = (v * v).sum().squareRoot()
        guard lu > 1e-9, lv > 1e-9 else { return nil }
        let cos = max(-1, min(1, (u * v).sum() / (lu * lv)))
        return acos(cos) * 180 / .pi
    }

    public static func angle(_ frame: PoseFrame, _ a: Joint, _ b: Joint, _ c: Joint) -> Double? {
        guard let pa = frame[a], let pb = frame[b], let pc = frame[c] else { return nil }
        return angle(pa.position, pb.position, pc.position)
    }
}
