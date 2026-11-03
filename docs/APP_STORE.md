# RepToll — App Store Connect listing (v1.0)

Final draft, ready to paste. Character counts were checked with zsh `${#s}` / `wc -m` (trailing newline excluded) and are App Store Connect's limits. "Free", "best" and "#1" don't appear in the name, subtitle or keywords.

## App information

| Field | Value | Count / limit |
|---|---|---|
| Name | `RepToll: Push-ups Unlock Apps` | 29 / 30 |
| Subtitle | `Earn screen time with exercise` | 30 / 30 |
| Primary category | Health & Fitness | |
| Secondary category | Productivity | |
| Age rating | 4+ (answer "None" to every content question) | |
| Privacy Policy URL | https://github.com/safiali-ada/PrivacyPolicy/blob/main/README_RepToll.md | |

### Keywords (98 / 100)

```
limit,blocker,doomscroll,focus,detox,squat,plank,workout,fitness,habit,social,media,lock,addiction
```

No spaces after commas, and no words already in the name or subtitle (push-ups, unlock, apps, screen, time, exercise, earn); Apple indexes those already.

## Promotional text (167 / 170)

Can be changed any time without a new build.

```
Locked apps, unlocked by push-ups. Do a quick set, bank the minutes, and scroll only after you've earned it. Counting happens on-device; video never leaves your phone.
```

## Description (1,725 / 4,000)

```
Your thumb shouldn't get more exercise than you do.

RepToll locks the apps you doomscroll. To open them, earn minutes with push-ups, squats or a plank, counted by your front camera.

HOW IT WORKS
1. Pick the apps that eat your day. They get locked behind a shield.
2. Exercise in front of your camera. Every rep turns into minutes.
3. Spend minutes when you need them.

FEATURES
• On-device rep counting for push-ups, squats and plank. No wearable, no tapping.
• Minutes per rep: each rep, or each second of plank, adds time to your bank.
• Fair timing: time only ticks inside locked apps. Lock early and the unused part comes back after a 10-minute break.
• Five difficulty levels, from Very easy to Very hard.
• Streaks and stats for the last 7 days.
• Pause for an hour, until tomorrow, or until you resume.

PRIVATE BY DESIGN
Video is analyzed on your iPhone and never recorded or uploaded. No account, no ads, no tracking.

REPTOLL PRO
The basic plan locks 1 app. Pro adds:
• Unlimited apps, categories and websites
• Strict Mode, which hides the pause button

Choose Yearly (with a 7-day free trial), 3 months, or Lifetime (one-time purchase).

Payment is charged to your Apple Account at confirmation of purchase, or when the free trial ends. Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Renewal is charged within 24 hours before the period ends. Manage or cancel in your Apple Account settings. Any unused part of a free trial is forfeited when you buy a subscription.

Terms of Use: https://www.apple.com/legal/internet-services/itunes/dev/stdeula/
Privacy Policy: https://github.com/safiali-ada/PrivacyPolicy/blob/main/README_RepToll.md
```

## Screenshots — iPhone 6.9" (1320 × 2868)

Six portrait screenshots, caption at the top in large type, device frame below. Order matters: the first three show in search results.

| # | Caption | Chars | Screen shown |
|---|---|---|---|
| 1 | Doomscroll apps stay locked | 27 | The RepToll shield over a locked app: "Not so fast.", "[App] is locked. Do a few reps to earn your scroll.", **Earn time** / **Close app** |
| 2 | Every rep counted on-device | 27 | Camera workout screen with the pose skeleton drawn over a person mid push-up and the live rep counter |
| 3 | Bank minutes, not regrets | 25 | Home: the **Banked screen time** card with a large minute total and "2 min per rep of push-ups · Medium" |
| 4 | Unlock exactly what you earned | 30 | Unlock sheet: minute presets, "Exactly N min" stepper, the refund note and **Unlock for N min** |
| 5 | Watch your streak grow | 22 | Stats: streak and totals, the last-7-days chart by exercise, recent workouts |
| 6 | Unlimited apps with Pro | 23 | Paywall: Yearly with 7-day free trial, 3 months, Lifetime; unlimited apps, categories, websites and Strict Mode |

Use real-looking but generic app names in the shield shot (or "This app"), not a third-party logo.

## In-app purchases

Display name limit 30, description limit 45.

