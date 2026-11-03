import StoreKit
import SwiftUI

/// RepToll Pro paywall. Yearly (with the free trial) is preselected so buying is one tap.
/// Shows the price, period, trial and auto-renewal terms that App Review requires, plus restore
/// and policy links. Every price comes from StoreKit, so it's localized per storefront.
struct PaywallView: View {
    /// Why the paywall appeared, e.g. after picking more apps than the free plan allows.
    var reason: String?
    @Environment(\.dismiss) private var dismiss
    @State private var selected = ProPlan.yearly
    @State private var isPurchasing = false
    @State private var alert: String?
    private let store = Store.shared

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    features
                    plans
                }
                .padding(24)
                .padding(.top, 8)
            }
            .scrollIndicators(.hidden)
            footer
        }
        .background(Theme.background.ignoresSafeArea())
        .overlay(alignment: .topTrailing) { closeButton }
        .presentationBackground(.black)
        .task { if store.products.isEmpty { await store.loadProducts() } }
        .alert(alert ?? "", isPresented: .init(get: { alert != nil }, set: { if !$0 { alert = nil } })) {
            Button("OK", role: .cancel) {}
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Wordmark(size: 24)
            Text("Earn your scroll.\nWithout limits.")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
            if let reason {
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }

    /// Only what Pro actually adds; everything else is free for everyone.
    private var features: some View {
        VStack(alignment: .leading, spacing: 14) {
            feature("apps.iphone", "Lock every app that eats your day", "Free locks 1 app, category or site")
            feature("lock.shield.fill", "Strict Mode", "Hides the pause button, so there's no way around the reps")
            feature("heart.fill", "Support an indie developer", "No ads, no tracking, ever")
        }
    }

    @ViewBuilder
    private var plans: some View {
        if store.products.isEmpty {
            HStack {
                Spacer()
                if store.productsFailedToLoad {
                    VStack(spacing: 10) {
                        Text("Couldn't reach the App Store.")
                            .foregroundStyle(Theme.secondaryText)
                        Button("Try again") { Task { await store.loadProducts() } }
                            .fontWeight(.semibold)
                    }
                } else {
                    ProgressView()
                }
                Spacer()
            }
            .frame(minHeight: 180)
        } else {
            VStack(spacing: 10) {
                ForEach(ProPlan.allCases) { plan in
                    if let product = store.product(for: plan) { planCard(plan, product) }
                }
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Button {
                Task { await buy() }
            } label: {
                if isPurchasing {
                    ProgressView().tint(.black)
                } else {
                    Text(ctaTitle)
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(isPurchasing || store.product(for: selected) == nil)

            Text(termsLine)
                .font(.footnote.weight(.medium))
                .multilineTextAlignment(.center)

            HStack(spacing: 18) {
                Button("Restore") { Task { await restore() } }
                Link("Terms", destination: Store.termsURL)
                Link("Privacy", destination: Store.privacyURL)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)

            if selected != .lifetime {
                Text("Renews automatically until cancelled in Settings ▸ Apple Account at least 24 hours before the period ends.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.background)
    }

    private var closeButton: some View {
        Button { dismiss() } label: {
            Image(systemName: "xmark")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(.white.opacity(0.8))
                .frame(width: 36, height: 36)
                .background(Theme.card, in: .circle)
        }
        .padding(16)
        .accessibilityLabel("Close")
    }

    // MARK: - Pieces

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.headline)
                .foregroundStyle(Theme.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }

    private func planCard(_ plan: ProPlan, _ product: Product) -> some View {
        let isSelected = selected == plan
        return Button {
            selected = plan
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.accent : .white.opacity(0.35))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(plan.title).font(.headline)
                        if plan == .yearly {
                            Text("BEST VALUE")
                                .font(.caption2.weight(.heavy))
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(Theme.accent, in: .capsule)
                                .foregroundStyle(.black)
                        }
                    }
                    Text(detail(plan, product))
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Text(product.displayPrice).font(.headline)
            }
            .padding(16)
            .background(Theme.card, in: .rect(cornerRadius: 18))
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(isSelected ? Theme.accent : .white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
            )
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    // MARK: - Copy

    private func detail(_ plan: ProPlan, _ product: Product) -> String {
        switch plan {
        case .yearly:
            let monthly = "\(perMonth(product, months: 12))/month"
            return trialDays.map { "\($0) days free, then \(monthly)" } ?? monthly
        case .quarterly:
            return "\(perMonth(product, months: 3))/month, billed every 3 months"
        case .lifetime:
            return "Pay once, keep Pro forever"
        }
    }

    private var ctaTitle: String {
        if selected == .yearly, let days = trialDays { return "Start \(days)-day free trial" }
        return selected == .lifetime ? "Unlock Pro forever" : "Continue"
    }

    private var termsLine: String {
        guard let product = store.product(for: selected) else { return " " }
        switch selected {
        case .yearly:
            let price = "\(product.displayPrice)/year"
            return trialDays.map { "Free for \($0) days, then \(price). Cancel anytime." }
                ?? "\(price), renews automatically. Cancel anytime."
        case .quarterly:
            return "\(product.displayPrice) every 3 months, renews automatically. Cancel anytime."
        case .lifetime:
            return "\(product.displayPrice) once. No subscription."
        }
    }

    /// Length of the yearly free trial, if this user can still get it.
    private var trialDays: Int? {
        guard store.isEligibleForTrial,
              let offer = store.product(for: .yearly)?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }
        let period = offer.period
        switch period.unit {
        case .day: return period.value
        case .week: return period.value * 7
        case .month: return period.value * 30
        default: return nil
        }
    }

    private func perMonth(_ product: Product, months: Int) -> String {
        (product.price / Decimal(months)).formatted(product.priceFormatStyle)
    }

    // MARK: - Actions

    private func buy() async {
        guard let product = store.product(for: selected) else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        do {
            if try await store.purchase(product) { dismiss() }
        } catch {
            alert = "The purchase didn't go through. \(error.localizedDescription)"
        }
    }

    private func restore() async {
        switch await store.restore() {
        case .restored: dismiss()
        case .nothingFound: alert = "No RepToll Pro purchase found for this Apple Account."
        case .failed: alert = "Couldn't reach the App Store. Try again in a moment."
        }
    }
}
