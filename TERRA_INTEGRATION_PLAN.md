# Terra API integration plan — wearable data beyond Apple Health

**Planning only.** No code changed, no Terraform applied, no Terra account
created, no dependency added. This document maps Terra's API (as documented
publicly at `docs.tryterra.co`, researched via web search in September 2026 —
direct fetches to that domain are blocked by this session's network egress
policy, so re-verify exact payload shapes and current pricing against the
live docs before writing code; see §6) onto the tree as of this PR.

⚠️ **Not to be confused with Terra Money / `terra.py`** (the LUNA/UST
blockchain SDK at `terra-money/terra.py`) — same name, unrelated project. The
right vendor is `github.com/tryterra`, the right PyPI package is
`terra-python`, not `terra-sdk`.

---

## 0. Why this doc exists

Two pieces of scaffolding already assume Terra, but neither is wired to
anything:

- `CloudSourceLabel.displayName()` —
  `ForgeSwift/ForgeCore/Sources/ForgeCore/Cloud/ForgeCloudContracts.swift:824-843`
  — renders `"Oura via Terra"`, `"WHOOP via Terra"`, `"Garmin via Terra"`,
  `"Strava via Terra"`.
- `POST /integrations/{provider}/sync` —
  `backend/infra/lambda/routes/integrations.py` — accepts exactly
  `{apple-health, oura, whoop, garmin, strava}` but only writes a fake
  `"syncing"` status to DynamoDB. It never calls anything external.

No Terra credentials exist anywhere in Terraform, and the iOS "Connect"
button (`ConnectedDevicesLibraryView.swift`) only toggles local state and
re-prompts HealthKit — it makes no network call. This plan defines the gap
between "the code already expects Terra to exist" and "Terra is actually
wired up."

---

## 1. What Terra actually is (verified)

- A unified REST + webhook API aggregating 30+ wearables/health apps (Oura,
  WHOOP, Garmin, Strava, Fitbit, Polar, Withings, Coros, and others) into one
  normalized schema — integrate once instead of once per vendor.
- Auth to Terra's own API uses two headers, `dev-id` and `x-api-key`, issued
  from the Terra dashboard.
- Two ways to connect an end user's provider account — see §3.
- Pushes new data as webhooks once a user is connected — see §4.
- Official SDKs: Python (`pip install terra-python`,
  `github.com/tryterra/terra-client-python`) and Swift
  (`TerraSwift`, `github.com/tryterra/TerraSwift` — aimed at direct
  HealthKit ingestion, likely redundant here since Forge already reads
  HealthKit natively).
- **Not free.** Search results report plans starting at $399/mo billed
  annually ($499/mo month-to-month) with 100,000 included credits; ~200
  credits/month per connected user+provider pair; first 400 webhook events
  per active connection/month free; no free tier, but a first-month refund
  window. **Treat these numbers as approximate — confirm at
  `tryterra.co/pricing` before committing.** This is a budget decision as
  much as an engineering one.

---

## 2. Fit against the existing architecture

