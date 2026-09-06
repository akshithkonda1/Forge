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

[Overview](#overview) · [Current State](#current-state--whats-built) · [Architecture](#architecture) · [Key Strengths](#key-strengths) · [Features](#features) · [Getting Started](#getting-started) · [SimRunner](#simrunner--offline-ai-evaluation) · [Roadmap](#roadmap) · [Contributing](#contributing)

</div>

---

## Overview

**Forge** is building the definitive unified health AI platform. Instead of five siloed apps (Garmin for runs, WHOOP for recovery, Oura for sleep, Apple Health for everything else, and a generic fitness tracker), Forge ingests data from everywhere, normalizes it into one coherent picture, and delivers **contextual, lifestyle based AI coaching** tailored to real human lives — coders with irregular sleep, deep sleepers, desk workers, athletes, and everyone in between.

The core problems it solves: **fragmentation kills insight and apps typically ground you to stats and charts not to your life**. Your data exists, but it's scattered. You're human, everyone's different and everyone operates differently, Forge learns what makes you tick and makes it actionable.

### What Makes Forge Different

| Traditional Apps                  | Forge                                      |
|-----------------------------------|--------------------------------------------|
| Siloed to one hardware ecosystem  | Aggregates 50+ sources via adapters + middleware |
| Generic "move more" advice        | Multi-model ARIA coaching with a persistent companion memory |
| Static dashboards                 | Adaptive plans that evolve with your patterns |
| One-size-fits-all metrics         | Unified readiness + recovery intelligence  |
| Platform lock-in                  | Works with the hardware you already own    |
| Bolt-on safety disclaimers        | Deterministic medical-boundary policy gates every AI response |

**Vision**: The health app that feels like it *knows* you — because it actually sees the full picture.

---

## Current State — What's Built

Forge is well past the prototype stage. The README's last snapshot (late August 2026) was followed by an unusually intense one-week sprint (Aug 30 – Sep 6, 2026) that shipped a multi-model ARIA reasoning ensemble, a companion memory engine, a full medical-boundary safety layer with native emergency escalation, medication/pharmacy intelligence, cycle & partner features, a mature watchOS companion, and a refreshed ARIA visual/voice identity. The sections below reflect that state.

### iOS (Primary — ForgeSwift/)
- **Mature native SwiftUI app** (iOS 27+ / watchOS 27+) — still the sole iOS codebase; no parallel/duplicate client exists.
- Full feature set: Home dashboard with readiness ring + AI greeting + today's plan, rich **ARIA ChatView** with contextual cards, detailed **SleepView** (stages, timelines, trends, AI insights), **WorkoutView** (live biometrics, rest timer, exercise nav, progressive overload), Lifestyle, Profile, multi-step Onboarding with coaching style selection.
- **`ForgeCore`** — a shared Swift package (Swift tools 6.4) underpinning both the phone app and the watch app: design system (`ForgeDS`, `ForgePalette`), HealthKit query helpers, secure on-device storage (`SecureStore`, `CycleVault`), and an on-device "Intelligence" layer (`AriaGuidancePolicy`, `AriaHealthRiskMonitor`, `AriaIntentResolver`, `CircadianRhythm`, `WorkoutSuggestionEngine`, and more).
- **`ForgeWatch`** — a full watchOS companion: a Mindfulness Coach (breathing orb + haptic guidance + on-device suggestion engine), on-wrist workout sessions, complications (Readiness, Hydration, SleepQuality, MindfulnessReset, ActiveWorkout, Support), App Intents/Shortcuts, and a phone-link bridge.
- **`ForgeWidgetExtension`** — the real, wired WidgetKit target: Readiness, Hydration (with a Log Water intent), Sleep, CyclePhase, SupportGlance, and Today widgets for the Home Screen and Lock Screen. (The standalone `ForgeWidget/` at the repo root is an older single-widget prototype, intentionally left unwired as scaffolding — see its own README.)
- **`ForgeMessagesExtension`** — an iMessage app extension powering the partner/supporter "invite" flow.
- **`LiveActivities`** — Lock Screen + Dynamic Island activities for live workouts and cycle fertile-window tracking.
- Heavy investment in polish: custom design system, Swift Charts, HealthKitManager (deep integration), advanced UI patterns (glassmorphism, particles, animations, Aurora Orb components), accessibility.
- Dozens of high-quality planning and implementation docs living alongside the code (AWARD_WINNING_*, CHATVIEW_IMPROVEMENTS, IMPLEMENTATION_SUMMARY, etc.).
- **This is the canonical, most advanced client.**

### Web / Cross-Platform (src/ + Next.js)
- Next.js 16 + React 19 + TypeScript 6 frontend (Tailwind 4), targeting web today with Android on the longer-term roadmap.
- Matching flows: home, chat (with rich cards), onboarding, sleep, workout, progress (heatmap, PRs), settings, profile.
- Shared state (Zustand 5), API client, types, and the same ARIA "fluid ember" brand mark (`src/components/brand/aria-mark.tsx`) used across platforms, kept in lockstep with `shared/aria-mark.json`.
- Designed to feel native on its platform while sharing the exact same backend.

### Backend & AI (`backend/`)
- **One Python serverless backend** on AWS (Lambda + API Gateway + DynamoDB + Bedrock) for iOS, web, and Android — deployed from **`backend/infra/lambda/`**, which is the real, actively-developed handler/routes/services. (`backend/app/` and `backend/ai/app/` are deprecated legacy stubs kept only for backward compatibility — new logic never goes there.)
- **`ai_router.py`** — multi-model consensus routing across a 3-model ensemble (`anthropic.claude-sonnet-4-6`, `anthropic.claude-opus-4-7`, and `global.xai.grok-4.6` as a differently-trained second opinion), reconciled through a consensus window and finalizer.
- **`services/aria_engine.py`** — the deterministic reasoning engine, with an opt-in Bedrock Converse overlay (`ARIA_BEDROCK_ENABLED`) that always falls back to the deterministic response on any failure, plus a robust JSON-envelope parser for model output.
- **`services/aria_context.py`** — ARIA's companion memory: a long-term `UserContext`, short-term `MemoryItem`s, a daily `MemoryReview` self-evaluation, and check-in prompts.
- **`services/guidance.py`** — ARIA's medical-boundary policy: `COACH` / `FIRST_AID` / `EMERGENCY` / `REFER_OUT` bands, whole-word matching (so "burnout" or "sunburn" don't trip a "burn" first-aid response), and a crisis-line reply (988 Suicide & Crisis Lifeline) for self-harm messages instead of generic first aid. ARIA suggests lifestyle changes — it never diagnoses or prescribes.
- **`services/emergency.py`** — a deterministic vitals safety monitor. On detecting a life-threatening state it raises an escalation intent for the *client's* native Emergency SOS; the backend never dials emergency services itself (an earlier RapidSOS/carrier-webhook path was tried and then deliberately removed in favor of this native-only design).
- Medication & pharmacy intelligence: real FDA drug data and federal drug lists, medications treated as a lifestyle signal rather than a prescription, and photo-based medication logging.
- REST routes (chat, coach, sleep, workouts, dashboard, profile, integrations, health), seed data, `dev_server.py`, `backend/ai/aria_cli.py`.