| Product ID | Type | Price | Display name | Description |
|---|---|---|---|---|
| `com.syedsafiali.RepToll.pro.yearly` | Auto-renewable, 1 year, 7-day free trial (introductory offer) | €11.99 | RepToll Pro Yearly (18) | Unlimited apps and Strict Mode, billed yearly (45) |
| `com.syedsafiali.RepToll.pro.quarterly` | Auto-renewable, 3 months | €2.99 | RepToll Pro 3 Months (20) | Unlimited apps and Strict Mode for 3 months (43) |
| `com.syedsafiali.RepToll.pro.lifetime` | Non-consumable | €24.99 | RepToll Pro Lifetime (20) | Unlimited apps and Strict Mode, pay once (40) |

Both subscriptions go in one subscription group, **RepToll Pro** (group display name: "RepToll Pro"), with Yearly ranked above 3 months so a switch counts as an upgrade. Each product needs a review screenshot of the paywall.

## App Privacy

**Data Not Collected.**

Why this is accurate (from `docs/PRIVACY.md`): camera frames are analyzed on-device by Vision and never stored or sent; Screen Time selections are opaque tokens kept on-device; workouts, streaks, settings and optional pose recordings stay on-device and leave only if the user shares them; there's no account, analytics, ads or tracking. Purchases are handled by Apple and don't count as collection by the developer. If an analytics or crash SDK is ever added, revisit this answer before shipping that build.

## App Review notes (1,141 / 4,000)

Sign-in required: **No**. Leave the demo account fields empty.

```
RepToll needs a physical iPhone and a person in front of it. Screen Time shields and the front-camera rep counter do not work in the Simulator, and reps are only counted when a body is visible to the camera.

No login or account is needed.

Steps:
1. Launch the app and go through onboarding.
2. Tap Allow for Screen Time (and Camera and Notifications).
3. On "What do you doomscroll?", tap Choose apps and pick 1 app (for example Safari). Tap Start earning.
4. Open that app from the Home Screen. RepToll's shield appears ("Not so fast.").
5. Tap Earn time (on the shield, or on RepToll's Home screen).
6. Prop the phone up, step back so your whole upper body is in frame, and do 3 push-ups or hold a 10-second plank. On the default Medium difficulty that earns 6 or 10 minutes.
7. Tap Unlock apps, choose a number of minutes and tap Unlock (there is a 5-second wait). The app opens normally until the time runs out.

RepToll Pro (unlimited apps, Strict Mode) can be tested with the sandbox account; the paywall appears once at the end of onboarding (closable), when you pick more than 1 app, from the "Go Pro" button on Home, or from Settings ▸ Unlock RepToll Pro.

Screen recording of the full flow: [PASTE LINK]
```

Before submitting: record the flow on a real iPhone, upload it (unlisted YouTube, iCloud link or similar) and replace `[PASTE LINK]`. Also make sure the Family Controls **distribution** entitlement has been approved for all four bundle IDs; without it the build can't be submitted.

## What's New in 1.0 (381 / 4,000)

```
Welcome to RepToll 1.0.

• Lock the apps you doomscroll behind a Screen Time shield
• Earn minutes with push-ups, squats or a plank, counted on-device by your front camera
• Time only ticks inside locked apps; unused minutes come back after a break
• Five difficulty levels, streaks and 7-day stats
• RepToll Pro: unlimited apps, categories and websites, plus Strict Mode
```

## Launch checklist

- [ ] Family Controls distribution entitlement approved (app + 3 extensions).
- [ ] Trademark check: search "RepToll" on the App Store, [USPTO](https://tmsearch.uspto.gov), [EUIPO](https://euipo.europa.eu/eSearch/) and domains before submitting. A Nov 2026 web search found no app with this name; that is not clearance.
- [ ] Screen recording uploaded and linked in the review notes.
- [ ] IAPs and subscription group submitted with the first build; paywall review screenshots attached.
- [ ] Turn on **phased release** (7-day rollout) so a rep-counting or shield bug can be paused before it reaches everyone.
- [ ] Hold off on Apple Search Ads until the app has **20+ ratings**; ads to a page with no ratings convert poorly.
- [ ] Follow-up (not in 1.0): ask for a rating with `requestReview` after the user's **3rd completed workout**, right after the minutes are banked.
