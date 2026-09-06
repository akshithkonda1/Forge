# Forge Backend Plan — Evaluation & Recommended Changes

> **Status: planning only. No backend code was changed to produce this
> document.** It is an evaluation of `backend/` as it stands today plus a
> prioritized set of proposed changes. Nothing here has been applied.

Companion to [`infra/TERRAFORM_PLAN.md`](infra/TERRAFORM_PLAN.md). That plan
covers *infrastructure*; this one covers the *application* the infrastructure
deploys.

---

## 1. Verdict

The backend is **solid and coherent**, not a scaffold. It is a single Python
Lambda behind an API Gateway HTTP API, with a clean single‑table DynamoDB
layer, a deterministic‑first AI engine (ARIA) with an optional, well‑gated
Bedrock path, and a real test suite (~21 backend tests + ~17 SimRunner tests,
stdlib `unittest`). It is **close to production‑ready**. The gaps are mostly
(a) drift between Terraform and code, (b) a few security/scoping sharp edges,
and (c) some duplication and cold‑start cost — none of them structural.

**Readiness: green with caveats.** Ship‑blockers are the two 🔴 items in §4.

---

## 2. Architecture at a glance

- **Entry:** `infra/lambda/handler.py` → `_route()`. Flat `if/elif` dispatch
  over ~14 route modules. API Gateway HTTP API v2 event shape.
- **Routes:** `infra/lambda/routes/` — `aria`, `coach`, `dashboard`,
  `biometrics`, `chat`, `devices`, `form_check`, `health`, `integrations`,
  `profile`, `progress`, `sleep`, `watch`, `workouts`.
- **Services:** `infra/lambda/services/` — `aria_engine.py` (~1,920 LOC, the
  core), plus `coach_context`, `aria_context`, `readiness`, `scoring`,
  `normalization`, `weekly_review`, `watch_debrief`, `daily_metrics`,
  `feedback`, and `biometrics/` (classify, statistics, estimators, body_model,
  inference).
- **AI router:** `infra/lambda/ai_router.py` — multi‑model Bedrock fan‑out with
  consensus + a hard `bedrock_enabled()` kill‑switch.
- **Storage:** `infra/lambda/storage/` — single‑table DynamoDB (`pk`/`sk`
  prefix queries) with an **in‑memory fallback** when `APP_DATA_TABLE_NAME` is
  unset (used by tests and local dev). boto3 is **lazily imported**.
- **Auth:** `infra/lambda/auth.py` + `security.py` — Cognito JWT first, then
  dev/test identities gated by `is_production_like()` / `allow_test_identity()`.
- **Local dev:** `dev_server.py` (stdlib threading HTTP server) translates HTTP
  → API Gateway event → `handler()`.

Strengths: deterministic‑first AI with Bedrock strictly optional and doubly
gated; lazy boto3 + in‑memory store make the whole thing runnable and testable
with **no AWS**; consistent `RouteError`→status‑code error contract with a
correlation id on 500s; IDOR guard (`assert_body_user_matches_auth`).

---

## 3. Terraform ↔ code contract drift (fix alongside the TF plan)

The backend reads environment variables that Terraform does not set, and
Terraform sets one the backend never reads. This is the highest‑value,
lowest‑risk cleanup because it's where infra and app disagree.

| Variable | Code reads it? | Terraform sets it? | Action |
|---|---|---|---|
| `AI_PROVIDER_SECRET_ARN` | ❌ never | ✅ yes | Either consume it (see §4.1) or drop it from the Lambda env block |
| `AI_ROUTER_MODEL_1_ID` | ✅ (`ai_router`) | ❌ | Add to TF env (or accept code default `anthropic.claude-sonnet-4-6`) |
| `AI_ROUTER_MODEL_2_ID` | ✅ (`ai_router`) | ❌ | Add to TF env (or accept code default `anthropic.claude-opus-4-7`) |
| `BIOMETRICS_MODEL_ENDPOINT` | ✅ (`biometrics/inference`) | ❌ | Add to TF as an optional var if the ML path is used |
| `APP_DATA_TABLE_NAME`, `ENVIRONMENT`, `ARIA_BEDROCK_ENABLED`, `AI_ROUTER_MODEL_3_ID/NAME`, `UPLOADS_BUCKET_NAME`, `USER_POOL_ID` | ✅ | ✅ | ✅ aligned |

---

## 4. Findings, by severity

### 🔴 P0 — resolve before real users

1. **The AI provider secret is created but never consumed.**
   Terraform provisions `aws_secretsmanager_secret.ai_provider` and passes
   `AI_PROVIDER_SECRET_ARN`, but no code in `infra/lambda/` reads it. If any AI
   provider key (e.g. a non‑Bedrock model, or an API key) is meant to come from
   Secrets Manager, that wiring is missing; if it isn't needed, the secret +
   env var + the IAM `secretsmanager:GetSecretValue` statement are dead surface
   area. **Decide one way**: implement a small cached secret loader, or remove
   the secret, env var, and IAM grant. Leaving it half‑wired is the kind of
   ambiguity that turns into a 3 a.m. incident.

2. **`POST /devices/catalog/seen` mutates a global, shared record.**
   It requires auth but writes to `CATALOG#DEVICES` with **no user scoping**
   (`routes/devices.py`). Any authenticated user can alter catalog entries every
   other user sees. Either make it admin‑only, write to a per‑user staging key,
   or treat client input as suggestions that never overwrite canonical entries.

### 🟠 P1 — correctness / consistency

3. **Model‑ID drift between the two AI paths.** Router slot‑2 defaults to
   `anthropic.claude-opus-4-7` (`ai_router.py`) while ARIA's live path lists
   `anthropic.claude-opus-4-8` (`aria_engine.LIVE_MODEL_IDS`). Two entry points
   can answer from different Opus generations. Centralize model IDs in one
   module (or drive both from the same env vars) so a transcript never claims a
   model that didn't answer.

