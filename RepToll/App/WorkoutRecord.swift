import Foundation
import SwiftData
import RepTollKit

@Model
final class WorkoutRecord {
    var date: Date
    var exerciseRaw: String
    var difficultyRaw: String
    /// Reps, or held seconds for plank.
    var units: Int
    var earnedSeconds: Int

    init(date: Date = .now, exercise: Exercise, difficulty: Difficulty, units: Int, earnedSeconds: Int) {
        self.date = date
        self.exerciseRaw = exercise.rawValue
        self.difficultyRaw = difficulty.rawValue
        self.units = units
        self.earnedSeconds = earnedSeconds
    }

    var exercise: Exercise { Exercise(rawValue: exerciseRaw) ?? .pushups }
}
