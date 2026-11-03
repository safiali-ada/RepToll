import Foundation
import Observation
import RepTollShared
import StoreKit
import UserNotifications
import os

private let log = Logger(subsystem: "com.syedsafiali.RepToll", category: "Store")

/// The ways to own RepToll Pro, in the order the paywall lists them.
enum ProPlan: String, CaseIterable, Identifiable {
    case yearly, quarterly, lifetime

    var id: Self { self }

    /// Must match App Store Connect and `RepToll.storekit`.
    var productID: String { "com.syedsafiali.RepToll.pro.\(rawValue)" }

    var title: String {
        switch self {
        case .yearly: "Yearly"
        case .quarterly: "3 months"
        case .lifetime: "Lifetime"
        }
    }

    init?(productID: String) {
        guard let plan = Self.allCases.first(where: { $0.productID == productID }) else { return nil }
        self = plan
    }
}

/// RepToll Pro state, backed by StoreKit 2. No server: entitlements are verified on device.
/// Pro is either an active subscription (yearly or 3 months) or the lifetime purchase.
@Observable
final class Store {
    static let shared = Store()

    static let allProductIDs = ProPlan.allCases.map(\.productID)
    /// Apple's standard EULA; App Review accepts it as the Terms of Use link.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Public policy page in safiali-ada/PrivacyPolicy (source: docs/PRIVACY.md).
    static let privacyURL = URL(string: "https://github.com/safiali-ada/PrivacyPolicy/blob/main/README_RepToll.md")!

    enum RestoreOutcome { case restored, nothingFound, failed }

    private static let trialReminderID = "reptoll.trialEnding"

    private(set) var isPro: Bool
    private(set) var activePlan: ProPlan?
    private(set) var renewalDate: Date?
    /// Paywall products, sorted like `ProPlan.allCases`. Empty until loaded.
    private(set) var products: [Product] = []
    private(set) var productsFailedToLoad = false
    private(set) var isEligibleForTrial = false
    /// Called when Pro becomes active, e.g. to apply a selection that was over the free limit.
    @ObservationIgnored var onProActivated: (() -> Void)?
    @ObservationIgnored private var updates: Task<Void, Never>?

    private init() {
        isPro = SharedStore.shared.isPro
        // Renewals, refunds and purchases made on other devices arrive here.
        updates = Task { [weak self] in
            for await result in Transaction.updates {
                await self?.handle(result)
            }
        }
    }

    func product(for plan: ProPlan) -> Product? {
        products.first { $0.id == plan.productID }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: Self.allProductIDs)
            products = ProPlan.allCases.compactMap { plan in loaded.first { $0.id == plan.productID } }
            productsFailedToLoad = products.isEmpty
        } catch {
            log.error("Couldn't load products: \(error.localizedDescription, privacy: .public)")
            productsFailedToLoad = true
        }
        isEligibleForTrial = await product(for: .yearly)?.subscription?.isEligibleForIntroOffer ?? false
    }

    /// Re-derives Pro status. Uses the subscription status API (the same source the paywall uses
    /// for "your current plan") and falls back to current entitlements, so the two can't disagree.
    func refresh() async {
        if products.isEmpty { await loadProducts() }

        var plan: ProPlan?
        var renewal: Date?
        var trialEnd: Date?

        // Statuses cover the whole subscription group, so any subscription product works.
        if let statuses = try? await product(for: .yearly)?.subscription?.status {
            for status in statuses {
                log.info("Subscription status: \(String(describing: status.state), privacy: .public)")
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    guard case .verified(let transaction) = status.transaction else { continue }
                    plan = ProPlan(productID: transaction.productID) ?? .yearly
                    renewal = transaction.expirationDate
                    if transaction.offer?.type == .introductory { trialEnd = transaction.expirationDate }
                default:
                    break
                }
            }
        }

        for await result in Transaction.currentEntitlements {
            let transaction: Transaction
            switch result {
            case .verified(let verified):
                transaction = verified
            case .unverified(let unverified, let error):
                log.error("Unverified transaction \(unverified.productID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                continue
            }
            guard let owned = ProPlan(productID: transaction.productID), transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }
            // Lifetime wins over a subscription the user forgot to cancel.
            if owned == .lifetime {
                plan = .lifetime
                renewal = nil
                trialEnd = nil
            } else if plan == nil {
                plan = owned
                renewal = transaction.expirationDate
            }
        }

        log.info("RepToll Pro plan: \(plan?.rawValue ?? "none", privacy: .public)")
        setPlan(plan, renewal: renewal)
        await updateTrialReminder(endingAt: trialEnd)
    }

    /// Buys a plan. Returns whether Pro is now active; cancelling or Ask to Buy returns false.
    func purchase(_ product: Product) async throws -> Bool {
        switch try await product.purchase() {
        case .success(let verification):
            await handle(verification)
            return isPro
        case .pending, .userCancelled:
            return false
        @unknown default:
            return false
        }
    }

    func handle(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
        await refresh()
    }

    func restore() async -> RestoreOutcome {
        do {
            try await AppStore.sync()
        } catch {
            log.error("Restore failed: \(error.localizedDescription, privacy: .public)")
            await refresh()
            return isPro ? .restored : .failed
        }
        await refresh()
        return isPro ? .restored : .nothingFound
    }

    private func setPlan(_ plan: ProPlan?, renewal: Date?) {
        let active = plan != nil
        let activated = active && !isPro
        isPro = active
        activePlan = plan
        renewalDate = renewal
        SharedStore.shared.isPro = active
        if activated { onProActivated?() }
    }

    /// Reminds the user two days before a free trial turns into a charge.
    private func updateTrialReminder(endingAt end: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.trialReminderID])
        guard let end else { return }
        let fireDate = end.addingTimeInterval(-2 * 86_400)
        guard fireDate > .now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Your RepToll trial ends soon"
        let price = product(for: .yearly)?.displayPrice
        content.body = "It ends on \(end.formatted(date: .abbreviated, time: .omitted))."
            + (price.map { " You'll be charged \($0) for a year unless you cancel in Settings." } ?? "")
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate),
            repeats: false)
        try? await center.add(UNNotificationRequest(identifier: Self.trialReminderID, content: content, trigger: trigger))
    }
}
