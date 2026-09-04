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
