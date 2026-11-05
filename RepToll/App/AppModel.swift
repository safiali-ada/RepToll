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

    #if DEBUG
    @ObservationIgnored let store = DemoMode.isOn ? DemoMode.store : SharedStore.shared
    #else
    @ObservationIgnored let store = SharedStore.shared
    #endif

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

    #if DEBUG
    var hasOnboarded: Bool = DemoMode.isOn || UserDefaults.standard.bool(forKey: "hasOnboarded") {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }
    #else
    var hasOnboarded: Bool = UserDefaults.standard.bool(forKey: "hasOnboarded") {
        didSet { UserDefaults.standard.set(hasOnboarded, forKey: "hasOnboarded") }
    }
    #endif

    var isMuted: Bool = UserDefaults.standard.bool(forKey: "isMuted") {
        didSet { UserDefaults.standard.set(isMuted, forKey: "isMuted") }
    }

    /// Saves pose data from workouts for tuning the detectors.
    var recordsPoses: Bool = UserDefaults.standard.bool(forKey: "recordsPoses") {
        didSet { UserDefaults.standard.set(recordsPoses, forKey: "recordsPoses") }
    }

    /// Pro: hides the pause menu so the only way into a locked app is earned time.
    var strictMode: Bool = UserDefaults.standard.bool(forKey: "strictMode") {
        didSet { UserDefaults.standard.set(strictMode, forKey: "strictMode") }
    }

    var isStrict: Bool { strictMode && Store.shared.isPro }

    /// The paywall is offered once at the end of onboarding, then only at limits or on request.
    private var hasSeenIntroPaywall: Bool = UserDefaults.standard.bool(forKey: "hasSeenIntroPaywall") {
        didSet { UserDefaults.standard.set(hasSeenIntroPaywall, forKey: "hasSeenIntroPaywall") }
    }

    var bankMinutes: Int { bankSeconds / 60 }
    var spendableMinutes: Int { Ledger.spendableMinutes(bankSeconds: bankSeconds) }

    /// A selection over the free limit, applied in full if the user subscribes.
    @ObservationIgnored private var pendingSelection: FamilyActivitySelection?

    private init() {
        difficulty = store.difficulty
        refresh()
        Store.shared.onProActivated = { [weak self] in self?.applyPendingSelection() }
        #if DEBUG
        switch DemoMode.screen {
        case .unlock: sheet = .unlock
        case .paywall: sheet = .paywall(reason: nil)
        default: break
        }
        #endif
    }

    /// Re-syncs with the shared store (extensions may have changed it) and fixes shield drift.
    func refresh() {
        #if DEBUG
        let reconciles = hasOnboarded && !DemoMode.isOn
        #else
        let reconciles = hasOnboarded
        #endif
        if reconciles { BudgetController.reconcile(store: store) }
        bankSeconds = store.bankSeconds
        session = store.activeSession
        isPaused = store.isPaused
        pausedUntil = store.pausedUntil
        selection = store.selection
        restrictedCount = store.restrictedCount
        #if DEBUG
        if DemoMode.isOn { restrictedCount = DemoMode.restrictedCount }
        #endif
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

    /// Refreshes the subscription first so a just-made purchase is never missed.
    func saveSelectionCheckingPro(_ newSelection: FamilyActivitySelection) async {
        await Store.shared.refresh()
        saveSelection(newSelection)
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
        // A paywall the onboarding selection already triggered counts as the intro one.
        if !Store.shared.isPro && !hasSeenIntroPaywall && sheet == nil {
            sheet = .paywall(reason: nil)
        }
        hasSeenIntroPaywall = true
    }

    /// Settings ▸ Reset all data. Workout history (SwiftData) is deleted by the caller.
    func resetAllData() {
        BudgetController.resetAll(store: store)
        PoseRecorder.deleteAll()
        pendingSelection = nil
        strictMode = false
        isMuted = false
        recordsPoses = false
        difficulty = .medium
        hasOnboarded = false
        refresh()
    }

    /// The user tapped the shield's notification.
    func handleShieldTap() {
        activeExercise = nil
        sheet = bankMinutes > 0 ? .unlock : .chooseExercise
    }
}
