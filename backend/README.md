# FORGE Backend (Python)

Canonical Python backend for Forge — runs locally for development and deploys to AWS Lambda via Terraform.

## Layout

```
backend/
├── api/              # Lambda-compatible API package (routes, services, ARIA, storage)
├── dev_server.py     # Local HTTP server for iOS/web clients (port 3001)
├── organize_users.py # CLI utility for grouping user profiles
└── requirements.txt
```

## Quick start

```bash
pip install -r backend/requirements.txt
python3 backend/dev_server.py          # → http://127.0.0.1:3001
python3 scripts/run_tests.py           # unit tests
FORGE_API_BASE_URL=http://127.0.0.1:3001 python3 scripts/smoke_test.py
```

Set `FORGE_TEST_USER_ID` to control the dev user identity (default: `test-user-00000000`).

## API routes

See `IMPLEMENTATION_PLAN.md` for the full route map. Core client routes:

- `GET /health`, `GET /dashboard/today`, `GET /me`, `PUT /me/profile`
- `GET /sleep`, `GET /workouts/history`, `GET /progress/summary`
- `POST /aria/chat`, `POST /health/batch`, `POST /workouts/logs`

## Deployment

Terraform packages `backend/api` into the Lambda zip:

```bash
cd infra/terraform && terraform apply
```

## Implementation Plan

See `IMPLEMENTATION_PLAN.md` for the backend build plan derived from the current frontend surfaces and AWS infrastructure.

The important current decision: the working backend is the Python Lambda under `infra/terraform/lambda`, even though the root README still describes a future TypeScript backend folder. New backend implementation should extend the Lambda route/service modules first, then revisit runtime migration once the API is stable.

## Implemented Routes

Phase 1 — client-unblocking reads:

- `GET /me`
- `PUT /me/profile`
- `GET /dashboard/today`
- `GET /sleep?days=14`
- `GET /workouts/today`
- `GET /workouts/history?days=30`
- `GET /progress/summary?days=30`
- `GET /chat/threads/current`
- `POST /chat/threads/current/messages`

Phase 2 — ingestion:

- `POST /health/batch` — normalized metric writes
- `POST /sleep/sessions`
- `POST /workouts/logs`
- `POST /integrations/{provider}/sync` — queues a sync job and flips the connection to `syncing`

Phase 4 — AI coach (wraps `POST /ai/router`):

- `POST /coach/messages`
- `POST /coach/workout-plan`
- `POST /coach/sleep-insight`
- `POST /coach/progress-review`

Each coach route gathers a bounded user-context package via `services/coach_context.py` and falls back to a deterministic answer if Bedrock is unreachable, so clients and tests can run without AWS credentials.

All routes return deterministic seed data when no persisted data exists, so clients can move from local mocks to API calls before ingestion pipelines are populated.

## User Category Organizer

`organize_users.py` groups user JSON by the same profile dimensions shown in the iOS onboarding app:

- fitness goals
- experience level
- preferred workout types
- coaching style
- connected devices
- weekly schedule

Example:

```bash
python3 backend/organize_users.py users.json --category fitness-goal --pretty
```

Use `--category all` to emit every grouping at once.

## AI Router

`POST /ai/router` is a Python-based Bedrock router that:

- starts with Claude Sonnet 4.6
- escalates to Claude Opus 4.7 if no answer arrives within the SLA window
- escalates again to Kimi K2.5 if needed
- activates more models as `packageSizeBytes` grows toward the 10 GB cap

Default models: Sonnet 4.6 → Opus 4.7 → Kimi K2.5 (configurable via `AI_ROUTER_MODEL_3_ID`).

## AI / ARIA

`POST /aria/chat` requires AWS Bedrock credentials in deployed environments. Locally it may return `503` without credentials; other routes return deterministic seed data via the in-memory DynamoDB store.