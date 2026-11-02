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

/// Counts push-ups by how far the shoulders travel toward the planted hands in the camera image.
///
/// Tuned on a real session with the phone on the floor facing the user. There, the 3D elbow
/// angle barely moved (about 150° at the top, 125° at the bottom) and arms often vanished at the
/// bottom, while the shoulder-to-hand gap shrank from ~1.7 to ~0.6 shoulder-widths every rep.
///
/// - Arming: shoulders and hands steady in a push-up position for `armDuration`; the
///   shoulder-to-hand gap measured there is the reference "top" (followed slowly afterwards).
/// - Down: the gap shrinks to `downRatio` of the top. If the body drops out of view right
///   after descending (face too close to the camera), that also counts as down.
/// - Rep: back up to `upRatio`, with the hands still where they started.
/// - Standing or sitting (knees far below hips) disarms after a grace period.
public struct PushupDetector: ExerciseDetector {
    public let exercise = Exercise.pushups
    public let thresholds: DetectionThresholds
    static let downRatio = 0.75
    static let upRatio = 0.9
    static let armDuration: TimeInterval = 1.0
    /// While arming, shoulders and hands may wobble at most this many shoulder-widths.
    static let maxWobble = 0.25
    /// Wrists must sit this many shoulder-widths below the shoulders to start.
    static let minHandDrop = 0.5
    /// Knees more than this many shoulder-widths below the hips means standing/sitting upright.
    static let maxLegDrop = 0.9
    /// Hands may move at most this many shoulder-widths during a rep.
    static let maxHandDrift = 0.5
    /// A body that disappears within this time of descending is treated as at the bottom.
    static let vanishWindow: TimeInterval = 0.6
    /// Out of view or out of position longer than this requires arming again.
    static let lostTimeout: TimeInterval = 3.0
    static let outOfPositionGrace: TimeInterval = 1.5
    static let shoulders: Set<Joint> = [.leftShoulder, .rightShoulder]
    static let wrists: Set<Joint> = [.leftWrist, .rightWrist]

    private struct ArmSample { var time: TimeInterval; var shoulderY: Double; var hands: SIMD2<Double>; var gap: Double }

    public private(set) var count = 0
    private var isArmed = false
    private var armWindow: [ArmSample] = []
    private var topGap = 0.0
    /// Where the hands are planted (smoothed), so reps still track when wrists drop out at the bottom.
    private var hands: SIMD2<Double>?
    private var isDown = false
    private var handsMoved = false
    private var lastSeen: TimeInterval?
    private var lastRatio: Double?
    private var outOfPositionSince: TimeInterval?

    public init(thresholds: DetectionThresholds = .default) { self.thresholds = thresholds }

    public mutating func process(_ frame: PoseFrame) -> DetectionEvent {
        let conf = thresholds.minConfidence
        let t = frame.timestamp
        guard let leftShoulder = frame.image(.leftShoulder, minConfidence: conf),
              let rightShoulder = frame.image(.rightShoulder, minConfidence: conf)
        else { return bodyLost(at: t) }

        let scale = Geometry.distance(leftShoulder, rightShoulder)
        guard scale > 0.02 else { return bodyLost(at: t) }
        let shoulderY = (leftShoulder.y + rightShoulder.y) / 2
        let wrists = frame.imageMidpoint(.leftWrist, .rightWrist, minConfidence: conf)

        if legsLookUpright(frame, scale: scale) {
            outOfPositionSince = outOfPositionSince ?? t
            if t - (outOfPositionSince ?? t) > Self.outOfPositionGrace { reset() }
            armWindow.removeAll()
            return .getReady(.getDown)
        }
        outOfPositionSince = nil

        guard isArmed else { return arm(frame, shoulderY: shoulderY, wrists: wrists, scale: scale) }

        if let wrists {
            if !isDown { hands = hands.map { $0 * 0.8 + wrists * 0.2 } ?? wrists }
            if let planted = hands, Geometry.distance(wrists, planted) > Self.maxHandDrift * scale { handsMoved = true }
        }
        guard let planted = hands, topGap > 0 else { return .notInFrame(Self.wrists) }

        let gap = planted.y - shoulderY
        let ratio = gap / topGap
        lastSeen = t
        lastRatio = ratio

        if !isDown && ratio <= Self.downRatio {
            isDown = true
            handsMoved = false
        } else if isDown && ratio >= Self.upRatio {
            isDown = false
            if handsMoved { return .badForm(Self.wrists) }
            count += 1
            return .counted(total: count)
        }
        if !isDown && ratio >= Self.upRatio { topGap = topGap * 0.9 + gap * 0.1 }
        return .tracking
    }

    private mutating func arm(_ frame: PoseFrame, shoulderY: Double, wrists: SIMD2<Double>?, scale: Double) -> DetectionEvent {
        guard let wrists else {
            armWindow.removeAll()
            return .notInFrame(Self.wrists)
        }
        let gap = wrists.y - shoulderY
        guard gap > Self.minHandDrop * scale else {
            armWindow.removeAll()
            return .getReady(.handsOnFloor)
        }

        let t = frame.timestamp
        armWindow.append(ArmSample(time: t, shoulderY: shoulderY, hands: wrists, gap: gap))
        armWindow.removeAll { t - $0.time > Self.armDuration }
        let shoulderYs = armWindow.map(\.shoulderY), handYs = armWindow.map(\.hands.y)
        let wobble = max((shoulderYs.max() ?? 0) - (shoulderYs.min() ?? 0), (handYs.max() ?? 0) - (handYs.min() ?? 0))
        if wobble > Self.maxWobble * scale {
            armWindow = [armWindow[armWindow.count - 1]]
        } else if let first = armWindow.first, t - first.time >= Self.armDuration * 0.95 {
            let gaps = armWindow.map(\.gap).sorted()
            topGap = gaps[gaps.count / 2]
            hands = wrists
            isArmed = true
            isDown = false
            lastSeen = t
            lastRatio = 1
            armWindow.removeAll()
            return .tracking
        }
        return .getReady(.holdStart)
    }

    /// No shoulders this frame. Right after descending this is the bottom of a deep rep.
    private mutating func bodyLost(at t: TimeInterval) -> DetectionEvent {
        armWindow.removeAll()
        if isArmed, let seen = lastSeen {
            if !isDown, let ratio = lastRatio, ratio < Self.upRatio, t - seen <= Self.vanishWindow {
                isDown = true
                handsMoved = false
            } else if t - seen > Self.lostTimeout {
                reset()
            }
        }
        return .notInFrame(Self.shoulders)
    }

    private func legsLookUpright(_ frame: PoseFrame, scale: Double) -> Bool {
        let conf = thresholds.minConfidence
        guard let hips = frame.imageMidpoint(.leftHip, .rightHip, minConfidence: conf),
              let knees = frame.imageMidpoint(.leftKnee, .rightKnee, minConfidence: conf) else { return false }
        return knees.y - hips.y > Self.maxLegDrop * scale
    }

    private mutating func reset() {
        isArmed = false
        armWindow.removeAll()
        hands = nil
        isDown = false
        handsMoved = false
        lastSeen = nil
        lastRatio = nil
        outOfPositionSince = nil
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
