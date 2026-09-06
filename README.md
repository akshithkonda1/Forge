<div align="center">

```
███████╗ ██████╗ ██████╗  ██████╗ ███████╗
██╔════╝██╔═══██╗██╔══██╗██╔════╝ ██╔════╝
█████╗  ██║   ██║██████╔╝██║  ███╗█████╗  
██╔══╝  ██║   ██║██╔══██╗██║   ██║██╔══╝  
██║     ╚██████╔╝██║  ██║╚██████╔╝███████╗
╚═╝      ╚═════╝ ╚═╝  ╚═╝ ╚═════╝ ╚══════╝
```

**One platform. Every health metric. Zero friction.**

[![iOS](https://img.shields.io/badge/iOS-27%2B-black?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![Swift](https://img.shields.io/badge/Swift-6-orange?logo=swift&logoColor=white)](https://swift.org)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python&logoColor=white)](https://python.org)
[![AWS](https://img.shields.io/badge/AWS-Serverless-ff9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-844FBA?logo=terraform&logoColor=white)](https://terraform.io)
[![Next.js](https://img.shields.io/badge/Next.js-16-black?logo=next.js)](https://nextjs.org)
[![License](https://img.shields.io/badge/License-Proprietary-red)](LICENSE.md)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](#contributing)

**23** behavioral archetypes · **3-model** ARIA ensemble · **7** CI workflows · **iOS 27+ / watchOS 27+**

[Overview](#overview) · [Current State](#current-state--whats-built) · [Architecture](#architecture) · [Key Strengths](#key-strengths) · [Features](#features) · [Getting Started](#getting-started) · [SimRunner](#simrunner--offline-ai-evaluation) · [Roadmap](#roadmap) · [Contributing](#contributing)

</div>

---

## Overview

**Forge** is building the definitive unified health AI platform. Instead of five siloed apps (Garmin for runs, WHOOP for recovery, Oura for sleep, Apple Health for everything else, and a generic fitness tracker), Forge ingests data from everywhere, normalizes it into one coherent picture, and delivers **contextual, lifestyle-based AI coaching** tailored to real human lives — coders with irregular sleep, deep sleepers, desk workers, athletes, and everyone in between.

The core problem: **fragmentation kills insight, and most apps ground you in stats and charts instead of your actual life**. Your data exists, but it's scattered — and you're not a spreadsheet. Everyone operates differently; Forge learns what makes *you* tick and turns that into something actionable.

### What Makes Forge Different

| Traditional Apps                  | Forge                                      |
|-----------------------------------|--------------------------------------------|
| Siloed to one hardware ecosystem  | Aggregates 50+ sources via adapters + middleware |
| Generic "move more" advice        | Multi-model ARIA coaching with a persistent companion memory |
| Static dashboards                 | Adaptive plans that evolve with your patterns |
| One-size-fits-all metrics         | Unified readiness + recovery intelligence  |
| Platform lock-in                  | Works with the hardware you already own    |
| Bolt-on safety disclaimers        | Deterministic medical-boundary policy gates every AI response |

### Meet ARIA

At the center of Forge is **ARIA** — the **Adaptive Recovery Interactive Assistant**. ARIA isn't a chatbot bolted onto a dashboard: it's a multi-model reasoning engine (Claude Sonnet + Claude Opus + Grok, reconciled into one answer) paired with a persistent companion memory that tracks your patterns across days, not just messages. And it knows exactly where its authority ends — a deterministic medical-boundary policy means ARIA suggests, hands real emergencies off to your phone's native Emergency SOS, and never diagnoses or prescribes. **Adaptive** to your recovery. **Interactive** like a coach who actually remembers you.

**Vision**: The health app that feels like it *knows* you — because it actually sees the full picture.

---

## Current State — What's Built

Forge is well past the prototype stage. An intense one-week sprint (Aug 30 – Sep 6, 2026) shipped most of what's below: the multi-model ARIA ensemble, a companion memory engine, a full medical-boundary safety layer with native emergency escalation, medication/pharmacy intelligence, cycle & partner features, a mature watchOS companion, and ARIA's refreshed visual/voice identity.

### iOS (Primary — ForgeSwift/)
- **Mature native SwiftUI app** (iOS 27+ / watchOS 27+) — the canonical, most advanced client; no parallel/duplicate iOS codebase exists.
- Full feature set: Home dashboard (readiness ring, AI greeting, today's plan), rich **ARIA ChatView** with contextual cards, detailed **SleepView** (stages, trends, AI insights), **WorkoutView** (live biometrics, rest timer, progressive overload), Lifestyle, Profile, multi-step Onboarding with coaching-style selection.
- **`ForgeCore`** — a shared Swift package (tools 6.4) behind both the phone and watch apps: design system (`ForgeDS`, `ForgePalette`), HealthKit helpers, secure storage (`SecureStore`, `CycleVault`), and an on-device "Intelligence" layer (`AriaGuidancePolicy`, `AriaHealthRiskMonitor`, `AriaIntentResolver`, `CircadianRhythm`, `WorkoutSuggestionEngine`, and more).
- **`ForgeWatch`** — a full watchOS companion: a Mindfulness Coach (breathing orb + haptic guidance), on-wrist workout sessions, 6 complications (readiness, hydration, sleep, mindfulness, workouts, support), App Intents/Shortcuts, and a phone-link bridge.
- **`ForgeWidgetExtension`** — the real, wired WidgetKit target: Readiness, Hydration, Sleep, CyclePhase, Support, and Today widgets for Home Screen and Lock Screen. (Root-level `ForgeWidget/` is an older prototype, intentionally left unwired — see its own README.)
- **`ForgeMessagesExtension`** — an iMessage extension powering the partner/supporter "invite" flow.
- **`LiveActivities`** — Lock Screen + Dynamic Island activities for live workouts and cycle fertile-window tracking.
- Heavy investment in polish: custom design system, Swift Charts, deep HealthKit integration, advanced UI patterns (glassmorphism, particles, Aurora Orb components), accessibility, and dozens of high-quality planning docs alongside the code.

### Web / Cross-Platform (src/ + Next.js)
- Next.js 16 + React 19 + TypeScript 6 (Tailwind 4), targeting web today with Android on the longer-term roadmap.
- Matching flows: home, chat, onboarding, sleep, workout, progress (heatmap, PRs), settings, profile.
- Shared state (Zustand 5), API client, types, and the same ARIA "fluid ember" brand mark used across platforms, kept in lockstep via `shared/aria-mark.json`.
- Built to feel native on its platform while sharing the exact same backend as iOS.

### Backend & AI (`backend/`)
- **One Python serverless backend** on AWS (Lambda + API Gateway + DynamoDB + Bedrock) for iOS, web, and Android — deployed from **`backend/infra/lambda/`**, the real, actively-developed code. (`backend/app/` and `backend/ai/app/` are deprecated stubs kept only for backward compatibility.)
- **`ai_router.py`** — multi-model consensus across a 3-model ensemble (`claude-sonnet-4-6`, `claude-opus-4-7`, and `grok-4.6` as a differently-trained second opinion), reconciled through a consensus window and finalizer.
- **`services/aria_engine.py`** — the deterministic reasoning engine, with an opt-in Bedrock Converse overlay (`ARIA_BEDROCK_ENABLED`) that always falls back to the deterministic response on failure.
- **`services/aria_context.py`** — ARIA's companion memory: long-term `UserContext`, short-term `MemoryItem`s, a daily `MemoryReview` self-evaluation, and check-in prompts.
- **`services/guidance.py`** — ARIA's medical-boundary policy: `COACH` / `FIRST_AID` / `EMERGENCY` / `REFER_OUT` bands with whole-word matching (so "burnout" doesn't trip a "burn" response), plus a crisis-line reply (988) for self-harm instead of generic first aid. ARIA suggests — it never diagnoses or prescribes.
- **`services/emergency.py`** — a deterministic vitals monitor that raises an escalation intent for the *client's* native Emergency SOS on a life-threatening state; the backend never dials emergency services itself.
- Medication & pharmacy intelligence: real FDA drug data, medications treated as a lifestyle signal rather than a prescription, and photo-based medication logging.
- REST routes (chat, coach, sleep, workouts, dashboard, profile, integrations, health), seed data, `dev_server.py`, `backend/ai/aria_cli.py`.

### SimRunner — Offline AI Evaluation Harness (`backend/ai/simrunner/`)
One of Forge's standout engineering achievements: a fully deterministic, stdlib-only harness (zero dependencies, no network calls) covering **23** behavioral archetypes across 5 tiers, scored on 6 dimensions, with a **dummy multi-agent orchestrator** for offline sanity checks and a **ship/hold gate** that reuses the production `guidance.py` policy directly — so SimRunner and the live backend can never quietly drift apart on safety. Full details in [SimRunner](#simrunner--offline-ai-evaluation) below.

### Shared Layer
- `shared/api-contracts.ts` for frontend/backend type safety; `shared/aria-mark.json` keeps ARIA's visual identity in lockstep across iOS and web.
- **7 CI workflows**: Swift (ForgeCore/ForgeWatch/widgets), backend (unit tests + an AI/ARIA gate), frontend (typecheck + build), SimRunner (ship/hold gate), Terraform (plan + gated apply), AWS IAM policy validation, and repo-hygiene checks (redaction boundaries, duplicate declarations, widget registration, and more).

---

## Architecture

```
forge/
├── ForgeSwift/                   # Canonical iOS + watchOS (SwiftUI + HealthKit) — most mature
│   ├── ForgeSwift/                # App source: Views, Models, Services, Theme
│   ├── ForgeCore/                 # Shared Swift package — design system, HealthKit helpers, on-device Aria intelligence
│   ├── ForgeWatch/                # watchOS companion — Mindfulness Coach, complications, workout sessions
│   ├── ForgeWidgetExtension/      # Home/Lock Screen widgets
│   ├── ForgeMessagesExtension/    # iMessage partner/invite flow
│   ├── LiveActivities/            # Workout + cycle Live Activities / Dynamic Island
│   └── docs/                      # iOS-specific planning docs
├── ForgeWidget/                  # Older single-widget scaffold — unwired, superseded by ForgeWidgetExtension
├── src/                          # Next.js 16 web/Android-track client (TypeScript)
│   ├── app/, components/, stores/, types/
├── backend/                      # Shared AWS backend (iOS + web + Android)
│   ├── infra/                     # Terraform + the deployed Lambda — the real backend
│   │   ├── lambda/                 # handler, routes, ai_router.py, services/{aria_engine,aria_context,guidance,emergency,...}.py
│   │   └── *.tf
│   ├── ai/
│   │   ├── simrunner/               # Offline AI evaluation harness (SimRunner)
│   │   ├── aria_cli.py              # Local ARIA CLI driver
│   │   └── app/                     # Deprecated legacy routes
│   ├── app/, simrunner/            # Deprecated stub + compat shim — not the live code path
│   ├── tests/                       # Python test suite (~100+ tests) against backend/infra/lambda
│   ├── dev_server.py
│   └── pyproject.toml / requirements.txt
├── shared/                        # Cross-language contracts + brand assets
├── .github/workflows/             # CI: swift, backend, frontend, simrunner, terraform, policy-validator-tf, repo-hygiene
├── package.json + pnpm            # Web tooling
└── README.md + planning docs (FORGE_ARIA_BUILD_PLAN.md, backend/ARIA_INTELLIGENCE_PLAN.md, …)
```

**Core Principles**
- One backend, two (or more) tailored frontends.
- Adapter/normalization layer for future integrations (HealthKit today, Strava/Garmin/WHOOP/Oura/Terra planned).
- Safety-gated generation: a deterministic guidance/emergency layer bands every ARIA response before it reaches a user, and SimRunner enforces that same policy in CI.
- Infrastructure as code + full CI gates.
- Native-first where it matters (HealthKit requires native iOS).

---

## Key Strengths

1. **iOS Polish & Ambition** — Apple Design Award-level ambition: rich interactions, deep HealthKit integration, a full watchOS companion, and home/lock-screen widgets.
2. **Layered AI Safety** — A multi-model ensemble reconciled through a deterministic medical-boundary policy and native-only emergency escalation, so safety gates generation rather than disclaiming it afterward.
3. **SimRunner Safety Net** — 23-archetype deterministic eval, regression gates, and a ship/hold gate that reuses the production safety policy verbatim.
4. **Production-Ready Backend Infra** — Terraform + Python Lambdas + DynamoDB + Bedrock, structured for scale — not a toy Flask app.
5. **Unified Data Vision** — A well-thought-out normalization + scoring + ARIA context pipeline, even ahead of full end-to-end data flow.
6. **Monorepo Discipline** — Clear separation, strong CI (including automated redaction-boundary and duplicate-declaration checks), and high-signal documentation throughout.

---

## Features (Shipped Highlights)

### Home & Readiness
- AI-generated daily greeting based on real data
- Composite readiness ring (sleep + recovery + load + HR trends)
- Today's plan + quick actions
- Live biometric snapshot

### ARIA AI Coach
- Multi-model consensus (Claude Sonnet 4.6 + Claude Opus 4.7 + Grok 4.6 via Bedrock), reconciled into one answer
- Persistent companion memory: long-term context, short-term memory, daily check-ins
- "Suggest, don't prescribe" enforced in the guidance layer, not just prompt wording
- Refreshed identity: fluid-ember breathing mark, welcome chime, updated conversational voice
- Rich response cards, coaching-style adaptation, full normalized-history context

### ARIA Safety & Medical Boundaries
- Deterministic `COACH` / `FIRST_AID` / `EMERGENCY` / `REFER_OUT` bands with whole-word matching to avoid false positives
- Crisis-appropriate self-harm handling (988 Suicide & Crisis Lifeline) instead of generic first aid
- Real-time vitals monitor → native-only Emergency SOS escalation; the backend never places emergency calls itself
- The same policy module gates both production and SimRunner, so it can't silently drift

### Medication & Pharmacy Intelligence
- Real FDA drug data and federal drug lists; medications treated as a lifestyle signal, not a prescription to manage
- Photo-based medication logging

### Cycle, Partner & Wellness
- Secure on-device Cycle Vault
- iMessage-based partner "invite" flow, with a CI-enforced redaction boundary so supporters never see cycle data
- Cycle fertile-window Live Activity

### Sleep Intelligence
- Stage timeline (REM/deep/light/awake) with Swift Charts
- Trends, efficiency, correlations to next-day readiness
- AI-generated personalized insights

### Workout Experience
- Active session tracking with live HR/calories/zones (phone and watch)
- Rest timer, exercise library navigation
- Set/rep/weight logging + progressive overload
- Post-session AI summary

### Wearable & Live Activities
- ForgeWatch Mindfulness Coach (breathing orb + haptic guidance)
- Watch complications for readiness, hydration, sleep, mindfulness, and workouts
- Home/Lock Screen widgets (Readiness, Hydration, Sleep, Cycle, Support, Today)
- Live Activities / Dynamic Island for active workouts and cycle tracking

### Progress & Analytics (web + iOS)
- Activity heatmaps, PR tracking, volume trends
- Platform data source visibility

### Backend & Data
- HealthKit sync (iOS)
- Biometrics inference, normalization, unified scoring
- DynamoDB persistence
- Ready for adapter-based integrations

---

## Getting Started

### Prerequisites
- Xcode 27 + iOS 27 / watchOS 27 simulator or device (ForgeSwift + ForgeWatch)
- Node.js 20+ + pnpm (pinned to `pnpm@10.29.2` via Corepack)
- Python 3.10+ (backend/SimRunner)
- AWS CLI + Terraform (infra)
- (Optional) AWS Bedrock access for real ARIA calls

### 1. Clone
```bash
git clone https://github.com/akshithkonda1/Forge.git
cd Forge
```

### 2. iOS (Recommended starting point — most complete)
```bash
open ForgeSwift/ForgeSwift.xcodeproj
```
- Select simulator or device (iOS 27), build & run (⌘R), grant HealthKit permissions
- Explore Home → Chat (ARIA) → Sleep → Workout
- Switch the scheme to **ForgeWatch** to build the watch companion on a paired watchOS 27 simulator

Many implementation notes live in `ForgeSwift/ForgeSwift/*.md` files.

### 3. Web Client (Next.js)
```bash
pnpm install
pnpm dev
```
Runs at http://localhost:3000. Uses the same backend concepts as iOS.

### 4. Backend & SimRunner (Python)
SimRunner is the best way to explore the AI layer locally without any API keys:

```bash
# Full evaluation across all archetypes + models
python -m backend.ai.simrunner --all

# With statistical confidence
python -m backend.ai.simrunner --all --seeds 5

# Regression gate (what CI uses)
SIMRUNNER_TODAY=$(date +%Y-%m-%d) python -m backend.ai.simrunner --all --gate
```

(`python -m backend.simrunner` still works as a compat alias, but new commands should use `backend.ai.simrunner`.)

See `backend/ai/simrunner/README.md` for full options and architecture. Dev server / CLI tools also available in `backend/`.

### 5. Infrastructure (Terraform)
```bash
cd backend/infra
terraform init
terraform plan
# terraform apply (with AWS credentials configured)
```

### Environment & Secrets
- HealthKit, cycle, and medication data stay on-device until explicitly synced.
- Backend uses AWS secrets / SSM / env vars for Bedrock, DynamoDB, etc.
- Never commit real keys.

---

## SimRunner — Offline AI Evaluation

Before ARIA's advice reaches a real user, it has to survive SimRunner: a fully offline, deterministic harness that replays **23** behavioral archetypes through the exact prompt → context → response pipeline, grades the output on **6 dimensions** with no LLM-as-judge, and reduces it to one call — **SHIP** or **HOLD** — using the same medical-boundary policy that gates production. A local-only dummy multi-agent orchestrator sanity-checks ARIA's conversational shape without any cloud calls, and committed golden baselines turn every run into a regression test against the full AWS Bedrock model catalog.

We believe this kind of behavioral validation, regression control, and deployment gating deserves to be a first-class part of shipping AI — not an afterthought.

Full documentation: [`backend/ai/simrunner/README.md`](backend/ai/simrunner/README.md)

---

## Roadmap

### Phase 1 — Foundation (Complete)
- [x] Mature SwiftUI iOS client (ForgeSwift/) with HealthKit, rich ARIA chat, sleep/workout views, design system
- [x] Next.js web client with matching flows
- [x] Python backend services + ARIA engine
- [x] AWS serverless infra (Terraform + Lambda handlers + DynamoDB)
- [x] SimRunner offline eval harness — 23 archetypes, regression gates, full model catalog
- [x] Monorepo + comprehensive CI/CD
- [x] Multi-model ARIA consensus ensemble (Claude Sonnet + Claude Opus + Grok)
- [x] Companion memory engine (long/short-term context, daily check-ins)
- [x] Deterministic medical-boundary safety layer + native-only emergency escalation

### Phase 2 — Real Data Flow (In Progress)
- [ ] End-to-end HealthKit → normalized backend → ARIA context pipeline
- [ ] Full user auth / persistence / profile management
- [ ] Polish remaining iOS screens and widget experience
- [x] Consolidate iOS duplication — `ForgeSwift/` is the sole client

### Phase 3 — Platform Integrations
- [ ] Strava, Garmin, WHOOP, Oura adapters (or Terra/Vital middleware)
- [ ] Biometrics inference improvements
- [ ] Unified health score v2

### Phase 4 — Intelligence & Polish
- [x] Apple Watch companion — `ForgeWatch`: Mindfulness Coach, complications, on-wrist workouts, shared `ForgeCore` package. See `ForgeSwift/WATCH_APP_IMPLEMENTATION_PLAN.md`.
- [x] Medication & pharmacy intelligence layer (FDA data, photo-based logging)
- [x] Cycle, partner (iMessage), and Live Activities features
- [x] Refreshed ARIA visual identity (fluid-ember mark, chime) + updated voice
- [ ] Adaptive training plans
- [ ] Deeper trend/anomaly detection
- [ ] Prompt A/B testing in CI

### Phase 5 — Growth
- Android native improvements (not yet started), social features, export APIs, etc.

---

## Contributing

Forge is source-available, not open-source (see [License](#license)), so contributions land as branches on this repo from authorized collaborators rather than public forks. Within that, contributions are welcome — especially in:
- New health platform adapters
- SimRunner archetype expansion or scoring refinements
- iOS UI/UX polish and animations
- Backend normalization/biometrics logic
- Documentation and tests

**Workflow**
1. Create a feature branch off `main`
2. Make changes + tests where applicable
3. Run relevant CI locally (especially `python -m backend.ai.simrunner --all --gate` for AI changes)
4. Open a PR with a clear description

See existing high-quality docs in `ForgeSwift/ForgeSwift/` and `backend/ai/simrunner/` for style and depth expectations.

---

## License

Forge is a proprietary product. That said, Forge's technology can be used to inspire, not imitate. Imitations are not encouraged and will be prosecuted if it can be proved in a court of law that a component of the product was stolen or copied under a similar name. In short, Forge can be used as inspiration, not as a rebranded product. 
---

## Acknowledgments

- Anthropic (Claude via Bedrock) for powering ARIA
- xAI (Grok via Bedrock) for ARIA's second-opinion ensemble model
- Apple for HealthKit and SwiftUI
- The broader open-source health/fitness data community

---

<div align="center">

**Forge** is being built with an obsession for people who take their health seriously.

*Forge yourself.*

Questions, ideas, or want to collaborate? Open an issue or reach out.

</div>
