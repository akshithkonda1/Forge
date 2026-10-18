# Performance in Forge

Forge's performance work has two halves. **Policy** — caps, shedding and budgets the app must obey — lives in `ForgeRuntimeGuard` and is locked by `ForgeStabilityTests`. **Measurement** — knowing where time actually goes on a device — is `ForgePerf`, an `os_signpost` layer defined in `ForgeCore/Sources/ForgeCore/Perf/ForgePerf.swift`.

This page is about the measurement half: what is instrumented, how to read it, and how to extend it.

## What is instrumented

Everything reports into one subsystem — `com.forge.core` — so the phone app, Watch, widgets and the share extension land in the same trace.

| Category | Instrumented spans |
| --- | --- |
| `launch` | `AppStoreInit` (the state container's init), `appInit` (migration + coordinator activation in `ForgeSwiftApp.init`) |
| `healthkit` | `quantitySamples` (every quantity read funnels through this one query), `refreshSleepCache` (anchor delta, regroup, store), `sleepSegments` |
| `aria` | reserved for ARIA turn spans — none yet; add them at the service boundary when that path stabilizes |
| `store` | `compact` (context-store decay/consolidation — the same work ForgeStabilityTests budgets) |

## Recording a trace

1. Open `ForgeSwift.xcodeproj`, pick the **ForgeSwift** scheme and a real device (signposts from the simulator are real but timings are not representative).
2. Product → Profile (⌘I) → choose the **os_signpost** instrument (Time Profiler's companion — or add the Signposts instrument to any trace).
3. Run the flow you care about (cold launch, Sleep tab open, a chat turn), stop, then filter by subsystem `com.forge.core` in the signpost track.
4. The categories above are the tracks; each interval name is one operation. Durations are in the track's table view.

Console also works without Instruments: filter a device's live log stream by the subsystem.

## Rules for adding spans

- Names are `StaticString` — no interpolation, no string building. If you need to attach a *count* (how many samples a query fetched), that is a size, not a value, and may appear in an event name. **Never** put health values or user text in a name or event: signposts are durations and structure only, because traces are exportable and health data is not.
- Wrap the work with `ForgePerf.measure(_:category:_:)` (sync or async) when the work is one block. Use `ForgePerf.begin` / `Span.end()` — with a `defer` — when the block has multiple exits or you need the span to cross an `await` you don't own.
- Prefer instrumenting funnels (one shared query helper, one refresh entry point) over individual call sites — one span at the funnel covers every caller.
- Signposts are compiled in but effectively free when nothing is recording; do not add feature flags or debug-only wrappers around them.
- Don't assert wall-clock durations in unit tests. Budgets belong in `ForgeStabilityTests` (e.g. `storeCompactBaselineSeconds`) on a controlled input; CI Macs are too noisy for timing assertions.

## Related performance infrastructure

- **Policy:** `ForgeRuntimeGuard` + `ForgeStabilityTests` — Hz caps, thermal/memory shedding, store budgets.
- **Backend load testing:** `backend/loadtest/` — k6 harness against a locally started Dummy backend (never AWS), with limiter and capacity ramp scenarios. See `backend/loadtest/README.md`.
- **ARIA offline evaluation:** `backend/ai/simrunner` — the CI gate for coaching changes (`python -m backend.ai.simrunner --all --gate`).
