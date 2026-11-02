# Push-to-Scroll — iOS recreation plan (from the Pushscroll v1.72 APK)

## 0. Source and trust

| Fact | Observed |
|---|---|
| File | `Pushscroll v1.72 (Premium).apk`, SHA-256 `6e557f33…57995b` |
| Package | `com.pushscroll.pushscrollapp`, versionName 1.72 (73), minSdk 28, target 35, arm64 only |
| Build | **Kotlin Multiplatform + Compose Multiplatform** (`pushscroll.composeapp.generated.resources`), R8-obfuscated. It contains iOS strings (`permission_ios_screen_time_*`) and iOS-only code paths ("Skipping unlockAppsForMs on Android", "Skipping refreshBlocking on Android"), so the official iOS app shares this code |
| **Tampering** | This is a third-party "Premium" mod. `classes3.dex` has injected code in package `ī/íì/*` that decrypts a string and opens `https://liteapks.com/app.html`. **Do not install this file on a real device.** It was only read statically here; nothing was run |

Method: `aapt2 dump badging`, `dexdump -d` (Android build-tools 37.0.0), and decoding the Compose `strings.commonMain.cvr`. Each claim below is marked **[obs]** (seen in the bytecode or resources), **[inf]** (inferred from it) or **[design]** (my recommendation for iOS).

---

## 1. What the app does

**Core loop** [obs, from strings and class names]
1. The user picks apps to **restrict**. Android uses a usage-stats foreground service plus an overlay; iOS uses Screen Time.
2. Opening a restricted app shows a **shield**: "You again." → "Choose a time budget for your restricted app", with a "Use X minutes **(wait N s)**" countdown button and Cancel.
3. The budget comes from exercise. "Time only counts while using restricted apps. The budget will reset after a **%d minute break** from them." A banner shows "Using <app> counts towards your budget · N minutes left · For more, go to Pushscroll to do push-ups."
4. **Exercise screen**: front camera on the floor ("Place your phone on the floor facing you in a well-lit area"), a tutorial video per exercise, live rep counting, then a congratulations screen.
5. **Pause/Resume**, plus a scheduled "pause until <date> <time>".

**Exercises** [obs]: `PUSHUPS`, `SQUATS`, `PLANK`. There's a sit-up icon but no detector for it.

**Difficulty** [obs]: `VERY_EASY, EASY, MEDIUM, HARD, VERY_HARD`, with an "Adaptive Difficulty" feature. Lowering the difficulty breaks your streak.

**Minutes earned per rep** [obs, `Ca/c.b(Exercise)`]. For plank, the unit is one *second held*:

| | Very easy | Easy | Medium | Hard | Very hard |
|---|---|---|---|---|---|
| Pushups | 10 | 5 | 2 | 1 | 0.33 |
| Squats | 5 | 2 | 1 | 0.33 | 0.2 |
| Plank (per sec) | 5 | 2 | 1 | 0.33 | 0.2 |

[inf] The keys `exercise_multipliers` and `exercise_difficulties` suggest these numbers can also be overridden by remote config.

**Other features** [obs]:
- **Streaks**: an event-sourced `StreakTimeline` table and a `getCurrentStreak` SQL query. Disabling an app or lowering the difficulty breaks the streak.
- **Stats**: daily, weekly and monthly reps and app usage charts.
- **"Journey"**: levels Rookie → Scout → Gladiator → Champion → Titan → Olympian, with lessons and collectibles, plus screen-time "offline activity" suggestions (walk, read, meditate, music, museum…).
- **Onboarding**: a quiz ("why is it hard for you": boredom, FOMO, job, procrastinating…), an "analysis" screen, and a commitment signature (`Signature`/`SignatureStroke`).
- Referral codes, feedback/report issue, reminder notifications ("It's about time…").

---

## 2. Rep detection, decoded

**Engine** [obs]: Google **MediaPipe Pose Landmarker** (`libmediapipe_tasks_vision_jni.so`) with CameraX. It ships three models: `pose_landmarker_lite/full/heavy.task`. The model is picked by an on-device **benchmark** (`ExercisesUtilAndroid … Successfully finished benchmark`):
- inference time < 26 ms → heavy
- 26–50 ms → full
- ≥ 51 ms → lite

