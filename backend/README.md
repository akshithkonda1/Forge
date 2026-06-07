# Forge Backend (Python)

Canonical Python backend for Forge. The Lambda application lives in `backend/app`, runs locally on port **3001**, and deploys to AWS Lambda via Terraform.

## Layout

```
backend/
├── app/                 # Lambda deploy root (handler.handler)
│   ├── handler.py       # API Gateway entry point
│   ├── core/            # auth, responses, runtime, seed policy, health
│   ├── data/            # seed + lifestyle reference data (dev only)
│   ├── ai/              # ARIA agent, tools, memory, AI router
│   ├── routes/          # HTTP route handlers
│   ├── services/        # scoring, readiness, coach context
│   ├── storage/         # DynamoDB + in-memory fallback
│   └── integrations/    # Terra middleware
├── dev/
│   └── server.py        # Local HTTP server wrapping handler.handler
├── tools/               # run_tests, smoke_test, package_lambda, aria_cli, …
├── cli/
│   └── organize_users.py
├── tests/               # Unit tests (unittest)
└── requirements.txt
```

## Quick start

```bash
pip install -r backend/requirements.txt
python3 backend/dev/server.py          # → http://127.0.0.1:3001
python3 backend/tools/run_tests.py
FORGE_API_BASE_URL=http://127.0.0.1:3001 python3 backend/tools/smoke_test.py
```

Or via npm scripts from the repo root:

| Script | Command |
|--------|---------|
| `npm run backend:dev` | Start local API |
| `npm run backend:test` | Unit tests |
| `npm run backend:package` | Zip `backend/app` for Lambda |
| `npm run backend:smoke` | Smoke test against local server |
| `npm run aria` | ARIA CLI against dev server |

## Deploy

Terraform packages `backend/app` into a versioned S3 artifact and deploys it as the API Lambda (`handler.handler`). A healer Lambda can automatically redeploy from that artifact if health checks fail.

```bash
cd terraform && terraform apply
```

See [`terraform/README.md`](../terraform/README.md) for secrets, Terra webhooks, and self-healing.