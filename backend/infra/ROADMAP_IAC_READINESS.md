# Forge IaC readiness — RMSSD, editable memory/persona, model routing

Indie cheapest path. **Planning / config only.** This document is grounded in
the tree as of this PR. **No `terraform apply` was run. No AWS resources were
created. No live Bedrock or other generative-AI API calls were made.**
`aria_bedrock_enabled` stays `false` (Terraform default).

**This PR (green path, still no apply):** Lambda IAM now allows Anthropic **and**
Grok CRIS (`xai.*` foundation models, `us.xai.*` / `global.xai.*` inference
profiles, plus `project/default` from the Grok 4.6 card). Router slots 1 and 2
are Terraform-driven like slot 3. Optional AWS Budgets spend-guard stays
**off** (`enable_spend_guard = false`). Token spend still requires the flag,
account model-access, and Hex `client_configuration` fill.

Companion docs: [`README.md`](README.md), [`TERRAFORM_PLAN.md`](TERRAFORM_PLAN.md)
(apply-failure catalog; still planning-only),
[`../README.md`](../README.md) (routes),
[`../ARIA_INTELLIGENCE_PLAN.md`](../ARIA_INTELLIGENCE_PLAN.md) (intelligence
roadmap; some Kimi prose is stale — slot 3 in code is already Grok).

---

## 0. Plan-only evidence (how to reproduce)

CI (`.github/workflows/terraform.yml` job `terraform-checks`) already runs this
on every PR that touches `backend/infra/**`. PRs never apply. The apply job is
gated to `main` / `workflow_dispatch` **and** successful AWS credentials; it is
not evidence for this audit.

Local (no credentials, no account):

```bash
cd backend/infra
export AWS_EC2_METADATA_DISABLED=true
export TF_VAR_environment=dev
export TF_VAR_skip_aws_provider_checks=true
terraform init -backend=false -input=false -lockfile=readonly -no-color
terraform fmt -check -diff -recursive -no-color
terraform validate -no-color
terraform plan -input=false -no-color
```

Expect: init / fmt / validate success; plan is a **full create** of the unused
stack (local state, no remote backend). That is not a license to apply.

Dummy-offline client-config (no Terraform outputs, no Cognito):

```bash
python3 scripts/generate_client_config.py --check
python3 scripts/generate_client_config.py --dummy-offline --dry-run
```

