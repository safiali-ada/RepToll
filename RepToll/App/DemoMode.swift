#if DEBUG
import Foundation
import SwiftData
import SwiftUI
import RepTollKit
import RepTollShared

/// Debug-only demo for App Store screenshots in the Simulator: a set-up user with history.
/// Launch with `-RepTollDemo YES`, optionally `-RepTollDemoScreen home|unlock|stats|paywall`.
/// Nothing is written to the real stores: the bank lives in its own defaults suite and
/// workouts in an in-memory SwiftData container.
enum DemoMode {
    enum Screen: String { case home, unlock, stats, paywall }

    // Launch arguments land in the arguments domain of `UserDefaults.standard`.
    static let isOn = UserDefaults.standard.bool(forKey: "RepTollDemo")
    static let screen = UserDefaults.standard.string(forKey: "RepTollDemoScreen").flatMap(Screen.init(rawValue:))

    /// The free plan's one app; FamilyControls tokens can't be faked, so the count is.
    static let restrictedCount = Plan.freeRestrictedLimit

    static let store: SharedStore = {
        let defaults = UserDefaults(suiteName: "RepTollDemo")!
        defaults.removePersistentDomain(forName: "RepTollDemo")
        let store = SharedStore(defaults: defaults)
        store.bankSeconds = 42 * 60
        store.difficulty = .medium
        return store
    }()

    static let container: ModelContainer = {
        let container = try! ModelContainer(for: WorkoutRecord.self,
                                            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        seed(container.mainContext)
        return container
    }()

    /// A 12-day streak, plus an older 19-day run so "longest streak" isn't the same number.
    private static func seed(_ context: ModelContext) {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        // (exercise, units, hour, minute) per day, cycled; plank units are seconds.
        let days: [[(Exercise, Int, Int, Int)]] = [
            [(.pushups, 18, 7, 40), (.squats, 25, 19, 5)],
            [(.pushups, 22, 8, 10), (.plank, 45, 13, 20), (.pushups, 15, 21, 30)],
            [(.squats, 30, 7, 55), (.pushups, 20, 18, 40)],
            [(.pushups, 12, 9, 15), (.plank, 60, 12, 50), (.squats, 20, 20, 10)],
            [(.pushups, 25, 7, 30), (.squats, 15, 17, 45)],
            [(.plank, 50, 8, 5), (.pushups, 17, 14, 25), (.squats, 28, 21, 0)],
            [(.pushups, 20, 7, 20), (.squats, 22, 18, 15)],
        ]
        func insert(dayOffset: Int, sets: [(Exercise, Int, Int, Int)]) {
            guard let day = calendar.date(byAdding: .day, value: -dayOffset, to: today) else { return }
            for (exercise, units, hour, minute) in sets {
                var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
                // Today's sets must already have happened.
                if date > .now { date = max(day, Date.now.addingTimeInterval(-Double(units) * 60)) }
                context.insert(WorkoutRecord(date: date, exercise: exercise, difficulty: .medium, units: units,
                                             earnedSeconds: EarningRules.earnedSeconds(units: units, exercise, .medium)))
            }
        }
        for offset in 0..<12 { insert(dayOffset: offset, sets: days[offset % days.count]) }
        for offset in 15..<34 { insert(dayOffset: offset, sets: days[offset % days.count]) }
        try? context.save()
    }
}

extension View {
    /// Swaps in the seeded in-memory workouts when demo mode is on.
    @ViewBuilder func demoModelContainer() -> some View {
        if DemoMode.isOn { modelContainer(DemoMode.container) } else { self }
    }
}
#endif
