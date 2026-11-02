# Unscroll

Your doomscroll apps stay locked. Push-ups, squats or a plank unlock them, one rep at a time.

- **Architecture:** [docs/ADR-001-unscroll-architecture.md](docs/ADR-001-unscroll-architecture.md)
- **Reverse-engineering notes:** [IOS_RECREATION_PLAN.md](IOS_RECREATION_PLAN.md)

## Layout
| Path | What |
|---|---|
| `Packages/UnscrollKit/Sources/UnscrollKit` | Pure logic: joint model, angle math, debouncer, push-up/squat/plank detectors, earning table, ledger, streaks |
| `Packages/UnscrollKit/Sources/UnscrollShared` | iOS Screen Time glue shared with the extensions (App Group store, shield, budget sessions) |
| `Unscroll/` | SwiftUI app: onboarding, home, camera + Vision pose pipeline, stats, settings |
| `UnscrollShieldConfig/` | The lock screen shown in place of restricted apps |
| `UnscrollShieldAction/` | Shield buttons; posts a notification that deep-links into the unlock sheet |
| `UnscrollMonitor/` | DeviceActivity monitor: tracks minutes used, re-locks, refunds unused time |
| `Config/` | Entitlements and extension Info.plists |

## Run
```bash
cd Packages/UnscrollKit && swift test   # detector + ledger tests, no device needed
```
Open `Unscroll.xcodeproj` and run the **Unscroll** scheme on a **physical iPhone**. Screen Time shields and the camera don't work in the Simulator.

### First device run
1. Signing & Capabilities: team `J8G5UT5LRV` is preset. Let Xcode register the four bundle IDs and the App Group `group.com.syedsafiali.Unscroll`.
2. The **Family Controls** capability works in development builds right away. TestFlight and the App Store need Apple to approve the distribution entitlement: [request form](https://developer.apple.com/contact/request/family-controls-distribution).
3. Tune `DetectionThresholds.default` (`minConfidence`) after a few real sessions.

## Before any public release
"Unscroll" is already the name of an App Store app. Pick an original name, then change `INFOPLIST_KEY_CFBundleDisplayName` and the strings in `Theme.swift`/the shield.
