import FamilyControls
import Foundation
import Observation
import UnscrollKit
import UnscrollShared

/// App-wide state. Mirrors the App Group store, which the extensions also write to.
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Sheet: Identifiable, Equatable {
        case unlock, chooseExercise
        var id: Self { self }
    }

    @ObservationIgnored let store = SharedStore.shared

    private(set) var bankSeconds = 0
    private(set) var session: BudgetSession?
    private(set) var isPaused = false
    private(set) var pausedUntil: Date?
    private(set) var restrictedCount = 0
    var selection = FamilyActivitySelection()
    var sheet: Sheet?
    var activeExercise: Exercise?
    var errorMessage: String?

    var difficulty: Difficulty = .medium {
        didSet { store.difficulty = difficulty }
    }

    var hasOnboarded: Bool = UserDefaults.standard.bool(forKey: "hasOnboarded") {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }

    var isMuted: Bool = UserDefaults.standard.bool(forKey: "isMuted") {
        didSet { UserDefaults.standard.set(isMuted, forKey: "isMuted") }
    }

    var bankMinutes: Int { bankSeconds / 60 }
    var spendableMinutes: Int { Ledger.spendableMinutes(bankSeconds: bankSeconds) }

    private init() {
        difficulty = store.difficulty
        refresh()
    }

    /// Re-syncs with the shared store (extensions may have changed it) and fixes shield drift.
    func refresh() {
        if hasOnboarded { BudgetController.reconcile(store: store) }
        bankSeconds = store.bankSeconds
        session = store.activeSession
        isPaused = store.isPaused
        pausedUntil = store.pausedUntil
        selection = store.selection
        restrictedCount = store.restrictedCount
    }

    func saveSelection(_ newSelection: FamilyActivitySelection) {
        store.selection = newSelection
        refresh()
    }

    func earn(seconds: Int) {
        guard seconds > 0 else { return }
        store.bankSeconds += seconds
        store.lifetimeEarnedSeconds += seconds
        refresh()
    }

    func unlock(minutes: Int) -> Bool {
        do {
            try BudgetController.startSession(minutes: minutes, store: store)
            refresh()
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func lockNow() {
        BudgetController.endSession(store: store)
        refresh()
    }

    func pause(for duration: TimeInterval?) {
        BudgetController.pause(until: duration.map { Date.now.addingTimeInterval($0) }, store: store)
        refresh()
    }

    func resume() {
        BudgetController.resume(store: store)
        refresh()
    }

    func finishOnboarding() {
        hasOnboarded = true
        refresh()
    }

    /// The user tapped the shield's notification.
    func handleShieldTap() {
        activeExercise = nil
        sheet = bankMinutes > 0 ? .unlock : .chooseExercise
    }
}
