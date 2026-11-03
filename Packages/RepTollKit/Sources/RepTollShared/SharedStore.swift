#if os(iOS)
import Foundation
import FamilyControls
import RepTollKit

/// Small state shared between the app and its Screen Time extensions through the App Group.
/// `UserDefaults` is thread-safe, so the store can be used from any context.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.com.syedsafiali.RepToll"
    public static let shared = SharedStore()

    private let defaults: UserDefaults

    public init(defaults: UserDefaults? = nil) {
        self.defaults = defaults ?? UserDefaults(suiteName: Self.appGroupID) ?? .standard
    }

    private enum Key {
        static let bankSeconds = "bankSeconds"
        static let session = "activeSession"
        static let selection = "restrictedSelection"
        static let pausedUntil = "pausedUntil"
        static let isPaused = "isPaused"
        static let difficulty = "difficulty"
        static let lifetimeEarnedSeconds = "lifetimeEarnedSeconds"
        static let isPro = "isPro"
        /// Everything except `isPro`, which StoreKit re-derives anyway.
        static let userData = [bankSeconds, session, selection, pausedUntil, isPaused, difficulty, lifetimeEarnedSeconds]
    }

    /// Deletes the user's bank, selection, pause and settings. Callers also clear the shield.
    public func removeUserData() {
        Key.userData.forEach(defaults.removeObject(forKey:))
    }

    /// Cached RepToll Pro status; the app re-verifies it with StoreKit on every launch.
    public var isPro: Bool {
        get { defaults.bool(forKey: Key.isPro) }
        set { defaults.set(newValue, forKey: Key.isPro) }
    }

    /// Keeps the first restricted item so a selection fits the free plan.
    public static func trimmedToFreePlan(_ selection: FamilyActivitySelection) -> FamilyActivitySelection {
        var trimmed = FamilyActivitySelection()
        if let app = selection.applicationTokens.first {
            trimmed.applicationTokens = [app]
        } else if let category = selection.categoryTokens.first {
            trimmed.categoryTokens = [category]
        } else if let domain = selection.webDomainTokens.first {
            trimmed.webDomainTokens = [domain]
        }
        return trimmed
    }

    public static func count(_ selection: FamilyActivitySelection) -> Int {
        selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
    }

    public var bankSeconds: Int {
        get { defaults.integer(forKey: Key.bankSeconds) }
        set { defaults.set(max(0, newValue), forKey: Key.bankSeconds) }
    }

    public var lifetimeEarnedSeconds: Int {
        get { defaults.integer(forKey: Key.lifetimeEarnedSeconds) }
        set { defaults.set(newValue, forKey: Key.lifetimeEarnedSeconds) }
    }

    public var activeSession: BudgetSession? {
        get { decode(BudgetSession.self, Key.session) }
        set { encode(newValue, Key.session) }
    }

    public var selection: FamilyActivitySelection {
        get { decode(FamilyActivitySelection.self, Key.selection) ?? FamilyActivitySelection() }
        set { encode(newValue, Key.selection) }
    }

    public var restrictedCount: Int { Self.count(selection) }

    public var isPaused: Bool {
        get { defaults.bool(forKey: Key.isPaused) }
        set { defaults.set(newValue, forKey: Key.isPaused) }
    }

    /// Optional end of a pause; nil means paused until resumed manually.
    public var pausedUntil: Date? {
        get { defaults.object(forKey: Key.pausedUntil) as? Date }
        set { defaults.set(newValue, forKey: Key.pausedUntil) }
    }

    public var difficulty: Difficulty {
        get { defaults.string(forKey: Key.difficulty).flatMap(Difficulty.init(rawValue:)) ?? .medium }
        set { defaults.set(newValue.rawValue, forKey: Key.difficulty) }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private func encode<T: Encodable>(_ value: T?, _ key: String) {
        guard let value, let data = try? JSONEncoder().encode(value) else {
            defaults.removeObject(forKey: key)
            return
        }
        defaults.set(data, forKey: key)
    }
}
#endif
