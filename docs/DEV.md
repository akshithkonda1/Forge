# Forge — Local Development Guide

Run the full stack on your Mac in three terminals (or fewer with the shortcuts below).

## Prerequisites

| Tool | Version |
|------|---------|
| Python 3 | 3.10+ |
| Node.js | 18+ |
| Xcode | 15+ (for iOS) |

## 1. Backend API (port 3001)

From the repo root:

```bash
npm run backend:dev
# or: python3 backend/dev/server.py
```

Verify it's up:

```bash
curl http://127.0.0.1:3001/health
```

Run tests:

```bash
npm run backend:test   # 100 unit tests
```

## 2. Web client (Next.js)

**Terminal 1** — keep the backend running.

**Terminal 2:**

```bash
cd clients/web
npm install
npm run dev
```

Open [http://localhost:3000](http://localhost:3000).

Optional env — copy [`clients/web/.env.example`](../clients/web/.env.example) to `.env.local`:

```
NEXT_PUBLIC_API_URL=http://127.0.0.1:3001
```

For production client wiring after Terraform, see [`PRODUCTION-CLIENTS.md`](PRODUCTION-CLIENTS.md).

### What you'll see

- **First visit** → onboarding flow (profile, devices, coaching style). Progress is saved in `localStorage`.
- **After onboarding** → live dashboard from `/dashboard/today`, ARIA chat history from `/aria/conversation`, insights from `/aria/insights`.
- **Backend offline** → amber banner + demo data so you can still explore the UI.

## 3. iOS app (ForgeSwift)

One command starts the backend, verifies the build, and opens Xcode:

```bash
npm run ios:open
# or: ./scripts/ios_dev.sh open
```

**Important:** Open `Forge.xcworkspace` at the **repo root**. Do not open `clients/ios/...` — that copy is deprecated and will not build.

In Xcode:

1. Scheme: **ForgeSwift** (not `ForgeWidgetExtension`)
2. Destination: an **iPhone simulator** (e.g. iPhone 17) — not **My Mac**
3. Press **⌘R**

If signing fails, set your team under **Signing & Capabilities**, or edit `ForgeSwift/Config/Forge-Debug.xcconfig` (`DEVELOPMENT_TEAM`).

### Simulator (default)

`ForgeSwift/ForgeSwift/Forge-Info.plist` points at `http://127.0.0.1:3001`. No changes needed.

### Physical device

Your phone can't reach `127.0.0.1` on your Mac. Update `FORGE_API_BASE_URL` in `Forge-Info.plist` to your Mac's LAN IP:

```
http://192.168.x.x:3001
```

Find your IP: **System Settings → Network**, or `ipconfig getifaddr en0`.

Also set `FORGE_USE_AUTH` to `false` for local dev without Cognito.

### HealthKit

The simulator has limited Health data. On a real device, grant Health permissions during onboarding — Forge syncs metrics via `POST /health/batch`.

### Terra / wearables

Device connect opens a Safari flow and returns via the `forge://` URL scheme configured in the plist.

## Quick reference

| Command | What it does |
|---------|----------------|
| `npm run backend:dev` | Start API on :3001 |
| `npm run web:dev` | Start Next.js dev server |
| `npm run ios:open` | Backend + open `Forge.xcworkspace` |
| `npm run ios:build` | CI-style simulator build |
| `npm run backend:test` | Run all Python tests |

## Architecture

```
Browser / Simulator
       │
       ▼
  clients/web  or  ForgeSwift/
       │
       ▼
  backend/dev/server.py  (:3001)
       │
       ▼
  backend/app/  (routes, ARIA, DynamoDB)
```

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Web shows "Can't reach API" banner | Start `npm run backend:dev` |
| Xcode build fails on `OnboardingCoordinator` | You opened `clients/ios` — use repo-root `Forge.xcworkspace` |
| Xcode runs but screen is blank | Pick an **iPhone simulator**, not My Mac; use **ForgeSwift** scheme |
| Signing / provisioning errors | Set **Team** in Signing & Capabilities or `Forge-Debug.xcconfig` |
| iOS can't load data on device | Set `FORGE_API_BASE_URL` to Mac LAN IP |
| Chat returns errors | Backend must be running; check `curl :3001/health` |
| Onboarding loops | Clear site data or `localStorage` keys `forge.isOnboarded` |

## Branch & PR

Active feature work: `feat/forge-swift-live-data` → [PR #26](https://github.com/akshithkonda1/Forge/pull/26).