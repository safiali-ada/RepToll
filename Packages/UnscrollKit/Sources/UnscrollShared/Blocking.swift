#if os(iOS)
import Foundation
import DeviceActivity
import ManagedSettings
import UnscrollKit

extension ManagedSettingsStore.Name {
    // Computed: these Apple name types aren't Sendable, so they can't be stored statics under Swift 6.
    public static var unscroll: Self { Self("unscroll") }
}

extension DeviceActivityName {
    public static var budgetSession: Self { Self("unscroll.budgetSession") }
    public static var pauseTimer: Self { Self("unscroll.pauseTimer") }
}

/// Turns the shield on and off for the restricted selection.
public enum Shield {
    public static func apply(_ store: SharedStore = .shared) {
        let selection = store.selection
        let settings = ManagedSettingsStore(named: .unscroll)
        settings.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        settings.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil : .specific(selection.categoryTokens)
        settings.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    public static func clear() {
        ManagedSettingsStore(named: .unscroll).clearAllSettings()
    }
}

public enum BudgetError: Error, LocalizedError {
    case notEnoughTime, nothingRestricted, monitoring(Error)

    public var errorDescription: String? {
        switch self {
        case .notEnoughTime: "You don't have enough earned time. Go exercise!"
        case .nothingRestricted: "Pick some apps to restrict first."
        case .monitoring(let error): "Screen Time couldn't start the session: \(error.localizedDescription)"
        }
    }
}

/// Starts and ends spend sessions. Used by the app and the DeviceActivity monitor extension.
public enum BudgetController {
    static let eventPrefix = "used."

    /// Moves `minutes` from the bank into an unlock and starts usage monitoring.
    public static func startSession(minutes: Int, store: SharedStore = .shared, now: Date = .now) throws(BudgetError) {
        guard store.restrictedCount > 0 else { throw .nothingRestricted }
        if let existing = store.activeSession { endSession(existing, store: store) }
        guard let started = Ledger.startSession(minutes: minutes, bankSeconds: store.bankSeconds, now: now) else {
            throw .notEnoughTime
        }

        let selection = store.selection
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        for minute in 1...started.session.grantedMinutes {
            events[DeviceActivityEvent.Name("\(eventPrefix)\(minute)")] = DeviceActivityEvent(
                applications: selection.applicationTokens,
                categories: selection.categoryTokens,
                webDomains: selection.webDomainTokens,
                threshold: DateComponents(minute: minute),
                includesPastActivity: false
            )
        }
        let schedule = oneOffSchedule(from: now, to: started.session.expiresAt)

        let center = DeviceActivityCenter()
        center.stopMonitoring([.budgetSession])
        do {
            try center.startMonitoring(.budgetSession, during: schedule, events: events)
        } catch {
            throw .monitoring(error)
        }
        store.bankSeconds = started.bankSeconds
        store.activeSession = started.session
        Shield.clear()
    }

    /// Records usage reported by a threshold event; re-shields once the grant is used up.
    public static func recordUsage(eventName: DeviceActivityEvent.Name, store: SharedStore = .shared) {
        guard var session = store.activeSession,
              let minute = Int(eventName.rawValue.dropFirst(eventPrefix.count)) else { return }
        session.usedMinutes = max(session.usedMinutes, minute)
        store.activeSession = session
        if session.isUsedUp { endSession(session, store: store) }
    }

    /// Ends the session, refunds unused minutes, and restores the shield.
    public static func endSession(_ session: BudgetSession? = nil, store: SharedStore = .shared) {
        guard let session = session ?? store.activeSession else { return }
        store.bankSeconds = Ledger.endSession(session, bankSeconds: store.bankSeconds)
        store.activeSession = nil
        DeviceActivityCenter().stopMonitoring([.budgetSession])
        if !store.isPaused { Shield.apply(store) }
    }

    /// Brings shield state back in line with the store, e.g. on app launch or if an extension callback was missed.
    public static func reconcile(store: SharedStore = .shared, now: Date = .now) {
        if store.isPaused, let until = store.pausedUntil, until <= now {
            store.isPaused = false
            store.pausedUntil = nil
        }
        if let session = store.activeSession, session.expiresAt <= now || session.isUsedUp {
            endSession(session, store: store)
            return
        }
        if store.isPaused || store.activeSession != nil {
            Shield.clear()
        } else {
            Shield.apply(store)
        }
    }

    /// `stopMonitoring` can also deliver an interval end, so only end sessions that are actually due.
    /// Otherwise starting a new session could end it immediately.
    public static func handleSessionIntervalEnd(store: SharedStore = .shared, now: Date = .now) {
        guard let session = store.activeSession, session.expiresAt <= now.addingTimeInterval(60) else { return }
        endSession(session, store: store)
    }

    public static func handlePauseIntervalEnd(store: SharedStore = .shared, now: Date = .now) {
        guard store.isPaused, let until = store.pausedUntil, until <= now.addingTimeInterval(60) else { return }
        resume(store: store)
    }

    public static func pause(until: Date?, store: SharedStore = .shared, now: Date = .now) {
        store.isPaused = true
        store.pausedUntil = until
        Shield.clear()
        let center = DeviceActivityCenter()
        center.stopMonitoring([.pauseTimer])
        // A timed pause ends in the monitor extension's intervalDidEnd, even if the app never opens.
        if let until {
            try? center.startMonitoring(.pauseTimer, during: oneOffSchedule(from: now, to: until))
        }
    }

    public static func resume(store: SharedStore = .shared) {
        store.isPaused = false
        store.pausedUntil = nil
        DeviceActivityCenter().stopMonitoring([.pauseTimer])
        if store.activeSession == nil { Shield.apply(store) }
    }

    static func oneOffSchedule(from start: Date, to end: Date) -> DeviceActivitySchedule {
        let parts: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let calendar = Calendar.current
        let minimumEnd = start.addingTimeInterval(TimeInterval(Ledger.minimumIntervalMinutes * 60))
        return DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(parts, from: start),
            intervalEnd: calendar.dateComponents(parts, from: max(end, minimumEnd)),
            repeats: false
        )
    }
}
#endif
