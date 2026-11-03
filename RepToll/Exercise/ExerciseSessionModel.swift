import AVFoundation
import Observation
import RepTollKit

@Observable
final class ExerciseSessionModel {
    enum Status: Equatable {
        case starting, notInFrame, getReady(PositionHint), badForm, tracking, cameraDenied

        func message(for exercise: Exercise) -> String {
            switch self {
            case .starting: "Starting camera…"
            case .notInFrame: exercise == .pushups ? "Get your shoulders, arms and hands in view" : "Get your whole body in frame"
            case .getReady(.handsOnFloor): "Hands on the floor, under your shoulders"
            case .getReady(.getDown): "Get down into push-up position"
            case .getReady(.holdStart): exercise == .squats ? "Stand tall to start" : "Hold the top position to start"
            case .badForm: "Adjust your form"
            case .tracking: "Counting — keep going"
            case .cameraDenied: "Camera access is off. Enable it in Settings."
            }
        }

        var isGood: Bool { self == .tracking }
    }

    let exercise: Exercise
    let difficulty: Difficulty
    let isMuted: Bool

    private(set) var count = 0
    private(set) var status = Status.starting
    private(set) var overlay: [Joint: CGPoint] = [:]
    private(set) var problems: Set<Joint> = []
    private(set) var imageSize = CGSize(width: 720, height: 1280)

    @ObservationIgnored let pipeline = PosePipeline()
    @ObservationIgnored private var detector: any ExerciseDetector
    @ObservationIgnored private var consumer: Task<Void, Never>?
    @ObservationIgnored private let speech = AVSpeechSynthesizer()
    @ObservationIgnored private var recorder: PoseRecorder?
    // A new status must persist this long before it replaces the shown one, so messages don't flicker.
    @ObservationIgnored private var pendingStatus: Status?
    @ObservationIgnored private var pendingSince: TimeInterval = 0
    private static let statusHold: TimeInterval = 0.6
    private static let smoothing = 0.45

    var earnedSeconds: Int { EarningRules.earnedSeconds(units: count, exercise, difficulty) }

    init(exercise: Exercise, difficulty: Difficulty, isMuted: Bool, recordsPoses: Bool) {
        self.exercise = exercise
        self.difficulty = difficulty
        self.isMuted = isMuted
        self.detector = exercise.makeDetector()
        self.recorder = recordsPoses ? PoseRecorder(exercise: exercise) : nil
    }

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            status = .cameraDenied
            return
        }
        let stream = pipeline.samples()
        pipeline.start()
        consumer = Task { [weak self] in
            for await sample in stream {
                self?.handle(sample)
            }
        }
    }

    func stop() {
        consumer?.cancel()
        consumer = nil
        pipeline.stop()
        speech.stopSpeaking(at: .immediate)
        recorder?.save()
        recorder = nil
    }

    private func handle(_ sample: PoseSample) {
        updateOverlay(sample.overlay)
        // Only assign on change: @Observable notifies on every set, even with an equal value.
        if imageSize != sample.imageSize { imageSize = sample.imageSize }
        recorder?.append(sample.frame)

        let next: Status
        var joints: Set<Joint> = []
        switch detector.process(sample.frame) {
        case .notInFrame(let missing):
            next = .notInFrame
            joints = missing
        case .getReady(let hint):
            next = .getReady(hint)
        case .badForm(let bad):
            next = .badForm
            joints = bad
        case .tracking:
            next = .tracking
        case .counted(let total):
            next = .tracking
            count = total
            announce(total)
        }
        setStatus(next, problems: joints, at: sample.frame.timestamp)
    }

    private func setStatus(_ next: Status, problems joints: Set<Joint>, at time: TimeInterval) {
        guard next != status else {
            pendingStatus = nil
            if problems != joints { problems = joints }
            return
        }
        // Counting is immediate feedback; everything else waits to be stable.
        if (next == .tracking && status == .starting) || (pendingStatus == next && time - pendingSince >= Self.statusHold) {
            status = next
            if problems != joints { problems = joints }
            pendingStatus = nil
        } else if pendingStatus != next {
            pendingStatus = next
            pendingSince = time
        }
    }

    /// Exponential smoothing so the skeleton doesn't jitter; joints that disappear are dropped.
    private func updateOverlay(_ raw: [Joint: CGPoint]) {
        var smoothed: [Joint: CGPoint] = [:]
        for (joint, point) in raw {
            if let old = overlay[joint] {
                let a = Self.smoothing
                smoothed[joint] = CGPoint(x: old.x + (point.x - old.x) * a, y: old.y + (point.y - old.y) * a)
            } else {
                smoothed[joint] = point
            }
        }
        overlay = smoothed
    }

    private func announce(_ total: Int) {
        guard !isMuted else { return }
        // Plank counts seconds, so only call out every 10.
        if exercise == .plank && total % 10 != 0 { return }
        speech.stopSpeaking(at: .word)
        let utterance = AVSpeechUtterance(string: "\(total)")
        utterance.rate = 0.55
        speech.speak(utterance)
    }
}