**Landmarker parameters** [obs, `PoseLandmarkerParams`]. `numPoses = 1`.

| | Detection confidence | Presence confidence | Tracking confidence |
|---|---|---|---|
| Pushups | 0.8 | 0.7 | 0.5 |
| Squats | 0.9 | 0.8 | 0.6 |
| Plank | 0.8 | 0.7 | 0.5 |

Landmark indices below are MediaPipe's 33-point skeleton: 11/12 shoulders, 13/14 elbows, 15/16 wrists, 23/24 hips, 25/26 knees, 27/28 ankles. Angles are computed on **world landmarks**, which are 3D and in meters [obs].

**Detector interface** [obs, `Ca/e`]: `analyze(timestampMs, landmarks, worldLandmarks) -> Result`.
- The result is one of `NO_CHANGE`, `NOT_ENOUGH_LANDMARKS`, `LOW_VISIBILITY`, `LOW_PRESENCE`, `REP`, or an extra state.
- Every detector also exposes a set of "bad" landmark indices so the UI can highlight the wrong joints.

**Debouncer** [obs, `Ca/b`, used by pushups and squats]. It works like a majority vote:
- It keeps a sliding **250 ms** window of `(state, frameDuration)`.
- It drops frames whose inference time is more than half the window (125 ms).
- It switches state only when one state holds at least **60 %** of the frames expected in that window.
- It returns whether the debounced state changed.

**Pushups** [obs, `Ca/q`]
- Required points: 11–16 and 23–28, each with visibility ≥ 0.6 and presence ≥ 0.6.
- `elbow = avg(angle(11,13,15), angle(12,14,16))`, and the left/right difference must be ≤ 40°.
- **UP** when the elbow angle is between 148° and 200°. **DOWN** when it is between 35° and 148° and the plausibility checks pass.
- Plausibility checks use world-landmark y-thresholds (−0.05 and 0.01) on wrists vs hips and on knees, plus wrist/elbow/shoulder ordering checks.
- A **rep is counted on a debounced DOWN→UP transition.**
- [inf] The two bands touch at 148°. The debouncer, not a dead zone, is what stops jitter from double-counting.

**Squats** [obs, `Ca/u`]
- Required points: 11, 12, 15, 16, 23–28.
- `knee = avg(angle(23,25,27), angle(24,26,28))`.
- **UP** when the knee angle is between 100° and 200°. **DOWN** when it is between 20° and 100° and the side checks pass.
- A posture angle (hip/torso) must stay within 65°–140°.
- A rep is counted on DOWN→UP.

**Plank** [obs, `Ca/o`]
- Required points: 11–16 and 23–26, with visibility ≥ 0.7 and presence ≥ 0.6.
- Both elbow angles must be between 85° and 180°. Both shoulder angles (elbow–shoulder–other shoulder) must be between 55° and 135°.
- Alignment checks:
  - elbow vs shoulder offset −0.1
  - wrist vs shoulder offset 0.2
  - wrist/elbow ordering
  - knee/ankle visibility ≥ 0.6
  - hips below 0 in world y
- While the pose is valid, it accumulates held time. Each new **whole second** counts as a "rep". Breaking the pose resets the hold timer.

---

## 3. Data and services

**Local DB** [obs, SQLDelight]:
```sql
CREATE TABLE ExerciseLog (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  date TEXT NOT NULL,              -- UTC 'YYYY-MM-DD'
  exercise TEXT NOT NULL,          -- PUSHUPS | SQUATS | PLANK
  repetitions INTEGER NOT NULL,
  msEarned INTEGER NOT NULL,
  createdAtUtc INTEGER NOT NULL DEFAULT (strftime('%s','now')),
  updatedAtUtc INTEGER NOT NULL DEFAULT (strftime('%s','now')));
CREATE TABLE StreakTimeline (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  event TEXT NOT NULL,
  timestampUtc INTEGER NOT NULL DEFAULT (strftime('%s','now')));
CREATE INDEX StreakTimeline_event_timestamp_index ON StreakTimeline(event, timestampUtc);
```

**Settings** [obs]: DataStore preferences, e.g. `difficulty`, `exercise_kind`, `exercise_tutorial_seen`, `should_show_budget_chooser`.