| Forge already has | Terra concept | Where |
|---|---|---|
| Source strings `apple-health`/`oura`/`whoop`/`garmin`/`strava` in `CloudSourceLabel` and `SleepSurfacePresence.canonicalizeSource` | Terra's own provider identifiers (same names) | `ForgeCloudContracts.swift:824`, `SleepSurfacePresence.swift:113` |
| `connection_key(user_id, provider)` DynamoDB item, already written by the sync stub | One row per connected (user, provider) | `backend/infra/lambda/storage/keys.py:8` |
| `sleep_key(user_id, date, source)`, `workout_log_key(user_id, started_at)`, `metric_key(user_id, metric_type, started_at)` | Land Terra's `sleep`/`activity`/`body`/`daily` webhook payloads | `keys.py:16,20,12` — no new tables needed |
| `aws_secretsmanager_secret.ai_provider`, currently seeded with `ELEVENLABS_*` keys | Pattern to copy for `TERRA_DEV_ID` / `TERRA_API_KEY` / `TERRA_WEBHOOK_SECRET` | `backend/infra/main.tf:400-405` |
| `aws_apigatewayv2_route.health` — the **only** route today with no `authorization_type`/`authorizer_id` | Precedent for an unauthenticated webhook route (Terra can't send a Cognito JWT) | `backend/infra/main.tf:553-557` |
| `forge://` custom URL scheme (currently used for `forge://cycle/sharing` Messages hand-off) | Reusable as the OAuth `auth_success_redirect_url`/`auth_failure_redirect_url` | `ForgeSwift/ForgeSwift/Info-Add.plist:74-86` |
| Per-device "Connect" button, currently local-only | Where the real network call goes | `ConnectedDevicesLibraryView.swift:325` (`onConnect`) |

Nothing here requires a new subsystem — it's new logic slotted into storage
keys, a secret, and a route pattern that already exist.

---

## 3. Connecting a user's account — recommend Custom UI, not the Widget

Terra offers two auth flows:

| | Terra Widget | Custom UI (recommended) |
|---|---|---|
| Backend call | `POST /v2/auth/generateWidgetSession` | `POST /v2/auth/authenticateUser?resource={oura\|whoop\|garmin\|strava}` |
| User sees | Terra-hosted, Terra-branded picker across *all* providers | Only that one provider's OAuth screen |
| Fit here | Poor — duplicates/fights `ConnectedDevicesLibraryView`'s existing per-device catalog with individual Connect buttons | Good — one tap on one device row → one `resource=` call → that provider's OAuth screen |

Both accept `reference_id` in the request body. **Recommendation: always pass
Forge's own Cognito `user_id` as `reference_id`.** Every later webhook then
self-identifies the Forge user directly — no separate
Terra-id-to-Forge-id mapping table needed, since `connection_key(user_id,
provider)` already is what the sync stub writes.

Both also accept `auth_success_redirect_url` / `auth_failure_redirect_url`.
On iOS this should open in `ASWebAuthenticationSession` (not currently used
anywhere in this app — this would be new) and redirect back through the
existing `forge://` scheme, e.g. `forge://integrations/terra/callback`.
Treat that redirect as a UX nicety only — the `auth` webhook (§4) is the
source of truth for whether the connection actually succeeded, since a
redirect can be lost (app killed, network blip) in a way a webhook retry
generally isn't.

---

## 4. Receiving data — webhook, HMAC-verified

- Terra POSTs to one developer-configured URL per event: an `auth` family
  (connect / re-auth / deauth / error lifecycle — docs reference at least a
  `user_reauth` variant fired alongside a successful re-auth; get the full
  enumerated list from the live event-types reference before writing the
  handler, see §6), plus one event per data type: `activity`, `sleep`,
  `body`, `daily`, `nutrition`, `menstruation`, `athlete`.
- Every payload carries a `type`, a `user` block (Terra's own `user_id`, the
  `reference_id` you passed at connect time, and `provider`), and a `data`
  array.
- Payloads are HMAC-SHA256 signed via a `terra-signature` header —
  **verify before trusting**, same posture as any other webhook. Verification
  needs `TERRA_WEBHOOK_SECRET`, issued once a webhook destination is
  registered in the Terra dashboard.
- `daily`/`body`/`nutrition`/`menstruation` are keyed by connection +
  calendar date (per Terra's own guidance, ignore time-of-day) — maps
  directly onto `sleep_key(user_id, date, source)`'s existing shape;
  `activity` maps onto `workout_log_key(user_id, started_at)`.
- **New Terraform is required for exactly one thing**: an unauthenticated
  route, e.g. `POST /webhooks/terra`, following the
  `aws_apigatewayv2_route.health` pattern (no `authorization_type` /
  `authorizer_id`), same Lambda integration. Everything else can ride the
  existing `ANY /{proxy+}` route that `backend/README.md` says needs zero
  Terraform for new endpoints — this webhook is the one exception, because
  Terra cannot present a Cognito JWT.

---

## 5. Open decisions

These are product/account calls, not engineering ones — flagging rather than
guessing:

1. **Provider scope.** Ship all four already-stubbed providers
   (oura/whoop/garmin/strava) together, or start with one to validate the
   pipe end-to-end? Oura is the narrowest single-purpose device (sleep +
   readiness only) and would be the fastest validation.
2. **Account ownership.** Nobody has a Terra account yet. Given the
   $399+/mo floor (§1), who signs up and owns that billing before any code
   depends on it?
3. **Custom UI vs. Widget** (§3 recommends Custom UI) — confirm before
   building either, since they're genuinely different backend endpoints and
   different iOS UX.
4. **New dependency or none.** `backend/pyproject.toml` currently declares
   exactly one dependency (`boto3`), and `backend/README.md` is explicit
   about not growing a second handler tree. Terra's REST calls + HMAC
   verification are simple enough to hand-roll with zero new dependencies —
   but that means maintaining it yourselves instead of on `terra-python`.
   Worth deciding deliberately rather than defaulting.
5. **Precedence vs. HealthKit.** Some Terra-covered devices (e.g. WHOOP)
   already write some data to Apple Health directly. If a user connects both
   paths, which source wins for the same night's sleep or the same workout?
   `SleepSurfacePresence.canonicalizeSource` already has the source-string
   plumbing to express a precedence rule (e.g. "prefer Terra when connected,
   else Apple Health") — it just doesn't have one yet.

---

## 6. What this pass could not verify

Direct fetches to `docs.tryterra.co` were blocked by this session's network
egress policy (`EGRESS_BLOCKED`); everything in §1, §3, and §4 came from
search-result snippets of those pages, not the full pages. Before writing
code, re-verify against the live docs:

- The complete enumerated list of `auth`-family webhook event subtypes.
- Exact JSON field names inside each event type's `data` array.
- Current pricing (`tryterra.co/pricing`) — pricing pages change.
- Whether a sandbox/test-user allowance exists separate from paid production
  connections (not confirmed either way in this pass).