Committed `ForgeSwift/ForgeSwift/Info-Add.plist` is `FORGEEnvironment=dummy`
with empty API / Cognito fields (PR #278 ship-gate).

---

## 1. What the stack actually is

Single-table DynamoDB (`pk`/`sk`, PAY_PER_REQUEST, TTL on, **no GSI**), one
Lambda (`ANY /{proxy+}` — new routes need **zero** Terraform), HTTP API +
Cognito JWT, Cognito identity pool (authenticated S3 prefix only), S3 uploads,
CloudWatch logs (14-day retention), empty Secrets Manager secret
`{project}-{env}/ai/provider`.

Bedrock is **IAM + env-flag only**. Terraform always attaches a
Claude+Grok-scoped `bedrock:Converse*` / `InvokeModel` statement. The Lambda
never calls Bedrock unless `ARIA_BEDROCK_ENABLED=true`. Default is `"false"`.

| Resource | Dummy-offline | Live API, Bedrock off | Live Bedrock |
|---|---|---|---|
| Cognito user + identity pools | not required | required | required |
| HTTP API + Lambda | not required | required | required |
| DynamoDB `app_data` | not required (in-memory / on-device) | required | required |
| S3 uploads | not required | required for form-check / cycle PDF / router previews | required |
| Secrets Manager `ai_provider` | not required | **idle fixed cost if applied** | needed only for ElevenLabs keys (`provider_secrets.py`) |
| Bedrock invoke | off | off (flag + no traffic) | **paid tokens; do not turn on for indie** |

---

## 2. Cost: Dummy-offline vs applied idle vs Bedrock

### Dummy-offline = $0 AWS

`scripts/generate_client_config.py --dummy-offline` writes empty
`FORGEAPIBaseURL` / Cognito ids and `FORGEEnvironment=dummy`. The iOS binary
does not impersonate live auth (`ForgeAuthConfig.dummyOfflineAPI`). ARIA is the
on-device Dummy orchestrator. **Do not apply this Terraform stack** for that
product.

### Applied idle stack (live-API-no-Bedrock)

If this root module is applied with `aria_bedrock_enabled = false` (default):

| Line item | Why it bills | Indie note |
|---|---|---|
| **Secrets Manager** | **$0.40 / secret / month**, no permanent free tier ([pricing](https://aws.amazon.com/secrets-manager/pricing/)). API calls $0.05 / 10k. | Dummy / Device Hub does not need this secret (resource description already says so). **This is the idle fixed cost.** `recovery_window_in_days = 7` also blocks cheap destroy→recreate (`TERRAFORM_PLAN.md` §3.2). |
| DynamoDB on-demand | Request units + storage; PITR **on by default** (`enable_point_in_time_recovery = true`) | Empty table is cheap; PITR is extra. Leave off until you have real data you cannot rebuild. No GSI — good (an unused ALL-projection GSI previously doubled writes). |
| Lambda 512 MB / 15 s | Invoke + GB-seconds | $0 at zero traffic. Do not raise memory “for Grok”. |
| HTTP API | Request units | $0 at zero traffic. |
| Cognito | MAU | $0 with no users. |
| S3 + versioning | Storage + versions | Cycle-report prefix expires in 1 day; other prefixes do not. Versioning can accumulate. |
| CloudWatch logs | Ingestion + stored bytes | 14-day retention already set. |
| Bedrock | Per-token | **$0 while the flag is false.** IAM exists but is unused. |

Do **not** create the proposed `backend/infra/bootstrap/` state bucket / lock
table from `TERRAFORM_PLAN.md` until you actually apply. That is more always-on
S3.

### If someone flips `aria_bedrock_enabled = true`

Then you pay Bedrock tokens **and** risk a 3-model fan-out per `/ai/router`
request (`ai_router.default_models()`). Cheapest live experiment, if ever:

1. Keep one model (Claude Sonnet via a **US geo inference profile**, not three).
2. Do not enable Grok until IAM + project ARN + residency are explicit.
3. Leave `/ai/chat` on the deterministic engine until that experiment is proven.

**Grok 4.6 is on Amazon Bedrock.** Standard-tier list prices from the official
[Grok 4.6 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-xai-grok-4-6.html)
(per 1M tokens): In-Region / Geo CRIS **$2.20 / $6.60** (cache read $0.55);
Global CRIS **$2.00 / $6.00** (cache read $0.50). Forge’s slot-3 default is the
Global CRIS id, so a live probe would bill at the Global row.

Claude Opus 4.8 (`aria_engine.LIVE_MODEL_IDS`) is a separate, more expensive
chat path than router slot 2 (Opus 4.7). See the
[Opus 4.8 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-8.html).

---

## 3. Bedrock: Grok **is** on Bedrock — Forge access gates keep it idle

Verified from **official AWS model cards** (HTML regional tables, 2026-09-16).
**No `InvokeModel` / Converse / live generative-AI calls were made.**
Availability and residency below are **not** taken from blogs.

### 3.1 Official IDs and residency (cite the cards)

**Grok 4.6** ([model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-xai-grok-4-6.html)):

| Endpoint | Model ID | In-Region | Geo CRIS | Global CRIS |
|---|---|---|---|---|
| bedrock-mantle | `xai.grok-4.6` | URL `https://bedrock-mantle.{region}.api.aws/openai/v1` | Not supported | Not supported |
| bedrock-runtime | `xai.grok-4.6` | **Not supported** | `us.xai.grok-4.6` | `global.xai.grok-4.6` |

Regional table on that same card (In-Region / Geo / Global):

- **bedrock-mantle:** `us-west-2` and `us-gov-east-1` In-Region **yes**; Geo no; Global no.
- **bedrock-runtime:** In-Region **no** in every listed Region. US commercial
  (`us-east-1`, `us-east-2`, `us-west-1`, `us-west-2`): Geo **yes**, Global **yes**.
  Non-US commercial Regions: Geo **no**, Global **yes**. Gov: Geo **yes**, Global **no**.

Card note for runtime: name `us.xai.grok-4.6` or `global.xai.grok-4.6`; IAM also
needs `bedrock:InvokeModel` on `arn:aws:bedrock:{region}:{account-id}:project/default`
in addition to the inference profile. Sample Converse uses `us-east-1` +
`us.xai.grok-4.6`.

**Grok 4.3** ([model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-xai-grok-4-3.html)):
**In-Region only** on **bedrock-mantle** (`xai.grok-4.3`). Geo **not supported**,
Global **not supported**. Pricing table is In-Region only. Regional table:
In-Region **yes** in `us-west-2`, `us-east-1`, `us-east-2`, `us-gov-west-1`;
Geo no; Global no. **Forge does not reference Grok 4.3.**

**Claude (same runtime residency pattern as Grok 4.6, from their cards):**
Sonnet 4.6, Opus 4.7, and Opus 4.8 on **bedrock-runtime** in `us-east-1` are
In-Region **no**, Geo **yes**, Global **yes**
([Sonnet 4.6](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-4-6.html),
[Opus 4.7](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-7.html),
[Opus 4.8](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-8.html)).
Geo/global ids are `us.` / `eu.` / `jp.` / `au.` / `global.` prefixes on the
foundation-model id.

### 3.2 What `backend/infra` currently sets vs those cards

| Gate | What the tree sets | Card / product implication |
|---|---|---|
| Kill-switch | `aria_bedrock_enabled` default **`false`** → Lambda `ARIA_BEDROCK_ENABLED=false` | `/ai/router` returns 503 `bedrock_disabled`; `BedrockGateway.converse` refuses before boto3. **No token spend.** Keep this. |
| Slot 1 id | Unset `ai_router_model_1_id` → `AI_ROUTER_MODEL_1_ID=anthropic.claude-sonnet-4-6` | Matches `default_models()`. `us-east-1` runtime wants `us.` / `global.` CRIS at cutover. Long-term Sonnet 5 id is `us.anthropic.claude-sonnet-5` ([Sonnet 5 card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-sonnet-5.html), launch 2026-06-30). |
| Slot 2 id | Unset `ai_router_model_2_id` → `AI_ROUTER_MODEL_2_ID=anthropic.claude-opus-4-7` | Matches `default_models()`. Long-term Opus 5 id is `us.anthropic.claude-opus-5` ([Opus 5 card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-5.html), launch 2026-07-24). |
| Slot 3 id | Unset `ai_router_model_3_id` → env `AI_ROUTER_MODEL_3_ID=global.xai.grok-4.6` (same fallback in `ai_router.py`) | **Valid Grok 4.6 Global CRIS id** on bedrock-runtime. From stack region `us-east-1`, Global **is** a supported source profile on the 4.6 runtime table. |
| Slot 3 name | `AI_ROUTER_MODEL_3_NAME=Grok` | Display only. |
| Runtime client | `boto3.client("bedrock-runtime")` + `converse` | Matches the 4.6 **runtime** row, not mantle. Do **not** send bare `xai.grok-4.6` on runtime (in-Region unsupported). `global.xai.grok-4.6` is the correct Global profile; `us.xai.grok-4.6` is the US-residency profile. |
| Region | `aws_region` default `us-east-1` | 4.6 runtime: Geo + Global yes, In-Region no. Mantle in-Region for 4.6 is **Oregon / GovCloud East**, not N. Virginia. |
| IAM | `sid = BedrockInvokeClaudeAndGrok` — `foundation-model/anthropic.*` + `xai.*`; inference-profile `*anthropic*` + `global.xai.*` + `us.xai.*`; `project/default` | **This PR closes the xAI CRIS IAM gap.** Still $0 until the flag is on. Anthropic also needs Marketplace subscribe + FTU ([model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)). |
| Model access enablement | **Not in Terraform** | First-party Bedrock still requires the account to enable the foundation model ([model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)). Console/API enablement is an extra gate after IAM + flag. |
| `/ai/chat` live ids | `anthropic.claude-opus-4-8` + `anthropic.claude-sonnet-4-6` | Real ids, but runtime in `us-east-1` wants **geo/global CRIS** (`us.` / `global.`), not in-Region. Router slot 2 is Opus **4.7**, chat is Opus **4.8**. |

**Grok is available on Bedrock.** Forge does not call it today because of
**access gates** (flag default false, account model-access enablement, Hex
Dummy ship-gate) — not because the model is missing, and not because IAM
omits xAI (this PR adds Grok CRIS).

**Cheapest path:** leave the flag false; **do not** apply. Unused IAM is still
attack surface if the flag is flipped without spend-guard + model-access
hygiene. Keep the documented Global CRIS id in code (SimRunner / health);
treat it as **inert configuration**, not a live subscription. Optional
`enable_spend_guard` stays false.

### 3.3 Claude ids used by the stack

| Path | Code default | Official card |
|---|---|---|
| Router slot 1 | `anthropic.claude-sonnet-4-6` | Real foundation-model id; `us-east-1` runtime In-Region **no** — use `us.anthropic.claude-sonnet-4-6` or `global.anthropic.claude-sonnet-4-6` |
| Router slot 2 | `anthropic.claude-opus-4-7` | Same runtime pattern ([Opus 4.7 card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-7.html)) |
| `/ai/chat` live | `anthropic.claude-opus-4-8` + Sonnet 4.6 | Opus 4.8 is real; same `us-east-1` runtime CRIS requirement ([Opus 4.8 card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-anthropic-claude-opus-4-8.html)) |

Not a Dummy-offline problem. IAM already allows Anthropic inference profiles;
the **code defaults omit the `us.` / `global.` prefix**.

### 3.4 Docs drift (do not “fix” by enabling Bedrock)

- `ARIA_INTELLIGENCE_PLAN.md` still says slot 3 “currently defaults to Kimi
  K2.5”. Code, Terraform fallback, tests, and SimRunner already use Grok.
- `GET /health` (non-prod) lists router model ids even when Bedrock is disabled.
  This PR adds `router.bedrockEnabled` so that listing is not mistaken for a
  live path.
- `BACKEND_PLAN.md` §4.1 said `AI_PROVIDER_SECRET_ARN` is never read. That is
  stale: `services/provider_secrets.py` loads ElevenLabs keys from it.

---

## 4. Roadmap item blockers (recommend, do not build)

New HTTP routes need **no Terraform** (`ANY /{proxy+}`). New Dynamo **tables /
GSIs** are the expensive mistake. Stay on `USER#{id}` + existing `sk` prefixes.

### 4.1 RMSSD truth ingest

**Today**

- Canonical autonomic metric is **`HRV_SDNN` only** (`biometrics/types.py`).
- Classifier alias `"rmssd" → MetricType.HRV_SDNN` (`classify.py`) — **wrong
  statistic**. SDNN ≠ RMSSD.
- `POST /health/batch` allowlist is `"hrv"` (normalized to the existing HRV
  slot), not `"rmssd"` (`routes/health.py`).
- Persist key already exists: `METRIC#{metric_type}#{started_at}`
  (`storage/keys.py`).
- `POST /ai/observe` classifies incoming samples onto that taxonomy and writes
  a body snapshot at `ARIA#BODY_SNAPSHOT`.
- Dummy-offline: HealthKit / FakeHealthPack on device; Apple’s common HRV type
  is SDNN. No AWS.

**Blockers**

1. No `MetricType.HRV_RMSSD` — cannot tell the truth if WHOOP/Oura/manual RMSSD
   is stored as SDNN.
2. `/health/batch` will **reject** `metricType: "rmssd"`.
3. No dedicated RMSSD route (not needed).

**Cheapest deferred design (code-only, no apply)**

1. Add `HRV_RMSSD` to the registry + aliases (`rmssd`, `hrv_rmssd`,
   HealthKit-style names if/when present).
2. **Stop** mapping `rmssd` → `HRV_SDNN`.
3. Allow `"rmssd"` / `"hrv-rmssd"` on `/health/batch` writing
   `METRIC#hrv_rmssd#…` (reuse `metric_key`).
4. Body-model / readiness: keep SDNN for Apple-shaped series; add RMSSD as a
   sibling autonomic input when present. Do not dual-write.
5. Dummy-offline: ingest on-device; sync later through `/ai/observe` or batch.

Do **not** add a table, GSI, stream, or Bedrock call for HRV.

### 4.2 Editable memory / persona

**Today — two stores, neither is a user-facing CRUD API**

| Store | Key | Who writes | Editable by user? |
|---|---|---|---|
| iOS QoL persona | `QualityOfLifeLivingStore` (UserDefaults) | Lifestyle interview / “Update who I am” (`WhatIKnowView`) | **Yes, on-device** |
| iOS knowledge ledger | `AriaKnowledgeLedgerStore` | local | view + interview, not a cloud PATCH |
| Learner persona | `ARIA#PERSONA` | `contextual_learner.save` from chat / observe / feedback | **No GET/PATCH route** |
| Companion long-term | `ARIA#CONTEXT` | `CoachContextEngine` | No user PATCH |
| Short-term | `ARIA#STM#{id}` | engine; Dynamo TTL | No user PATCH |
| Profile | `PROFILE` | `PUT /me/profile` | Yes, but not ARIA persona |

Dummy-offline already has the cheap UX: local interview + What I Know. **$0.**

**Blockers for a live-API editor**

1. No `GET/PATCH /ai/persona` or `/ai/memory`.
2. Learner writes would clobber a naive overwrite of `ARIA#PERSONA`.
3. Partner/cycle tokens are denied on ingest (`routes/aria.py`) — keep that.

**Cheapest deferred design**

1. Dummy-offline: keep UserDefaults as source of truth; do not sync until a
   live stack exists.
2. Live: **one** `PATCH /ai/memory` (proxy route, no TF) that updates
   **user-authored** fields on `ARIA#CONTEXT` (`life_facts`, `current_goals`,
   `constraints`) and a small `user_overrides` map on `ARIA#PERSONA`.
3. Learner merges: never replace locked user overrides.
4. STM stays engine-owned + TTL. Do not build a second memory table.
5. Optional later: `GET /ai/memory` for the What I Know screen when
   `cognitoConfigured` is true.

### 4.3 Model routing

**Today**

- `POST /ai/router` — 503 `bedrock_disabled` unless the flag is on
  (`handler.py` + `BedrockGateway.converse`).
- Coach routes wrap the router and **fall back deterministically** if routing
  fails (`routes/coach.py`).
- `/ai/chat` uses `aria_engine` (deterministic default; optional single-model
  Bedrock, not the 3-slot ensemble).
- GET `/health` (non-prod) advertises the three slot ids.

**Blockers for a live Grok + Claude ensemble** (Grok **is** on Bedrock; these
are Forge gates + cost, not availability):

1. Kill-switch default **false** (keep it).
2. ~~IAM is Anthropic-only~~ **Closed in this PR** — `xai.*` + `us.xai.*` /
   `global.xai.*` + `project/default`. Flag still false.
3. Account **model access enablement** for xAI / Anthropic is not in Terraform
   ([model access](https://docs.aws.amazon.com/bedrock/latest/userguide/model-access.html)).
4. Residency: from `us-east-1` + bedrock-runtime, Grok 4.6 **Global and US Geo
   CRIS are supported**; in-Region runtime is **not**. Slot 3’s
   `global.xai.grok-4.6` is a valid Global profile (worldwide routing). Use
   `us.xai.grok-4.6` if US-only processing is required. Do not use Grok 4.3
   (mantle In-Region only) on this runtime client.
5. Three-way fan-out is a cost multiplier (15 s Lambda timeout still binds).
6. Chat vs router Opus versions differ (4.8 vs 4.7); both want CRIS prefixes
   on runtime in `us-east-1`.

**Cheapest deferred design**

1. Dummy-offline + live-API-no-Bedrock: **do nothing**. Deterministic ARIA is
   the product. Grok stays a documented idle id.
2. If a paid probe is ever required: one Sonnet **`us.`** profile, flag on in
   **dev only**, enable that Anthropic model in the account, `enable_spend_guard`
   with an email, no three-way fan-out until that probe is signed off.
3. Do not add SageMaker, extra Lambdas, or a second secret for model keys.
   Bedrock is IAM-auth; the existing secret is ElevenLabs.

---

## 5. Required vs optional resources (summary)

### Dummy-offline (recommended indie default)

**Required:** committed empty plist, Dummy orchestrator, on-device HealthKit /
QoL store.

**Optional / do not create:** entire `backend/infra` root module, Cognito,
API, Dynamo, S3, Secrets Manager, Bedrock.

### Live API, no Bedrock

**Required:** Cognito (web + iOS clients), identity pool, HTTP API, Lambda,
DynamoDB table, log groups. S3 if you use uploads / cycle PDF / form-check.

**Optional:** Secrets Manager (only if ElevenLabs live mouth is on), PITR,
Bedrock IAM (already in the module; unused at $0), remote state bootstrap.

**Keep off:** `aria_bedrock_enabled`, `enable_spend_guard`, extra router slots in
production.

### Three roadmap items vs infra

| Item | Needs new TF? | Needs new Dynamo table? | Dummy-offline |
|---|---|---|---|
| RMSSD truth ingest | No | No (`METRIC#hrv_rmssd#…`) | On-device; alias fix in Python later |
| Editable memory/persona | No | No (`ARIA#CONTEXT` + overrides on `ARIA#PERSONA`) | UserDefaults / interview already |
| Model routing | No (env/IAM only if paid) | No | N/A — flag stays false |

---

## 6. Safe fixes in this PR (no apply)

- Lambda IAM: Anthropic **and** Grok CRIS (`xai.*`, `us.xai.*`, `global.xai.*`,
  `project/default`). Flag default stays **false**.
- Terraform variables + Lambda env for slots 1 and 2, mirroring slot 3.
  Defaults match `ai_router.default_models()`.
- Optional `aws_budgets_budget` spend-guard, `count = 0` unless
  `enable_spend_guard = true`.
- Honest comments / README: Grok 4.6 **is** on Bedrock; token spend is the
  real bill after flag + Hex cutover.
- `archive_file.excludes` so `__pycache__` does not churn Lambda hashes.
- `data.aws_region.current.region` (provider v7 deprecation).
- `GET /health` reports `router.bedrockEnabled`.

**Explicitly not done:** `terraform apply`, Bedrock enablement, Hex
`client_configuration` fill, `aria_bedrock_enabled = true`, live model calls.

---

## 7. Dummy vs live cutover (not this PR)

Hex [#301](https://github.com/akshithkonda1/Forge/pull/301) (`9fdc32d6`) stays
the Dummy ship-gate until Akshith says go: committed
`ForgeSwift/ForgeSwift/Info-Add.plist` is `FORGEEnvironment=dummy`, empty API /
Cognito; `FORGEProviderRoutingEnabled` off-by-absence. Do **not** flip Hex
flags or fill `client_configuration` in this PR.

| Layer | Dummy (today) | Live cutover (later) |
|---|---|---|
| iOS | `AriaOperatingMode.dummy` → `AriaDummyOrchestrator` (`AriaService.sendMessage`) | Fill plist from Terraform `client_configuration`; mode `liveBackend`; `postChat` → `/ai/chat` |
| Lambda | `ARIA_BEDROCK_ENABLED=false` | `aria_bedrock_enabled = true` (dev first) |
| Tokens | $0 | Bedrock + Anthropic Marketplace; enable `enable_spend_guard` first |
| Hex | #301 `--check` refuses Dummy + routing flag on | Live env may set `FORGEProviderRoutingEnabled` |

Sonnet/Opus **5** gens are real on first-party cards (`anthropic.claude-sonnet-5`,
`anthropic.claude-opus-5`; us-east-1 runtime In-Region **no**, Geo/Global **yes**).
Stack defaults stay **4.6 / 4.7** until tfvars swap. Fable 5.1 / Mythos 5.1 exist
on the Anthropic index; they are not the Sonnet/Opus product slots.

Tree cited from `main` `0bde95e337afa7de22edb86341c43e4e26b3a271`. Cards fetched
2026-09-16. **No `terraform apply`. No `InvokeModel` / Converse.**
