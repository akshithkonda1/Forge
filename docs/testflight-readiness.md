# TestFlight readiness gap audit

**Issue:** [#364](https://github.com/akshithkonda1/Forge/issues/364) — WS2 iOS TestFlight-ready build with premium Oura/Whoop-grade UI  
**Branch / PR:** this document ships with the Home premium design pass (draft only)  
**Audited tip:** `main` at `7f69323` (plus this branch)  
**Coordinate with:** open draft [#360](https://github.com/akshithkonda1/Forge/pull/360) (Akshith’s TestFlight draft). Do not restage that PR’s files.

Locks this audit respects: procedural Nest brand (`AriaNest*`); ring-field only for Home readiness data; no PNG brand mark; friend-coach tone (never “recovery week” / “recovery-first”); Dummy ARIA remains the shipped default; no live Bedrock.

---

## How to read this

Items are ranked **TestFlight blockers first**, then **quality**. A blocker is something that stops an external TestFlight build, App Review, or install. Quality items can ship internally but will not feel Oura/Whoop-grade.

Status key: **BLOCKER** · **FLAG (Akshith)** · **QUALITY** · **CLEAN** · **OWNED BY #360**

---

## 1. TestFlight blockers

| # | Item | Status | Owner | Notes |
|---|------|--------|-------|-------|
| B1 | Hosted privacy-policy URL | **BLOCKER / FLAG (Akshith)** | Akshith | `ForgeLegalConfig.privacyPolicyURLString` in `SettingsPageView.swift` is `""`. Settings shows a **“Privacy Policy — Required”** badge. App Store Connect requires a public HTTPS privacy-policy URL for **external** TestFlight. There is no privacy-policy document in this repo to host. Do not invent a URL. |
| B2 | iOS / watchOS 27.0 deployment target | **BLOCKER** | Follow-up (toolchain) | Every native target pins `IPHONEOS_DEPLOYMENT_TARGET` / `WATCHOS_DEPLOYMENT_TARGET` to `27.0`. Testers not already on the newest OS cannot install. #360 tried lowering to 26.0, hit compile-time `#if compiler(>=6.4)` gates in `SleepSoundEngine.swift` / `SpeechManager.swift` (one stored-property type switch), and reverted. Needs an Xcode-equipped pass. |
| B3 | `NSAppleMusicUsageDescription` placeholder | **OWNED BY #360** | #360 | `project.pbxproj` still has *“This allows users to access the vast libraries of Apple Music ”* on `main`. #360 replaces it with first-person coach copy. Do not restage that string here. |
| B4 | Push entitlement is `development` | **BLOCKER** (if remote notifications are used) | Signing | `ForgeSwift.entitlements` sets `aps-environment` = `development`. Cycle CloudKit share wake-ups need **production** for a TestFlight/App Store archive. Xcode usually rewrites this on archive; confirm on the exported IPA. |
| B5 | No `ExportOptions.plist` / archive pipeline | **BLOCKER** (process) | Akshith / CI | Repo has no export options, no Fastlane, no `xcodebuild -exportArchive` recipe. Archive is a local Xcode step. Team ID `L85K85Q7MB`, Automatic signing, bundle IDs `com.forge.ForgeSwift` (+ `.watchkitapp`, `.widgets`, `.messages`). Confirm App Store Connect app record, devices, and provisioning before the first upload. |
| B6 | `main` CI is red for inherited reasons | **OWNED BY #351 / #352** | Those PRs | Tip is red for SwiftPM sources list (`PromptGuardTests.swift` missing from `ForgeCoreTests`) and SimRunner. #360 also carries the Package.swift one-liner. **Do not fix those in this PR.** Dummy-offline TestFlight does not wait on SimRunner quality. |
| B7 | #360 rebase / merge | **FLAG** | Akshith | #360 is the CTO TestFlight draft (hygiene + Apple Music string + catalog URL sanitization). Rebase onto tip after #351/#352, then this Home PR. Scopes do not overlap if that order is kept. |

### Not blockers (confirmed clean)

| Item | Status | Evidence |
|------|--------|----------|
| Shipped API host | **CLEAN** | `Info-Add.plist` `FORGEAPIBaseURL` is empty. No `127.0.0.1` / `localhost` in the committed ship plist. Loopback exists only as `ForgeAuthConfig.defaultLocalAPI` (dev default), guards, tests, and `scripts/generate_client_config.py`. |
| Dummy ARIA default | **CLEAN** | `FORGEEnvironment` = `dummy`. Empty Cognito ids. `AriaService` routes to `AriaDummyOrchestrator`. Bedrock stays off. Matches the Dummy ship-gate. |
| Privacy manifests | **CLEAN** (structure) | `PrivacyInfo.xcprivacy` present on iPhone, Watch, Widget, Messages. Tracking `false`. UserDefaults reasons declared. Collected types: Health, Fitness, Email, UserID, OtherUserContent (iPhone); Health/Fitness/UserID (Watch); none (Widget). |
| Health / camera / mic / speech / calendar / location / contacts usage strings | **CLEAN** (copy quality) | First-person, specific, on-device promises. Duplicated in `Info-Add.plist` and `INFOPLIST_KEY_*` so a missing merge cannot ship a blank string. Watch also has motion + always-location. |
| Clinical records usage | **CLEAN** (declared) | Share + usage strings exist; tests lock them. App Review will still read them — keep the “names and dates only / nothing leaves this iPhone” promise honest. |
| Localhost in Release | **CLEAN** | `ForgeAuthTests` asserts production config must not contain loopback. Generator `--check` refuses dummy-offline loopback. |

---

## 2. Quality gaps (after the build can install)

Ranked by user-visible impact on a TestFlight first session.

| # | Item | Status | Surface | Notes |
|---|------|--------|---------|-------|
| Q1 | Home readiness hierarchy | **This PR** | Home | Live hero was three Whoop-style dials. The unused `HomeHeroReadinessCard` held a generic ring. Brand lock: **ring-field is Home readiness data language**; Nest is the ARIA mark. This PR makes `AriaRingFieldGeometry` the hero (≥90pt, five ellipses), with vitals as supporting metrics. |
| Q2 | Home trend chart | **This PR** | Home | `HomeTrendSection` hid Swift Charts behind expand and showed “Not enough data” with no coach empty state. Now always-on sparkline + expand, average rule, loading/empty, VoiceOver summary. Same sleep-score mapping (3+ nights, clamp 30–100). |
| Q3 | Typography / spacing / Dynamic Type | **This PR (Home)** | Home | Home used mixed `.system(size:)` literals. `FDS.TypeScale` and `ForgeTypography` do not scale. This PR adds `FDS.TypeScale.Dynamic` + `HomeType` and applies them on Home. Other tabs still use fixed sizes. |
| Q4 | Reduce Motion on Home entrance / charts / streaks | **This PR** | Home | Aurora, ring, and vitals already froze. `homeEntrance`, streak-cell stagger, and chart grow-from-zero did not. They do now. |
| Q5 | VoiceOver on Home | **This PR** | Home | Header / CTA / vitals were partial. Field, trend, agenda rows, win card, and secondary actions now have labels/hints. |
| Q6 | “Recovery-first” Home copy | **This PR** | Home | `HomePrimaryAction` said “Recovery-first day…”. Banned by lock. Now friend-coach “Easy session” / “Keep today light.” Enum case `recoveryDay` is internal only. |
| Q7 | Sleep tab polish | **QUALITY** | Sleep | Night / alarm / sounds / wake are feature-rich. Empty night uses `ForgeEmptyStateCard`. Charts and type still feel denser than Oura Sleep. Wake hold-to-dismiss is strong. Next dedicated PR. |
| Q8 | Train tab polish | **QUALITY** | Train | Suggestion box + habit learner + sports shelf recently landed. Empty / active / summary exist. Intensity chrome and exercise rows are not yet Oura/Whoop-grade. |
| Q9 | Lifestyle tab polish | **QUALITY** | Lifestyle | Nutrition / wellbeing / lifetime / places. Has Charts and empty cards. Spacing and type drift from Home tokens. |
| Q10 | Chat polish | **QUALITY** | Chat | Empty state is already atmospheric (Nest mark). Message list, rich cards, and input chrome need a calm pass. Dummy ARIA stays default. |
| Q11 | Onboarding / auth | **QUALITY** | Onboarding | Interview + Forge prep + age-gate (13+). DEBUG skip only. Age-blocked is clinical-legal, not coach. Reduce Motion on interview voice delay exists; ambient motion should be audited on-device. |
| Q12 | Settings / You | **QUALITY** | Settings | Hero + destinations grid is dense. Privacy row is honest about the missing URL. Backend URL editor is a tester foot-gun — keep Dummy as default; do not expose a live Bedrock toggle in TestFlight. |
| Q13 | Watch Home | **QUALITY** | Watch | Glanceable, strong VoiceOver. Readiness is nest orb + `ReadinessRing`, **not** the phone ring-field. Compact Watch sizes are allowed to stay 3-ring compact (`AriaRingFieldGeometry.visibleRingIndices`). Dedicated PR should paint ring-field for score, Nest for ARIA only. |
| Q14 | Widgets / Live Activities / StandBy | **QUALITY** | Widgets | Shared `WidgetChrome` + App Group snapshot. Placeholders exist. Empty Support glance is good. StandBy uses Nest face (correct — brand, not readiness). Lock Screen / home-screen type is still caption-sized fixed. |
| Q15 | Three readiness palettes | **QUALITY** | Home / Chat / Theme | `HomeReadiness` (Peak/Good/Fair/Low · vitality/ember/steel/alert), `Theme+Readiness` (Primed/Ready/Moderate/**Recovery** · success/steel/warning/danger), ForgeCore `ReadinessBand`. Unifying is a design decision, not a drive-by. Home keeps its own words; Theme’s “Recovery” label is a later copy pass. |
| Q16 | `AriaLogo.png` still in the catalog | **QUALITY / retire** | Assets | `Assets.xcassets/AriaLogo.imageset/AriaLogo.png` (~505 KB). Chime still names asset `"AriaLogo"` (`AriaWelcomeChime`). Live UI mark is procedural Nest. **List for retirement** once the chime uses a generated frame or silence. Do not add new raster brand assets. |
| Q17 | Dead Home hero card | **QUALITY** | Home | `HomeHeroReadinessCard` is unused. Leave it this PR; delete in a cleanup once the ring-field hero has soaked. |
| Q18 | Chat empty “Recovery is part of training” | **QUALITY** | Chat | Coach-ok, not the banned phrase. Fine to keep; optional soften on the Chat PR. |
| Q19 | Core “recovery-first session” strings | **QUALITY** | ForgeCore / backend | `WorkoutSuggestionEngine` and Lambda `workout_suggestion.py` still say “recovery-first session”. Not on Home. Do not change in this PR (could overlap coaching contracts). Follow-up copy PR. |
| Q20 | Dynamic Type / large text on Watch & widgets | **QUALITY** | Watch, Widgets | Almost no `@ScaledMetric` / text-style fonts. Watch has little room; still needed for Digital Crown + accessibility sizes. |
| Q21 | On-device VoiceOver / Reduce Motion matrix | **QUALITY** | All | Watch `QA_CHECKLIST.md` exists. iPhone has no equivalent device matrix. Tess should run one before external testers. |
| Q22 | Messages extension | **QUALITY** | iMessage | Invite bubbles have labels. Privacy manifest is present. Not a TestFlight install blocker. |
| Q23 | Marketing version `1.0` / build `1` | **FLAG** | Signing | Fine for first TF; bump `CURRENT_PROJECT_VERSION` per upload. Display name `"Forge "` has a trailing space — tidy later, not a blocker. |

---

## 3. Screen and flow inventory

### 3.1 Onboarding and auth

| Flow | Files | Empty | Loading | Error | A11y |
|------|-------|-------|---------|-------|------|
| Welcome / sign-in / sign-up | `AuthWelcomeView`, `AuthSignInView`, `AuthSignUpFlowView` | Auth empty fields only | Progress on submit | Inline field errors | Partial VoiceOver; Nest mark on welcome |
| Interview onboarding | `OnboardingView`, `OnboardingCoordinator`, `AriaInterviewLayout`, `AriaForgePrepView` | Age-blocked (≥13) | `isPrepping` / `needsForgePrep` | Age block + reset | Reduce Motion on interview voice; ambient bloom not fully frozen |
| Health permissions | HealthKit prompt via usage strings; `DataPermissionsView` | Denied path exists | Pulling… | `authorizationErrorMessage` / ingest error | Usage strings are shippable |

**Gap:** no illustrated “why Health” interstitial at Oura quality. Denied Health still reaches Home with sample-pack / offline pills (good). Prep screen should stay Dummy.

### 3.2 Home

| Block | Files | Empty | Loading | Error | A11y |
|-------|-------|-------|---------|-------|------|
| Greeting + Health pill | `HomeView` / `HomeHeaderView` | Offline pill, tap to reconnect | “Pulling…” / “Reconnecting…” | Ingest warning + cloud sync error | Header traits; pill hint |
| Readiness hero | `HomeHeroCards` + `HomeReadinessViews` | Status line + easy-session CTA when score is 0 | Refresh is pull-to-refresh only | Same ingest line | **This PR:** ring-field label, vitals, CTA |
| ARIA briefing | `HomeARIABriefingCard` | Compact when quiet mode | — | — | Mark is `accessibilityHidden` inside identity; card has copy |
| Cycle / support | `HomeCycleModule` | Hidden when no consent / entry always shown | — | — | Partial |
| Lifestyle preview / widgets / agenda / win / day tiles / streak | `HomeCards`, `HomeWidgetBoard` | Widget empty copy; win “Nothing logged yet” | — | — | **This PR** fills gaps |
| 7-day signal | `HomeTrendSection` | Coach empty (this PR) | Skeleton when `dataLoadState == .loading` (this PR) | Relies on header ingest | VoiceOver series summary (this PR) |

Pull-to-refresh calls `AppStore.refreshDailyData(force:)`. Dummy / test-ready pack is explicit in the status pill (“Sample data · connect Apple Health”).

### 3.3 Sleep

| Tab | Empty | Loading | Error | Notes |
|-----|-------|---------|-------|-------|
| Night | `ForgeEmptyStateCard` — does not ask ARIA when there is no night (`HealthKitSleepService.dayEmptyCopy`) | `SleepSurfacePresence` keys off load + empty | Health offline | Strong empty copy |
| Alarm / sounds / wake | Configured vs none | Sound engine load | Audio session | Reduce Motion on wake orb; iOS 27 audio taps are the deploy-target trap (B2) |
| Energy schedule | Sheet | — | — | Secondary |

Quality: stage bars and insight cards are good; 14/30-day trend is not Oura-grade yet.

### 3.4 Train

| State | Treatment |
|-------|-----------|
| No plan | `WorkoutEmptyState` + write-session CTA |
| Plan ready | Suggestion box + habit learner + sports shelf |
| Active | `ActiveWorkoutView` + Live Activity |
| Summary | `WorkoutSummaryView` |
| History | `ForgeEmptyState` |
| Library | `ContentUnavailableView` |

Quality: set rows and rest timer are functional, not premium. Watch workout coordinator is further along on VoiceOver.

### 3.5 Lifestyle

Nutrition / restaurants / wellbeing / lifetime / places / hydration / cooking. Loading skeleton when `dataLoadState == .loading && !hasMeaningfulLifeSignal`. Empty card when Health is offline. Charts exist in wellbeing + health cards. Places use location usage string. QoL band colors need to stay non-clinical.

### 3.6 Chat (ARIA)

`ChatEmptyStateView` + `MessageListView` + input + voice orb. Empty is already Nest-hero and coach-toned. Generating state exists. Errors surface as assistant text (Dummy never “connection drop” for wobble — prompt guard on live path). **Dummy stays default.** Do not add a TestFlight Bedrock toggle.

### 3.7 Settings / You / Stats

`ProfileTabView` → `SettingsPageView`, editors, devices, data permissions, about, memory vault. Stats: `ProgressPageView` with skeleton + empty cards. Privacy row is the B1 badge. “What ARIA sees” inspector is good for testers.

### 3.8 Watch

Home / onboarding / sleep / workout / mindfulness / lifestyle / week. `QA_CHECKLIST.md` + `XCODE_SETUP.md`. Reduce Motion and Minimal Animation are first-class on orbs. Complications have labels. Companion independence banner when phone is missing. Location never leaves the watch (manifest comment is accurate).

### 3.9 Widgets and Live Activities

Today, Readiness, Hydration, Sleep, Cycle, Support, Lifestyle, StandBy nest. `HomeWidgetSnapshot` App Group contract is tested in ForgeCore. Placeholders use `.preview`. Empty Support glance is coach-toned. Live Activities: workout + fertile window, with labels.

---

## 4. Permissions and usage-description strings

Shipped on iPhone (`Info-Add.plist` + `INFOPLIST_KEY_*`):

| Key | Quality |
|-----|---------|
| `NSHealthShareUsageDescription` | Good, specific |
| `NSHealthUpdateUsageDescription` | Good |
| `NSHealthClinicalHealthRecordsUsageDescription` | Good, narrow |
| `NSHealthClinicalHealthRecordsShareUsageDescription` | Same text as usage — acceptable |
| `NSCalendarsFullAccessUsageDescription` | Good; demo-calendar honesty |
| `NSCalendarsUsageDescription` | Older “busy windows” variant in pbxproj — slightly diverges from Full Access; align later |
| `NSCameraUsageDescription` | Good (meds + barcodes, on-device) |
| `NSContactsUsageDescription` | Good |
| `NSLocationWhenInUseUsageDescription` | Good (Maps meals) |
| `NSMicrophoneUsageDescription` | Good |
| `NSSpeechRecognitionUsageDescription` | Good |
| `NSAppleMusicUsageDescription` | **Placeholder on main** — #360 |

Watch extras: always-location + motion. No `NSPhotoLibrary*` / Bluetooth usage strings — confirm no API calls that would reject the build.

---

## 5. Privacy manifest and legal

### `PrivacyInfo.xcprivacy` (iPhone)

- `NSPrivacyTracking` false; no tracking domains.
- Accessed API: UserDefaults `CA92.1` only.
- Collected: Health, Fitness, Email, UserID, OtherUserContent — all linked, not used for tracking, purpose App Functionality.

**Gaps (quality, not instant reject):** File Timestamp / System Boot Time / Disk space are not declared. Audit any `getattrlist` / `stat` / `Date()` boot math before a later iOS if App Store starts flagging. Widget and Messages manifests are thinner (correct if they do not collect).

### `privacyPolicyURLString`

```swift
static let privacyPolicyURLString = ""
```

**Akshith:** host a real policy (HTTPS, public, matches the manifest: Health, Fitness, account identifiers, chat content, on-device Health records, CloudKit cycle shares, no sale). Paste the URL into `ForgeLegalConfig`. Until then, external TestFlight cannot be enabled.

---

## 6. Signing, export, config

| Setting | Value | Gap |
|---------|-------|-----|
| Team | `L85K85Q7MB` | Confirm App Store Connect membership |
| Style | Automatic | Fine for TF; document who archives |
| Bundle IDs | `com.forge.ForgeSwift` + extensions | Must exist in the portal |
| Entitlements | HealthKit (+ records, background), MusicKit, CloudKit, App Group, aps | `aps-environment` development |
| Version | 1.0 (1) | Bump build each upload |
| Deploy | 27.0 | B2 |
| `FORGEEnvironment` | `dummy` | Correct |
| `FORGEAPIBaseURL` | empty | Correct — no loopback |
| ExportOptions | missing | Add `method: app-store` when CI exists |
| Capability: Health Records | entitled | Matches usage strings |

`scripts/generate_client_config.py --dummy-offline` is the TestFlight-safe plist path. A live archive is a later cutover (WS1), not this ship.

---

## 7. Reduce Motion, VoiceOver, Dynamic Type

| Area | Reduce Motion | VoiceOver | Dynamic Type |
|------|---------------|-----------|--------------|
| Home aurora / field / vitals | Yes (this PR completes entrance + chart + streak) | Yes on hero, trend, agenda (this PR) | Home tokens now text-style based; other Home chips still mix |
| Sleep / Train / Lifestyle / Chat | Partial (orbs, some sheets) | Partial | Mostly fixed `size:` |
| Settings | Low motion need | Rows unlabeled in places | Fixed |
| Watch | Strong (orbs, AOD, Minimal Animation) | Strong | Weak |
| Widgets | N/A / still | Labels on most | Weak |
| Splash / auth | Partial | Partial | Weak |

`FDS.adaptiveAnimation` exists but is rarely used. Prefer `@Environment(\.accessibilityReduceMotion)` at the view, as Home now does.

---

## 8. Brand and copy locks (audit)

| Lock | Tip state |
|------|-----------|
| Nest mark procedural, no PNG brand | Live UI uses `AriaNest*` / `AuroraOrbView`. `AriaLogo.png` remains for the welcome chime asset name — **retire later**. |
| Ring-field only for Home readiness | Geometry lives in `AriaRingFieldGeometry`. This PR is the first phone Home paint path. Watch still uses nest+ring. |
| Friend-coach, no clinical copy | Home easy-day copy fixed here. Theme label “Recovery” and Core/backend “recovery-first session” remain. |
| Never “recovery week” / “recovery-first” | Tests in this PR lock Home CTA copy. Memory tests already ban “recovery week”. |
| Dummy ARIA default | Unchanged. |

---

## 9. Overlap with #360 (do not touch)

#360 files: `ForgeCore/Package.swift` (PromptGuardTests line), `project.pbxproj` (Apple Music string only after revert), `dummy_orchestrator.py`, `test_nyx_eval_gates.py`, `routes/devices.py`, `test_backend_handler.py`, `ARIA_INTELLIGENCE_PLAN.md`.

This PR: `docs/testflight-readiness.md` + Home Swift + existing `TrainSleepUsableTests.swift`. No Package.swift, no pbxproj, no backend.

---

## 10. Suggested next PRs (one surface each)

See the Home PR body for the same list. Short form:

1. **Sleep** — night hierarchy, stage chart, empty/loading, Dynamic Type, Reduce Motion.
2. **Train** — idle / active / summary chrome; keep suggestion engine contracts.
3. **Lifestyle** — wellbeing charts + QoL hero; same tokens as Home.
4. **Chat** — empty already good; message rhythm + rich cards; Dummy stays.
5. **Onboarding** — Health why-screen + motion freeze; no graph changes.
6. **Settings + legal** — wire Akshith’s URL; tidy Privacy row; no Bedrock toggle.
7. **Watch Home** — ring-field for score, Nest for ARIA; compact 3-ring rule.
8. **Widgets** — snapshot empty/error, type, StandBy Nest-only.

Parallel (not UI): deploy-target 26.x with real `@available` (B2); `ExportOptions.plist`; retire `AriaLogo.png`; unify readiness vocabulary after a design call.

---

*Audit is a snapshot of tip + this Home pass. Re-run the blocker table after #351, #352, and #360 land.*
