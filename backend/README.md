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
# Install dependencies (optional — local dev works without Bedrock)
pip install -r backend/requirements.txt

# Start local API
python3 backend/dev_server.py
# → http://127.0.0.1:3001

# Run unit tests
python3 scripts/run_tests.py

# Smoke test (with dev server running)
FORGE_API_BASE_URL=http://127.0.0.1:3001 python3 scripts/smoke_test.py
```

Set `FORGE_TEST_USER_ID` to control the dev user identity (default: `test-user-00000000`).

## API routes

See `IMPLEMENTATION_PLAN.md` for the full route map. Core client routes:

- `GET /health`
- `GET /dashboard/today`
- `GET /me` / `PUT /me/profile`
- `GET /sleep`, `GET /workouts/history`, `GET /progress/summary`
- `POST /aria/chat`, `POST /health/batch`, `POST /workouts/logs`

## Deployment

Terraform packages `backend/api` into the Lambda zip:

```bash
cd infra/terraform
terraform apply
```

The old `infra/terraform/lambda/` folder is deprecated — all source lives here in `backend/api/`.

## AI / ARIA

`POST /aria/chat` requires AWS Bedrock credentials in deployed environments. Locally it may return `503` without credentials; other routes return deterministic seed data via the in-memory DynamoDB store.
