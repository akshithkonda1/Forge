# Forge Terraform

Shared AWS backend for the Next.js app, the Swift app, and Kotlin.
**Dummy-offline (TestFlight / Device Hub) does not need this stack** — empty
Cognito / API in `Info-Add.plist` (`scripts/generate_client_config.py
--dummy-offline`, PR #278) is $0 AWS. Keep `aria_bedrock_enabled = false`.

Roadmap audit (RMSSD, editable memory/persona, model routing, Bedrock cards vs
this module): [`ROADMAP_IAC_READINESS.md`](ROADMAP_IAC_READINESS.md).
Apply-failure catalog (also plan-only): [`TERRAFORM_PLAN.md`](TERRAFORM_PLAN.md).

## What it provisions (only if you apply)

- Cognito user pool on **Essentials** (justified: free prefix domain + managed
  login for the authorization-code + PKCE flow; at ~1k MAU this is still $0)
- Free Cognito prefix domain (`aws_cognito_user_pool_domain`)
- One public PKCE app client per platform:
  - iOS callback `forge://auth/callback`, logout `forge://auth/logout`
  - Web callback/logout URLs as variables (CI may use `example.com`
    placeholders; a real apply rejects any web or Kotlin URL containing
    `example.com`)
  - Kotlin `[0]` is the custom scheme (`com.forge.app://auth/callback` /
    `com.forge.app://auth/logout`). An https App Link may follow as a second
    entry only; it works only once `assetlinks.json` is live on that domain
- Localhost clients (`web_localhost`, `kotlin_localhost`) only when
  `environment` is one of `dev`, `local`, or `sandbox`. Any other name
  (beta, testflight, prd, test, ci, staging, prod) gets no localhost clients
  and no localhost IDs on the JWT authorizer audience
- Apple and Google identity providers (secrets from Parameter Store SecureString,
  never tfvars). Rotate with `aws cognito-idp update-identity-provider`,
  **never** `terraform apply -replace` on the IdP resource
- JWT authorizer audience listing every *existing* client ID
- Cognito identity pool and authenticated IAM role for direct client access to AWS resources
- API Gateway HTTP API with access logs
- Lambda backend on **arm64 / 256 MB**, wired to the API (`ANY /{proxy+}`)
- `GET /devices/catalog` public with a per-route throttle (2 rps / burst 10);
  clients should cache this catalog. `POST /devices/catalog/seen` stays on JWT
- `GET /health` stays public, throttled at 1 rps / burst 5
- DynamoDB single-table store (`pk` / `sk`, no GSI)
- S3 uploads bucket
- Parameter Store SecureString parameters for `ELEVENLABS_*` (standard tier; seed after apply)
- CloudWatch log groups with retention (30 prod / 14 dev)
- Optional CloudTrail management-event trail (`create_cloudtrail`, default
  **false** — exactly one trail per AWS account; enable on one stack only).
  The trail bucket has its own `force_destroy_cloudtrail_bucket` (default false)
- AWS Budgets spend guard (default on, $25/mo). **Alerts only — never stops
  spend.** ElevenLabs is invisible to it; that cap lives in the app quota.
  A real apply requires `spend_guard_notification_email`
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
- `variables.tf`: stack inputs (`environment` has no default; `aria_bedrock_enabled` stays false)
- `locals.tf`: shared naming, tagging, Cognito/SSM paths, JWT audiences, dev allowlist
- `main.tf`: Lambda, HTTP API, DynamoDB, uploads, spend guard
- `cognito.tf`: prefix domain, Kotlin + localhost clients, Apple/Google IdPs
- `ssm.tf`: ElevenLabs SecureString parameters
- `cloudtrail.tf`: optional management-event trail + locked bucket
- `outputs.tf`: `client_configuration` plus allowlist-only `dev_client_configuration`
- `bootstrap/`: SSE-S3 state bucket (TLS-only, GetObject limited to deploy role + account root, 30-day noncurrent expiry). IdP secrets land in state
- `lambda/handler.py`: shared backend handler (iOS, web, Android)
- `remote.tf.example`: optional S3 remote state (S3 lockfile, no DynamoDB)
- `ROADMAP_IAC_READINESS.md`: indie cost / Bedrock / roadmap gates

## Usage

From this directory (`backend/infra`):

1. Copy `terraform.tfvars.example` to `terraform.tfvars`. Set web callback URLs
   to the real https origins (a real apply fails if any web or Kotlin
   callback/logout URL contains `example.com`). Kotlin `[0]` is already the
   custom scheme. Do **not** put Apple/Google/ElevenLabs secrets in tfvars.
2. Before a real apply, seed the social IdP SecureString parameters listed in `terraform.tfvars.example`.
3. Optionally apply `bootstrap/` once (pass `state_bucket_deploy_role_arn`), then
   `cp remote.tf.example remote.tf` and substitute the bucket name.
4. Run `terraform init`.
5. **Plan-only (CI-safe, no credentials):**
   `AWS_EC2_METADATA_DISABLED=true TF_VAR_environment=dev TF_VAR_skip_aws_provider_checks=true terraform plan`
   `.github/workflows/terraform.yml` job `terraform-checks` runs init / fmt / validate / plan this way on every PR. **PRs never apply.**
6. `terraform apply` is a paid-account decision. Dummy-offline must not apply.
   Do not set `aria_bedrock_enabled = true` for indie cheapest path.
   Set `spend_guard_notification_email` (required on a real apply when the
   budget is enabled). Set `create_cloudtrail = true` on **one** stack in the
   account if you want the management-event trail.
7. If you did apply and need ElevenLabs, seed the three `/…/ai/ELEVENLABS_*`
   parameters with `aws ssm put-parameter --overwrite` so the key never lands in state.
8. Rotate Apple/Google IdP secrets with
   `aws cognito-idp update-identity-provider` after updating Parameter Store.
   Never `terraform apply -replace=aws_cognito_identity_provider.google` (or
   Apple) — Cognito rewrites `provider_details` after create, and `-replace`
   recreates the IdP and can unlink existing users.

## After apply

Wire the outputs into clients via `scripts/generate_client_config.py`
(`client_configuration`: apiBaseUrl, cognito.region, iosClientId, userPoolId,
hostedUiDomain, webClientId, kotlinClientId, plus ios/web/kotlin RedirectUri
and LogoutUri from `[0]` of each callback/logout list). Localhost client IDs
are in the separate `dev_client_configuration` output and are `null` off the
dev allowlist. Dummy-offline needs none of those.

For client uploads, use the Cognito identity pool to obtain authenticated AWS credentials and write objects under the caller's private prefix:

- `s3://<uploads bucket>/private/{identityId}/...`

## Current limitation

`GET /health` is public for smoke tests and is throttled (1 rps / burst 5).
`GET /devices/catalog` is the only other JWT exemption, throttled at 2 rps /
burst 10 — cache it on the client. Unimplemented routes return `404`.
Implemented routes (see `lambda/routes/`) run behind Cognito-or-test-user auth
in `lambda/auth.py`. Live Bedrock is off by default.

New routes need no Terraform change — `aws_apigatewayv2_route.proxy`
(`ANY /{proxy+}`) forwards everything to the one Lambda — except a route that
must be public, which needs its own `authorization_type = "NONE"` resource.
