# Forge Terraform

Shared AWS backend for the Next.js app and the Swift app. **Dummy-offline
(TestFlight / Device Hub) does not need this stack** — empty Cognito / API in
`Info-Add.plist` (`scripts/generate_client_config.py --dummy-offline`, PR #278)
is $0 AWS. Keep `aria_bedrock_enabled = false`.

Roadmap audit (RMSSD, editable memory/persona, model routing, Bedrock cards vs
this module): [`ROADMAP_IAC_READINESS.md`](ROADMAP_IAC_READINESS.md).
Apply-failure catalog (also plan-only): [`TERRAFORM_PLAN.md`](TERRAFORM_PLAN.md).

## What it provisions (only if you apply)

- Cognito user pool with separate app clients for web and iOS
- Cognito identity pool and authenticated IAM role for direct client access to AWS resources
- API Gateway HTTP API
- Lambda backend wired to the API (`ANY /{proxy+}` — new routes need no TF)
- DynamoDB single-table store (`pk` / `sk`, no GSI)
- S3 uploads bucket
- Secrets Manager secret for ElevenLabs keys (**idle ~$0.40/month if applied**, even empty)
- CloudWatch log groups for API and Lambda logs
- Anthropic-scoped plus Grok CRIS Bedrock IAM (unused while the kill-switch is off)

Grok 4.6 **is** on Bedrock (`xai.grok-4.6` plus runtime profiles
`us.xai.grok-4.6` / `global.xai.grok-4.6` — official model card). This module
still does not call it: `aria_bedrock_enabled` default **false**. IAM now
allows Anthropic wildcards and Grok CRIS (`global.xai.*` / `us.xai.*`).

## Why this shape

One Lambda, one table, one HTTP API. The DynamoDB table uses a single-table
pattern on `pk` / `sk` (no GSI today — an unused ALL-projection GSI previously
doubled write cost). You can store:

- user profiles
- readiness snapshots
- daily metrics
- workout plans and history
- chat sessions and messages
- device connections
- ARIA persona / companion memory (`ARIA#PERSONA`, `ARIA#CONTEXT`, `ARIA#STM#`)

## Files

- `versions.tf`: Terraform and provider requirements
- `providers.tf`: AWS provider configuration (`skip_aws_provider_checks` for CI)
- `variables.tf`: stack inputs (`environment` has no default; `aria_bedrock_enabled` and `enable_spend_guard` default false)
- `locals.tf`: shared naming and tagging
- `main.tf`: core infrastructure
- `outputs.tf`: values both clients can consume
- `lambda/handler.py`: shared backend handler (iOS, web, Android)
- `remote.tf.example`: optional S3 remote state
- `ROADMAP_IAC_READINESS.md`: indie cost / Bedrock / roadmap gates

## Usage

From this directory (`backend/infra`):

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Optionally `cp remote.tf.example remote.tf` for S3 state.
3. Run `terraform init`.
4. **Plan-only (CI-safe, no credentials):**
   `AWS_EC2_METADATA_DISABLED=true TF_VAR_environment=dev TF_VAR_skip_aws_provider_checks=true terraform plan`
   `.github/workflows/terraform.yml` job `terraform-checks` runs init / fmt / validate / plan this way on every PR. **PRs never apply.**
5. `terraform apply` is a paid-account decision. Dummy-offline must not apply.
   Do not set `aria_bedrock_enabled = true` for indie cheapest path.
6. If you did apply and need ElevenLabs, seed the AI provider secret out-of-band
   with `aws secretsmanager put-secret-value` so the key never lands in state.

## After apply

Wire the outputs into both clients via `scripts/generate_client_config.py`
(`client_configuration`: apiBaseUrl, cognito.region, iosClientId, userPoolId).
Dummy-offline needs none of those.

For client uploads, use the Cognito identity pool to obtain authenticated AWS credentials and write objects under the caller's private prefix:

- `s3://<uploads bucket>/private/{identityId}/...`

## Current limitation

`GET /health` is public. Unimplemented routes return `404`. Implemented routes
(see `lambda/routes/`) run behind Cognito-or-test-user auth in `lambda/auth.py`.
Live Bedrock is off by default.

New routes need no Terraform change — `aws_apigatewayv2_route.proxy`
(`ANY /{proxy+}`) forwards everything to the one Lambda.