**Third-party services** [obs]:
- `api.pushscroll.com` (`/users`, profile, referrals, quiz answers)
- RevenueCat (subscriptions)
- **Superwall** (paywalls)
- OneSignal (push notifications)
- AppsFlyer (attribution)
- Firebase Analytics
- Sentry (crash reports and session replay)
- Compottie (Lottie for Compose)

You need none of these for a personal build.

---

## 4. iOS architecture [design]

Use native **SwiftUI** rather than Kotlin Multiplatform, unless you already write Kotlin. The rules above port directly to Swift.

```
Main app (SwiftUI)
 ├─ Onboarding → FamilyControls auth (.individual) → FamilyActivityPicker
 ├─ Exercise screen: AVCaptureSession → MediaPipe PoseLandmarker (live stream)
 │     → Detector (Pushup/Squat/Plank) → Debouncer → +minutes
 ├─ Home (budget, streak, pause/resume), Stats, Journey, Settings
 └─ SwiftData (ExerciseLog, StreakEvent)
App Group (shared state) ──────────────────────────────────────────
 ├─ ShieldConfiguration ext.: "You again." + budget text
 ├─ ShieldAction ext.: "Use budget" → notification → opens the app's budget chooser
 └─ DeviceActivityMonitor ext.: re-shield when the budget threshold or break timer hits
```

- **Pose:** use the **MediaPipe Tasks Vision iOS SDK** (`MediaPipeTasksVision` pod, `PoseLandmarker` in `.liveStream` mode). It gives the same 33 landmarks plus world landmarks, so every angle and index above carries over. Download the `.task` models from Google's MediaPipe model page instead of copying them out of the APK. Copy the benchmark-based model choice too.
- **Fallback:** Apple Vision `VNDetectHumanBodyPose3DRequest` avoids the extra dependency, but it uses a different 17-joint skeleton and needs re-tuned thresholds.
- **Blocking:** `ManagedSettingsStore().shield.applications = selection.applicationTokens`.
- **Budget spending:** this matches the app's own "time only counts while using restricted apps" rule.
  - When the user spends N minutes, clear the shield and call `DeviceActivityCenter.startMonitoring` with a `DeviceActivityEvent(applications:, threshold: N min)`.
  - In the extension's `eventDidReachThreshold`, put the shield back.
  - Implement "budget resets after an X-minute break" by restarting monitoring.
  - The Android code's `unlockAppsForMs` / `refreshBlocking` hooks are where the official iOS app does this.
- **Shield "wait N s" countdown:** the shield UI can't run timers. Put the countdown in the app after a notification deep link, which is what the iOS notification-permission string describes: "help you choose a session length when opening restricted apps".

---

## 5. Milestones

| # | Milestone | Done when |
|---|---|---|
| 1 | Xcode project, App Group, three Screen Time extensions, Family Controls capability. **Request the Family Controls distribution entitlement now** (it takes days to weeks) | Auth prompt and picker work on a device |
| 2 | Shield on/off, a custom shield screen, a notification that opens the app | Picked apps are blocked, and tapping the shield lands in the app |
| 3 | Camera + MediaPipe landmarker + skeleton overlay + model benchmark | ≥ 20 fps with joints drawn |
| 4 | Port the detectors and debouncer from §2. Unit-test them with recorded landmark sequences (save JSON from real sessions) | Pushup/squat counts ≥ 95 % accurate, half reps rejected, plank seconds correct |
| 5 | Earning/spending: the difficulty × minutes table, budget chooser, DeviceActivity threshold re-shield, break reset | Blocked → 5 pushups at Medium → 10 min → blocked again |
| 6 | SwiftData log, streak timeline + current-streak query, stats charts (Swift Charts), pause/resume + scheduled pause | — |
| 7 | Onboarding quiz, Journey levels, widget, StoreKit 2 paywall (optional) | TestFlight build |

Test on a physical iPhone. Screen Time shields don't work in the Simulator.

---

## 6. Notes
- Use your own name, icon, tutorial videos and animations. The APK's assets, videos and copy belong to Pushscroll GmbH.
- Unresolved: the exact meaning of the pushup y-offset checks, and whether remote config overrides the difficulty table at runtime. Tune both with your own recordings.
