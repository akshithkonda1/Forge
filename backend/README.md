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

## AI Router

`POST /ai/router` is a Python-based Bedrock router that:

- starts with Claude Sonnet 4.6
- escalates to Claude Opus 4.7 if no answer arrives within the SLA window
- escalates again to Kimi K2.5 if needed
- activates more models as `packageSizeBytes` grows toward the 10 GB cap

Default models: Sonnet 4.6 → Opus 4.7 → Kimi K2.5 (configurable via `AI_ROUTER_MODEL_3_ID`).

## AI / ARIA

`POST /aria/chat` requires AWS Bedrock credentials in deployed environments. Locally it may return `503` without credentials; other routes return deterministic seed data via the in-memory DynamoDB store.