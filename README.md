<div align="center">

```
███████╗ ██████╗ ██████╗  ██████╗ ███████╗
██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
█████╗  ██║   ██║██████╔╝██║  ███╗█████╗
██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝
██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
```

# Forge

**Your sleep, workouts, and how you feel — in one place. With a coach who remembers you.**

An iOS health + lifestyle app. Built around **ARIA**, your AI lifestyle coach.

[What is Forge?](#what-is-forge) · [Meet ARIA](#meet-aria) · [What you can do today](#what-you-can-do-today) · [Where we are](#where-we-are) · [For developers](#for-developers)

</div>

---

## What is Forge?

Most health apps leave you with pieces. Sleep in one place. Workouts in another. How you actually felt — if you wrote it down at all — somewhere else. The numbers exist. The story doesn’t.

**Forge pulls that picture together** from Apple Health and your phone, then helps you act on it. One home. One coach. Your baseline, not someone else’s average.

If you’ve ever stared at a perfect sleep score and still felt off — or crushed a workout week and wondered why everything else slipped — that’s the gap Forge is for.

## Meet ARIA

ARIA is the heart of Forge. She’s an **AI lifestyle coach** — a companion who notices patterns in your life and helps you keep habits. She remembers you over time. She is not a chatbot bolted onto a dashboard.

She talks like a coach: short, structured, human. She might catch that your sleep is sliding, that training is stacking up, or that a habit you care about keeps getting crowded out. Then she helps you do something small about it.

She is a **lifestyle coach, never a doctor**. She does not diagnose, treat, cure, or prescribe. If something looks like a real emergency, she hands you to your phone — Emergency SOS, or 988 if you’re in crisis. That’s the line, and she stays on her side of it.

The longer you use Forge, the more she has to go on. That’s the relationship: not one-off chat, a coach who already knows your week.

## What you can do today

- **Home** — today’s readiness, what’s next, and a short note from ARIA
- **Talk with ARIA** — chat or voice; she keeps context across days
- **Sleep** — last night, stages, and how it lines up with the next day
- **Workouts** — run and log sessions on iPhone or Apple Watch, with a rest timer and a recap
- **Lifestyle** — habits, meals, hydration, and how you feel — not just charts
- **Cycle tracking** — optional, kept on your phone
- **Watch & widgets** — readiness, sleep, hydration, and more on your wrist, Home Screen, and Lock Screen

| Scattered apps | Forge |
| --- | --- |
| Sleep here, workouts there, “how I feel” in notes | One home for the whole picture |
| Charts and scores | A coach who notices patterns |
| Starts over every chat | Remembers you over time |
| Advice for a generic person | Tuned to *your* life |

## Where we are

Forge is a **strong local iOS app in active development**. The phone experience is the real product — Home, ARIA, sleep, workouts, lifestyle, watch, and widgets are all in the app today.

It is **not on the App Store**, and there is **no public TestFlight** yet. If you’re a friend or a tester, you’ll run it from Xcode.

The backend can run on your machine. ARIA’s coaching has a **local path that always works**; cloud AI is optional when you want richer replies.

This is a solo indie project. I’m still building it. What you see here is real software, not a landing-page mock — and it’s not a shipped consumer product yet.

---

# For developers

[![iOS](https://img.shields.io/badge/iOS-27%2B-black?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![watchOS](https://img.shields.io/badge/watchOS-27%2B-black?logo=apple&logoColor=white)](https://developer.apple.com/watchos/)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python&logoColor=white)](https://python.org)
[![Next.js](https://img.shields.io/badge/Next.js-16-black?logo=next.js)](https://nextjs.org)
[![License](https://img.shields.io/badge/License-Proprietary-red)](LICENSE.md)

iOS is canonical. The Xcode project targets **iOS 27** and **watchOS 27**. There is also a Next.js web client and a shared Python backend. Deeper plans live in [`FORGE_ARIA_BUILD_PLAN.md`](FORGE_ARIA_BUILD_PLAN.md) and [`backend/ai/simrunner/README.md`](backend/ai/simrunner/README.md).

### Architecture

```
forge/
├── ForgeSwift/                 # iOS + watchOS (SwiftUI) — the product
│   ├── ForgeSwift/             # Phone app
│   ├── ForgeCore/              # Shared Swift package (design, HealthKit helpers, on-device coaching)
│   ├── ForgeWatch/             # watchOS companion
│   ├── ForgeWidgetExtension/   # Home / Lock Screen widgets
│   ├── ForgeMessagesExtension/ # iMessage invite flow
│   └── LiveActivities/         # Workout + cycle Live Activities
├── src/                        # Next.js 16 web client
├── backend/                    # Shared Python backend (local + AWS)
│   ├── infra/lambda/           # Live handlers and ARIA services
│   ├── infra/*.tf              # Terraform
│   ├── ai/simrunner/           # Offline ARIA evaluation
│   └── dev_server.py           # Local API
├── shared/                     # Cross-client contracts + brand assets
└── .github/workflows/          # CI
```

One backend, native-first on iPhone (Apple Health requires it). AI coaching is deterministic by default; Amazon Bedrock is an opt-in overlay (`ARIA_BEDROCK_ENABLED`) and falls back if the cloud path fails. A guidance layer bands replies before they reach a person — coach, first aid, emergency, or refer-out — and never claims medical authority.

### Getting started

**Prerequisites:** Xcode with an iOS 27 / watchOS 27 simulator or device · Node.js 20+ and pnpm (`pnpm@10.29.2` via Corepack) · Python 3.10+ · optional AWS CLI, Terraform, and Bedrock for cloud AI

```bash
git clone https://github.com/akshithkonda1/Forge.git
cd Forge
```

**iOS (start here)**

```bash
open ForgeSwift/ForgeSwift.xcodeproj
```

Pick a simulator or device, build and run (⌘R), grant Apple Health permissions. Home → ARIA → Sleep → Workout. Switch the scheme to **ForgeWatch** for the watch app.

**Web**

```bash
pnpm install
pnpm dev
```

http://localhost:3000 — same backend ideas as iOS; the phone app is further along.

**Backend & SimRunner**

```bash
python backend/dev_server.py
# local API at http://127.0.0.1:3001

# Offline ARIA evaluation (no API keys)
python -m backend.ai.simrunner --all
SIMRUNNER_TODAY=$(date +%Y-%m-%d) python -m backend.ai.simrunner --all --gate
```

(`python -m backend.simrunner` still works as a compat alias.) Full options: [`backend/ai/simrunner/README.md`](backend/ai/simrunner/README.md).

**Infrastructure** (optional)

```bash
cd backend/infra
terraform init
terraform plan
```

Apple Health, cycle, and medication data stay on-device until explicitly synced. Don’t commit keys.

### CI

Seven workflows: Swift, backend, frontend, SimRunner (ship/hold), Terraform, IAM policy checks, and repo hygiene. For AI changes, run `python -m backend.ai.simrunner --all --gate` locally.

### Contributing

Forge is source-available, not open-source (see [License](#license)). Changes land as branches on this repo from people who already have access — not public forks.

1. Branch off `main`
2. Change + tests where they fit
3. Run the relevant CI locally
4. Open a PR with a clear description

Useful starting points: iOS polish, SimRunner coverage, backend normalization, docs and tests. Style and depth live in `ForgeSwift/` and `backend/ai/simrunner/`.

### License

Forge is a proprietary product. See [`LICENSE.md`](LICENSE.md). The work can inspire original projects. It is not a kit to rebrand or copy. Imitations are not encouraged.

### Acknowledgments

Apple (Health, SwiftUI) · Anthropic and xAI via Bedrock for optional cloud coaching · the open health and fitness data community.

---

<div align="center">

Built for people who take their health seriously — and want a coach, not another dashboard.

*Forge yourself.*

<sup>In the codebase, ARIA is sometimes expanded as Adaptive Recovery Interactive Assistant. In the product, she’s just ARIA — your lifestyle coach.</sup>

</div>
