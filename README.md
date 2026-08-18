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

[![iOS](https://img.shields.io/badge/iOS-17%2B-black?logo=apple&logoColor=white)](https://developer.apple.com/ios/)
[![SwiftUI](https://img.shields.io/badge/SwiftUI-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![Python](https://img.shields.io/badge/Python-3.10%2B-blue?logo=python&logoColor=white)](https://python.org)
[![AWS](https://img.shields.io/badge/AWS-Serverless-ff9900?logo=amazon-aws&logoColor=white)](https://aws.amazon.com)
[![Terraform](https://img.shields.io/badge/Terraform-IaC-844FBA?logo=terraform&logoColor=white)](https://terraform.io)
[![Next.js](https://img.shields.io/badge/Next.js-14-black?logo=next.js)](https://nextjs.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)

[Overview](#overview) · [Current State](#current-state--whats-built) · [Architecture](#architecture) · [Key Strengths](#key-strengths) · [Features](#features) · [Getting Started](#getting-started) · [SimRunner](#simrunner--offline-ai-evaluation) · [Roadmap](#roadmap) · [Contributing](#contributing)

</div>

---

## Overview

**Forge** is building the definitive unified health AI platform. Instead of five siloed apps (Garmin for runs, WHOOP for recovery, Oura for sleep, Apple Health for everything else, and a generic fitness tracker), Forge ingests data from everywhere, normalizes it into one coherent picture, and delivers **contextual, recovery-first AI coaching** tailored to real human lives — coders with irregular sleep, deep sleepers, desk workers, athletes, and everyone in between.

The core problem it solves: **fragmentation kills insight**. Your data exists, but it's scattered. Forge makes it actionable.

### What Makes Forge Different

| Traditional Apps                  | Forge                                      |
|-----------------------------------|--------------------------------------------|
| Siloed to one hardware ecosystem  | Aggregates 50+ sources via adapters + middleware |
| Generic "move more" advice        | Data-grounded, personalized ARIA coaching  |
| Static dashboards                 | Adaptive plans that evolve with your patterns |
| One-size-fits-all metrics         | Unified readiness + recovery intelligence  |
| Platform lock-in                  | Works with the hardware you already own    |

**Vision**: The health app that feels like it *knows* you — because it actually sees the full picture.

---

## Current State — What's Built (July 2026)

Forge is well past the prototype stage. The monorepo contains production-grade pieces across the stack:

### iOS (Primary — ForgeSwift/)
- **Mature native SwiftUI app** (iOS 17+)
- Full feature set: Home dashboard with readiness ring + AI greeting + today's plan, rich **ARIA ChatView** with contextual cards, detailed **SleepView** (stages, timelines, trends, AI insights), **WorkoutView** (live biometrics, rest timer, exercise nav, progressive overload), Lifestyle, Profile, multi-step Onboarding with coaching style selection.
- Heavy investment in polish: custom design system, Swift Charts, HealthKitManager (deep integration), advanced UI patterns (glassmorphism, particles, animations, Aurora Orb components), accessibility, widgets (ForgeWidget).
- Dozens of high-quality planning and implementation docs living alongside the code (AWARD_WINNING_*, CHATVIEW_IMPROVEMENTS, IMPLEMENTATION_SUMMARY, etc.).
- **This is the canonical, most advanced client.**

### Web / Cross-Platform (src/ + Next.js)
- Parallel React/Next.js 14 frontend (TypeScript + Tailwind) targeting web + Android.
- Matching flows: home, chat (with rich cards), onboarding, sleep, workout, progress (heatmap, PRs), settings.
- Shared state (Zustand), API client, types.
- Designed to feel native on its platform while sharing the exact same backend.

### Backend & AI (`backend/`)
- **One Python serverless backend** on AWS (Lambda + API Gateway + DynamoDB + Bedrock) for iOS, web, and Android.
- Terraform and the deployable Lambda live together at `backend/infra/`.
- ARIA, Claude/Bedrock, and SimRunner live under `backend/ai/`.
- REST routes (chat, coach, sleep, workouts, dashboard, profile, integrations, health).
- Seed data, `dev_server.py`, `backend/ai/aria_cli.py`.

### SimRunner — Offline AI Evaluation Harness (`backend/ai/simrunner/`)
One of Forge's standout engineering achievements:
- Fully deterministic, stdlib-only Python harness.
- 20 behavioral archetypes (Tier 1 compliant athlete → Tier 5 system gamers/ambiguous signals).
- 6-dimension scoring (context utilization, actionability, epistemic honesty, chronotype alignment, etc.).
- Mission-critical triage with SHIP/HOLD verdicts.
- Full AWS Bedrock model catalog baselines + regression gates against golden files.
- Multi-seed statistical reporting.
- CI-integrated (fails builds on regressions or new safety violations).
- Real-API opt-in mode for live testing.

This is how you safely ship an AI health coach that gives advice like "your readiness is 38 — today is a recovery day."

### Shared Layer
- `shared/api-contracts.ts` for type safety between frontend and backend (Pydantic models in Python stay in sync manually for now).
- Strong CI/CD: separate workflows for Swift, Python backend, frontend, SimRunner, Terraform policy validation, AWS deploy.

`ForgeSwift/` is the sole iOS codebase — no parallel/duplicate client remains.

---

## Architecture

```
forge/
├── ForgeSwift/                  # Canonical iOS (SwiftUI + HealthKit) — most mature
│   ├── ForgeSwift/              # App source, Views, Models, Services, Theme
│   ├── ForgeWidget/             # Widgets
│   └── docs/                    # iOS-specific planning docs
├── src/                         # Next.js web/Android client (TypeScript)
│   ├── app/, components/, stores/, types/
├── backend/                     # Shared AWS backend (iOS + web + Android)
│   ├── infra/                   # Terraform + deployable Lambda
│   │   ├── lambda/              # handler, routes, ARIA engine, Bedrock
│   │   └── *.tf
│   ├── ai/                      # ARIA CLI + SimRunner + local AI package
│   ├── tests/                   # Python unit tests
│   ├── dev_server.py
│   └── pyproject.toml / requirements.txt
├── shared/                      # Cross-language contracts (api-contracts.ts)
├── .github/workflows/           # CI for everything (swift, backend, frontend, simrunner, terraform, aws)
├── package.json + pnpm          # Web tooling
└── README.md + planning docs at root
```

**Core Principles**
- One backend, two (or more) tailored frontends.
- Adapter/normalization layer for future platform integrations (HealthKit today, Strava/Garmin/WHOOP/Oura/Terra planned).
- Safety-first AI via SimRunner before any user sees advice.
- Infrastructure as code + full CI gates.
- Native-first where it matters (HealthKit requires native iOS).

---

## Key Strengths

1. **iOS Polish & Ambition** — ForgeSwift/ aims for Apple Design Award level. Rich interactions, thoughtful UX for real lifestyles (coders, irregular sleepers), deep HealthKit integration, and extensive internal docs on award-winning features.
2. **SimRunner Safety Net** — Rare in AI health projects. Deterministic eval + regression gates give real confidence when shipping contextual coaching.
3. **Production-Ready Backend Infra** — Terraform + Python Lambdas + DynamoDB + Bedrock is already structured for scale. Not a toy Flask app.
4. **Unified Data Vision** — Even in early data flow stage, the normalization + scoring + ARIA context pipeline is well thought out.
5. **Monorepo Discipline** — Clear separation, excellent CI, lots of high-signal documentation.

---

## Features (Shipped Highlights)

### Home & Readiness
- AI-generated daily greeting based on real data
- Composite readiness ring (sleep + recovery + load + HR trends)
- Today's plan + quick actions
- Live biometric snapshot

### ARIA AI Coach
- Contextual chat powered by Claude family via Bedrock
- Rich response cards (workout plans, sleep reports, insights)
- Coaching style adaptation (motivational, scientific, direct, balanced)
- Full context from normalized health history

### Sleep Intelligence
- Stage timeline (REM/deep/light/awake) with Swift Charts
- Trends, efficiency, correlations to next-day readiness
- AI-generated personalized insights

### Workout Experience
- Active session tracking with live HR/calories/zones
- Rest timer, exercise library navigation
- Set/rep/weight logging + progressive overload
- Post-session AI summary

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
- Xcode 15+ + iOS 17+ simulator/device (for ForgeSwift)
- Node.js 18+ + pnpm (for web client)
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
- Select simulator or device (iOS 17+)
- Build & run (⌘R)
- Grant HealthKit permissions when prompted
- Explore Home → Chat (ARIA) → Sleep → Workout flows

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
- HealthKit data stays on-device until explicitly synced (iOS client).
- Backend uses AWS secrets / SSM / env vars for Bedrock, DynamoDB, etc.
- Never commit real keys.

---

## SimRunner — Offline AI Evaluation

**SimRunner** is Forge's secret weapon for shipping trustworthy AI coaching.

It stress-tests the entire prompt → context → response pipeline using:
- 20 difficulty-graded behavioral archetypes
- Deterministic data generation (same seed = identical output forever)
- 6 scoring dimensions with no LLM-as-judge
- Mission-critical failure detection (e.g., recommending hard training at low readiness)
- SHIP / HOLD triage + detailed failure reports
- Committed golden baselines + CI regression gates
- Optional real Bedrock calls for live grading

This level of rigor is uncommon in consumer AI health apps and is a major differentiator for safety and defensibility.

Full documentation: [`backend/ai/simrunner/README.md`](backend/ai/simrunner/README.md)

---

## Roadmap

### Phase 1 — Foundation (Mostly Complete)
- [x] Mature SwiftUI iOS client (ForgeSwift/) with HealthKit, rich ARIA chat, sleep/workout views, design system
- [x] Next.js web client prototype with matching flows
- [x] Python backend services + ARIA engine
- [x] AWS serverless infra (Terraform + Lambda handlers + DynamoDB)
- [x] SimRunner offline eval harness with regression gates + full model catalog
- [x] Monorepo + comprehensive CI/CD

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
- [ ] Adaptive training plans
- [ ] Deeper trend/anomaly detection
- [ ] Expanded SimRunner archetypes + prompt A/B testing in CI
- [x] Apple Watch companion — **v1 underway**: `ForgeWatch` watchOS 10 target with context-aware Mindfulness Coach (breathing orb + haptic guidance + on-device suggestion engine), readiness/sleep/mindfulness complications, and a shared `ForgeCore` Swift package. See `ForgeSwift/WATCH_APP_IMPLEMENTATION_PLAN.md`.

### Phase 5 — Growth
- Android native improvements, social features, export APIs, etc.

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
3. Run relevant CI locally (especially `python -m backend.simrunner --gate` for AI changes)
4. Open PR with clear description

See existing high-quality docs in `ForgeSwift/ForgeSwift/` and `backend/ai/simrunner/` for style and depth expectations.

---

## License

Forge is a proprietary product. That said, Forge's technology can be used to inspire, not imitate. Imitations are not encouraged and will be prosecuted if it can be proved in a court of law that a component of the product was stolen or copied under a similar name. In short, Forge can be used as inspiration, not as a rebranded product. 
---

## Acknowledgments

- Anthropic (Claude via Bedrock) for powering ARIA
- Apple for HealthKit and SwiftUI
- The broader open-source health/fitness data community

---

<div align="center">

**Forge** is being built with an obsession for people who take their health seriously.

*Forge yourself.*

Questions, ideas, or want to collaborate? Open an issue or reach out.

</div>