### SimRunner — Offline AI Evaluation Harness (`backend/ai/simrunner/`)
One of Forge's standout engineering achievements:
- Fully deterministic, stdlib-only Python harness — zero dependencies, no network calls.
- **23** behavioral archetypes across 5 tiers (Tier 1 compliant athlete → Tier 5 system gamers/data-sparsity/ambiguous-signal personas).
- 6-dimension scoring (context utilization, directional correctness, chronotype awareness, actionability, epistemic honesty, tone).
- A **dummy orchestrator** — a staged, local-only stand-in for a live multi-agent turn (intent scoring → specialist fan-out → synthesized companion-voice reply) that sanity-checks ARIA's conversational shape without any cloud calls.
- A **ship/hold medical-boundary gate** that reuses the production `guidance.py` policy directly, so SimRunner and the live backend can never quietly drift apart on safety.
- Full AWS Bedrock model catalog (59 cataloged models, with an opt-in live-catalog refresh) + regression gates against committed golden baseline files.
- Multi-seed statistical reporting. CI-integrated (fails builds on regressions or new safety violations). Real-API opt-in mode for live testing.

This is how you safely ship an AI health coach that gives advice like "your readiness is 38 — today is a recovery day."

### Shared Layer
- `shared/api-contracts.ts` for type safety between frontend and backend (Pydantic models in Python stay in sync manually for now); `shared/aria-mark.json` + brand assets keep ARIA's visual identity in lockstep across iOS and web.
- Strong CI/CD: 7 workflows — Swift (builds ForgeCore + ForgeSwift + ForgeWatch + widgets on iOS/watchOS simulators), backend (unit tests plus a dedicated AI/ARIA gate), frontend (typecheck + build), SimRunner (ship/hold regression gate), Terraform (plan + gated apply), AWS IAM policy validation, and repo-hygiene checks (partner-data redaction boundaries, no duplicate declarations, widget bundle registration, and more).

