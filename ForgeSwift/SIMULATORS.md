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
