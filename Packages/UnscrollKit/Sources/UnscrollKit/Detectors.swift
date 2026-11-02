import Foundation

public struct DetectionThresholds: Sendable, Equatable {
    /// Minimum joint confidence. Vision reports lower values than MediaPipe's visibility (0.6–0.7 in Pushscroll), so this needs tuning on a device.
    public var minConfidence: Double
    /// Maximum left/right disagreement, in degrees, before a pose is rejected.
    public var maxAsymmetry: Double

    public init(minConfidence: Double, maxAsymmetry: Double) {
        self.minConfidence = minConfidence
        self.maxAsymmetry = maxAsymmetry
    }

    public static let `default` = DetectionThresholds(minConfidence: 0.3, maxAsymmetry: 40)
}

public enum DetectionEvent: Equatable, Sendable {
    /// Body not (fully) in frame; the set holds the joints that are missing or unsure.
    case notInFrame(Set<Joint>)
    /// In frame, but the pose doesn't match any phase of the exercise.
    case badForm(Set<Joint>)
    case tracking
    /// A new unit was counted; `total` is the running count.
    case counted(total: Int)
}

public protocol ExerciseDetector: Sendable {
    var exercise: Exercise { get }
    /// Reps, or held seconds for plank.
    var count: Int { get }
    mutating func process(_ frame: PoseFrame) -> DetectionEvent
}

enum Phase: Sendable, Hashable { case unknown, up, down }

/// Shared rep counting: classify each frame into up/down/unknown, debounce, and count down→up transitions.
struct RepCounter: Sendable {
    private var debouncer = StateDebouncer<Phase>(initial: .unknown)
    private var lastTimestamp: TimeInterval?
    private(set) var count = 0

    mutating func feed(_ phase: Phase, frame: PoseFrame) -> Bool {
        defer { lastTimestamp = frame.timestamp }
        guard let last = lastTimestamp else { return false }
        let changed = debouncer.update(phase, frameDuration: frame.timestamp - last, processingTime: frame.processingTime)
        guard changed == true, debouncer.previous == .down, debouncer.current == .up else { return false }
        count += 1
        return true
    }
}

/// Elbow angle (shoulder–elbow–wrist), averaged over both arms. Up ≥ 148°, down 35–148°.
public struct PushupDetector: ExerciseDetector {
    public let exercise = Exercise.pushups
    public let thresholds: DetectionThresholds
    static let upRange = 148.0...200.0
    static let downRange = 35.0..<148.0
    static let required: Set<Joint> = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftHip, .rightHip]

    private var counter = RepCounter()
    public var count: Int { counter.count }

    public init(thresholds: DetectionThresholds = .default) { self.thresholds = thresholds }

    public mutating func process(_ frame: PoseFrame) -> DetectionEvent {
        let weak = frame.weakJoints(Self.required, minConfidence: thresholds.minConfidence)
        guard weak.isEmpty else { return .notInFrame(weak) }
        guard let left = Geometry.angle(frame, .leftShoulder, .leftElbow, .leftWrist),
              let right = Geometry.angle(frame, .rightShoulder, .rightElbow, .rightWrist)
        else { return .notInFrame([.leftElbow, .rightElbow]) }

        let elbow = (left + right) / 2
        var phase = Phase.unknown
        if abs(left - right) <= thresholds.maxAsymmetry {
            if Self.upRange.contains(elbow) { phase = .up }
            else if Self.downRange.contains(elbow) { phase = .down }
        }
        if counter.feed(phase, frame: frame) { return .counted(total: count) }
        return phase == .unknown ? .badForm([.leftElbow, .rightElbow, .leftWrist, .rightWrist]) : .tracking
    }
}

