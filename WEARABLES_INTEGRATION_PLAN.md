# Wearables integration plan

**Planning only.** No code changed, nothing deployed, no vendor account
created. Renamed twice now: `TERRA_INTEGRATION_PLAN.md` →
`WEARABLES_AND_LABS_INTEGRATION_PLAN.md` → this. History: Terra was the
original candidate, then the decision became "split wearables and labs
across two vendors," then labs was dropped from scope entirely — see §3 for
why. What's left is a single-vendor plan: Open Wearables for the four
device providers already referenced in the codebase.

## 0. Decision

**Wearables** (Oura, WHOOP, Garmin, Strava): **Open Wearables**
(self-hosted, MIT-licensed, no per-user fee) — §2.

## 1. What's already in the codebase

- `CloudSourceLabel.displayName()` —
  `ForgeSwift/ForgeCore/Sources/ForgeCore/Cloud/ForgeCloudContracts.swift:824-843`
  — currently renders `"Oura via Terra"` etc. **Needs to change** — the
  "via Terra" suffix is inaccurate once Open Wearables is the real pipe;
  either drop the suffix or rename it descriptively once the integration
  lands.
- `POST /integrations/{provider}/sync` —
  `backend/infra/lambda/routes/integrations.py` — accepts
  `{apple-health, oura, whoop, garmin, strava}`, writes a fake `"syncing"`
  status. Still the right shape (provider-scoped sync trigger), still not
  wired to anything.
- `connection_key(user_id, provider)`, `sleep_key(user_id, date, source)`,
  `workout_log_key(user_id, started_at)`, `metric_key(user_id, metric_type,
  started_at)` — `backend/infra/lambda/storage/keys.py` — the DynamoDB shapes
  new data lands in.
- `aws_apigatewayv2_route.health` (`backend/infra/main.tf:553-557`) — the one
  existing unauthenticated route, the pattern to copy for a webhook
  endpoint.
- iOS `ConnectedDevicesLibraryView`'s "Connect" button is still local-only —
  needs real wiring to actually call anything.

## 2. Open Wearables

Verified via web search, September 2026 (`github.com/the-momentum/open-wearables`,
`themomentum.ai`):

- **What it is**: a self-hosted platform (MIT licensed) that normalizes
  wearable data behind one REST API. Covers cloud-based providers (Garmin,
  Oura, WHOOP, Strava, Suunto, Polar, Ultrahuman, Fitbit) plus SDK-based
  Apple HealthKit / Google Health Connect / Samsung Health integration — the
  SDK side is likely redundant for Forge, which already reads HealthKit
  natively.
- **How it works**: handles OAuth with each provider, normalizes into one
  schema, delivers data via webhooks (HMAC-verified, event-per-data-type),
  and exposes a REST API for on-demand pulls. Also ships mobile SDKs and an
  MCP server (LLM/agent access to wearable data) — interesting given ARIA,
  not scoped here.
