# Wearables & labs integration plan

**Planning only.** No code changed, nothing deployed, no vendor account
created. Renamed from `TERRA_INTEGRATION_PLAN.md` — the decision below is to
split what that doc treated as one problem (Terra, doing both wearables and
implicitly nothing for labs) into two separate integrations, each picked for
its own domain rather than one vendor's bundle.

## 0. Decision

- **Wearables** (Oura, WHOOP, Garmin, Strava): **Open Wearables**
  (self-hosted, MIT-licensed) — §2.
- **Labs** (blood panels / biomarkers): a dedicated lab-testing API, not yet
  chosen between three candidates — §3.
- Explicitly *not* one vendor for both. A combined platform (Junction, née
  Vital) prices its lab-ordering capability at Enterprise tier regardless of
  whether its bundled wearables aggregation is used — paying for wearables
  aggregation Forge doesn't need in order to reach the labs tier is exactly
  the "obnoxious" cost this split avoids.

Sections 1–2 of the original Terra research are kept condensed below since
the scaffolding they describe (`CloudSourceLabel`, the `/integrations/{provider}/sync`
stub, the DynamoDB key shapes) is still the real target regardless of which
vendor fills it — only §3–5 (the vendor mechanics, auth flow, webhook
handling) actually change.

---

## 1. What's already in the codebase (unchanged from the Terra pass)

- `CloudSourceLabel.displayName()` —
  `ForgeSwift/ForgeCore/Sources/ForgeCore/Cloud/ForgeCloudContracts.swift:824-843`
  — currently renders `"Oura via Terra"` etc. **This needs to change** —
  the "via Terra" suffix is no longer accurate once Open Wearables is the
  actual pipe; either drop the suffix or rename it descriptively once the
  real integration lands.
- `POST /integrations/{provider}/sync` —
  `backend/infra/lambda/routes/integrations.py` — accepts
  `{apple-health, oura, whoop, garmin, strava}`, writes a fake `"syncing"`
  status. Still the right shape (provider-scoped sync trigger), still not
  wired to anything.
- `connection_key(user_id, provider)`, `sleep_key(user_id, date, source)`,
  `workout_log_key(user_id, started_at)`, `metric_key(user_id, metric_type,
  started_at)` — `backend/infra/lambda/storage/keys.py` — the DynamoDB shapes
  new data lands in, regardless of vendor.
- `aws_apigatewayv2_route.health` (`backend/infra/main.tf:553-557`) — the one
  existing unauthenticated route, still the pattern to copy for a webhook
  endpoint, whichever vendor sends it.
- iOS `ConnectedDevicesLibraryView`'s "Connect" button is still local-only —
  still needs real wiring regardless of vendor choice.

---

## 2. Wearables: Open Wearables

Verified via web search, September 2026 (`github.com/the-momentum/open-wearables`,
`themomentum.ai`):

- **What it is**: a self-hosted platform (Python backend + a frontend, MIT
  licensed) that normalizes wearable data behind one REST API. Covers
  cloud-based providers (Garmin, Oura, WHOOP, Strava, Suunto, Polar,
  Ultrahuman, Fitbit) plus SDK-based Apple HealthKit / Google Health Connect
  / Samsung Health integration — the SDK side is likely redundant for Forge,
  which already reads HealthKit natively.
- **How it works**: handles OAuth with each provider, normalizes into one
  schema, delivers data via webhooks (same shape of problem as Terra's
  webhooks — HMAC-style verification, event-per-data-type), and exposes a
  REST API for on-demand pulls. Also ships mobile SDKs and an MCP server
  (for LLM/agent access to wearable data) — interesting given ARIA, not
  scoped here.
- **Deployment — the real architectural difference from Terra**: this is
  **not** a SaaS API you call from the existing Lambda. It's a service you
  run: `docker compose up` with the official
  `themomentum/open-wearables-backend` + `-frontend` images, single-tenant
  per deployment. Forge's backend today is 100% serverless (one Lambda
  behind API Gateway, DynamoDB, no long-running compute — see
  `backend/infra/ROADMAP_IAC_READINESS.md` §1). Adopting Open Wearables adds
  a genuinely new infrastructure category: something has to keep a
  container running (ECS/Fargate task, EC2, or Momentum's managed hosting
  below) — this is not a drop-in Python import.
