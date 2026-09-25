# Open Wearables integration (WS4 / issue #366)

**Status:** design + adapter scaffold. Draft only. No Terraform apply, no AWS
changes, no Swift or ARIA-engine edits.

This is the scoping document for integrating the project Akshith calls
"OpenWearable" into Forge as **self-hosted AWS infrastructure**, so wearable
sync is costed as compute and storage rather than a metered per-call or
per-user API. The prior planning note (`WEARABLES_INTEGRATION_PLAN.md`) already
pointed at this project; this document names it precisely, prices a
free-first AWS path, and maps the data into Forge's existing ingest.

---

## 1. Identified project

| Field | Value |
|---|---|
| Canonical name | **Open Wearables** |
| Also seen as | OpenWearable, Open Wearable, "open-wearables" |
| Repo | https://github.com/the-momentum/open-wearables |
| Docs / site | https://openwearables.io · https://openwearables.io/docs |
| Maintainer | [Momentum](https://themomentum.ai/) (company). Active committers include Bartek Michalak and Dependabot. |
| License | **MIT** (`LICENSE`, copyright 2025 Momentum) |
| Homepage claim | "Self-hosted platform to unify wearable health data through one AI-ready API" |
| Activity (checked 2026-09-25) | ~2.2k GitHub stars, ~400 forks, ~160 open issues. Commits the same day (docs, Whoop steps, telemetry). Pre-1.0: they tell production users to pin official images (e.g. `0.7.0`), not `main` / `nightly`. |
| Runtime | FastAPI (Python 3.13), PostgreSQL 18, Redis 8, Celery + Celery Beat, optional Flower + Svix. React / TanStack developer portal. Official images: `themomentum/open-wearables-backend`, `themomentum/open-wearables-frontend`. |

No other public project matches the brief as well. Nearby names that are
**not** this:

| Candidate | Why it is not the fit |
|---|---|
| **Terra** (tryterra.co) | Hosted aggregator. Metered / seat-priced SaaS. Already rejected in `WEARABLES_INTEGRATION_PLAN.md`. |
| **Junction / Vital** | Same class: commercial API, not self-hostable MIT infra. |
| **Open mHealth / Open Humans** | Schemas or research donation, not a multi-vendor OAuth + sync platform. |
| **Building each vendor API in Forge** | Possible, but this issue is specifically "integrate the open-source wearable-data project." |

**Recommendation:** adopt **Open Wearables, self-hosted on AWS**, as the
cloud-provider pipe (Oura, WHOOP, Garmin, Strava first). Keep Apple Health on
the existing HealthKit path. Do not pay Momentum Enterprise until a BAA / SLA
is a hard requirement. Do not rewrite their stack onto DynamoDB.

---

## 2. License vs a closed-source App Store app + our backend

MIT is **compatible**.

- Forge itself is source-available / all-rights-reserved (`LICENSE.md`). That
  does not conflict with *depending on* an MIT service.
- MIT lets us run, fork, modify, and ship Open Wearables in a commercial
  product, including a closed-source iOS binary and a proprietary Lambda
  backend, provided we keep the Momentum copyright notice on copies of *their*
  software.
- MIT is not copyleft and not AGPL. Linking from Forge, calling their REST
  API, or running their containers in our VPC does not force Forge source
  disclosure.
- Practical boundary: **run their code as pinned containers** (or a clearly
  marked fork) rather than pasting it into `backend/infra/lambda`. The adapter
  in this PR is original Forge mapping code.
- Their iOS SDK is a separate repo. **Do not add it.** Forge already reads
  HealthKit natively; shipping a second HealthKit SDK would duplicate PII
  paths and App Store review surface.

If we later fork, keep the MIT header on every distributed file we took from
upstream and pin a release tag.

---

## 3. Wearables, APIs, and whether we still need vendor OAuth apps

**Yes. Self-hosting does not replace vendor developer programs.**

Open Wearables performs the OAuth dance, token refresh, webhook ingest, and
normalization. Each *cloud* provider still requires Forge (the organization)
to register an application and put client id / secret / redirect URI into the
Open Wearables deployment.

| Provider | Path | Vendor app / credentials still required? | Notes |
|---|---|---|---|
| Garmin | Cloud OAuth | **Yes** — Garmin Developer Program approval | Live workouts; sleep coverage still partial / upcoming in their matrix |
| Oura | Cloud OAuth | **Yes** — Oura developer app | Live |
| WHOOP | Cloud OAuth | **Yes** — WHOOP developer app; user needs a WHOOP membership | Workouts + sleep live; timeseries marked unavailable in their coverage table |
| Strava | Cloud OAuth | **Yes** | Live |
| Polar | Cloud OAuth | **Yes** — Polar API program | Live |
| Suunto | Cloud OAuth | **Yes** — Suunto Developer Program | Live |
| Ultrahuman | Cloud OAuth | **Yes** | Live |
| Fitbit | Cloud OAuth | **Yes** | **Web API turns down September 2026**; they point at Google Health API as the migration |
| Withings | Cloud OAuth | **Yes** | Per-user webhook subscriptions |
| Google Health API | Cloud OAuth | **Yes** — GCP project | Live |
| Apple Health / HealthKit | On-device SDK | No OAuth; would need their iOS SDK | **Skip.** Forge already ingests HealthKit via `/health/batch` and `/ai/observe` |
| Google Health Connect / Samsung Health | On-device SDK | No OAuth | Android later; out of this issue's iOS-beta path |

Phase-1 Forge scope stays the four providers already stubbed in
`POST /integrations/{provider}/sync`: `oura`, `whoop`, `garmin`, `strava`.

---

## 4. Architecture and runtime (what cannot be a Lambda)

Open Wearables is a **long-running, single-tenant** stack:

```
wearable vendor APIs
        │  OAuth + webhooks / polling
        ▼
┌─────────────────────────────────────────────┐
│  Open Wearables (our VPC)                   │
│  FastAPI app  │  Celery worker + beat       │
│  PostgreSQL 18│  Redis 8 (broker + cache)   │
│  optional Svix (outgoing webhooks)          │
└─────────────────────────────────────────────┘
        │  HMAC-signed POST (Svix headers)
        ▼
┌─────────────────────────────────────────────┐
│  Forge (already shipped)                    │
│  API Gateway + Lambda adapter               │
│  DynamoDB USER#{cognito-sub}                │
│  /health/batch  /ai/observe                 │
│  /sleep/sessions  /workouts/logs            │
│  ARIA fusion → iOS / web                    │
└─────────────────────────────────────────────┘
```

- **Lambda is not feasible for Open Wearables itself.** Celery workers, Beat
  schedules, Redis, and a Postgres-backed FastAPI process need a process that
  stays up. Forcing that onto Lambda + DynamoDB is a rewrite, not a host.
- **Lambda is the right place for the Forge adapter:** verify Svix signatures,
  map the payload (this PR), write through existing ingest routes.
- **DynamoDB vs their native DB:** keep **PostgreSQL** as Open Wearables'
  source of truth (connections, raw sync, timeseries). Keep **DynamoDB** as
  Forge's product store (`METRIC#`, `SLEEP#`, `WORKOUT#`, `ARIA#CONTEXT`). Do
  not try to make Open Wearables speak DynamoDB.
- Official compose services: `app`, `db`, `redis`, `celery-worker`,
  `celery-beat`, `frontend`, optional `flower` and `svix-server` (Svix needs
  its own `svix` database). Production should pin
  `themomentum/open-wearables-backend` / `-frontend` release tags.
- Turn **telemetry off** (`TELEMETRY_ENABLED=false` or `DO_NOT_TRACK=1`).
  Upstream sends a daily anonymous ping; we do not want a health-adjacent
  product phoning home by default.

---

## 5. AWS hosting options (no apply)

All-AWS, us-east-1, free-first, **$25/month ceiling at the starting scale**.

### 5.1 What to run where

| Piece | Where | Why |
|---|---|---|
| Open Wearables app + Celery + Redis + Postgres | **One EC2** at 100 MAU; **ECS Fargate + RDS + ElastiCache** only when a single box is too small | Long-running workers |
| Developer portal | Same box, or omit in production and use the API | Not user-facing |
| Outgoing webhooks | Svix container on the box, or pull-API backfill if we disable outgoing webhooks | Extra DB if enabled |
| Forge adapter | **Existing Lambda** behind API Gateway | Burst ingest, already how `/health/batch` works |
| Forge data | **Existing DynamoDB** | No new table required for the scaffold |
| Tokens / OAuth secrets / webhook signing key | **SSM Parameter Store** (SecureString). Standard parameters are $0 | Issue constraint. Do not put secrets in env files on disk or in git |

Avoid **NAT Gateway** ($0.045/hour ≈ $33/month by itself — already over the
ceiling). Put the box in a public subnet with a tight security group (443 in
from vendor webhook IPs / Cloudflare as documented; 22 or SSM Session Manager
for admin). Prefer **SSM Session Manager** so we do not open SSH.

Fargate is the right *scale-up* shape (stateless app + worker replicas) once
MAU or HA requires it. It is the wrong *day-one* shape: a minimal split
(app + worker + beat + RDS + Redis + ALB) clears $25 before traffic.

### 5.2 Published us-east-1 rates used below

Estimates. 730 hours/month. Sources: [AWS Fargate pricing](https://aws.amazon.com/fargate/pricing/)
examples (Linux/x86 $0.000011244 per vCPU-second ≈ $0.04048/vCPU-hour,
$0.000001235 per GB-second ≈ $0.004445/GB-hour; Linux/ARM
$0.0000089944/s ≈ $0.03238/vCPU-hour, $0.0000009889/s ≈ $0.00356/GB-hour);
[EC2 On-Demand](https://aws.amazon.com/ec2/pricing/on-demand/) T4g Linux
($0.0168/hour `t4g.small`, $0.0336 `t4g.medium`, $0.0672 `t4g.large`);
RDS PostgreSQL Single-AZ `db.t4g.micro` $0.016/hour, `db.t4g.small`
$0.032/hour; EBS gp3 $0.08/GB-month; public IPv4 $0.005/hour; NAT Gateway
$0.045/hour; ALB $0.0225/hour; Lambda $0.20/1M requests +
$0.0000166667/GB-second; HTTP API $1.00/1M; DynamoDB on-demand
$1.25/1M WRU, $0.25/1M RRU; SSM standard parameters $0.

### 5.3 Self-hosted monthly estimate vs hosted

Momentum's public pricing ([openwearables.io/pricing](https://openwearables.io/pricing)):

- **Open Source:** $0 forever. MIT, all providers, REST + webhooks, community Discord. You pay cloud.
- **Enterprise:** custom. HIPAA-eligible setup, BAA, SLA, they deploy on your AWS/GCP/Azure. **No public per-MAU or per-call rate card.** Their FAQ also says a self-serve "managed cloud" product is **not currently available**.

So "hosted service" cannot be priced as "$X / 100 MAU." The honest comparison
is **our AWS estimate vs "custom professional services + cloud at-cost,"**
which will not land under $25/month.

| Scale | Self-hosted on AWS (recommended shape) | Est. $/mo | Hosted / Enterprise | Under $25? |
|---|---|---|---|---|
| **100 MAU** | One `t4g.small` (2 vCPU, 2 GB) running official compose: app + worker + beat + Postgres + Redis. Public IPv4, 30 GB gp3, CloudWatch ~5 GB ingest, Lambda adapter + DynamoDB writes | **~$21** = 12.26 compute + 3.65 IPv4 + 2.40 disk + ~2.50 logs + <0.20 adapter/DDB | Custom / not self-serve. Treat as **n/a (>> $25)** | **Yes** (self-host) |
| **1k MAU** | Same pattern on `t4g.medium` (4 GB), 80 GB disk, more logs. Still one box if we store daily summaries + 30-day raw retention, not year-long 1-second HR | **~$40** = 24.53 compute + 3.65 IPv4 + 6.40 disk + ~5 logs + ~0.50 adapter | Custom | **No** |
| **10k MAU** | ECS Fargate ARM: app 0.5 vCPU/1 GB + worker 0.5/1 + beat 0.25/0.5; RDS `db.t4g.small` + 100 GB; ElastiCache `cache.t4g.micro`; ALB; **no NAT** | **~$119** = 14.42+14.42+7.21 Fargate + 23.36+11.50 RDS + 11.68 Redis + 16.43 ALB + ~15 logs + ~5 adapter/DDB | Custom | **No** |

100 MAU line items:

| Item | Monthly |
|---|---|
| EC2 `t4g.small` Linux | 730 × $0.0168 = $12.26 |
| Public IPv4 | 730 × $0.005 = $3.65 |
| EBS gp3 30 GB | 30 × $0.08 = $2.40 |
| CloudWatch Logs (order-of 5 GB ingest) | ~$2.50 |
| Lambda + HTTP API + DynamoDB writes (~30k events) | < $0.20 |
| SSM SecureString parameters | $0 |
| **Total** | **~$21** |

Do **not** add: NAT Gateway (~$33), ALB (~$16), separate RDS (~$12+),
ElastiCache (~$12), Multi-AZ, or a second Fargate service. Those are how a
"correct" HA diagram blows the ceiling.

Adapter traffic is negligible at all three sizes relative to the always-on
box. The jump from 100 → 10k is **retention of high-frequency timeseries**,
not Lambda.

These are estimates from published list prices, not a quote. Actuals move
with log volume, public-IPv4 policy, burst CPU-credits on T4g, and how
aggressive we are about dropping raw HR samples.

---

## 6. Data flow into Forge

### 6.1 End-to-end

1. User taps Connect on iOS/web for `oura` | `whoop` | `garmin` | `strava`.
2. Forge creates (or reuses) an Open Wearables user whose **external key is
   the Cognito `sub`**. Store `OW user_id ↔ sub` in DynamoDB
   (`CONNECTION#{provider}` plus an `externalUserId` attribute). Never treat
   the Open Wearables UUID as a Forge user id.
3. Open Wearables returns a connection link / widget. User completes vendor
   OAuth on that host.
4. Celery syncs. Open Wearables POSTs Svix-signed webhooks to a new
   unauthenticated API Gateway route (same precedent as today's
   `GET /health` unauthenticated route — HMAC, not a public write).
5. Lambda adapter (`services.open_wearables.adapt_webhook`) maps the
   envelope to:
   - `POST /health/batch` metrics (durable `METRIC#` rows)
   - `POST /ai/observe` samples (classify → BodyModel → ARIA context)
   - `POST /sleep/sessions` / `POST /workouts/logs` when the event is a session
   - `CONNECTION#` status on `connection.created` / `connection.revoked`
6. `/ai/observe` already fuses incoming samples with stored `METRIC#` rows
   (`routes/biometrics.py`) and projects onto ARIA. iOS
   (`BiometricsObserveService`, dashboard, Today's Story) and the web
   dashboard read that same DynamoDB / coach context. **No ARIA engine
   change.** Clients keep HealthKit as the TestFlight path.

### 6.2 One kebab-case metric vocabulary (SI-aligned)

Open Wearables: snake_case (`heart_rate`, `active_energy`, `weight` in kg).
Forge batch route: kebab-case (`heart-rate`, `active-calories`) and
**pounds** for `body-weight`.
ARIA classify: snake_case enum values, aliases for both spellings, kg / m /
ms / kcal.

This adapter emits **kebab-case names and SI-aligned units**. Clinical
conventions that are already SI-derived stay (bpm = min⁻¹, kcal, ms). We do
not invent joules or kelvin.

| Open Wearables | Forge kebab | Unit | `/health/batch` today | `/ai/observe` |
|---|---|---|---|---|
| `heart_rate` | `heart-rate` | bpm | `heart-rate` | `heart-rate` / `heart_rate` |
| `resting_heart_rate` | `resting-heart-rate` | bpm | `resting-heart-rate` | yes |
| `heart_rate_variability_sdnn` | `hrv-sdnn` | ms | `hrv` (SDNN) | `hrv-sdnn` — **never alias RMSSD → SDNN** |
| `heart_rate_variability_rmssd` | `hrv-rmssd` | ms | observe only until batch allowlists it | yes |
| `steps` | `steps` | count | `steps` | yes |
| `active_energy` / `energy` | `active-energy` | kcal | `active-calories` | `active-energy` |
| `weight` | `body-mass` | **kg** | `body-weight` + `unit: kg` (existing converter → lbs) | `body-mass` kg |
| `distance_*` | `distance` | m | `distance` / meters | yes |
| `vo2_max` | `vo2-max` | ml/kg/min | `vo2-max` | yes |
| `oxygen_saturation` | `oxygen-saturation` | fraction 0–1 | observe only | yes |
| sleep session | `sleep-duration` + stages | seconds (observe), minutes (batch `sleep-stage`) | `sleep-stage` + `/sleep/sessions` | yes |
| workout event | workout log + `active-energy` + `distance` | min, kcal, m | `/workouts/logs` | samples |

Implemented in `backend/infra/lambda/services/open_wearables/` with fixture
tests. Unmapped types (`nike_fuel`, …) are rejected, not coerced.

### 6.3 Surfaces

| Surface | How it sees the data | Change in this PR |
|---|---|---|
| DynamoDB | `USER#{sub}` / `METRIC#…`, `SLEEP#`, `WORKOUT#`, `CONNECTION#` | none yet — adapter only builds payloads |
| ARIA orchestration | `/ai/observe` → `fusion.fuse_turn` → `ARIA#CONTEXT` / body snapshot | none (do not touch `aria_core`) |
| iOS | HealthKit now; later Connect uses OW link. Labels still say "via Terra" (`CloudSourceLabel`) — rename in a later client PR | none (Swift out of scope) |
| Web | Same API as iOS | none |
| `POST /integrations/{provider}/sync` | Still a "syncing" stub. Later: trigger OW sync or no-op because webhooks already flow | none |

---

## 7. Security

- **User key:** Cognito `sub` only. `auth.extract_user_id` already reads
  `requestContext.authorizer.jwt.claims.sub`. The adapter requires
  `cognito_sub` and stores the Open Wearables UUID as `external_user_id`.
- **Webhook route** (later): HMAC via Svix (`svix-id`, `svix-timestamp`,
  `svix-signature`). Reject stale timestamps. Look up `sub` from the stored
  mapping; never take `user_id` from the body as a Forge identity.
- **Tokens:** Garmin / Oura / WHOOP / Strava client secrets, Open Wearables
  admin password, API keys, and the Svix signing secret live in **SSM
  Parameter Store SecureString** (e.g. `/forge/{env}/open-wearables/...`).
  Standard parameters are free. Instance role + Lambda role get
  `ssm:GetParameter` on that prefix only.
- **PII / PHI stays in AWS.** Open Wearables runs in our account and region.
  No Terra / Junction / Momentum multi-tenant SaaS in the path. Disable
  upstream telemetry. Optional raw-payload S3 they support stays in *our*
  bucket if we ever enable it.
- **Network:** security group default-deny. Provider OAuth callbacks need a
  public HTTPS URL (`API_BASE_URL`). Prefer an ACM certificate on the box or
  a cheap HTTP API custom domain that only forwards `/oauth/*` and `/api/v1/*`.
- **No PII in CloudWatch message bodies.** Log event type, provider, and
  counts, not samples.

---

## 8. Phased migration

| Phase | Work | Out of scope / gate |
|---|---|---|
| **0 — this PR** | Identify project, design doc, typed adapter + fixture tests | No deploy |
| **1 — vendor apps** | Register Oura, WHOOP, Garmin, Strava OAuth apps. Put blanks in Parameter Store. Expect Garmin approval lag | Not a TestFlight blocker (HealthKit covers beta) |
| **2 — local compose** | Pin official images. One mapped test user (`sub` ↔ OW user). Hit adapter with `webhook test` events | No AWS apply |
| **3 — cheapest AWS** | Single `t4g.small` + SSM + Lambda webhook route (Terraform in a later PR). `$25` envelope | No NAT, no RDS split |
| **4 — one live provider** | Oura or WHOOP end-to-end. Precedence rule vs HealthKit (`SleepSurfacePresence` already has the hook) | Client string cleanup ("via Terra") is a follow-up |
| **5 — remaining three** | Garmin, Strava, then Polar/Ultrahuman if needed | Fitbit only if Google Health API is ready before the 2026 sunset |
| **6 — scale** | If 1k+ MAU or HA is required: Fargate + RDS + ElastiCache, still no NAT if possible | Accept leaving the $25 ceiling |

Depends on WS1 (DynamoDB, Cognito) and the `/v1` contract, as the issue says.

---

## 9. Risks

| Risk | Why it matters | Mitigation |
|---|---|---|
| Pre-1.0 API drift | They warn payloads may change before 1.0 | Pin image tags; adapter tests on fixtures; changelog watch |
| New infra class | Forge is 100% serverless today | Day-one = one EC2, not a second platform team |
| Single-box HA | `t4g.small` dies, sync pauses | Acceptable at 100 MAU; backups of the EBS volume; HealthKit still works |
| OAuth lead time | Garmin / WHOOP programs are not instant | Start apps in phase 1; HealthKit covers TestFlight |
| Dual source overlap | WHOOP/Oura also write Apple Health | Define precedence before enabling both pipes for the same night |
| Coverage holes | WHOOP timeseries ❌; Garmin sleep 🔜 | Session events still useful; don't promise 1 Hz HR from every vendor |
| Fitbit sunset (2026-09) | Dead API | Do not build Fitbit first |
| Telemetry | Upstream daily ping | `TELEMETRY_ENABLED=false` |
| Cost cliff | Raw HR at 10k MAU | Summaries + retention policy; $25 is a 100-MAU constraint, not a 10k one |
| Public subnet | Box is reachable | SG + SSM; no SSH; no vendor data leaves AWS |
| License hygiene | MIT notice required on *their* distribution | Containers / fork, not a silent copy into the Lambda zip |

---

## 10. Adapter scaffold (this PR)

Fit is clear, so this PR includes a **minimal, typed mapper** — not a live
route and not a container deploy.

- `backend/infra/lambda/services/open_wearables/vocabulary.py` — kebab-case
  SI-aligned names and OW → Forge type table
- `backend/infra/lambda/services/open_wearables/mapping.py` —
  `adapt_webhook(event, *, cognito_sub=...)` → `/health/batch`,
  `/ai/observe`, sleep, workout, connection payloads
- `backend/tests/fixtures/open_wearables/*.json` — official-schema examples
  (heart rate, weight, sleep, workout, connection, unknown type)
- `backend/tests/test_open_wearables_adapter.py`

Not wired into `handler.py` yet. A later PR adds
`POST /integrations/open-wearables/webhook` (HMAC, mapping lookup, then the
existing handlers).

---

## 11. Decision

**Self-host Open Wearables (MIT, Momentum) on AWS as infrastructure.**

- 100 MAU: one `t4g.small` compose stack, ≈ **$21/month**, under the $25
  ceiling. Lambda adapter on the existing API.
- 1k / 10k MAU: still cheaper than a metered aggregator; the $25 ceiling
  does not survive raw timeseries at those sizes (~$40 / ~$119).
- Hosted Enterprise: no public price; skip until we need a BAA.
- Vendor OAuth apps: still required for every cloud wearable.
- PII stays in us-east-1. User key is Cognito `sub`.
- HealthKit remains the beta path. This work is not a TestFlight blocker.
