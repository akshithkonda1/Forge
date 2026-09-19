# Simulators

Forge is developed against **iOS 27** (Xcode 27) and the paired **watchOS 27**
simulator. iOS 26.5 remains installed locally for regression checks; the
deployment target is 27.0.

CI uses the `xcode-27` GitHub-hosted image and still builds a generic
iOS / watchOS Simulator destination so it does not need a booted device.
Locally:

```bash
xcrun simctl list runtimes
# pick iPhone + iOS 27 (and a paired Apple Watch on watchOS 27)
```

Do not lower the bar to an older Health / MapKit / CloudKit surface just to
make an old simulator happy.

## Reset / erase (do not hang on `simctl`)

`xcrun simctl` can block forever when CoreSimulatorService is wedged. Do **not**
run a bare `simctl erase` from a shell you need back. Use:

```bash
# Erase the iOS 27 iPhone Forge develops against (or pass a UDID)
./ForgeSwift/Scripts/reset-simulator.sh
./ForgeSwift/Scripts/reset-simulator.sh 29B53C96-6BE3-4A79-991C-C652E44650FD

# If every simctl command hangs:
./ForgeSwift/Scripts/reset-simulator.sh --unwedge
```

The helper times out, shuts the device down, and retries after killing
`com.apple.CoreSimulator.CoreSimulatorService`. After erase, boot the iPhone
in Xcode and ⌘R **ForgeSwift**. Connect Apple Health once — Test-Ready then
writes the Health pack.

Xcode **Run post-action** (`launch-watch-companion.sh`) uses the same timeouts
so a wedged simctl cannot freeze ⌘R.

## DeviceHub (Xcode 27)

Xcode 27 replaces `Simulator.app` with **DeviceHub**
(`Xcode*.app/Contents/Applications/DeviceHub.app`). A DeviceHub `SIGABRT` is
an Apple host crash, not Forge — quit it and relaunch from the same toolchain
you build with:

```bash
killall DeviceHub DevicesTrampoline 2>/dev/null || true
xcode-select -p   # must point at the Xcode you open
```

Prefer scheme **ForgeSwift** + one iPhone destination for day-to-day runs.
Use **ForgeCompanion** only when you need Watch auto-launch. Keep a single
active `xcode-select` path so stable Simulator.app and beta DeviceHub do not
fight.

### DeviceKitError 4002 ("Live device view took longer than expected to connect")

Same DeviceHub host layer, a different symptom: DeviceKit times out (60s)
trying to bring up the live display for a specific device — `DeviceState`
stuck at `connectingDisplays`, `FramebufferProviderStates: ["none"]`. Try in
order:

```bash
# 1. Reboot just that device/simulator (id from the error's DeviceIdentifier)
xcrun simctl shutdown <DEVICE-ID>
xcrun simctl boot <DEVICE-ID>

# 2. Still stuck: reset the host layer (same as the SIGABRT above)
killall DeviceHub DevicesTrampoline 2>/dev/null || true
xcode-select -p

# 3. Still stuck: erase that simulator (wipes its simulated data, not your code)
xcrun simctl erase <DEVICE-ID>
```

On a physical device, skip the `simctl` steps: unlock it, confirm the
cable/Wi-Fi connection, and re-accept "Trust This Computer" — Apple's own
`NSLocalizedRecoverySuggestion` on this error says exactly that.

### Tell: other apps crash too, not just Forge

If a *stock* app — Calendar (`MobileCal`), Reminders, Settings — also dies on
the same simulator, that confirms the host layer, not Forge: look for
`EXC_CRASH (SIGKILL)` / termination reason `FRONTBOARD` / code `0x8BADF00D`
("process-launch watchdog transgression") in Console, with the crashed
process's `Coalition` naming the same `SimDevice.<DEVICE-ID>` you've been
fighting. A trace stuck in `_UIApplicationConfigurationLoader` waiting on an
XPC call to `BoardServices` means that device's OS services are wedged
before any app code runs — it is not something app code can catch or work
around. Skip straight past step 1 above:

```bash
xcrun simctl erase <DEVICE-ID>
```

Still unstable after erase → stop fighting this device; pick or create a
different simulator. Still unstable on a *fresh* simulator → this is
DeviceHub/BoardServices host-daemon state, which `killall` does not always
fully clear — restart the Mac.

## Apple Calendar (MobileCal) `0x8BADF00D`

`com.apple.mobilecal` is **Apple Calendar** in the simulator, not Forge.
A process-launch watchdog (`FRONTBOARD` / `0x8BADF00D`, 30 seconds,
Background) means Calendar.app was launched and dyld did not finish in
time — usually after a year of EventKit writes on a loaded host (Low
Power Mode, DeviceHub live view, 90%+ CPU). The stack is entirely
`dyld_sim`; MobileCal never reached app code.

Test-Ready **does not write EventKit on Simulator**. The same
`FakeCalendarPack` year is generated in memory on launch and turned
into **lifestyle assets** ARIA can sort: weddings, trips, flights,
lifestyle events. Structured fields (kind, when, bucket) go to ARIA;
titles and places stay on-device. Connect Calendar in onboarding is
the same step without launching Apple Calendar. A physical phone
classifies EventKit the same way. Real Calendar ingest (Test-Ready
off) still reads EventKit.

## Fast, reliable Forge launch

Home must paint before any Test-Ready rewrite. On Simulator:

1. Apply the Health pack **in memory** so ARIA has numbers on first frame.
2. Skip EventKit entirely (see MobileCal above).
3. Coalesce the duplicate `refreshDailyData` from `AppStore` init and
   Home `.task`.
4. Wait `simulatorBackgroundIngestDelaySeconds` (2.5s) after Home is
   loaded, **then** write the Health pack into HealthKit and run 30-day
   queries. Pull-to-refresh still forces a fetch.

Do not dump a year of calendar events or a HealthKit rewrite onto a
booting DeviceHub. That is what made Forge feel stuck and what killed
Calendar.app.

## Simulator microphone (Mac)

The iOS Simulator can route input from the Mac microphone. That is a **host
I/O setting**, not an in-app switch — Forge cannot force it on a device, and
a fake “use Mac mic” toggle would not change Simulator routing.

To talk to ARIA in Simulator:

1. Simulator menu: **I/O → Audio Input → Mac microphone** (wording varies by
   Xcode).
2. Mac **System Settings → Privacy & Security → Microphone** must allow
   Xcode / Simulator.
3. The app still asks on first use via `NSMicrophoneUsageDescription` and
   `SpeechManager`.

Welcome-chime motion and sound are verified on a Mac Simulator the same way.
This cloud environment has no iOS Simulator.
