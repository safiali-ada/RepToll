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

/// Why counting is on hold even though the body is visible.
public enum PositionHint: Sendable, Equatable {
    /// Push-ups: wrists aren't clearly below the shoulders.
    case handsOnFloor
    /// Push-ups: legs look like standing, not a plank.
    case getDown
    /// Hold the start position briefly before counting begins.
    case holdStart
}

public enum DetectionEvent: Equatable, Sendable {
    /// Body not (fully) in frame; the set holds the joints that are missing or unsure.
    case notInFrame(Set<Joint>)
    /// In frame but not in the exercise's position, so nothing counts.
    case getReady(PositionHint)
    /// In position, but the pose doesn't match any phase of the exercise.
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

/// Debounces up/down phases and reports rep boundaries. Nothing is reported until the
/// start (up) position has been held for `armDelay`, so setting up the phone or walking
/// into frame can't produce reps.
struct PhaseTracker: Sendable {
    enum Transition: Equatable { case none, enteredDown, completedRep }

    static let armDelay: TimeInterval = 1.0

    private var debouncer = StateDebouncer<Phase>(initial: .unknown)
    private var lastTimestamp: TimeInterval?
    private var upSince: TimeInterval?
    private(set) var isArmed = false

    mutating func disarm() {
        isArmed = false
        upSince = nil
        debouncer = StateDebouncer<Phase>(initial: .unknown)
        lastTimestamp = nil
    }

    mutating func feed(_ phase: Phase, frame: PoseFrame) -> Transition {
        defer { lastTimestamp = frame.timestamp }
        guard let last = lastTimestamp else { return .none }
        let changed = debouncer.update(phase, frameDuration: frame.timestamp - last, processingTime: frame.processingTime)

        if !isArmed {
            if debouncer.current == .up {
                upSince = upSince ?? frame.timestamp
                if frame.timestamp - (upSince ?? frame.timestamp) >= Self.armDelay { isArmed = true }
            } else {
                upSince = nil
            }
            return .none
        }

        guard changed == true else { return .none }
        if debouncer.current == .down { return .enteredDown }
        if debouncer.previous == .down && debouncer.current == .up { return .completedRep }
        return .none
    }
}

/// Elbow angle (shoulder–elbow–wrist), averaged over both arms. Up ≥ 148°, down 35–148°.
/// Only counts while the body is in a push-up position:
/// - wrists clearly below the shoulders in the image (hands on the floor);
/// - legs not hanging below the hips like when standing or sitting;
/// - hands planted: a rep is thrown out if the hands moved during it.
public struct PushupDetector: ExerciseDetector {
    public let exercise = Exercise.pushups
    public let thresholds: DetectionThresholds
    static let upRange = 148.0...200.0
    static let downRange = 35.0..<148.0
    static let required: Set<Joint> = [.leftShoulder, .rightShoulder, .leftElbow, .rightElbow, .leftWrist, .rightWrist]
    /// Wrists must sit this many shoulder-widths below the shoulders.
    static let minHandDrop = 0.5
    /// Knees more than this many shoulder-widths below the hips means standing/sitting upright.
    static let maxLegDrop = 0.9
    /// Hands may move at most this many shoulder-widths during a rep.
    static let maxHandDrift = 0.5
    /// Being out of position longer than this requires holding the start position again.
    static let outOfPositionGrace: TimeInterval = 1.5

    public private(set) var count = 0
    private var tracker = PhaseTracker()
    private var handAnchor: SIMD2<Double>?
    private var handsMoved = false
    private var lastInPosition: TimeInterval?

    public init(thresholds: DetectionThresholds = .default) { self.thresholds = thresholds }

