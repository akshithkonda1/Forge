# ForgeWatch — Xcode Setup & Verification

The `ForgeWatch` (watchOS app) and `ForgeWatchWidgets` (complications
extension) targets are **already wired into `ForgeSwift.xcodeproj`**, along
with the local `ForgeCore` Swift Package. This doc covers what to check on
first open, and how to recreate the targets manually if anything looks off.

## First open checklist

1. **Install the watchOS platform** if Xcode prompts for it
   (Settings → Components → watchOS). The iOS app now embeds the watch app,
   so the watchOS SDK is required to build `ForgeSwift`.
2. Open `ForgeSwift/ForgeSwift.xcodeproj`. You should see four targets:
   `ForgeSwift`, `ForgeWatch`, `ForgeWatchWidgets`, `ForgeWidgetExtension`
   (iOS widgets + workout Live Activity), plus the `ForgeCore` package in
   the navigator.
3. Select the **ForgeWatch** scheme → a watchOS Simulator → Run.
4. **Signing**: all targets use automatic signing with team `L85K85Q7MB`.
   Xcode will provision the new bundle IDs on first build:
   - `com.forge.ForgeSwift.watchkitapp`
   - `com.forge.ForgeSwift.watchkitapp.widgets`
   - `com.forge.ForgeSwift.widgets` (iOS extension)
5. **Capabilities** (already in the checked-in entitlements): confirm
   Xcode shows HealthKit + App Groups (`group.com.forge.ForgeSwift`) for
   ForgeWatch, and App Groups for ForgeWatchWidgets. The App Group must
   also be registered on the developer portal the first time.
6. Run the **ForgeCoreTests** package tests: ⌘U with the ForgeCore scheme,
   or `swift test` inside `ForgeSwift/ForgeCore` on macOS.

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
   (companion: `com.forge.ForgeSwift`), deployment target **watchOS 10.0**.
   Delete the template ContentView/App files and add everything under
   `ForgeWatch/` (except `Complications/`) to the target.
2. File → New → Target → **watchOS → Widget Extension**, name
   `ForgeWatchWidgets`, embed in ForgeWatch, deployment 10.0. Delete the
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
