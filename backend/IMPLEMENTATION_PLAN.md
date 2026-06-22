# FORGE Backend Implementation Plan

This plan is based on the current repository state:

- The web and iOS clients are fully mock-data driven today.
- The deployed backend shape is an AWS HTTP API backed by a Python Lambda in `infra/terraform/lambda`.
- Terraform already provisions Cognito, a single-table DynamoDB table, an uploads S3 bucket, Secrets Manager, CloudWatch logs, and a Bedrock AI router endpoint.
- The top-level README describes a TypeScript backend, but the working backend code is currently Python Lambda. The next backend work should extend the working Lambda path unless the team explicitly decides to migrate runtime later.

## Target Backend Shape

The backend should be a small domain API around five product surfaces:

1. Identity and profile
2. Health data ingestion and normalization
3. Readiness and daily summary scoring
4. Workout planning and workout logs
5. AI coach chat and generated insights

The system should keep the clients simple. iOS can read HealthKit locally, normalize to shared payloads, and sync records. Web can use the same API contracts for profile, dashboard, chat, progress, and integration management.

## Existing Infrastructure To Build On

### AWS HTTP API

Current routes:

- `GET /health`
- `POST /ai/router`
- `ANY /`
- `ANY /{proxy+}`

Next route work should happen in `infra/terraform/lambda/handler.py` with internal modules split out once handler size grows.

### Cognito

Use Cognito JWT identity for all user-scoped routes. User ID should be derived server-side from JWT claims instead of trusting client-submitted IDs.

Expected principal fields:

- `sub`: canonical user ID
- `email`: display/contact only
- `cognito:username`: fallback identity label

### DynamoDB

Current table has:

- `pk`
- `sk`
- `gsi1pk`
- `gsi1sk`
- `ttl`

Recommended single-table keys:

| Entity | PK | SK | GSI1 |
|---|---|---|---|
| Profile | `USER#{userId}` | `PROFILE` | none |
| Connection | `USER#{userId}` | `CONNECTION#{provider}` | `PROVIDER#{provider}` / `USER#{userId}` |
| Health metric | `USER#{userId}` | `METRIC#{metricType}#{startTime}` | `METRIC#{metricType}` / `{startTime}#USER#{userId}` |
| Sleep session | `USER#{userId}` | `SLEEP#{date}#{source}` | `SLEEP#{date}` / `USER#{userId}` |
| Workout log | `USER#{userId}` | `WORKOUT#{startTime}` | `WORKOUT#{date}` / `USER#{userId}` |
| Workout plan | `USER#{userId}` | `PLAN#{date}` | none |
| Readiness summary | `USER#{userId}` | `READINESS#{date}` | none |
| Chat thread | `USER#{userId}` | `CHAT#{threadId}` | none |
| Chat message | `USER#{userId}` | `CHAT#{threadId}#MSG#{createdAt}` | none |
| AI job/result | `USER#{userId}` | `AI#{jobId}` | `AI_STATUS#{status}` / `{createdAt}#USER#{userId}` |

## API Surface

### Phase 1: Client Unblocking API

These endpoints replace the current mock store while keeping behavior familiar.

- `GET /me`
- `PUT /me/profile`
- `GET /dashboard/today`
- `GET /sleep?days=14`
- `GET /workouts/today`
- `GET /workouts/history?days=30`
- `GET /progress/summary?days=30`
- `GET /chat/threads/current`
- `POST /chat/threads/current/messages`

The first implementation can return persisted data when present and deterministic seed data when missing. That lets the clients integrate with real networking before all ingestion pipelines are ready.

### Phase 2: Ingestion And Normalization

Add normalized write APIs:

- `POST /health/batch`
- `POST /sleep/sessions`
- `POST /workouts/logs`
- `POST /integrations/{provider}/sync`

Initial supported sources:

- `apple-health`
- `oura`
- `whoop`
- `garmin`
- `strava`
- `manual`

The adapter boundary should convert external values into shared canonical units:

- duration: minutes unless otherwise specified
- weight: pounds for client display, store original unit too
- heart rate: bpm
- HRV: ms
- calories: kcal
- distance: meters
- timestamps: ISO 8601 UTC

### Phase 3: Derived Scoring

Add deterministic scoring services before using AI:

- Readiness score
- Sleep score reconciliation
- Training load trend
- Recovery trend
- Personal record detection
- Workout recommendation baseline