- **Deployment — the real architectural difference from a SaaS vendor**:
  not an API you call from the existing Lambda — a service you run:
  `docker compose up` with the official `themomentum/open-wearables-backend`
  + `-frontend` images, single-tenant per deployment. Forge's backend today
  is 100% serverless (one Lambda behind API Gateway, DynamoDB, no
  long-running compute — see `backend/infra/ROADMAP_IAC_READINESS.md` §1).
  Adopting Open Wearables adds a genuinely new infrastructure category:
  something has to keep a container running (ECS/Fargate task, EC2, or
  Momentum's managed hosting below) — not a drop-in Python import.
- **Cost**: MIT licensed, free to self-host, no per-user or per-API-call
  fees. Reported estimates: **~$6,000–12,000/year in cloud infra at 1,000
  users** (self-run, varies with retention/sync frequency), or
  **~$200–500/month at 100,000 active users** — cheaper than Terra's
  $399+/mo floor at both a small user base and at large scale.
- **Managed option**: Momentum (the company behind it) offers hosted
  deployment on US or EU cloud infra (US for HIPAA, EU for GDPR) — pay cloud
  costs at-cost plus a services fee. Enterprise tier adds HIPAA-eligible
  architecture, a BAA, and SLA-backed support. Given Forge is a health app,
  **the BAA/HIPAA-eligible tier is the relevant one to price out**, not the
  bare self-hosted default.
- **Migration precedent**: Momentum publishes a "Terra to Open Wearables"
  migration guide — a well-trodden switch, not a fringe move.

Net: cheaper and no vendor lock-in, at the cost of Forge (or Momentum, paid)
owning a running service instead of just an API key.

## 3. Labs: no dedicated integration — Apple Health only, for now

Decided (repo owner): no lab-ordering integration of any kind right now.
Concretely:

- ARIA is positioned as a lifestyle coach, not a clinical/medical product —
  ordering lab tests pulls the product toward a regulatory/liability surface
  (physician-authorization requirements in most US states, CLIA compliance,
  much more sensitive PHI) that doesn't fit that positioning.
- **If a user has lab results, the only path into Forge is Apple Health**
  (or, on a future non-iOS client, Google Health Connect). Whoever actually
  ran the test writes the result there; Forge already reads Apple Health
  natively and picks it up the same way it picks up everything else — no
  new code, no new vendor relationship, no new cost.
- Deliberately **not** routed through Open Wearables either, even though
  Open Wearables could theoretically proxy some lab-adjacent data — keeping
  it scoped to just the four wearable providers it's actually for keeps its
  API usage (and self-hosting cost, §2) predictable rather than growing
  scope creep into a second job.

**Kept on record, not being pursued**: Medplum (open-source, Apache 2.0,
self-hosted, FHIR-native lab ordering via `ServiceRequest`/
`DiagnosticReport`) is the one candidate that would actually clear a
self-hosted/low-cost bar if labs ever becomes a real product priority later
— worth revisiting then, not now. It still depends on connecting to a real
upstream lab network (e.g. Health Gorilla) to get a test actually processed,
and that piece's cost isn't confirmed to be low — so even "revisit Medplum
later" isn't a solved problem, just the least-bad starting point if this
comes back. The three vendor-hosted candidates also researched (Junction/
Vital Enterprise, Health Gorilla, Ash Wellness) are not being kept as
candidates — none are self-hostable or under a $200/mo-or-year floor.

## 4. Fit against the existing architecture

| Forge already has | Maps to |
|---|---|
| `connection_key(user_id, provider)` | One row per connected device — provider values already match Open Wearables' own provider names (`oura`/`whoop`/`garmin`/`strava`) |
| `sleep_key`/`workout_log_key`/`metric_key` | Land Open Wearables' normalized webhook payloads |
| `aws_secretsmanager_secret.ai_provider` pattern | Copy for Open Wearables' own API key/webhook secret |
| `aws_apigatewayv2_route.health` (unauthenticated route precedent) | Pattern for the new webhook route |
| Nothing today | **New**: wherever Open Wearables actually runs (ECS/Fargate task or Momentum-managed) needs to be reachable from the Lambda, or vice versa for webhooks — new network topology, not just a new route |

## 5. Open decisions

1. **Where does Open Wearables run?** Self-hosted on new AWS infra
   (ECS/Fargate — a real addition to a currently 100%-serverless stack), or
   Momentum-managed? The HIPAA/BAA question in §2 likely decides this by
   itself.
2. **Provider scope**: ship all four (oura/whoop/garmin/strava) at once, or
   start with one to validate the pipe end-to-end first?
3. **`CloudSourceLabel`'s "via Terra" strings** need to change regardless,
   since they're now simply wrong.
4. **Precedence vs. HealthKit**: some Open Wearables-covered devices (e.g.
   WHOOP) already write some data to Apple Health directly. If a user
   connects both paths, which source wins for the same night's sleep or
   workout? `SleepSurfacePresence.canonicalizeSource` already has the
   source-string plumbing to express a precedence rule — it just doesn't
   have one yet.

## 6. What this pass could not verify

- Exact Open Wearables webhook payload schema and event types — not fetched
  directly, only from search snippets and the GitHub repo's description.
- Real infra cost for Forge's actual expected user count — the $6–12k/yr and
  $200–500/mo figures are Momentum's published estimates for round
  user-count numbers, not a quote for Forge specifically.
