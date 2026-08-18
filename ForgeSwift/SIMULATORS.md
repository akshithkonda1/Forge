# Simulators

Forge is developed against the **iOS 26.5** and **iOS 27** simulators (and
macOS 27 “Designed for iPhone” when needed). That is the edge we keep frozen
for Lifestyle, Places, and Apple Health.

CI still builds a generic iOS Simulator destination so a runner without 26.5
or 27 installed can compile. Locally:

```bash
xcrun simctl list runtimes
# pick iPhone + iOS 26.5 or 27
```

Do not lower the bar to an older Health / MapKit / CloudKit surface just to
make an old simulator happy.
