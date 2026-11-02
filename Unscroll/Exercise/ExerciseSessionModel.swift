import AVFoundation
import Observation
import UnscrollKit

@Observable
final class ExerciseSessionModel {
    enum Status: Equatable {
        case starting, notInFrame, badForm, tracking, cameraDenied

        var message: String {
            switch self {
            case .starting: "Starting camera…"
            case .notInFrame: "Get your whole body in frame"
            case .badForm: "Adjust your form"
            case .tracking: "Looking good — keep going"
            case .cameraDenied: "Camera access is off. Enable it in Settings."
            }
        }
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

    var earnedSeconds: Int { EarningRules.earnedSeconds(units: count, exercise, difficulty) }

    init(exercise: Exercise, difficulty: Difficulty, isMuted: Bool) {
        self.exercise = exercise
        self.difficulty = difficulty
        self.isMuted = isMuted
        self.detector = exercise.makeDetector()
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
    }

    private func handle(_ sample: PoseSample) {
        overlay = sample.overlay
        imageSize = sample.imageSize

        switch detector.process(sample.frame) {
        case .notInFrame(let joints):
            status = .notInFrame
            problems = joints
        case .badForm(let joints):
            status = .badForm
            problems = joints
        case .tracking:
            status = .tracking
            problems = []
        case .counted(let total):
            status = .tracking
            problems = []
            count = total
            announce(total)
        }
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
