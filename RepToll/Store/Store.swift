import Foundation
import Observation
import RepTollShared
import StoreKit
import os

private let log = Logger(subsystem: "com.syedsafiali.RepToll", category: "Store")

/// RepToll Pro subscription state, backed by StoreKit 2. No server: entitlements are verified on device.
@Observable
final class Store {
    static let shared = Store()

    /// Auto-renewable subscription, 3-month period. Must match App Store Connect and `RepToll.storekit`.
    static let proProductID = "com.syedsafiali.RepToll.pro.quarterly"
    /// Apple's standard EULA; App Review accepts it as the Terms of Use link.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Public policy page in safiali-ada/PrivacyPolicy (source: docs/PRIVACY.md).
    static let privacyURL = URL(string: "https://github.com/safiali-ada/PrivacyPolicy/blob/main/README_RepToll.md")!

    private(set) var isPro: Bool
    private(set) var renewalDate: Date?
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

    /// Re-derives Pro status. Uses the subscription status API (the same source the paywall uses
    /// for "your current plan") and falls back to current entitlements, so the two can't disagree.
    func refresh() async {
        var active = false
        var renewal: Date?

        if let product = try? await Product.products(for: [Self.proProductID]).first,
           let statuses = try? await product.subscription?.status {
            for status in statuses {
                log.info("Subscription status: \(String(describing: status.state), privacy: .public)")
                switch status.state {
                case .subscribed, .inGracePeriod, .inBillingRetryPeriod:
                    active = true
                    if case .verified(let transaction) = status.transaction { renewal = transaction.expirationDate }
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
            guard transaction.productID == Self.proProductID, transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }
            active = true
            renewal = renewal ?? transaction.expirationDate
        }

        log.info("RepToll Pro active: \(active, privacy: .public)")
        setPro(active, renewal: renewal)
    }

    func handle(_ result: VerificationResult<Transaction>) async {
        if case .verified(let transaction) = result {
            await transaction.finish()
        }
        await refresh()
    }

    func restore() async {
        try? await AppStore.sync()
        await refresh()
    }

    private func setPro(_ active: Bool, renewal: Date?) {
        let activated = active && !isPro
        isPro = active
        renewalDate = renewal
        SharedStore.shared.isPro = active
        if activated { onProActivated?() }
    }
}
