import StoreKit
import SwiftUI

/// RepToll Pro paywall. Apple's `SubscriptionStoreView` shows the localized price, period and
/// renewal terms that App Review requires, plus restore and policy links.
struct PaywallView: View {
    /// Why the paywall appeared, e.g. after picking more apps than the free plan allows.
    var reason: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        SubscriptionStoreView(productIDs: [Store.proProductID]) {
            VStack(alignment: .leading, spacing: 18) {
                Wordmark(size: 26)
                Text("Go Pro")
                    .font(.system(size: 40, weight: .heavy, design: .rounded))
                if let reason {
                    Text(reason)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                }
                VStack(alignment: .leading, spacing: 12) {
                    feature("apps.iphone", "Lock as many apps and categories as you want")
                    feature("figure.strengthtraining.functional", "Push-ups, squats and plank — all included")
                    feature("chart.bar.fill", "Full stats and streak history")
                    feature("heart.fill", "Support an indie developer")
                }
                Text("The free plan locks 1 app. Pro removes the limit.")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
        }
        .storeButton(.visible, for: .restorePurchases)
        .storeButton(.visible, for: .cancellation)
        .subscriptionStorePolicyDestination(url: Store.termsURL, for: .termsOfService)
        .subscriptionStorePolicyDestination(url: Store.privacyURL, for: .privacyPolicy)
        .subscriptionStoreButtonLabel(.multiline)
        .tint(Theme.accent)
        .background(Theme.background)
        .onInAppPurchaseCompletion { _, result in
            if case .success(.success(let verification)) = result {
                await Store.shared.handle(verification)
                dismiss()
            }
        }
    }

    private func feature(_ symbol: String, _ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            Text(text).font(.body.weight(.medium))
        }
    }
}