`ForgeSwift/` is the sole iOS codebase — no parallel/duplicate client remains.

---

## Architecture

```
forge/
├── ForgeSwift/                   # Canonical iOS + watchOS (SwiftUI + HealthKit) — most mature
│   ├── ForgeSwift/                # App source: Views, Models, Services, Theme
│   ├── ForgeCore/                 # Shared Swift package — design system, HealthKit helpers, on-device Aria intelligence
│   ├── ForgeWatch/                # watchOS companion — Mindfulness Coach, complications, workout sessions
│   ├── ForgeWidgetExtension/      # Home/Lock Screen widgets (Readiness, Hydration, Sleep, Cycle, Support, Today)
│   ├── ForgeMessagesExtension/    # iMessage partner/invite flow
│   ├── LiveActivities/            # Workout + cycle fertile-window Live Activities / Dynamic Island
│   └── docs/                      # iOS-specific planning docs
├── ForgeWidget/                  # Older single-widget scaffold — intentionally unwired, superseded by ForgeWidgetExtension
├── src/                          # Next.js 16 web/Android-track client (TypeScript)
│   ├── app/, components/, stores/, types/
├── backend/                      # Shared AWS backend (iOS + web + Android)
│   ├── infra/                     # Terraform + the deployed Lambda — the real backend
│   │   ├── lambda/                 # handler, routes, ai_router.py, services/{aria_engine,aria_context,guidance,emergency,...}.py
│   │   └── *.tf
│   ├── ai/
│   │   ├── simrunner/               # Offline AI evaluation harness (SimRunner)
│   │   ├── aria_cli.py              # Local ARIA CLI driver
│   │   └── app/                     # Deprecated legacy routes — do not add new logic here
│   ├── app/                        # Deprecated legacy stub, superseded by backend/infra/lambda
│   ├── simrunner/                   # Compat shim — re-exports backend.ai.simrunner for old import paths
│   ├── tests/                       # Python test suite (~100+ tests), exercises backend/infra/lambda
│   ├── dev_server.py
│   └── pyproject.toml / requirements.txt
├── shared/                        # Cross-language contracts + brand assets (api-contracts.ts, aria-mark.json)
├── .github/workflows/             # CI: swift, backend, frontend, simrunner, terraform, policy-validator-tf, repo-hygiene
├── package.json + pnpm            # Web tooling
└── README.md + planning docs (FORGE_ARIA_BUILD_PLAN.md, backend/ARIA_INTELLIGENCE_PLAN.md, backend/BACKEND_PLAN.md, …)
```

**Core Principles**
- One backend, two (or more) tailored frontends.
- Adapter/normalization layer for future platform integrations (HealthKit today, Strava/Garmin/WHOOP/Oura/Terra planned).
- Safety-gated generation: a deterministic guidance/emergency layer bands every ARIA response before it reaches a user, and SimRunner enforces that same policy in CI.
- Infrastructure as code + full CI gates.
- Native-first where it matters (HealthKit requires native iOS).

---

## Key Strengths

1. **iOS Polish & Ambition** — ForgeSwift/ aims for Apple Design Award level. Rich interactions, thoughtful UX for real lifestyles (coders, irregular sleepers), deep HealthKit integration, a full watchOS companion, home/lock-screen widgets, and extensive internal docs on award-winning features.
2. **Layered AI Safety** — A multi-model consensus ensemble (Claude Sonnet + Claude Opus + Grok) is reconciled through a deterministic medical-boundary policy and a native-only emergency-escalation path, so safety isn't a disclaimer bolted onto generation — it gates the model's output itself.
3. **SimRunner Safety Net** — Rare in AI health projects. Deterministic eval across 23 archetypes + regression gates + a ship/hold gate that reuses the production safety policy give real confidence when shipping contextual coaching.
4. **Production-Ready Backend Infra** — Terraform + Python Lambdas + DynamoDB + Bedrock is already structured for scale. Not a toy Flask app.
5. **Unified Data Vision** — Even in early data flow stage, the normalization + scoring + ARIA context pipeline is well thought out.
6. **Monorepo Discipline** — Clear separation, excellent CI (including automated repo-hygiene checks for redaction boundaries and duplicate declarations), and lots of high-signal documentation.

---

## Features (Shipped Highlights)

### Home & Readiness
- AI-generated daily greeting based on real data
- Composite readiness ring (sleep + recovery + load + HR trends)
- Today's plan + quick actions
- Live biometric snapshot

