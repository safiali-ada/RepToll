# ADR-001: RepToll iOS architecture

**Status:** Accepted
**Date:** 2026-11-02
**Deciders:** Syed Safi Ali

## Context
RepToll blocks chosen apps until the user earns screen time by exercising in front of the camera. It is modeled on what we decoded from Pushscroll v1.72 (see `IOS_RECREATION_PLAN.md`). The forces at play:

- **Platform.** iOS only. Blocking must go through Apple's Screen Time APIs (FamilyControls, ManagedSettings, DeviceActivity). Those run partly in app extensions with tight memory limits (the DeviceActivity monitor gets about 6 MB).
- **Toolchain.** Xcode 27.2 and Swift 6.4. Nothing else is installed: no CocoaPods, XcodeGen or Tuist.
- **Correctness.** Rep counting is the core of the product and must be unit-testable without a phone or camera.
- **Size.** One developer, so the setup has to stay small.

## Decision
1. **Pose engine: Apple Vision.** Run `VNDetectHumanBodyPose3DRequest` for joint angles (in meters, in a body-relative space) together with `VNDetectHumanBodyPoseRequest` for per-joint confidence and the on-screen skeleton. If the 3D request returns nothing, fall back to aspect-corrected 2D angles.
2. **Detection logic in a pure Swift package** (`Packages/RepTollKit`, target `RepTollKit`). It contains the joint model, angle math, debouncer, the three detectors, the earning table, the bank ledger and the streak calculation. It has no UIKit or Vision imports, and `swift test` runs it on the Mac.
3. **Screen Time glue in a second package target** (`RepTollShared`, iOS-only). It holds the App Group store, the shield controller, session scheduling and the extension event handlers. The app and all three extensions link it.
4. **Budget mechanism.** A spend session works like this:
   - Lift the shield.
   - Start a one-off `DeviceActivitySchedule` that ends at `now + max(15 min, granted + 10 min break window)`.
   - Monitor the restricted tokens with one `DeviceActivityEvent` per granted minute (`used.1`…`used.N`, `includesPastActivity: false`).
   - Each event records the minutes used. Event N puts the shield back. When the interval ends, the shield goes back and any unused minutes are refunded to the bank.
5. **Persistence.**
   - **SwiftData** (app only) holds the workout history.
   - **App Group `UserDefaults`** holds the small state the extensions need: the bank, the active session, the app selection, the paused flag and the difficulty.
6. **Project file.** A hand-written `.xcodeproj` that uses Xcode's synchronized folder groups (objectVersion 77), so adding a file needs no edit to the project file.

## Options considered

### Pose engine
| | Apple Vision (chosen) | MediaPipe Pose Landmarker |
|---|---|---|
| Complexity | Low: built into the OS | Medium: CocoaPods-only on iOS, ~10–30 MB models |
| Parity with Pushscroll | Re-tuned. 17 joints with the same names, but different confidence ranges | Exact: the same 33 landmarks and thresholds |
| Binary size | +0 MB | +15–40 MB |
| Toolchain | Ready now | Needs CocoaPods installed, plus a workspace |

**Trade-off.** Parity is less important than shipping with zero dependencies. The angle bands carry over unchanged because joint *angles* don't depend on the model. Only the confidence gates need re-tuning (they are a config struct). If accuracy turns out poor on a device, this can be revisited: the detectors only see `PoseFrame`, so swapping engines touches only `PosePipeline.swift`.

### Budget enforcement
| | Per-minute threshold events (chosen) | Wall-clock unlock |
|---|---|---|
| Matches "time only counts while using restricted apps" | Yes | No |
| Refunds unused time | Yes, to the minute | No |
| Risk | Events are sometimes late. DeviceActivity enforces a 15-minute minimum interval | Simple, but users lose time |

Sessions are capped at 60 minutes to keep the number of events reasonable.

### Code structure
Putting everything in the app target is simpler, but then detectors can only be tested through Xcode on a simulator. The package split costs one local package reference and gives fast, camera-free tests.

## Consequences
- **Easier:** testing and tuning detectors with synthetic or recorded frames; renaming the app (one display-name setting); swapping the pose engine.
- **Harder:** the hand-written project file has to be maintained when targets change. There is no MediaPipe-style model-size choice per device.
- **Revisit:**
  - Confidence thresholds after real-device testing.
  - The plank earning rate. Pushscroll's 1 min per second at Medium is generous.
  - Trademark clearance for "RepToll" (renamed from "Unscroll", which an existing App Store app uses). A web search found no app by that name.
  - The Family Controls *distribution* entitlement, which needs Apple's approval before TestFlight.

## Action items
1. [x] Scaffold the package, the app and three extensions.
2. [x] Port the detectors and unit-test them on synthetic poses.
3. [ ] Device test: tune the confidence gates and angle bands with real sessions.
4. [ ] Request the Family Controls distribution entitlement.
5. [x] Pick an original name (RepToll) and icon.
