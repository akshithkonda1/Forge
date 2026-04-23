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
[![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift&logoColor=white)](https://swift.org)
[![Next.js](https://img.shields.io/badge/Next.js-14-black?logo=next.js)](https://nextjs.org)
[![TypeScript](https://img.shields.io/badge/TypeScript-5.x-blue?logo=typescript&logoColor=white)](https://typescriptlang.org)
[![License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)](CONTRIBUTING.md)

[Overview](#-overview) · [Architecture](#-architecture) · [Features](#-features) · [Getting Started](#-getting-started) · [Integrations](#-integrations) · [AI Coach](#-ai-coach) · [Roadmap](#-roadmap) · [Contributing](#-contributing)

</div>

---

## 🔥 Overview

**FORGE** is an AI-powered fitness platform designed to be the one app that unifies your entire health ecosystem. Instead of juggling five separate apps — one for running, one for sleep, one for nutrition, one for HRV, one for lifting — FORGE ingests data from all of them, normalizes it into a single coherent picture, and delivers personalized, intelligent coaching based on your *complete* physiological state.

The problem FORGE solves is simple: **fragmentation**. Your Garmin knows your run. Your WHOOP knows your recovery. Your Oura knows your sleep. But none of them talk to each other, and none of them can see the full picture. FORGE does.

### What makes FORGE different

| Other Apps | FORGE |
|---|---|
| Siloed to one platform or data source | Aggregates every major health platform |
| Generic recommendations | AI coaching personalized to your actual data |
| Static dashboards | Adaptive insights that evolve with your patterns |
| Platform lock-in | Works with hardware you already own |
| One-size-fits-all metrics | Unified health score across all dimensions |

---

## 🏗 Architecture

FORGE is built as a **monorepo** with a shared backend serving two native frontend clients. This design is intentional and deliberate — one piece of business logic, one integration layer, two perfectly tailored user experiences.

```
forge/
├── clients/
│   ├── ios/                        # Native SwiftUI app (iPhone)
│   │   └── Forge/
│   │       ├── ForgeApp.swift
│   │       ├── Models/             # Data models & types
│   │       ├── Stores/             # @Observable state management
│   │       ├── Theme/              # Design system, colors, typography
│   │       ├── Views/              # Screens & pages
│   │       │   ├── Onboarding/
│   │       │   ├── Home/
│   │       │   ├── Chat/
│   │       │   ├── Workout/
│   │       │   ├── Sleep/
│   │       │   ├── Progress/
│   │       │   └── Settings/
│   │       └── Components/         # Reusable UI components
│   │
│   └── web/                        # React/Next.js app (Android + Web)
│       ├── src/
│       │   ├── app/                # Next.js App Router pages
│       │   ├── components/         # Shared React components
│       │   ├── hooks/              # Custom React hooks
│       │   ├── lib/                # Utility functions & API client
│       │   └── types/              # TypeScript type definitions
│       ├── package.json
│       └── next.config.js
│
├── backend/                        # Shared TypeScript backend
│   ├── src/
│   │   ├── api/                    # REST API route handlers
│   │   ├── adapters/               # Platform-specific data adapters
│   │   │   ├── apple-health/
│   │   │   ├── strava/
│   │   │   ├── garmin/
│   │   │   ├── whoop/
│   │   │   ├── oura/
│   │   │   └── base-adapter.ts     # Abstract adapter contract
│   │   ├── normalizer/             # Unified data normalization layer
│   │   ├── ai/                     # AI coach logic & Claude API integration
│   │   ├── scoring/                # Unified health score algorithm
│   │   ├── auth/                   # Authentication & OAuth flows
│   │   └── db/                     # Database models & migrations
│   └── package.json
│
├── shared/                         # Shared types & API contracts
│   └── types/
│       ├── health.ts               # Health data types
│       ├── workout.ts              # Workout & activity types
│       ├── sleep.ts                # Sleep data types
│       └── api.ts                  # API request/response contracts
│
└── .github/
    └── workflows/                  # CI/CD pipelines
```

### Architectural Principles

#### 1. Platform-Agnostic Backend

The backend is completely decoupled from any frontend. It exposes a clean REST API with no knowledge of whether the calling client is a SwiftUI view, a React component, or a future Android Native screen. This means:

- **New frontend = zero backend changes**
- **Business logic lives in one place**
- All clients benefit from every backend improvement simultaneously

#### 2. Adapter / Normalization Layer

This is the core of FORGE's integration strategy. Every external health platform has its own data format, terminology, and API shape. The adapter layer solves this:

```
Apple Health ──────►┐
Strava ─────────────►│  Adapter Layer  ──►  Normalized Format  ──►  AI / Scoring / UI
Garmin ─────────────►│  (per-platform)      (universal schema)
WHOOP ──────────────►│
Oura ───────────────►┘
```

Each adapter implements the same `BaseAdapter` interface, mapping platform-specific data into FORGE's internal format. This means:

- Adding a new integration (e.g. Fitbit) = write one adapter
- Subsequent integrations get progressively easier
- The frontend never knows or cares which platform data came from

#### 3. Two Native Frontends, One Reason Each

| Frontend | Platform | Why Native? |
|---|---|---|
| SwiftUI | iPhone (iOS 17+) | HealthKit access requires native iOS code — no web API exists |
| React/Next.js | Android + Web | Cross-platform reach without a second native build |

Apple Health is the most comprehensive health data source available on iPhone, and it **cannot be accessed via a web API**. The only path to HealthKit is a native iOS app. The SwiftUI client exists to unlock this — it's a technical necessity, not just a UX preference.

---

## ✨ Features

### 🏠 Home Dashboard

The command center of your health. At a glance:

- **AI-generated daily greeting** — personalized, context-aware, based on your actual data
- **Readiness ring** — composite score across HRV, sleep quality, recovery, and training load
- **Today's plan** — AI-curated workout and recovery recommendations
- **Live biometric snapshot** — resting HR, HRV, steps, active calories
- **Cross-platform activity feed** — unified timeline from every connected source
- **Weather-aware suggestions** — outdoor training recommendations factoring in conditions

### 🤖 AI Coach (ARIA)

FORGE's AI coach, ARIA (Adaptive Recovery & Intelligence Assistant), is powered by the Claude API and has access to your complete health history across all integrated platforms. Not a generic chatbot — a contextual, data-aware training partner.

**What ARIA knows:**
- Your training load trends over the past 30 days
- Sleep quality and HRV patterns
- Workout history, PRs, and volume
- Recovery metrics from WHOOP/Oura
- Your stated goals and coaching style preferences

**What ARIA can do:**
- Build adaptive training plans that adjust based on your recovery state
- Explain *why* your HRV is lower today and what to do about it
- Suggest workout modifications when you're under-recovered
- Identify performance plateaus and recommend periodization changes
- Answer deep questions about physiology in plain language
- Rich response cards: inline workout plans, charts, sleep analysis reports

**Coaching styles:** Motivational, Scientific, Direct, Balanced — set during onboarding, adjustable anytime.

### 🏋️ Workout Tracking

Active workout experience with real-time data:

- **Exercise library** — searchable, categorized by muscle group and movement pattern
- **Live biometrics** — heart rate, calories burned, training zones (Z1–Z5)
- **Rest timer** — configurable auto-advance between sets
- **AI coach bar** — ask ARIA mid-workout without leaving the session
- **Set/rep/weight logging** — with progressive overload tracking across sessions
- **Post-workout summary** — auto-generated with AI insights and recovery recommendations
- **Workout templates** — save and repeat custom sessions

### 😴 Sleep Analysis

Deep sleep intelligence beyond just duration:

- **Sleep score ring** — composite score across multiple dimensions
- **Stage timeline** — visual breakdown of REM, deep, light, and awake periods
- **Key metrics** — sleep efficiency, time to sleep, total sleep time, restfulness
- **Trend charts** — 7/30/90 day rolling averages (Swift Charts)
- **Recovery correlation** — how last night's sleep affects today's readiness
- **AI sleep insight** — personalized analysis explaining what happened and why
- **Cross-source synthesis** — combines Apple Health, Oura, WHOOP for the most complete picture

### 📊 Progress & Analytics

Long-term performance tracking:

- **Activity heatmap calendar** — GitHub-style, color-coded by training intensity
- **Personal records tracker** — auto-detected PRs across all tracked lifts
- **Volume trends** — weekly/monthly training load visualization
- **Biometric history** — weight, body composition, resting HR over time
- **Platform comparison** — see where your data is coming from across integrations

### ⚙️ Settings & Integrations

- **Connected apps manager** — connect, disconnect, and manage all health platforms
- **Notification preferences** — granular control over alerts and coaching nudges
- **Units & display** — metric/imperial, date formats, language
- **Data privacy controls** — see exactly what data FORGE accesses and delete at will
- **AI preferences** — coaching style, response depth, topic focus
- **Export** — download your normalized data at any time

---

## 🚀 Getting Started

### Prerequisites

| Requirement | Version |
|---|---|
| Node.js | 18+ |
| npm / pnpm | Latest |
| Xcode | 15+ |
| iOS Simulator or Device | iOS 17+ |
| Claude API Key | [Get one](https://console.anthropic.com) |

### 1. Clone the repository

```bash
git clone https://github.com/akshithkonda1/Forge.git
cd Forge
```

### 2. Backend setup

```bash
cd backend
npm install

# Copy environment template
cp .env.example .env

# Fill in your credentials (see Environment Variables section below)
```

**Start the backend:**

```bash
npm run dev
# Backend runs at http://localhost:3001
```

### 3. Web client setup

```bash
cd clients/web
npm install

cp .env.local.example .env.local
# Add NEXT_PUBLIC_API_URL=http://localhost:3001
```

**Start the web client:**

```bash
npm run dev
# Web client runs at http://localhost:3000
```

### 4. iOS client setup

1. Open Xcode
2. Navigate to `clients/ios/Forge/`
3. Open `Forge.xcodeproj` (or `Forge.xcworkspace` if using CocoaPods)
4. Select your target device or simulator (iOS 17+)
5. Add your API URL to `Config.swift`:

```swift
enum Config {
    static let apiBaseURL = "http://localhost:3001/api"
    static let claudeAPIKey = "your_key_here" // Development only
}
```

6. Build and run (`⌘R`)

### 5. Environment Variables

Create a `.env` file in `backend/` with the following:

```env
# Server
PORT=3001
NODE_ENV=development

# Database
DATABASE_URL=postgresql://localhost:5432/forge

# Authentication
JWT_SECRET=your_super_secret_jwt_key
JWT_EXPIRES_IN=7d

# AI
ANTHROPIC_API_KEY=sk-ant-...

# Health Platform Integrations
STRAVA_CLIENT_ID=
STRAVA_CLIENT_SECRET=
STRAVA_REDIRECT_URI=http://localhost:3001/auth/strava/callback

GARMIN_CLIENT_ID=
GARMIN_CLIENT_SECRET=

WHOOP_CLIENT_ID=
WHOOP_CLIENT_SECRET=

OURA_CLIENT_ID=
OURA_CLIENT_SECRET=

# Optional: Terra API (middleware for multi-platform integration)
TERRA_API_KEY=
TERRA_DEV_ID=

# Optional: Vital (alternative middleware)
VITAL_API_KEY=
VITAL_TEAM_ID=
```

> **Note:** Apple Health data flows through the native iOS client directly — no backend credentials needed for HealthKit. The iOS app requests HealthKit permissions from the user at runtime.

---

## 🔗 Integrations

FORGE's value proposition is unified data. Here's the current integration status and roadmap:

### Supported Platforms

| Platform | Status | Data Types | Notes |
|---|---|---|---|
| **Apple Health (HealthKit)** | 🟡 In Progress | Workouts, sleep, HR, HRV, steps, calories, body metrics | iOS client only — no web API |
| **Strava** | 🔜 Planned | Runs, rides, swims, activities | REST API + OAuth |
| **Garmin Connect** | 🔜 Planned | Workouts, sleep, body battery, stress | REST API + OAuth |
| **WHOOP** | 🔜 Planned | Recovery, strain, sleep, HRV | REST API + OAuth |
| **Oura Ring** | 🔜 Planned | Sleep, readiness, HRV, activity | REST API + OAuth |
| **MyFitnessPal** | 🔜 Planned | Nutrition, calories | API access restricted — evaluating alternatives |
| **Google Fit / Health Connect** | 🔜 Planned | Android health data | Via web client |
| **Polar** | 🔜 Planned | Training load, sleep, HR | REST API |
| **Fitbit** | 🔜 Planned | Steps, sleep, HR | REST API |
| **Peloton** | 🔜 Planned | Classes, output, HR | Unofficial API |

### Integration Architecture (Deep Dive)

Every integration follows the same pattern, making each new one easier to add:

#### Step 1: OAuth Flow

The user connects their account. FORGE stores encrypted access/refresh tokens. The backend handles token refresh automatically.

```
User clicks "Connect Strava"
    → Backend generates OAuth URL
    → User authenticates with Strava
    → Strava redirects to callback
    → Backend exchanges code for tokens
    → Tokens stored (encrypted) in DB
    → Strava adapter marked active for user
```

#### Step 2: Data Sync

Once connected, data syncs on a schedule or on-demand:

```
StravaAdapter.sync(userId)
    → Fetch activities from Strava API
    → Map Strava Activity → ForgeWorkout
    → Normalize units (km → user preference)
    → Deduplicate against existing records
    → Upsert to FORGE database
    → Trigger health score recalculation
```

#### Step 3: Normalized Schema

All platform data maps to FORGE's internal types (defined in `shared/`):

```typescript
interface ForgeWorkout {
  id: string;
  source: 'strava' | 'apple_health' | 'garmin' | 'manual';
  startedAt: Date;
  duration: number;           // seconds
  activityType: ActivityType; // 'run' | 'ride' | 'strength' | ...
  distance?: number;          // meters
  elevationGain?: number;     // meters
  calories?: number;
  avgHeartRate?: number;
  maxHeartRate?: number;
  trainingLoad?: number;      // normalized TSS equivalent
  rawData: Record<string, unknown>; // original platform payload preserved
}
```

### Middleware Option: Terra API / Vital

Rather than building and maintaining 8+ individual integrations, FORGE is evaluating **Terra API** and **Vital** as unified health data middleware. These services:

- Act as a single integration point connecting to 50+ health platforms
- Handle OAuth, token management, and webhook sync for you
- Return data in a normalized format

**Trade-offs:**

| | Direct Integration | Terra API / Vital |
|---|---|---|
| Control | Full | Partial |
| Maintenance burden | High (per-platform) | Low (one SDK) |
| Platform coverage | Manual | 50+ out of the box |
| Cost | API costs only | Middleware subscription |
| Latency | Direct | One extra hop |

The adapter layer is designed to accommodate either approach — a `TerraAdapter` wraps the Terra SDK the same way a `StravaAdapter` wraps the Strava REST API.

---

## 🧠 AI Coach

ARIA (Adaptive Recovery & Intelligence Assistant) is the intelligence layer that transforms raw health data into actionable coaching.

### How It Works

```
User sends message or opens app
    ↓
Backend fetches last 30 days of normalized health data
    ↓
System prompt assembled with:
    - User profile (age, weight, goals, coaching style)
    - Recent sleep scores & patterns
    - HRV trends & current status  
    - Training load history
    - Recent workouts
    - Recovery metrics
    ↓
Claude API called with full context
    ↓
Response parsed and structured (text + optional rich cards)
    ↓
Displayed to user in Chat view
```

### System Prompt Philosophy

ARIA's system prompt is built to provide coaching, not just information. Key principles:

1. **Data-grounded** — Every recommendation is anchored in the user's actual numbers, not generic advice
2. **Recovery-first** — Training recommendations account for physiological readiness, not just schedule
3. **Explain the why** — ARIA teaches users to understand their own data, not just follow instructions
4. **Style-adaptive** — The tone and depth match the user's selected coaching style

### Rich Response Cards

ARIA responses can include structured data that renders as interactive UI components:

- **Workout plans** — Clickable sessions with exercises, sets, reps, and rest periods
- **Sleep reports** — Inline charts showing stage breakdown and trend data
- **Progress snapshots** — Embedded comparison tables and graphs
- **Recovery protocols** — Step-by-step guidance with timers and reminders

These are generated by prompting the Claude API to return structured JSON alongside prose, then rendering them in the Chat view.

---

## 📱 iOS Client (SwiftUI)

The native iPhone frontend built with SwiftUI and iOS 17+.

### Tech Stack

| Technology | Usage |
|---|---|
| SwiftUI | UI framework |
| `@Observable` | State management (iOS 17+ macro) |
| Swift Charts | Native data visualization |
| HealthKit | Apple Health data access |
| URLSession | Networking |
| Combine | Reactive data streams where needed |

### Key Design Decisions

#### `@Observable` over `ObservableObject`

FORGE uses Swift 5.9's `@Observable` macro (iOS 17+) rather than the older `ObservableObject` + `@Published` pattern. This reduces boilerplate significantly:

```swift
// Old pattern
class WorkoutStore: ObservableObject {
    @Published var workouts: [Workout] = []
    @Published var isLoading: Bool = false
}

// FORGE uses
@Observable
class WorkoutStore {
    var workouts: [Workout] = []
    var isLoading: Bool = false
}
```

#### Design System

All colors, typography, and spacing live in `Theme/`. Key components:

```swift
// Theme colors
extension Color {
    static let forgeOrange = Color("ForgeOrange")    // #FF6B35 — primary accent
    static let forgeDark = Color("ForgeDark")         // #0A0A0F — background
    static let forgeCard = Color("ForgeCard")         // #1A1A2E — card surface
    static let forgeText = Color("ForgeText")         // #F0F0F5 — primary text
}
```

#### HealthKit Integration

HealthKit requires explicit user permission for each data type. FORGE requests:

```swift
let readTypes: Set<HKObjectType> = [
    HKObjectType.workoutType(),
    HKObjectType.quantityType(forIdentifier: .heartRate)!,
    HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
    HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
    HKObjectType.quantityType(forIdentifier: .stepCount)!,
    HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
]
```

All HealthKit reads are then normalized and synced to the backend via the same API the web client uses, so ARIA has access to Apple Health data when generating coaching responses.

### Screen Map

| Screen | File | Key Functionality |
|---|---|---|
| Onboarding | `Views/Onboarding/` | 4-step flow: Welcome → Profile → Devices → Coaching style |
| Home | `Views/Home/HomeView.swift` | Dashboard, readiness ring, today's plan, activity feed |
| Chat | `Views/Chat/ChatView.swift` | ARIA conversation, rich cards, quick actions |
| Workout | `Views/Workout/WorkoutView.swift` | Active session, live biometrics, exercise navigation |
| Sleep | `Views/Sleep/SleepView.swift` | Score, stage timeline, trends, AI insight |
| Progress | `Views/Progress/ProgressView.swift` | Heatmap, PRs, volume trends |
| Settings | `Views/Settings/SettingsView.swift` | Integrations, preferences, account |

---

## 🌐 Web Client (React/Next.js)

The cross-platform frontend targeting Android and web browsers.

### Tech Stack

| Technology | Usage |
|---|---|
| Next.js 14 | Framework (App Router) |
| TypeScript | Type safety |
| Tailwind CSS | Styling |
| React Query | Data fetching & caching |
| Recharts | Data visualization |
| NextAuth.js | Authentication |

### Relationship to iOS Client

Both clients are intentionally designed to provide a **native-feeling experience on their respective platforms** rather than sharing UI components. The shared layer is the backend API and type definitions — not the UI. This means:

- SwiftUI client feels like an iPhone app
- React client feels like an Android/web app
- Both show the same data via the same backend

---

## 🧮 Unified Health Score

FORGE's health score is a composite metric that surfaces across all views and drives ARIA's recommendations. It synthesizes:

| Dimension | Weight | Data Sources |
|---|---|---|
| Sleep Quality | 25% | Apple Health, Oura, WHOOP |
| Recovery (HRV) | 25% | Apple Health, WHOOP, Garmin |
| Training Load Balance | 20% | All workout sources |
| Resting HR Trend | 15% | Apple Health, WHOOP, Oura |
| Activity Consistency | 15% | All sources |

The algorithm is normalized to a 0–100 scale. A score above 75 = green light for hard training. 50–74 = moderate. Below 50 = recovery day recommended.

This score is visible on the Home screen, informs ARIA's coaching tone, and trends over time in the Progress view.

---

## 🗺 Roadmap

### Phase 1 — Foundation ✅ (Complete)
- [x] SwiftUI iOS client — all screens (onboarding, home, chat, workout, sleep, progress, settings)
- [x] React/Next.js web/Android client prototype
- [x] Backend architecture design (adapter/normalization pattern)
- [x] ARIA AI coach (Claude API) — conversation flow and rich response cards
- [x] Monorepo structure

### Phase 2 — Real Data 🔄 (In Progress)
- [ ] Apple Health (HealthKit) native integration
- [ ] Backend REST API (complete endpoints, auth, database)
- [ ] Real data persistence (PostgreSQL)
- [ ] User authentication (JWT + refresh tokens)
- [ ] End-to-end data flow: HealthKit → iOS → Backend → ARIA

### Phase 3 — Platform Integrations 🔜
- [ ] Strava
- [ ] Garmin Connect
- [ ] WHOOP
- [ ] Oura Ring
- [ ] Terra API / Vital middleware evaluation

### Phase 4 — Intelligence Layer 🔜
- [ ] Unified health score v1 (algorithm implementation)
- [ ] Adaptive training plan generation
- [ ] Trend detection & anomaly alerts
- [ ] Periodization recommendations
- [ ] Sleep coaching protocols

### Phase 5 — Growth 🔜
- [ ] Android (Google Health Connect integration)
- [ ] Apple Watch companion app
- [ ] Social features (friends, challenges)
- [ ] Coach/athlete pairing mode
- [ ] Export & integrations API

---

## 🤝 Contributing

Contributions are welcome. FORGE is a big vision — health platform integrations, ML scoring, AI coaching improvements — and there's a lot of surface area to work on.

### Development workflow

```bash
# Fork the repo
# Create a feature branch
git checkout -b feat/your-feature-name

# Make your changes
# Write tests if applicable
# Commit with a descriptive message
git commit -m "feat: add Garmin adapter for workout sync"

# Push and open a PR
git push origin feat/your-feature-name
```

### Where to contribute

- **New adapters** — Adding a new health platform integration is well-scoped and high impact
- **Health score algorithm** — The scoring model needs research and refinement
- **ARIA prompting** — Improving AI coaching quality through better system prompts
- **UI components** — Both SwiftUI and React components
- **Tests** — Coverage is an area of opportunity

### Commit convention

```
feat:     New feature or integration
fix:      Bug fix
refactor: Code change without feature/fix
docs:     Documentation only
test:     Test coverage
chore:    Build, dependencies, config
```

---

## 📄 License

MIT License — see [LICENSE](LICENSE) for details.

---

## 🙏 Acknowledgments

- [Anthropic](https://anthropic.com) — Claude API powering ARIA
- [Apple Developer](https://developer.apple.com) — HealthKit framework
- [Terra API](https://tryterra.co) — Health data middleware (under evaluation)

---

<div align="center">

Built with obsession for the people who take their health seriously.

**FORGE** — *Forge yourself.*

</div>