### ARIA AI Coach
- Multi-model consensus (Claude Sonnet 4.6 + Claude Opus 4.7 + Grok 4.6 via Bedrock) reconciled into one answer
- Companion memory: persistent long-term context, short-term memory, and daily self-review check-ins
- "Suggest, don't prescribe" policy baked into the guidance layer, not just prompt language
- Refreshed visual identity — a "fluid ember" breathing mark and welcome chime — plus an updated conversational voice
- Rich response cards (workout plans, sleep reports, insights)
- Coaching style adaptation (motivational, scientific, direct, balanced)
- Full context from normalized health history

### ARIA Safety & Medical Boundaries
- Deterministic `COACH` / `FIRST_AID` / `EMERGENCY` / `REFER_OUT` guidance bands with whole-word matching to avoid false positives
- Crisis-appropriate self-harm handling (988 Suicide & Crisis Lifeline) instead of generic first-aid steps
- Real-time vitals monitor that raises a native-only Emergency SOS escalation intent — the backend never places emergency calls itself
- The exact same policy module gates both production and SimRunner, so it can't silently drift

### Medication & Pharmacy Intelligence
- Real FDA drug data and federal drug lists
- Medications treated as a lifestyle signal, not a prescription to manage
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
- ForgeWatch Mindfulness Coach (breathing orb + haptic guidance + on-device suggestion engine)
- Watch complications for readiness, hydration, sleep quality, mindfulness resets, and active workouts
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
- Xcode 27 + iOS 27 / watchOS 27 simulator or device (for ForgeSwift and the ForgeWatch companion)
- Node.js 20+ + pnpm (pinned to `pnpm@10.29.2` via Corepack) for the web client
- Python 3.10+ (for backend/SimRunner)
- AWS CLI + Terraform (for infra)
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
- Select simulator or device (iOS 27)
- Build & run (⌘R)
- Grant HealthKit permissions when prompted
- Explore Home → Chat (ARIA) → Sleep → Workout flows
- Switch the scheme to **ForgeWatch** to build/run the watch companion (Mindfulness Coach + complications) on a paired watchOS 27 simulator

Many implementation notes live in `ForgeSwift/ForgeSwift/*.md` files.

### 3. Web Client (Next.js)
```bash
pnpm install
pnpm dev
```
Runs at http://localhost:3000 (or configured port). Uses the same backend concepts.

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

(`python -m backend.simrunner` still works as a compat alias for older scripts, but new commands should use `backend.ai.simrunner`.)

See `backend/ai/simrunner/README.md` for full options and architecture.

Dev server / CLI tools also available in `backend/`.

### 5. Infrastructure (Terraform)
```bash
cd backend/infra
terraform init
terraform plan
# terraform apply (with AWS credentials configured)
```

Full Lambda handlers, DynamoDB tables, IAM roles, etc. are defined here.

### Environment & Secrets
- HealthKit, cycle, and medication data stay on-device until explicitly synced (iOS client).
- Backend uses AWS secrets / SSM / env vars for Bedrock, DynamoDB, etc.
- Never commit real keys.

---

## SimRunner — Offline AI Evaluation

**SimRunner** is Forge's secret weapon for shipping trustworthy AI coaching.

It stress-tests the entire prompt → context → response pipeline using:
- 23 difficulty-graded behavioral archetypes across 5 tiers
- Deterministic data generation (same seed = identical output forever)
- 6 scoring dimensions with no LLM-as-judge
- A dummy multi-agent orchestrator for sanity-checking ARIA's conversational shape offline
- Mission-critical failure detection (e.g., recommending hard training at low readiness)
- A ship/hold medical-boundary gate that reuses ARIA's own production guidance policy
- SHIP / HOLD triage + detailed failure reports
- Committed golden baselines + CI regression gates
- Optional real Bedrock calls for live grading


We believe systems like SimRunner can help shape the next generation of AI assurance by making behavioral validation, regression control, and deployment gating first-class parts of the AI release process. It's the first true step to making AI more secure and more usable for all of us.

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
- [x] Apple Watch companion — `ForgeWatch` watchOS 27 target with a context-aware Mindfulness Coach (breathing orb + haptic guidance + on-device suggestion engine), readiness/sleep/mindfulness complications, on-wrist workout sessions, and a shared `ForgeCore` Swift package. See `ForgeSwift/WATCH_APP_IMPLEMENTATION_PLAN.md`.
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

Contributions are very welcome — especially in:
- New health platform adapters
- SimRunner archetype expansion or scoring refinements
- iOS UI/UX polish and animations
- Backend normalization/biometrics logic
- Documentation and tests

**Workflow**
1. Fork → feature branch
2. Make changes + tests where applicable
3. Run relevant CI locally (especially `python -m backend.ai.simrunner --all --gate` for AI changes)
4. Open PR with clear description

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