    public mutating func process(_ frame: PoseFrame) -> DetectionEvent {
        let conf = thresholds.minConfidence
        let weak = frame.weakJoints(Self.required, minConfidence: conf)
        guard weak.isEmpty,
              let leftShoulder = frame.image(.leftShoulder, minConfidence: conf),
              let rightShoulder = frame.image(.rightShoulder, minConfidence: conf),
              let leftWrist = frame.image(.leftWrist, minConfidence: conf),
              let rightWrist = frame.image(.rightWrist, minConfidence: conf)
        else { return .notInFrame(weak.isEmpty ? Self.required : weak) }

        let scale = Geometry.distance(leftShoulder, rightShoulder)
        guard scale > 0.02 else { return .notInFrame([.leftShoulder, .rightShoulder]) }

        if let hint = positionProblem(frame, leftShoulder, rightShoulder, leftWrist, rightWrist, scale: scale) {
            if let last = lastInPosition, frame.timestamp - last > Self.outOfPositionGrace { reset() }
            return .getReady(hint)
        }
        lastInPosition = frame.timestamp

        guard let left = Geometry.angle(frame, .leftShoulder, .leftElbow, .leftWrist),
              let right = Geometry.angle(frame, .rightShoulder, .rightElbow, .rightWrist)
        else { return .notInFrame([.leftElbow, .rightElbow]) }

        let elbow = (left + right) / 2
        var phase = Phase.unknown
        if abs(left - right) <= thresholds.maxAsymmetry {
            if Self.upRange.contains(elbow) { phase = .up }
            else if Self.downRange.contains(elbow) { phase = .down }
        }

        let hands = (leftWrist + rightWrist) / 2
        if let anchor = handAnchor, Geometry.distance(hands, anchor) > Self.maxHandDrift * scale { handsMoved = true }

        switch tracker.feed(phase, frame: frame) {
        case .enteredDown:
            handAnchor = hands
            handsMoved = false
        case .completedRep:
            defer { handAnchor = nil }
            guard !handsMoved else { return .badForm([.leftWrist, .rightWrist]) }
            count += 1
            return .counted(total: count)
        case .none:
            break
        }

        if !tracker.isArmed { return .getReady(.holdStart) }
        return phase == .unknown ? .badForm([.leftElbow, .rightElbow, .leftWrist, .rightWrist]) : .tracking
    }

    private func positionProblem(_ frame: PoseFrame, _ leftShoulder: SIMD2<Double>, _ rightShoulder: SIMD2<Double>,
                                 _ leftWrist: SIMD2<Double>, _ rightWrist: SIMD2<Double>, scale: Double) -> PositionHint? {
        // Image y grows downward.
        let minDrop = Self.minHandDrop * scale
        guard leftWrist.y - leftShoulder.y > minDrop, rightWrist.y - rightShoulder.y > minDrop else { return .handsOnFloor }

        let conf = thresholds.minConfidence
        if let hips = frame.imageMidpoint(.leftHip, .rightHip, minConfidence: conf),
           let knees = frame.imageMidpoint(.leftKnee, .rightKnee, minConfidence: conf),
           knees.y - hips.y > Self.maxLegDrop * scale {
            return .getDown
        }
        return nil
    }

    private mutating func reset() {
        tracker.disarm()
        handAnchor = nil
        handsMoved = false
        lastInPosition = nil
    }
}

/// Knee angle (hip–knee–ankle), averaged over both legs. Up ≥ 100°, down 20–100°.
/// Counting starts after standing tall for a moment.
public struct SquatDetector: ExerciseDetector {
    public let exercise = Exercise.squats
    public let thresholds: DetectionThresholds
    static let upRange = 100.0...200.0
    static let downRange = 20.0..<100.0
    static let required: Set<Joint> = [.leftHip, .rightHip, .leftKnee, .rightKnee, .leftAnkle, .rightAnkle, .leftShoulder, .rightShoulder]

    public private(set) var count = 0
    private var tracker = PhaseTracker()

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
        if tracker.feed(phase, frame: frame) == .completedRep {
            count += 1
            return .counted(total: count)
        }
        if !tracker.isArmed { return .getReady(.holdStart) }
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