/// Knee angle (hip–knee–ankle), averaged over both legs. Up ≥ 100°, down 20–100°.
public struct SquatDetector: ExerciseDetector {
    public let exercise = Exercise.squats
    public let thresholds: DetectionThresholds
    static let upRange = 100.0...200.0
    static let downRange = 20.0..<100.0
    static let required: Set<Joint> = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder]

    private var counter = RepCounter()
    public var count: Int { counter.count }

    public init(thresholds: DetectionThresholds = .default) { self.thresholds = thresholds }

    public mutating func process(_ frame: PoseFrame) -> DetectionEvent {
        let weak = frame.weakJoints(Self.required, minConfidence: thresholds.minConfidence)
        guard weak.isEmpty else { return .notInFrame(weak) }
        guard let left = Geometry.angle(frame, .leftHip, .leftKnee, .leftAnkle),
              let right = Geometry.angle(frame, .rightHip, .rightKnee, .rightAnkle)
        else { return .notInFrame([.leftKnee, .rightKnee]) }

        let knee = (left + right) / 2
        var phase = Phase.unknown
        if abs(left - right) <= thresholds.maxAsymmetry {
            if Self.upRange.contains(knee) { phase = .up }
            else if Self.downRange.contains(knee) { phase = .down }
        }
        if counter.feed(phase, frame: frame) { return .counted(total: count) }
        return phase == .unknown ? .badForm([.leftKnee, .rightKnee]) : .tracking
    }
}

/// Counts whole seconds held in a valid plank. A break resets the current hold but keeps the total.
/// Elbows 85–180°, shoulders (elbow–shoulder–other shoulder) 55–135°, body straight (shoulder–hip–knee ≥ 150°).
public struct PlankDetector: ExerciseDetector {
    public let exercise = Exercise.plank
    public let thresholds: DetectionThresholds
    static let elbowRange = 85.0...180.0
    static let shoulderRange = 55.0...135.0
    static let minBodyLine = 150.0
    static let required: Set<Joint> = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist, .leftHip, .rightHip, .leftKnee, .rightKnee]

    public private(set) var count = 0
    private var holdElapsed: TimeInterval = 0
    private var holdCounted = 0
    private var lastTimestamp: TimeInterval?

    public init(thresholds: DetectionThresholds = .default) { self.thresholds = thresholds }

    public mutating func process(_ frame: PoseFrame) -> DetectionEvent {
        defer { lastTimestamp = frame.timestamp }
        let weak = frame.weakJoints(Self.required, minConfidence: thresholds.minConfidence)
        guard weak.isEmpty else { resetHold(); return .notInFrame(weak) }

        let bad = formProblems(frame)
        guard bad.isEmpty else { resetHold(); return .badForm(bad) }

        if let last = lastTimestamp { holdElapsed += max(0, frame.timestamp - last) }
        let seconds = Int(holdElapsed)
        guard seconds > holdCounted else { return .tracking }
        count += seconds - holdCounted
        holdCounted = seconds
        return .counted(total: count)
    }

    private mutating func resetHold() {
        holdElapsed = 0
        holdCounted = 0
    }

    private func formProblems(_ f: PoseFrame) -> Set<Joint> {
        var bad = Set<Joint>()
        func check(_ joint: Joint, _ value: Double?, _ ok: (Double) -> Bool) {
            if let value, !ok(value) { bad.insert(joint) } else if value == nil { bad.insert(joint) }
        }
        check(.leftElbow, Geometry.angle(f, .leftShoulder, .leftElbow, .leftWrist)) { Self.elbowRange.contains($0) }
        check(.rightElbow, Geometry.angle(f, .rightShoulder, .rightElbow, .rightWrist)) { Self.elbowRange.contains($0) }
        check(.leftShoulder, Geometry.angle(f, .leftElbow, .leftShoulder, .rightShoulder)) { Self.shoulderRange.contains($0) }
        check(.rightShoulder, Geometry.angle(f, .rightElbow, .rightShoulder, .leftShoulder)) { Self.shoulderRange.contains($0) }
        check(.leftHip, Geometry.angle(f, .leftShoulder, .leftHip, .leftKnee)) { $0 >= Self.minBodyLine }
        check(.rightHip, Geometry.angle(f, .rightShoulder, .rightHip, .rightKnee)) { $0 >= Self.minBodyLine }
        return bad
    }
}
