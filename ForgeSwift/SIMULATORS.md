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
