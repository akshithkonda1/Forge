# Forge Watch App — Implementation Plan & Status

> **Core philosophy, everywhere, always:**
> *"You can live your best life and still be healthy — it's just how and
> what advice you follow."*
> Every string, haptic, animation, and ARIA response on the wrist is
> calm, supportive, pattern-focused, and guilt-free. Skipping is data,
> never failure. Low readiness is a rest signal, never a red alarm.

## Vision

The intelligent wrist companion for knowledge workers: workout
coordination, sleep intelligence, lifestyle context, and — as the glue —
a proactive, data-driven **Mindfulness & Meditation Coach**. Apple
Fitness+ polish, Harvee-calm tone, Forge's unified health intelligence,
SimRunner epistemic honesty.

## Architecture

```
ForgeSwift/
├── ForgeCore/                     # Shared Swift Package (iOS 27+ / watchOS 27+)
│   ├── DesignSystem/              # ForgePalette, ForgeDS tokens, ForgeType
│   ├── Models/                    # Readiness (+calculator), LifestyleContext,
│   │                              #   MindfulnessPractice, WatchARIAContext
│   ├── Intelligence/              # MindfulnessSuggestionEngine (pure rules+templates)
│   ├── HealthKit/                 # ForgeHealthQueries (async, non-UI)
│   ├── Utils/                     # WatchSnapshotStore (App Group ⇄ complications)
│   └── Tests/                     # Readiness + suggestion engine unit tests
├── ForgeWatch/                    # watchOS 27 app target
│   ├── Views/                     # HomeView, MindfulnessView, LifestyleContextView
│   ├── Components/                # AuroraOrbWatch, BreathingOrb, ReadinessRing,
│   │                              #   ContextCard, HapticButton
│   ├── Managers/                  # WatchHealthKitManager, ContextEngine,
│   │                              #   MindfulnessSessionManager, ARIAWatchService
│   └── Complications/             # ForgeWatchWidgets extension target:
│                                  #   Readiness, MindfulnessReset, SleepQuality
```

**Data flow:** HealthKit → `WatchHealthKitManager` → `ReadinessCalculator`
(on-device) → `ARIAWatchService` (instant rule/template tier) →
`WatchSnapshotStore` (App Group) → complications reload (<2s). The
backend LLM tier (`/watch/aria/suggest`) only upgrades debrief copy and
never blocks the UI.

**ARIA two-tier strategy:** instant suggestions are deterministic,
on-device, and private; deeper coaching is an optional, token-gated
`URLSession` call with a 10s timeout and a local fallback. Epistemic
honesty is structural: readiness carries a `confidence` value, low
confidence renders as an estimate, and the engine never treats a
low-confidence score as fact (unit-tested).

## Phase status

