# RepToll Pro

| Plan | What you get |
|---|---|
| Free | All exercises, earning and spending time, stats, pause, **1** restricted app, category or website |
| Pro | Unlimited restricted apps, categories and websites, plus **Strict Mode** (hides the pause button) |

| Product | ID | Type | Price |
|---|---|---|---|
| Yearly (preselected, "Best value") | `com.syedsafiali.RepToll.pro.yearly` | Auto-renewable, 1 year, **7-day free trial** | €11.99 |
| 3 months | `com.syedsafiali.RepToll.pro.quarterly` | Auto-renewable, 3 months | €2.99 |
| Lifetime | `com.syedsafiali.RepToll.pro.lifetime` | Non-consumable | €24.99 |

- **Code:**
  - `RepToll/Store/Store.swift`: StoreKit 2 entitlements, purchase, restore, and the trial-ending reminder.
  - `RepToll/Store/PaywallView.swift`: a custom paywall. `SubscriptionStoreView` can't show a non-consumable.
- **Server:** none. Purchases are verified on device.
- **Where the paywall shows:**
  - Once, at the end of onboarding (closable).
  - When a free user picks a 2nd app or turns on Strict Mode.
  - From the "Go Pro" button on Home and from Settings.
- **Trial reminder:** a local notification 2 days before the free trial converts.

## Test on your iPhone now (no App Store Connect needed)
The shared **RepToll** scheme uses `RepToll.storekit`. Check this under Product ▸ Scheme ▸ Edit Scheme ▸ Run ▸ Options ▸ StoreKit Configuration.
1. Do a fresh install and finish onboarding. The paywall appears once, with Yearly preselected and "Start 7-day free trial".
2. Buy each plan in turn. Settings ▸ RepToll Pro shows the plan. Picks over the free limit apply right after purchase.
3. In Xcode, use Debug ▸ StoreKit ▸ Manage Transactions to refund or expire a purchase and test the free state. You can delete transactions there to reset trial eligibility. Renewals run in real time; change the rate under Editor ▸ Subscription Renewal Rate in `RepToll.storekit` if needed.

## App Store Connect checklist
1. **Agreements, Tax, and Banking:** accept the **Paid Apps** agreement and add your bank account and tax forms. Nothing can be sold until this shows *Active*.
2. **Small Business Program:** apply at developer.apple.com/app-store/small-business-program. That makes Apple's cut 15% instead of 30%.
3. **Create the app record** with bundle ID `com.syedsafiali.RepToll`.
4. **Monetization ▸ Subscriptions:** create the group **RepToll Pro** with two subscriptions. IDs must match exactly. Use Italy as the base country; Apple fills in the other storefronts.
   - `com.syedsafiali.RepToll.pro.yearly`: 1 Year, €11.99, level 1.
     - Under **Introductory Offers**, add Free, 1 week, for all countries.
   - `com.syedsafiali.RepToll.pro.quarterly`: 3 Months, €2.99, level 2.
   - For each, add a display name, a description and a review screenshot of the paywall.
5. **Monetization ▸ In-App Purchases:** add a Non-Consumable `com.syedsafiali.RepToll.pro.lifetime` at €24.99, with a display name, a description and a review screenshot.
6. **App Privacy** and **App Information:**
   - **Privacy Policy URL:** https://github.com/safiali-ada/PrivacyPolicy/blob/main/README_RepToll.md (public repo; source text in `docs/PRIVACY.md`).
   - The Terms of Use link uses Apple's standard EULA (`Store.termsURL`). If you write your own terms, add the link in the app description too.
7. Submit the first subscriptions and the lifetime purchase **together with an app version**. Apple reviews them together the first time.

## What each sale pays you (rough, Italy)
Prices include 22% VAT. Apple's cut is 15% (Small Business Program). Amounts differ by country and VAT rate.

| Plan | After VAT | You keep |
|---|---|---|
| Yearly €11.99 | ≈ €9.83 | ≈ **€8.36 / year** |
| 3 months €2.99 | ≈ €2.45 | ≈ **€2.08 / quarter** (€8.33 / year) |
| Lifetime €24.99 | ≈ €20.48 | ≈ **€17.41 once** |

## App Review notes for subscriptions
- The paywall shows the price, period, trial length and auto-renewal terms next to the buy button.
- Restore Purchases is in the paywall and in Settings, and both show the result.
- The Pro feature list names only what the free plan doesn't include.
