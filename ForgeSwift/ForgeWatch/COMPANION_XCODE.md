# ForgeWatch companion — Xcode quickstart

## 60-second setup

1. **Xcode → Settings → Platforms** → install **watchOS**.
2. Open **`ForgeSwift/ForgeSwift.xcodeproj`**.
3. Create a pair: **Window → Devices and Simulators → Simulators**  
   iPhone 16/17 + Apple Watch Ultra 2 (or Series 10).
4. Scheme **`ForgeSwift`** → destination = **paired iPhone** → **⌘R**.
5. On the Watch sim, launch **ForgeWatch**.

That installs the watch app as an embedded companion (`Embed Watch Content`).

## Debug the watch process

Scheme **`ForgeWatch`** → destination **`iPhone XX + Apple Watch YY`** → **⌘R**.  
Debugger attaches to the watch; phone is still built as the companion host.

## Prove companion link

| Check | How |
|-------|-----|
| Both installed | Watch home shows ForgeWatch after iPhone run |
| Same team / IDs | Phone `com.forge.ForgeSwift`, Watch `….watchkitapp` |
| Config sync | Launch phone first; watch gets `forge.aria.baseURL` via WCSession |
| Live Activity | Start workout on watch → iPhone lock screen / Dynamic Island updates |

## Do not

- Run an unpaired Watch-only destination and expect WCSession + Live Activity.
- Mix Debug phone build with a different Watch install.
- Rely only on App Groups in **Simulator** (use WCSession path).

Full notes: `XCODE_SETUP.md` · QA: `QA_CHECKLIST.md`.