| Phase | Scope | Status |
|---|---|---|
| 0 | Foundation: watch target, entitlements, ForgeCore package, HealthKit auth | ✅ Done |
| 1 | 3 complications + Home shell (orb, greeting, quick actions) | ✅ Done |
| 2 | Mindfulness Coach MVP: ContextEngine (manual + motion), session manager, BreathingOrb + haptics, suggestion engine, Mindful Minutes logging, skip-with-note | ✅ Done |
| 3 | Workout Coordinator: HKWorkoutSession live metrics + zones, adaptive cues, structured plans + rest timers, post-workout reset handoff, ActiveWorkout complication, iPhone Live Activity (ForgeWidgetExtension + WatchConnectivity) | ✅ Done (this PR) |
| 4 | Sleep Intelligence (SleepSummaryView + story + tonight's plan + WindDownPredictor + factor chips) and ContextEngine v2 (known places, HR cross-signal, predictor-timed wind-down, one notification) | ✅ Done (this PR) |
| 5 | Polish: onboarding, Minimal Animation toggle, a11y sweep, ContextRules extraction + tests, QA checklist | ✅ Done (this PR) — on-device battery/VoiceOver passes tracked in `ForgeWatch/QA_CHECKLIST.md` |
| 6 | Backend: `/watch/aria/suggest` endpoint + iOS→watch config bridge | ✅ Done (this PR) — calendar-density signal, background geofencing, and CloudKit sync remain deferred (see below) |

## Flagship user flows

### 1. Mindfulness during a long coding block (shipped)
1. User sets Desk/Coding (or motion heuristics suggest it, one tap to confirm).
2. After 90 min low movement, `ContextEngine` bumps its revision →
   `ARIAWatchService` re-suggests → snapshot updates → the Mindful Reset
   complication flips to "90s Focus Reset" within seconds.
3. Tap → `MindfulnessView` opens pre-filled (practice, duration, why-text).
4. Begin → `BreathingOrb` (single Canvas, 30fps) + wrist haptics pace each
   phase; works eyes-free, wrist down.
5. Live HR (via a discarded `.mindAndBody` session) feeds a gentle
   biofeedback line ("Heart rate settled ~6 bpm").
6. End → Mindful Minutes written to HealthKit, calm debrief card,
   complications refresh, optional deeper ARIA debrief from backend.
7. Skip at any point → four zero-judgment reasons, warm acknowledgement,
   context recorded for personalization. No streak broken, ever.

### 2. Workout on the wrist (Phase 3)
1. Home shows "Recovery day — Zone 2 recommended" when readiness is low.
2. Start → live HR/zone ring, elapsed, calories; ARIA cues at zone
   boundaries ("Perfect Zone 2 — this is what recovery pace feels like").
3. Rest timers count down haptically; the screen is optional throughout.
4. End → summary → automatic 3-5 min body-scan reset (one tap to skip,
   zero judgment) → workout + mindful minutes saved → debrief card with
   today's-plan update → "Full review on iPhone" handoff.

### 3. Waking up (Phase 4)
1. First wrist-raise after wake: SleepSummaryView — stages timeline lite,
   duration, quality.
2. "Last night's story": two supportive sentences linking sleep
   architecture to today's readiness (no scolding about the short night).
3. "Tonight's plan": one actionable wind-down ("High cognitive load today —
   a 4-min wind-down around 9:30 pm tilts tonight toward deep sleep"),
   scheduled as a gentle evening suggestion + complication update.

## Non-negotiables (enforced in code today)

- **Epilepsy-safe**: no flashing/strobing; the fastest luminance change is
  breath-speed (unit test asserts every breath phase ≥ 1s; orb rings
  wobble at ≤ ~0.15 Hz, low contrast).
- **Reduce Motion**: every animated component has a static or
  opacity-only variant (`accessibilityReduceMotion` checked in
  AuroraOrbWatch, BreathingOrb, ReadinessRing).
- **Always-On**: `isLuminanceReduced` freezes orbs and dims rings into an
  intentional composition.
- **Accessibility**: labels + hints on every control; scores get spoken
  values with supportive descriptors; the breathing guide explains its
  haptic language to VoiceOver users.
- **Battery**: one TimelineView + one Canvas per orb at 30fps; providers
  read a cached App Group struct (no queries in the widget process);
  motion checks every 5 min only while the app is alive.
- **Privacy**: readiness and suggestions computed on-device; the only
  network call is the opt-in debrief upgrade; location strings promise
  "never leaves your device" and Phase 4 must keep that promise
  (geofence evaluation on-device only).
- **Tone**: guilt vocabulary is banned and unit-tested
  (`testEveryRecommendationHasSupportiveNonEmptyReason`).

## Backend (Phase 6 — done)

- `POST /watch/aria/suggest` (`backend/infra/lambda/routes/watch.py` +
  `services/watch_debrief.py`) — accepts `{practice, minutes,
  heartRateSettleBPM, context: WatchARIAContext}` exactly as the watch's
  `Codable` emits it (camelCase, no `keyEncodingStrategy` set), returns
  `{message, trigger}`. Deterministic template tier today (same
  priority-ordered, ≤2-sentence, guilt-free voice contract as
  `MindfulnessSuggestionEngine`); a Bedrock upgrade can sit behind
  `aria_engine.bedrock_enabled()` later with this as the guaranteed
  fallback, matching the `/ai/chat` pattern. No Terraform change needed —
  the existing `ANY /{proxy+}` route already reaches it.
  Auth is soft (`auth.extract_user_id`, Cognito JWT or test-user
  fallback) — `ARIAWatchService.deeperDebrief`'s Bearer token is now
  optional, since no real token store exists yet.
- `ForgeSwift/WatchAriaConfigBridge.swift` mirrors the iOS app's
  `AriaService.baseURL` + `AriaContextStore`'s stable user id into the
  shared App Group on launch and on `setBaseURL`, so the watch's deeper
  call reaches the same backend as the phone.
- Tests: `backend/tests/test_watch_debrief.py` (17 cases — priority branches,
  tone/guilt-word sweep across every branch × biofeedback state, 400s on
  malformed input) plus a manual `dev_server.py` pass (desk-block+HRV-dip,
  low-confidence-never-claims-recovery, malformed-body 400).
- Deferred beyond v1 (not built): full SimRunner archetype integration for
  this endpoint (the pytest suite above covers the same tone/honesty
  rules more cheaply), calendar-density signal, background geofencing,
  CloudKit cross-device sync (HealthKit + App Group + WCSession already
  carry v1 state without it).
