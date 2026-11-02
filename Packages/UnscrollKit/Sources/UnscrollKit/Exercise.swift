import Foundation

public enum Exercise: String, CaseIterable, Sendable, Codable, Identifiable {
    case pushups, squats, plank

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .pushups: "Push-ups"
        case .squats: "Squats"
        case .plank: "Plank"
        }
    }

    /// What one counted unit is.
    public var unitName: String { self == .plank ? "second" : "rep" }

    public var symbolName: String {
        switch self {
        case .pushups: "figure.strengthtraining.functional"
        case .squats: "figure.cross.training"
        case .plank: "figure.core.training"
        }
    }

    public var setupTip: String {
        switch self {
        case .pushups: "Phone on the floor, facing you, about 1.5 m away. Keep your shoulders, arms and hips in view."
        case .squats: "Stand the phone up 2–3 m away so your whole body is in frame, hips to ankles."
        case .plank: "Phone on the floor facing you. Hold a forearm or straight-arm plank with your body straight."
        }
    }

    public func makeDetector(thresholds: DetectionThresholds = .default) -> any ExerciseDetector {
        switch self {
        case .pushups: PushupDetector(thresholds: thresholds)
        case .squats: SquatDetector(thresholds: thresholds)
        case .plank: PlankDetector(thresholds: thresholds)
        }
    }
}

public enum Difficulty: String, CaseIterable, Sendable, Codable, Identifiable {
    case veryEasy, easy, medium, hard, veryHard

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .veryEasy: "Very easy"
        case .easy: "Easy"
        case .medium: "Medium"
        case .hard: "Hard"
        case .veryHard: "Very hard"
        }
    }
}

/// Minutes of screen time earned per counted unit (rep, or second for plank).
/// Values match the table decoded from Pushscroll v1.72 (`Ca/c.b`).
public enum EarningRules {
    public static func minutesPerUnit(_ exercise: Exercise, _ difficulty: Difficulty) -> Double {
        switch (exercise, difficulty) {
        case (.pushups, .veryEasy): 10
        case (.pushups, .easy): 5
        case (.pushups, .medium): 2
        case (.pushups, .hard): 1
        case (.pushups, .veryHard): 1.0 / 3
        case (_, .veryEasy): 5
        case (_, .easy): 2
        case (_, .medium): 1
        case (_, .hard): 1.0 / 3
        case (_, .veryHard): 0.2
        }
    }

    public static func earnedSeconds(units: Int, _ exercise: Exercise, _ difficulty: Difficulty) -> Int {
        Int((Double(units) * minutesPerUnit(exercise, difficulty) * 60).rounded())
    }

    /// e.g. "2 min per rep" or "20 s per rep".
    public static func rateLabel(_ exercise: Exercise, _ difficulty: Difficulty) -> String {
        let minutes = minutesPerUnit(exercise, difficulty)
        if minutes >= 1 {
            return "\(Int(minutes.rounded())) min per \(exercise.unitName)"
        }
        return "\(Int((minutes * 60).rounded())) s per \(exercise.unitName)"
    }
}