AI should explain and personalize these scores, not be the only source of truth for them.

### Phase 4: AI Coach Productization

Keep `POST /ai/router` as a low-level model router, then build product routes on top:

- `POST /coach/messages`
- `POST /coach/workout-plan`
- `POST /coach/sleep-insight`
- `POST /coach/progress-review`

The coach layer should gather profile, recent metrics, sleep, workout history, and current plan into a bounded context package before calling the router.

### Phase 5: External Integrations

Provider-specific OAuth and sync jobs should be added after the core domain API is stable:

- Strava OAuth
- Oura OAuth
- Garmin import flow
- WHOOP OAuth
- Background sync scheduling
- Webhook handlers where providers support them

## Backend Module Layout

Recommended Lambda source layout:

```text
infra/terraform/lambda/
  handler.py
  ai_router.py
  auth.py
  responses.py
  routes/
    dashboard.py
    profile.py
    sleep.py
    workouts.py
    progress.py
    chat.py
    health.py
  services/
    readiness.py
    scoring.py
    normalization.py
    workout_planner.py
    coach_context.py
  storage/
    dynamodb.py
    keys.py
    models.py
```

Keep route handlers thin. Put validation, scoring, and persistence behind services so tests do not need API Gateway event fixtures for every behavior.

## Build Order

1. Add request routing helpers and user identity extraction. ✅
2. Add typed response helpers and route tests. ✅
3. Implement `GET /me`, `PUT /me/profile`, and `GET /dashboard/today`. ✅
4. Add DynamoDB storage helpers with local fake storage for tests. ✅
5. Move current client mock data into seed responses when a user has no persisted data. ✅
6. Wire web client API client to the Phase 1 endpoints. ⬜ (frontend work)
7. Wire iOS client API client to the same endpoints. ⬜ (frontend work)
8. Add normalized ingestion APIs for HealthKit and manual workout logs. ✅
9. Implement scoring services and persist readiness summaries. ✅ (compute path done; persistence to `READINESS#{date}` still pending)
10. Wrap `POST /ai/router` with coach-specific routes. ✅

## Status Snapshot

- Phase 1 (Client Unblocking API): complete with seed-data fallback through DynamoDB local store.
- Phase 2 (Ingestion): `POST /health/batch`, `POST /sleep/sessions`, `POST /workouts/logs` complete; `POST /integrations/{provider}/sync` is a queueing stub that flips the connection to `syncing`.
- Phase 3 (Scoring): `services/scoring.py` provides training load trend, recovery trend, PR detection, baseline workout recommendation. `services/readiness.py` computes a readiness score and is wired into the dashboard when persisted sleep is present. Background readiness persistence is still TODO.
- Phase 4 (AI Coach): `POST /coach/messages`, `POST /coach/workout-plan`, `POST /coach/sleep-insight`, `POST /coach/progress-review` route through `services/coach_context.py` into `ai_router`. Each falls back to a deterministic answer when Bedrock is unreachable so clients and tests can run without AWS. `POST /ai/chat` runs the deterministic ARIA engine (`services/aria_engine`); with `ARIA_BEDROCK_ENABLED` set it overlays a live Claude (Bedrock Converse) reasoning pass on the deterministic envelope and falls back to it on any error.
- Phase 5 (External Integrations): the sync stub is in place; OAuth flows, real provider clients, and webhook handlers are not yet built.

## Test Coverage

`tests/test_backend_handler.py` covers Phase 1 routes, ingestion accept/reject, sleep + workout post-then-list round trips, integration sync stub, coach routes (with router stub + failure path), and the scoring service primitives.

## Testing Plan

Minimum backend tests:

- Route matching and error responses
- Cognito identity extraction
- Profile read/write
- Dashboard aggregation from seed and persisted records
- Health batch validation
- Sleep summary windows
- Workout history windows
- Readiness scoring boundaries
- AI coach context packaging
- Existing AI router timeout and consensus tests

## Open Decisions

- Whether to keep Python Lambda long term or migrate to the TypeScript backend layout described in the root README.
- Whether API responses should use generated OpenAPI schemas or TypeScript-first contracts from `shared/`.
- Which auth flow the web app should use first: Cognito Hosted UI or direct SRP/password auth.
- Whether HealthKit sync happens opportunistically from app launches or through background delivery plus batch upload.
