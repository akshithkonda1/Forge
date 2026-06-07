# Forge Terraform

AWS serverless backend for Forge — Cognito auth, API Gateway HTTP API, Python Lambda (`backend/api`), DynamoDB, S3, and self-healing observability. No Kubernetes.

## What it provisions

- Cognito user pool with separate app clients for web and iOS
- Cognito identity pool and authenticated IAM role for direct client S3 access
- API Gateway HTTP API with JWT authorizer
- Lambda backend packaged from `backend/api`
- Versioned S3 artifacts bucket for Lambda zips (rollback + self-healing redeploy)
- DynamoDB single-table store with optional point-in-time recovery
- S3 uploads bucket with versioning and encryption
- Secrets Manager secrets for AI provider and Terra middleware credentials
- Terra integration routes (webhook, health, widget) and scheduled self-healing
- CloudWatch log groups for API and Lambda logs
- **Self-healing** (optional, enabled by default):
  - EventBridge schedule → healer Lambda probes `GET /health`
  - CloudWatch alarms on API health + Lambda errors → SNS alerts
  - Automatic redeploy from the versioned S3 artifact when unhealthy

## Backend packaging

Terraform zips `backend/api` (same code as the local dev server) into `build/forge-backend.zip`, uploads it to the artifacts bucket, and deploys it as `handler.handler`.

Local development uses the same package:

```bash
python3 backend/dev_server.py          # port 3001
python3 scripts/package_lambda.py      # build zip locally
```

## Self-healing (no K8s)

Forge uses managed AWS primitives instead of a container orchestrator:

| Component | Role |
|---|---|
| **S3 artifacts bucket** | Versioned Lambda zip — known-good rollback target |
| **Healer Lambda** | Probes `/health`, redeploys API Lambda from S3 on failure |
| **EventBridge schedule** | Runs health probe every N minutes (default 5) |
| **CloudWatch alarms** | API health metric + Lambda error rate → SNS |
| **DynamoDB PITR** | Point-in-time recovery for data (enabled by default) |
| **S3 versioning** | Uploads + artifacts buckets retain object history |

Disable with `enable_self_healing = false` in `terraform.tfvars`.

## Terra middleware

After `terraform apply`:

```bash
aws secretsmanager put-secret-value \
  --secret-id forge-dev/integrations/terra \
  --secret-string '{"dev_id":"...","api_key":"...","webhook_secret":"..."}'

terraform output -raw terra_webhook_url    # register in Terra dashboard
terraform output -raw terra_health_url     # ops health probe
```

Scheduled Terra self-healing runs on the API Lambda (`enable_terra_self_healing`, default `true`). `wire_production.sh` generates `ops_self_heal_token` in `terraform.tfvars` for manual `POST /integrations/terra/self-heal` over HTTP.

Seed runtime credentials after the first apply:

```bash
TERRA_DEV_ID=... TERRA_API_KEY=... TERRA_WEBHOOK_SECRET=... ./scripts/seed_secrets.sh
ANTHROPIC_API_KEY=... ./scripts/seed_secrets.sh
```

## Files

- `main.tf` — core infrastructure and API Lambda
- `artifacts.tf` — S3 bucket + Lambda zip upload
- `self_healing.tf` — healer Lambda, alarms, EventBridge, SNS
- `terra_self_healing.tf` — Terra stale-connection repair schedule + CloudWatch alarm
- `healer/handler.py` — health probe and S3 redeploy logic
- `variables.tf` / `outputs.tf` / `locals.tf` — configuration

## Production wiring (no deploy)

Run once with AWS admin credentials. This bootstraps remote state, creates a GitHub OIDC deploy role, sets GitHub `production` secrets/variables, and initializes the main stack — **without** `terraform apply`:

```bash
./scripts/wire_production.sh
```

After wiring, deploy manually when ready:

```bash
gh workflow run deploy-chain.yml --repo akshithkonda1/Forge -f run_deploy=true
```

## Usage

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
terraform init -backend-config=backend.hcl   # after wire_production.sh
TF_VAR_skip_aws_provider_checks=true terraform plan   # CI / no credentials
terraform apply
```

After apply, seed the AI provider secret out-of-band:

```bash
aws secretsmanager put-secret-value \
  --secret-id forge-dev/ai/provider \
  --secret-string '{"ANTHROPIC_API_KEY":"replace-me"}'
```

## Deploy chain (CI)

GitHub Actions runs a three-phase pipeline (`.github/workflows/deploy-chain.yml`):

| Phase | Job | What it does |
|---|---|---|
| **1 · Test** | `phase1-test-*` | Unit tests, smoke test, `terraform plan`, optional Swift build |
| **2 · Fix/Improve** | `phase2-fix-improve` | Package Lambda zip, compile checks, `terraform fmt/validate` |
| **3 · Deploy** | `phase3-deploy` | `terraform apply` + health check + smoke test (**manual** `workflow_dispatch` only) |

Run locally:

```bash
npm run ci:test    # Phase 1
npm run ci:fix     # Phase 2
npm run ci:deploy  # Phase 3 (needs AWS credentials)
```

## Testing

```bash
# From repo root
python3 scripts/run_tests.py
python3 backend/dev_server.py &
FORGE_API_BASE_URL=http://127.0.0.1:3001 python3 scripts/smoke_test.py

# Deployed API (after terraform apply)
terraform output -raw healthcheck_url
```

## Client wiring

Use `terraform output client_configuration` for Cognito IDs, API base URL, and uploads bucket settings for both the Next.js and Swift clients.