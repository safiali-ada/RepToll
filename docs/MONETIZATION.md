# RepToll Pro: €0.99 every 3 months

| Plan | What you get |
|---|---|
| Free | All exercises, earning and spending time, **1** restricted app, category or website |
| Pro | Unlimited restricted apps, categories and websites |

- **Product:** auto-renewable subscription `com.syedsafiali.RepToll.pro.quarterly`, 3-month period, €0.99.
- **Code:** `RepToll/Store/Store.swift` (StoreKit 2 entitlements) and `RepToll/Store/PaywallView.swift` (Apple's `SubscriptionStoreView`).
- **Server:** none. Purchases are verified on device.

## Test on your iPhone now (no App Store Connect needed)
The shared **RepToll** scheme uses `RepToll.storekit`. Check this under Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration.
1. Run on the device. Settings ▸ **Unlock RepToll Pro** buys the subscription with a fake local transaction.
2. Pick 2+ apps on the free plan. The paywall appears. After subscribing, all picks apply.
3. In Xcode, Debug ▸ StoreKit ▸ Manage Transactions lets you refund or expire it to test the free state. The config renews every 6 seconds per day of the period, so 3 months ≈ 9 minutes.

## App Store Connect checklist
1. **Agreements, Tax, and Banking:** accept the **Paid Apps** agreement and add your bank account and tax forms. Nothing can be sold until this shows *Active*.
2. **Small Business Program:** apply at developer.apple.com/app-store/small-business-program. That makes Apple's cut 15% instead of 30%.
3. **Create the app record** with bundle ID `com.syedsafiali.RepToll`.
4. **Monetization ▸ Subscriptions:**
   - Create the group **RepToll Pro**.
   - Add a subscription with:
     - Product ID `com.syedsafiali.RepToll.pro.quarterly` (must match exactly)
     - Duration **3 Months**
     - Price **€0.99**, with Italy as the base country. Apple fills in the other storefronts.
   - Add a display name, a description and a review screenshot of the paywall.
5. Optional: under the subscription ▸ **Introductory Offers**, add a free trial (e.g. 1 week). The paywall shows it automatically.
6. **App Privacy** and **App Information:**
   - Add a public **Privacy Policy URL**. `docs/PRIVACY.md` is ready, but this repo is private, so publish it somewhere public and update `Store.privacyURL`.
   - The Terms of Use link uses Apple's standard EULA (`Store.termsURL`). If you write your own terms, add the link in the app description too.
7. Submit the first subscription **together with an app version**. Apple reviews them together the first time.

## What a €0.99 renewal pays you (rough, Italy)
€0.99 includes 22% VAT, which leaves ≈ €0.81. Apple's 15% (Small Business Program) takes that to ≈ **€0.69** per renewal. The amount differs by country and VAT rate.

## App Review notes for subscriptions
- The paywall must show the price, period and auto-renewal. `SubscriptionStoreView` does this.
- A Restore Purchases button is required. It's in the paywall and in Settings.
- Don't promise features the free plan blocks without showing the price first.
