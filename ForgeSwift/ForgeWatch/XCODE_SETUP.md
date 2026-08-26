# ForgeWatch — Xcode Setup & Verification

The `ForgeWatch` (watchOS app) and `ForgeWatchWidgets` (complications
extension) targets are **already wired into `ForgeSwift.xcodeproj`**, along
with the local `ForgeCore` Swift Package. This doc covers what to check on
first open, and how to recreate the targets manually if anything looks off.

## First open checklist

1. **Install the watchOS platform** if Xcode prompts for it
   (Settings → Platforms / Components → watchOS). The iOS app embeds the
   watch app, so the **watchOS SDK is required** to build `ForgeSwift`.
2. Open `ForgeSwift/ForgeSwift.xcodeproj` (not only the nested iOS folder).
   You should see four targets: `ForgeSwift`, `ForgeWatch`,
   `ForgeWatchWidgets`, `ForgeWidgetExtension`, plus the `ForgeCore` package.
3. Shared schemes available:
   - **ForgeSwift** — iPhone app (builds + embeds ForgeWatch companion)
   - **ForgeWatch** — watch app (also builds the iPhone companion target)
4. **Signing**: all targets use automatic signing with team `L85K85Q7MB`.
   Xcode will provision on first build:
   - `com.forge.ForgeSwift` (iPhone)
   - `com.forge.ForgeSwift.watchkitapp` (Watch)
   - `com.forge.ForgeSwift.watchkitapp.widgets` (Watch complications)
   - `com.forge.ForgeSwift.widgets` (iOS extension)
5. **Capabilities** (checked-in entitlements): HealthKit + App Groups
   (`group.com.forge.ForgeSwift`) on iPhone + Watch. Register the App Group
   on the developer portal the first time if Xcode flags it.
6. Run **ForgeCore** tests: `swift test` inside `ForgeSwift/ForgeCore`.

## Run as a true iPhone + Watch companion (recommended)

Standalone “Watch only” destinations work for UI, but **companion features**
(WatchConnectivity, Live Activity push from phone, App Group pairing) need a
**paired** iPhone + Watch.

### Simulator pair

1. Xcode → **Window → Devices and Simulators → Simulators**.
2. Pick an **iPhone 16 / 17** (or similar) that supports pairing.
3. Click **+** under the phone’s “Paired Watches” (or File → New Simulator
   with a Watch device), e.g. **Apple Watch Ultra 2 (49mm)** or Series 10.
4. Wait until the pair shows as ready (both booted once helps).

### Install companion build

**Option A — install both via iPhone scheme (best for “companion”)**

1. Scheme: **ForgeSwift**
2. Destination: the **paired iPhone** (not “Any iOS Device”)
3. Run (⌘R)
4. Xcode embeds `ForgeWatch.app` into the iPhone build (`Embed Watch Content`).
5. On the paired Watch simulator: open the **ForgeWatch** app (or it may
   auto-install). Check the Watch home screen.

**Option B — launch the watch scheme against the pair**

1. Scheme: **ForgeWatch**
2. Destination: **iPhone XX + Apple Watch YY** (compound destination)
3. Run (⌘R)
4. Debugger attaches to the **watch** process; phone app is still built/installed.

### Verify the link is alive

- Both apps signed with the **same team**.
- Bundle IDs:
  - Phone: `com.forge.ForgeSwift`
  - Watch: `com.forge.ForgeSwift.watchkitapp`
  - Companion key on watch: `WKCompanionAppBundleIdentifier = com.forge.ForgeSwift`
- App Group on **both**: `group.com.forge.ForgeSwift`
- Start a watch workout → iPhone should receive Live Activity updates via
  `PhoneLinkService` / WatchConnectivity (phone must be running in sim).

### Physical Watch

1. iPhone unlocked, Watch unlocked, Developer Mode on (Settings → Privacy &
   Security → Developer Mode).
2. Select your **iPhone** as the ForgeSwift run destination (not the Watch alone).
3. Run ForgeSwift — Xcode installs iPhone app + pushes the watch companion.
4. Trust the developer certificate on both devices if prompted.

## Common “can’t test companion” failures

