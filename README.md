# RepToll

Your doomscroll apps stay locked. Push-ups, squats or a plank unlock them, one rep at a time.

- **Architecture:** [docs/ADR-001-reptoll-architecture.md](docs/ADR-001-reptoll-architecture.md)
- **Reverse-engineering notes:** [IOS_RECREATION_PLAN.md](IOS_RECREATION_PLAN.md)

## Layout
| Path | What |
|---|---|
| `Packages/RepTollKit/Sources/RepTollKit` | Pure logic: joint model, angle math, debouncer, push-up/squat/plank detectors, earning table, ledger, streaks |
| `Packages/RepTollKit/Sources/RepTollShared` | iOS Screen Time glue shared with the extensions (App Group store, shield, budget sessions) |
| `RepToll/` | SwiftUI app: onboarding, home, camera + Vision pose pipeline, stats, settings |
| `RepTollShieldConfig/` | The lock screen shown in place of restricted apps |
| `RepTollShieldAction/` | Shield buttons; posts a notification that deep-links into the unlock sheet |
| `RepTollMonitor/` | DeviceActivity monitor: tracks minutes used, re-locks, refunds unused time |
| `Config/` | Entitlements and extension Info.plists |

## Run
```bash
cd Packages/RepTollKit && swift test   # detector + ledger tests, no device needed
```
Open `RepToll.xcodeproj` and run the **RepToll** scheme on a **physical iPhone**. Screen Time shields and the camera don't work in the Simulator.

### First device run
1. Signing & Capabilities: team `J8G5UT5LRV` is preset. Let Xcode register the four bundle IDs and the App Group `group.com.syedsafiali.RepToll`.
2. The **Family Controls** capability works in development builds right away. TestFlight and the App Store need Apple to approve the distribution entitlement: [request form](https://developer.apple.com/contact/request/family-controls-distribution).
3. Tune `DetectionThresholds.default` (`minConfidence`) after a few real sessions.

## Pricing
Free plan locks 1 app. **RepToll Pro** adds unlimited apps and Strict Mode: €11.99/year (7-day free trial), €2.99 every 3 months, or €24.99 lifetime. Setup and testing: [docs/MONETIZATION.md](docs/MONETIZATION.md). Store listing: [docs/APP_STORE.md](docs/APP_STORE.md).

## Tuning rep counting
Settings → Tuning → **Record pose data** saves joint positions (no video) from each workout. Share the JSON files to add real-movement regression tests in `Packages/RepTollKit/Tests`.

## Before any public release
A web search (Nov 2026) found no existing app named RepToll. That isn't trademark clearance: check the App Store, [USPTO](https://tmsearch.uspto.gov) and domains before launch.
