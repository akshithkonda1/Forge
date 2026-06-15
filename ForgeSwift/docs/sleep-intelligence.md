# Forge Sleep Intelligence

Integrated Sleep experience for the Forge iOS app: HealthKit-backed data, chronotype personalization, adaptive sunrise/smart wake, gamification, and local ARIA context (backend wiring deferred).

Built June 2026.

## Architecture

```
HealthKit (sleepAnalysis)
        │
        ▼
HealthKitSleepService ──► chronotype scoring, debt, sunrise, goals
        │
        ├──► AppStore.sleepData (mergeSleepDataLocally — HK wins per date)
        ├──► ForgeSleepProductManager (adaptive sunrise + smart wake)
        └──► SleepView.swift (overview, wake-up, personalization UI)
```

## Files

| File | Role |
|------|------|
| `ForgeSwift/Services/HealthKitSleepService.swift` | Core intelligence layer |
| `ForgeSwift/SleepView.swift` | UI: overview, wake-up, personalization, adaptive cards |
| `ForgeSwift/Models.swift` | `Chronotype`, `UserSleepProfile`, adaptive types |
| `ForgeSwift/ForgePersistence.swift` | Persists `UserSleepProfile` |
| `ForgeSwift/ForgeSleepProductManager.swift` | Applies adaptive sunrise + alarm windows |
| `ForgeSwift/AppStore.swift` | `mergeSleepDataLocally()` |
| `ForgeSwift/HealthKitManager.swift` | Raw HK sleep sample fetch (reused) |

## Chronotypes

| Type | Target sleep | Deep goal | Wake bias | Sunrise |
|------|-------------|-----------|-----------|---------|
| Lion | 7.5 h | 75 min | Early (~6 AM) | 15 min, brighter |
| Bear | 8.0 h | 90 min | Mid (~7 AM) | 20 min, balanced |
| Wolf | 8.5 h | 85 min | Late (~8:30 AM) | 25 min, warmer |
| Dolphin | 7.0 h | 60 min | Sensitive | 30 min, gentle |

## Data flow (Sleep tab open)

1. `AppStore.refreshSleepData(days: 14)` — API/backend nights
2. `HealthKitSleepService.requestAuthorization()` + `fetchRecentSleepData`
3. `AppStore.mergeSleepDataLocally(hkSleep)` — chronotype-scored HK overwrites same dates
4. `computeSleepDebt` + `computeAdaptiveSunrise` → `ForgeSleepProductManager.applyAdaptiveSunrise`
5. Notifications + smart-wake refinement use debt + chronotype

## Personalization

- Tap **Chronotype badge** on Sleep overview → `SleepPersonalizationSheet`
- Pick Lion / Bear / Wolf / Dolphin, optional personality + lifestyle notes
- Saved via `ForgePersistence.saveUserSleepProfile`
- Re-scores recent nights on save

## Adaptive sunrise (Wake Up tab)

`AdaptiveSunriseCard` replaces the static sunrise card. Shows:
- Duration, color temperature (manual override still allowed)
- Rationale string (e.g. sleep debt, low last-night score)

Modifiers:
- `recentScore < 70` → longer, warmer, gentler
- `debt > 3 h` (7-day) → +5 min duration, lower intensity

## Smart wake

`ForgeSleepProductManager` delegates window sizing to `HealthKitSleepService.computeSmartAlarmWindow`:
- Low score → wider window (up to 45 min)
- High score → narrower (down to 15 min)
- Wolf/Dolphin → slightly wider; Lion → slightly narrower

## Gamification (data-driven)

| View | Source |
|------|--------|
| Sleep Goals | `computeAdaptiveGoals` |
| Sleep Debt | `computeSleepDebt` (chronotype target, not fixed 8 h) |
| Breakdown | Chronotype deep/REM goals |
| Recommendations | `chronotypeRecommendations(debt:)` |
| Achievements | `computeAchievements` (streak, deep avg, perfect week) |

## ARIA context (local only)

`HealthKitSleepService.buildARIAContext(sleepData:store:)` produces a structured text block shown in **Sleep AI — ARIA** sheet. Wire to your backend Claude endpoint when ready:

```swift
let context = HealthKitSleepService.shared.buildARIAContext(
    sleepData: store.sleepData,
    store: store
)
// POST to /aria/chat with context prepended to user message
```

## Scoring formula

Per night (0–100), weighted:
- Duration vs chronotype target — 35%
- Deep vs chronotype deep goal — 25%
- REM vs chronotype REM goal — 20%
- Efficiency — 15%
- Consistency placeholder — 5%

## Build & test

```bash
cd ForgeSwift
xcodebuild -project ForgeSwift.xcodeproj -scheme ForgeSwift \
  -destination 'platform=iOS Simulator,name=iPhone 16' build
```

Manual checks:
1. Grant HealthKit sleep access
2. Open Sleep tab — scores/timeline populate
3. Change chronotype — goals and sunrise rationale update
4. Wake Up tab — adaptive sunrise shows rationale
5. Sleep AI sheet — ARIA context block visible when data exists

## Not in scope (yet)

- Backend ARIA endpoint integration
- HomeKit environment sensors (`AISleepEnvironmentView` still static)
- Chronotype onboarding illustrations
- `clients/ios/` duplicate tree (canonical app: `ForgeSwift/`)

## Related

- Health sync to backend: `Sync/HealthSyncCoordinator.swift` (unchanged; uploads raw HK sessions)
- Onboarding HK auth: `OnboardingCoordinator.requestHealthKit()`