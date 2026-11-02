import Foundation

/// A spend session: screen time moved from the bank into a temporary unlock.
public struct BudgetSession: Codable, Sendable, Equatable {
    public var startedAt: Date
    public var grantedMinutes: Int
    public var usedMinutes: Int
    /// When the monitoring interval ends even if the time isn't used up (break window).
    public var expiresAt: Date

    public init(startedAt: Date, grantedMinutes: Int, usedMinutes: Int = 0, expiresAt: Date) {
        self.startedAt = startedAt
        self.grantedMinutes = grantedMinutes
        self.usedMinutes = usedMinutes
        self.expiresAt = expiresAt
    }

    public var remainingMinutes: Int { max(0, grantedMinutes - usedMinutes) }
    public var isUsedUp: Bool { usedMinutes >= grantedMinutes }
}

/// Bank arithmetic. All values in seconds so fractional earnings (e.g. 20 s per rep) aren't lost.
public enum Ledger {
    public static let maxSessionMinutes = 60
    /// After the granted time, how long a session waits for the user to come back before refunding.
    public static let breakWindowMinutes = 10
    /// DeviceActivity rejects schedules shorter than 15 minutes.
    public static let minimumIntervalMinutes = 15

    public static func spendableMinutes(bankSeconds: Int) -> Int {
        min(maxSessionMinutes, bankSeconds / 60)
    }

    /// Returns the session and the new bank, or nil if the bank can't cover it.
    public static func startSession(minutes: Int, bankSeconds: Int, now: Date) -> (session: BudgetSession, bankSeconds: Int)? {
        guard minutes > 0, minutes <= spendableMinutes(bankSeconds: bankSeconds) else { return nil }
        let interval = max(minimumIntervalMinutes, minutes + breakWindowMinutes)
        let session = BudgetSession(startedAt: now, grantedMinutes: minutes,
                                    expiresAt: now.addingTimeInterval(TimeInterval(interval * 60)))
        return (session, bankSeconds - minutes * 60)
    }

    /// Ends a session and returns the bank with unused minutes refunded.
    public static func endSession(_ session: BudgetSession, bankSeconds: Int) -> Int {
        bankSeconds + session.remainingMinutes * 60
    }
}

public enum Streaks {
    /// Current streak counts back from today (or from yesterday if nothing logged yet today).
    public static func current(activeDays: Set<Date>, today: Date, calendar: Calendar = .current) -> Int {
        let days = Set(activeDays.map { calendar.startOfDay(for: $0) })
        var day = calendar.startOfDay(for: today)
        if !days.contains(day) {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day) else { return 0 }
            day = yesterday
        }
        var streak = 0
        while days.contains(day) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    public static func longest(activeDays: Set<Date>, calendar: Calendar = .current) -> Int {
        let days = Set(activeDays.map { calendar.startOfDay(for: $0) }).sorted()
        var best = 0, run = 0
        var previous: Date?
        for day in days {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            best = max(best, run)
            previous = day
        }
        return best
    }
}
