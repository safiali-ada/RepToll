import Foundation
import Observation
import RepTollShared
import StoreKit

/// RepToll Pro subscription state, backed by StoreKit 2. No server: entitlements are verified on device.
@Observable
final class Store {
    static let shared = Store()

    /// Auto-renewable subscription, 3-month period. Must match App Store Connect and `RepToll.storekit`.
    static let proProductID = "com.syedsafiali.RepToll.pro.quarterly"
    /// Apple's standard EULA; App Review accepts it as the Terms of Use link.
    static let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    /// Must be a public page before submitting. See docs/MONETIZATION.md.
    static let privacyURL = URL(string: "https://github.com/safiali-ada/RepToll/blob/main/docs/PRIVACY.md")!

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

    /// Re-derives Pro status from the user's current entitlements.
    func refresh() async {
        var active = false
        var renewal: Date?
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result,
                  transaction.productID == Self.proProductID,
                  transaction.revocationDate == nil else { continue }
            if let expiration = transaction.expirationDate, expiration < .now { continue }
            active = true
            renewal = transaction.expirationDate
        }
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
