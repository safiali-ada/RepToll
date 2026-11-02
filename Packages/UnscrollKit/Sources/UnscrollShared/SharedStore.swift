#if os(iOS)
import Foundation
import FamilyControls
import UnscrollKit

/// Small state shared between the app and its Screen Time extensions through the App Group.
/// `UserDefaults` is thread-safe, so the store can be used from any context.
public final class SharedStore: @unchecked Sendable {
    public static let appGroupID = "group.com.syedsafiali.Unscroll"
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

    public var restrictedCount: Int {
        let s = selection
        return s.applicationTokens.count + s.categoryTokens.count + s.webDomainTokens.count
    }

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