| Symptom | Fix |
|---|---|
| No ForgeWatch target / files missing | You’re on an old branch. Use latest `claude/forge-fitness-frontend-TwlOQ` (or mainline with PR #85). |
| “Unable to find module dependency: watchOS” | Install watchOS platform in Xcode Settings → Platforms. |
| Only iPhone destinations | Product → Destination → show Watch pair; create a paired Watch sim. |
| Watch app never appears after iPhone run | Clean build folder, delete both apps from sims, re-run **ForgeSwift** on the paired iPhone. Confirm Embed Watch Content phase is on ForgeSwift. |
| WatchConnectivity never connects | Both processes must be installed from the **same build**; launch phone app once, then watch. |
| Signing / App Group errors | Same Development Team on all 4 targets; enable App Groups capability for group.com.forge.ForgeSwift. |
| HealthKit permission never shows | Run on Watch destination at least once; grant Health on the watch (not only iPhone). |
| App Group empty on Watch sim | **Expected** on many simulator pairs. Config is also pushed over **WatchConnectivity** (`WatchAriaConfigBridge` → `PhoneLinkService`). Launch **iPhone app first**, then Watch. |

## Xcode click-path (TL;DR)

```
1. Open ForgeSwift/ForgeSwift.xcodeproj
2. Scheme menu → ForgeSwift
3. Destination → paired iPhone (with Watch underneath it in the list)
4. ⌘R  (builds iPhone + embeds ForgeWatch)
5. On Watch sim: open ForgeWatch
6. Optional second launch: scheme ForgeWatch → "iPhone + Watch" destination → ⌘R
   to attach the debugger to the watch process
```

## What “and then some” companion plumbing does

- **Shared schemes**: `ForgeSwift` builds/embeds Watch; `ForgeWatch` scheme is checked in.
- **WCSession config sync**: phone pushes `baseURL` / `userId` / first name on activate + when the watch becomes reachable (simulator-friendly).
- **Watch receives config** in `PhoneLinkService` and writes App Group + standard defaults so ARIA deeper coaching can hit the same backend.
- **Live Activity path** remains `PhoneLinkService` (watch) → `WorkoutActivityCoordinator` (phone).

## Verification pass (Phase 0-2 acceptance)

- Launch ForgeWatch in the simulator → HealthKit permission sheet appears
  with the calm, specific usage strings.
- Home shows the orb + ring; with no Health data the ring shows an honest
  empty state ("still gathering today's signals"), never a fake score.
- Start a 90s Physiological Sigh: orb animates ~30fps, wrist haptics mark
  each phase (Simulator → I/O → Haptics to observe), pause/resume works,
  ending writes a Mindful Minutes sample (check the Health app on the
  paired iPhone simulator).
- Add the three Forge complications to a watch face; tap the Mindful Reset
  complication → app opens directly into the pre-filled session.
- Toggle "Reduce Motion" in watch Settings → Accessibility: orbs switch to
  the static/opacity variants.
- VoiceOver: every control reads a meaningful label + hint.

## Manual target recreation (fallback only)

If the project file is ever rebuilt from scratch:

1. File → New → Target → **watchOS → App**, name `ForgeWatch`, bundle ID
   `com.forge.ForgeSwift.watchkitapp`, "Watch App for Existing iOS App"
   (companion: `com.forge.ForgeSwift`), deployment target **watchOS 27.0**.
   Delete the template ContentView/App files and add everything under
   `ForgeWatch/` (except `Complications/`) to the target.
2. File → New → Target → **watchOS → Widget Extension**, name
   `ForgeWatchWidgets`, embed in ForgeWatch, deployment 27.0. Delete the
   template widget and add the files under `ForgeWatch/Complications/`.
3. Add the local package: File → Add Package Dependencies → Add Local →
   select `ForgeSwift/ForgeCore`; link the `ForgeCore` product to **both**
   watch targets.
4. Point each target's Code Signing Entitlements at the checked-in
   `.entitlements` files; set the widget target's `INFOPLIST_FILE` to
   `ForgeWatch/Complications/Info.plist`.
5. Add the Info.plist keys on the ForgeWatch target (as INFOPLIST_KEY_
   build settings): `NSHealthShareUsageDescription`,
   `NSHealthUpdateUsageDescription`, `NSLocationWhenInUseUsageDescription`,
   `NSLocationAlwaysAndWhenInUseUsageDescription`,
   `WKRunsIndependentlyOfCompanionApp = YES`.

## Notes

- Location entitlement strings ship now; `CLLocationManager` wiring lands
  in Phase 4 (ContextEngine is manual + motion-based until then).
- The widget extension performs no HealthKit queries — complications read
  the App Group snapshot written by the app (see `WatchSnapshotStore`).
- The `.mindAndBody` workout session used for live HR biofeedback is
  discarded after each mindfulness session on purpose: only Mindful
  Minutes are saved to Health.