4. **Vision is inconsistent across routes.** `POST /sleep/environment-check`
   does live Bedrock vision (`generate_coach_vision`), but `POST
   /workouts/form-check` mode=`vision` is a hard stub returning
   `available: false` — even though the underlying `BedrockGateway.converse`
   and `generate_coach_vision` support images. Either finish form‑check vision
   or make the "unavailable" contract explicit and identical in both places.

5. **`integrations` sync has no worker in this tree.** `POST
   /integrations/{provider}/sync` sets status `queued`/`syncing` but no
   processor exists in the Lambda. Clients will see jobs that never complete.
   Document the intended worker (separate Lambda/queue) or mark the route as a
   stub so the client doesn't poll forever.

6. **`handle_post_ai_archetype` swallows all exceptions** from the async import
   path (`except Exception: pass`) and silently falls back to duplicate local
   logic (`routes/aria.py`). At minimum log the swallowed error; better,
   collapse the duplicate archetype implementations into one.

### 🟡 P2 — hygiene, cost, performance

7. **Unused DynamoDB GSI with `projection_type = ALL`.** Terraform defines
   `gsi1` (pk/sk `gsi1pk`/`gsi1sk`) but **no lambda code writes or queries those
   attributes** — the storage layer only uses `pk`/`sk`. A `projection_type =
   ALL` GSI **doubles write cost** for zero read benefit today. Either start
   using it (there are natural access patterns: metrics by type across users,
   recent activity feeds) or drop it until needed.

8. **Cold‑start cost from eager imports.** `handler.py` imports all 14 route
   modules at module load, which transitively pulls the ~1,920‑LOC
   `aria_engine`. For a 15s‑timeout function this inflates cold starts. Consider
   lazy per‑route imports (import inside the dispatch branch) so a `/health` or
   `/dashboard/today` cold start doesn't pay for the AI engine.

9. **Duplicate / legacy trees.** `backend/ai/app/` holds a deprecated async
   layer with a second `CoachContextEngine`, a second minimal `dynamodb.py`, and
   a duplicate archetype implementation. It's clearly marked deprecated, but it
   is drift waiting to happen. Plan its removal or clearly fence it as
   CLI/SimRunner‑only.

10. **Minor:** `responses.created()` (201) is unused; `routes/` has no
    `__init__.py` (works as a namespace package, but is unconventional). Trivial.

---

## 5. What's genuinely good (don't "fix" these)

- **Deterministic‑first AI with a real kill‑switch.** `bedrock_enabled()` gates
  both the route (`/ai/router`, `/ai/chat`) and `BedrockGateway.converse()`
  itself — defense in depth. Live path falls back to deterministic on any error.
- **Runs with zero AWS.** In‑memory store + lazy boto3 means tests and
  `dev_server.py` work offline. This is why the suite is fast and hermetic.
- **Clean error contract.** `RouteError(status, message, code)` maps to precise
  HTTP codes; unexpected errors become a stable 500 with a correlation id and
  the detail logged, not leaked.
- **Input safety.** Body size caps (`MAX_JSON_BODY_CHARS` 256 KB), base64
  validation, object‑only JSON, prompt‑injection sanitization, and IDOR checks.
- **Security‑aware environment gating** shared with Terraform's `environment`
  variable (dev‑override tokens and demo data are off in prod‑like envs).

---

## 6. Testing posture

- **How to run:**
  ```bash
  python -m unittest discover -s backend/tests -p "test_*.py" -v
  python -m unittest discover -s backend/ai/simrunner/tests -p "test_*.py" -v
  ```
- `backend/tests/_bootstrap.py` puts `infra/lambda/` on `sys.path` so tests
  import the real handler/services. Coverage is meaningful: handler routing &
  auth edge cases, ARIA envelope/permissions/live‑degrade, router gate,
  biometrics pipeline, storage, weekly review, watch debrief, QoL life‑rhythm,
  structured replies.
- **Gap:** no automated test asserts the **Terraform↔code env‑var contract**
  (§3). A tiny test that parses `infra/main.tf`'s Lambda `environment` block and
  compares it to the set of `os.environ` keys the code reads would catch drift
  like the `AI_PROVIDER_SECRET_ARN` mismatch automatically. Recommended P1 add.

---

## 7. Prioritized action list

| Priority | Change | Where |
|---|---|---|
| P0 | Consume or remove the AI provider secret (+ its IAM grant/env) | `infra/lambda/*`, `infra/main.tf` |
| P0 | Scope or lock down `POST /devices/catalog/seen` | `routes/devices.py` |
| P1 | Single source of truth for model IDs (router vs ARIA) | `ai_router.py`, `services/aria_engine.py` |
| P1 | Resolve vision inconsistency (form‑check vs sleep‑env) | `routes/form_check.py` |
| P1 | Document/implement the integrations sync worker | `routes/integrations.py` |
| P1 | Add a Terraform↔code env‑var contract test | `backend/tests/` |
| P1 | Log (don't swallow) archetype fallback errors; de‑dup | `routes/aria.py`, `ai/app/` |
| P2 | Use or drop the `gsi1` GSI (write‑cost) | `infra/main.tf`, storage layer |
| P2 | Lazy per‑route imports to cut cold starts | `handler.py` |
| P2 | Remove/fence the legacy `ai/app/` tree | `backend/ai/app/` |

---

## 8. Out of scope

- No AWS account or Bedrock‑enablement changes (kill‑switch stays off).
- No code was modified for this plan; each item above is a proposal to be
  implemented and tested deliberately.