- **Cost**: MIT licensed, free to self-host, no per-user or per-API-call
  fees. Reported estimates: **~$6,000–12,000/year in cloud infra at 1,000
  users** (self-run, varies with retention/sync frequency), or
  **~$200–500/month at 100,000 active users** — notably cheaper than Terra's
  $399+/mo floor at both a small user base (a few dollars a month at
  Forge's likely current scale) and at large scale.
- **Managed option**: Momentum (the company behind it) offers hosted
  deployment on US or EU cloud infra (US for HIPAA, EU for GDPR) — you pay
  cloud costs at-cost plus a services fee for infra config/capacity
  planning/scaling; Enterprise tier adds HIPAA-eligible architecture, a BAA,
  and SLA-backed support. Given Forge is a health app, **the BAA/HIPAA-
  eligible tier is the relevant one to price out**, not the bare
  self-hosted default — self-hosting HIPAA-eligible infra yourself is
  extra work the managed tier is explicitly selling.
- **Migration precedent**: Momentum publishes a "Terra to Open Wearables"
  migration guide, meaning this is a well-trodden switch, not a fringe move.

Net: cheaper and no vendor lock-in, at the cost of Forge (or Momentum, paid)
owning a running service instead of just an API key — a real infrastructure
decision, not just a vendor swap.

---

## 3. Labs: three candidates, none with public self-serve pricing

Verified via web search, September 2026. Unlike the wearables space, none of
these publish pricing — all three are sales-quote/contract models, which
itself is informative (lab ordering typically requires contractual
relationships with the labs and, in most US states, a licensed physician
authorizing the order — this is a heavier compliance lift than wearables
data, and these vendors' business model reflects that).

| | What it is | Pricing signal |
|---|---|---|
| **Junction** (`junction.com`, formerly Vital, $18M Series A in 2025) | Nationwide lab ordering (all 50 states) + results from 10+ labs, in-person and at-home; same company as the wearables aggregator, but lab ordering is a separate, higher tier | Launch plan ($300/mo) is wearables-only (Link widget, device integrations). **Lab testing API requires their Enterprise plan** — quote-based, "no upcharges on the tests themselves" per their own pricing page, but no published number |
| **Health Gorilla** | Clinical interoperability network — orders/results across Labcorp, Quest, BioReference and others via a unified diagnostic API; positioned for clinical/EHR use cases (used at real scale — processed 12,000+ COVID test results) | No public pricing found; sales-quote model |
| **Ash Wellness** | Purpose-built lab-testing API for embedding at-home + in-person diagnostics into consumer/provider health apps; coordinates multiple lab networks behind one integration, 100+ test types, EHR-embeddable | No public pricing found; sales-quote model |

**I can't recommend one over the others without pricing** — that requires a
sales conversation with each, not something I can research further. What I
can say: Ash Wellness reads as the closest fit to "consumer health app
wants to offer lab tests" (its own positioning); Health Gorilla reads more
clinical/EHR-oriented; Junction's lab API is the same company Forge is
explicitly *not* using for wearables, so picking Junction for labs alone
means one fewer vendor relationship but re-introduces the "paying one
company for two things" dynamic the split was meant to avoid.

---

## 4. Fit against the existing architecture (updated for the split)

| Forge already has | Maps to |
|---|---|
| `connection_key(user_id, provider)` | One row per connected device, same as before — provider values become Open Wearables' own provider names (already `oura`/`whoop`/`garmin`/`strava`, matching) |
| `sleep_key`/`workout_log_key`/`metric_key` | Land Open Wearables' normalized webhook payloads, same as they would have landed Terra's |
| `aws_secretsmanager_secret.ai_provider` pattern | Copy for whatever Open Wearables deployment needs (its own API key/webhook secret) *and* separately for whichever labs vendor is chosen |
| `aws_apigatewayv2_route.health` (unauthenticated route precedent) | Still the pattern for a webhook route — now potentially two webhook routes (wearables + labs) instead of one |
| Nothing today | **New**: wherever Open Wearables actually runs (ECS/Fargate task or Momentum-managed) needs to be reachable from the Lambda, or the Lambda needs to be reachable from it for webhooks — this is new network topology, not just a new route |

---

## 5. Open decisions

1. **Where does Open Wearables run?** Self-hosted on new AWS infra (ECS/Fargate — a real addition to a currently 100%-serverless stack), or Momentum-managed? The HIPAA/BAA question in §2 likely decides this by itself for a health app.
2. **Which labs vendor** — Junction Enterprise, Health Gorilla, or Ash Wellness — needs an actual sales conversation for pricing before this can be scoped further; not resolvable by more research.
3. **Physician-order compliance for labs**: confirm which vendor handles the authorizing-physician requirement (most US states require one to order labs) versus expecting Forge to arrange it — this changes what Forge is responsible for operationally.
4. **Provider scope**: still open per the original Terra pass — ship all four (oura/whoop/garmin/strava) at once or start with one.
5. **`CloudSourceLabel`'s "via Terra" strings** need to change regardless of which wearables vendor lands, since they're now simply wrong.

## 6. What this pass could not verify

- Exact Open Wearables webhook payload schema and event types — same
  category of gap as Terra's, not fetched directly (only from search
  snippets and the GitHub repo's description).
- Real infra cost for Forge's actual expected user count — the $6–12k/yr
  and $200–500/mo figures are Momentum's published estimates for round
  user-count numbers, not a quote for Forge specifically.
- Any of the three labs vendors' actual pricing, contract terms, or which
  states/labs they each cover — none is publicly listed; needs direct
  outreach.
