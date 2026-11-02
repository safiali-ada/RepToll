import FamilyControls
import Foundation
import Observation
import RepTollKit
import RepTollShared

/// App-wide state. Mirrors the App Group store, which the extensions also write to.
@Observable
final class AppModel {
    static let shared = AppModel()

    enum Sheet: Identifiable, Hashable {
        case unlock, chooseExercise
        case paywall(reason: String?)
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

    /// Saves pose data from workouts for tuning the detectors.
    var recordsPoses: Bool = UserDefaults.standard.bool(forKey: "recordsPoses") {
        didSet { UserDefaults.standard.set(recordsPoses, forKey: "recordsPoses") }
    }

    var bankMinutes: Int { bankSeconds / 60 }
    var spendableMinutes: Int { Ledger.spendableMinutes(bankSeconds: bankSeconds) }

    /// A selection over the free limit, applied in full if the user subscribes.
    @ObservationIgnored private var pendingSelection: FamilyActivitySelection?

    private init() {
        difficulty = store.difficulty
        refresh()
        Store.shared.onProActivated = { [weak self] in self?.applyPendingSelection() }
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

    /// Saves the restricted apps. On the free plan, extra items wait behind the paywall:
    /// the first one is locked now, and the full selection applies if the user subscribes.
    func saveSelection(_ newSelection: FamilyActivitySelection) {
        let count = SharedStore.count(newSelection)
        if Store.shared.isPro || Plan.fitsFreePlan(restrictedCount: count) {
            store.selection = newSelection
        } else {
            pendingSelection = newSelection
            store.selection = SharedStore.trimmedToFreePlan(newSelection)
            sheet = .paywall(reason: "You picked \(count) apps and categories. The free plan locks 1 — go Pro to lock them all.")
        }
        refresh()
    }

    private func applyPendingSelection() {
        guard let pending = pendingSelection else { return }
        pendingSelection = nil
        saveSelection(pending)
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
