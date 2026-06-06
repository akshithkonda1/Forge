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
- `POST /integrations/terra/widget`, `GET /integrations/terra/status`, `POST /integrations/terra/webhook`

## Terra middleware

Wearable data flows through [Terra](https://docs.tryterra.co/) as middleware: widget auth, signed webhooks, and normalized storage into DynamoDB (sleep, daily metrics, workouts, connection status).

**Local dev** — set env vars before starting the dev server:

```bash
export TERRA_DEV_ID=your-dev-id
export TERRA_API_KEY=your-api-key
export TERRA_WEBHOOK_SECRET=your-webhook-signing-secret
python3 backend/dev_server.py
```

Expose `/integrations/terra/webhook` with ngrok and register that URL in the Terra dashboard. Webhook payloads are verified via the `terra-signature` header.

**Deployed** — seed `forge-<env>/integrations/terra` in Secrets Manager (see `infra/terraform/terraform.tfvars.example`), then use `terraform output -raw terra_webhook_url` as the Terra destination.

### Terra self-integration & self-healing

| Endpoint | Auth | Purpose |
|---|---|---|
| `GET /integrations/terra/health` | Public | Integration health, stale connection counts |
| `POST /integrations/terra/self-integrate` | `x-forge-ops-token` | Bootstrap credentials + persist integration state |
| `POST /integrations/terra/self-heal` | `x-forge-ops-token` | Re-queue backfills for stale/stuck connections |

EventBridge invokes the API Lambda on a schedule (`forgeAction: terra-self-heal`) to assess Terra health, emit `Forge/Terra` CloudWatch metrics, and automatically re-request historical data for stale links. Auth webhooks also trigger an immediate backfill when a user connects a device.

## Deployment

Terraform packages `backend/api` into a versioned S3 artifact and deploys it as the API Lambda. A healer Lambda can automatically redeploy from that artifact if health checks fail — no Kubernetes required.

```bash
cd infra/terraform && terraform apply
```

The deprecated `infra/terraform/lambda/` folder only contains a pointer README.

## AI / ARIA

`POST /aria/chat` requires AWS Bedrock credentials in deployed environments. Locally it may return `503` without credentials; other routes return deterministic seed data via the in-memory DynamoDB store.