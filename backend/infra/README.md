# Forge Terraform

This Terraform stack creates a shared AWS backend foundation for Forge, so the Next.js app and the Swift app can communicate with the same services without additional adapters. 

## What it provisions

- Cognito user pool with separate app clients for web and iOS
- Cognito identity pool and authenticated IAM role for direct client access to AWS resources
- API Gateway HTTP API
- Lambda placeholder backend wired to the API
- DynamoDB single-table store for shared app data
- S3 uploads bucket
- Secrets Manager secret for AI provider credentials
- CloudWatch log groups for API and Lambda logs

## Why this shape

The repo currently contains two client apps, but no backend implementation yet. This stack sets up the shared primitives both clients will need without locking you into one specific handler layout too early.

The DynamoDB table uses a single-table pattern with `pk`, `sk`, `gsi1pk`, and `gsi1sk`, so you can store:

- user profiles
- readiness snapshots
- daily metrics
- workout plans and history
- chat sessions and messages
- device connections

## Files

- `versions.tf`: Terraform and provider requirements
- `providers.tf`: AWS provider configuration
- `variables.tf`: stack inputs
- `locals.tf`: shared naming and tagging
- `main.tf`: core infrastructure
- `outputs.tf`: values both clients can consume
- `lambda/handler.py`: shared backend handler (iOS, web, Android)
- `remote.tf.example`: optional S3 remote state

## Usage

From this directory (`backend/infra`):

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Optionally `cp remote.tf.example remote.tf` for S3 state.
3. Run `terraform init`.
4. Run `TF_VAR_skip_aws_provider_checks=true terraform plan` for speculative planning without live AWS credentials.
5. Run `terraform apply`.
6. Seed the AI provider secret out-of-band with `aws secretsmanager put-secret-value` so the key never lands in Terraform state.

## After apply

Wire the outputs into both clients:

- Next.js app:
  - API base URL
  - AWS region
  - Cognito user pool ID
  - Cognito web client ID
  - Cognito identity pool ID
- Swift app:
  - API base URL
  - AWS region
  - Cognito user pool ID
  - Cognito iOS client ID
  - Cognito identity pool ID

For client uploads, use the Cognito identity pool to obtain authenticated AWS credentials and write objects under the caller's private prefix:

- `s3://<uploads bucket>/private/{identityId}/...`

## Current limitation

The Lambda is intentionally a placeholder. `GET /health` is public and returns a healthy response, while unimplemented routes still return `501 Not Implemented`. Implemented routes (see `lambda/routes/`) run behind the soft Cognito-or-test-user auth in `lambda/auth.py`.

New routes need no Terraform change — `aws_apigatewayv2_route.proxy` (`ANY /{proxy+}`) forwards everything to the one Lambda, which dispatches by path in `lambda/handler.py`. Example: `POST /watch/aria/suggest` (`lambda/routes/watch.py`) is the Apple Watch app's deeper-coaching debrief call — a deterministic, tone-tested template engine (`lambda/services/watch_debrief.py`) that can later be upgraded to call Bedrock the same way `/ai/chat` does, with the deterministic response as the guaranteed fallback.
