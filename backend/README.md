# FORGE Backend (Python)

Canonical Python backend for Forge. Source lives in `backend/api`, runs locally on port **3001**, and deploys to AWS Lambda via Terraform.

## Layout

```
backend/
├── api/              # Lambda-compatible API (handler, routes, ARIA, storage)
├── dev_server.py     # Local HTTP server wrapping handler.handler
├── organize_users.py # CLI utility for grouping user profiles
└── requirements.txt
```

## Quick start

```bash
pip install -r backend/requirements.txt
python3 backend/dev_server.py          # → http://127.0.0.1:3001
python3 scripts/run_tests.py           # unit tests (imports backend/api)
FORGE_API_BASE_URL=http://127.0.0.1:3001 python3 scripts/smoke_test.py
```

Set `FORGE_TEST_USER_ID` to control the dev user identity (default: `test-user-00000000`).

## Scripts (repo root)

| Command | Purpose |
|---|---|
| `npm run backend:dev` | Start local API on port 3001 |
| `npm run backend:test` / `npm run test:unit` | Run Python unit tests |
| `npm run backend:package` | Zip `backend/api` for Lambda |
| `npm run backend:smoke` | Smoke test against local or deployed API |

## API routes

See `IMPLEMENTATION_PLAN.md` for the full route map. Core client routes:

- `GET /health`, `GET /dashboard/today`, `GET /me`, `PUT /me/profile`
- `GET /sleep`, `GET /workouts/history`, `GET /progress/summary`
- `POST /aria/chat`, `POST /health/batch`, `POST /workouts/logs`

## Deployment

Terraform packages `backend/api` into a versioned S3 artifact and deploys it as the API Lambda. A healer Lambda can automatically redeploy from that artifact if health checks fail — no Kubernetes required.

```bash
cd infra/terraform && terraform apply
```

The deprecated `infra/terraform/lambda/` folder only contains a pointer README.

## AI / ARIA

`POST /aria/chat` requires AWS Bedrock credentials in deployed environments. Locally it may return `503` without credentials; other routes return deterministic seed data via the in-memory DynamoDB store.