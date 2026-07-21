# ForgeWatch companion — both apps pop up (Xcode / iOS 27)

## One-shot run (Simulator)

1. **Xcode → Settings → Platforms** — install **iOS** + **watchOS** (required on iOS 27 / Xcode 26+).
2. Open **`ForgeSwift/ForgeSwift.xcodeproj`**.
3. **Window → Devices and Simulators → Simulators**
   - Create/boot an **iPhone** (e.g. iPhone 16 / 17).
   - Under that iPhone, **pair + boot** an **Apple Watch** (Ultra 2 / Series 10).
4. Scheme menu → **`ForgeSwift`** or **`ForgeCompanion`**.
5. Destination → your **paired iPhone** (not “Any iOS Device”).
6. **⌘R**.

### What happens

| Step | Result |
|------|--------|
| Build | Builds `ForgeWatchWidgets` → `ForgeWatch` → `ForgeSwift` |
| Install | Watch app is **embedded** in the iPhone app (`Embed Watch Content`) |
| Launch phone | iPhone ForgeSwift opens |
| Post-action | `Scripts/launch-watch-companion.sh` launches `com.forge.ForgeSwift.watchkitapp` on every **booted** Watch sim |

Both windows should appear. Check the **Report navigator** for `launch-watch-companion:` log lines if the Watch does not open.

## Debug the watch process

Scheme **`ForgeWatch`** → destination **iPhone XX + Apple Watch YY** → ⌘R.  
Debugger attaches to the **watch**; phone remains the companion host.

## Physical iPhone + Watch (iOS 27)

1. iPhone unlocked, Watch unlocked, **Developer Mode** on both.
2. Same Apple ID / trust developer cert when prompted.
3. Scheme **ForgeSwift** → destination = **your iPhone** → ⌘R.
4. Xcode installs iPhone app **and** the watch companion automatically.
5. Open **Forge** on the Watch once (physical devices do not always auto-foreground the watch app).

## Bundle IDs (must match)

| Target | Bundle ID |
|--------|-----------|
| iPhone | `com.forge.ForgeSwift` |
| Watch | `com.forge.ForgeSwift.watchkitapp` |
| Watch widgets | `com.forge.ForgeSwift.watchkitapp.widgets` |
| Companion key | `WKCompanionAppBundleIdentifier = com.forge.ForgeSwift` |
| App Group | `group.com.forge.ForgeSwift` |

## If only the phone opens

1. Confirm a Watch sim is **Booted** and **paired** to that iPhone.
2. Product → **Clean Build Folder**, delete both apps from sims, ⌘R again.
3. Scheme → Edit Scheme → Run → **Post-actions** — ensure “Launch ForgeWatch…” is present and “Provide build settings from” = ForgeSwift.
4. Manually:  
   `xcrun simctl launch booted com.forge.ForgeSwift.watchkitapp`  
   (with the watch sim selected/booted).

## If the watch installs but never gets config

App Groups are flaky across Simulator pairs. Config is also pushed over **WatchConnectivity** (`WatchAriaConfigBridge` → `PhoneLinkService`). **Launch the phone first**, then the watch (the post-action does this order).

## Schemes

| Scheme | Use |
|--------|-----|
| **ForgeSwift** | Daily run — phone + auto-launch watch sim |
| **ForgeCompanion** | Same dual-launch intent (explicit name) |
| **ForgeWatch** | Watch-only debug (does **not** compile iOS sources for watchOS) |

More detail: `XCODE_SETUP.md` · QA: `QA_CHECKLIST.md`.
