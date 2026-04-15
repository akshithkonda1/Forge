# Forge Terraform

This Terraform stack creates a shared AWS backend foundation for Forge so the Next.js app and the Swift app can talk to the same services.

## What it provisions

- Cognito user pool with separate app clients for web and iOS
- API Gateway HTTP API
- Lambda placeholder backend wired to the API
- DynamoDB single-table store for shared app data
- S3 uploads bucket
- Secrets Manager secret for AI provider credentials
- CloudWatch log groups for API and Lambda logs

## Why this shape

The repo currently contains two client apps but no backend implementation yet. This stack sets up the shared primitives both clients will need without locking you into one specific handler layout too early.

The DynamoDB table uses a single-table pattern with `pk`, `sk`, `gsi1pk`, and `gsi1sk` so you can store:

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
- `lambda/handler.py`: placeholder shared backend handler

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars`.
2. Fill in any environment-specific values.
3. Run `terraform init`.
4. Run `terraform plan`.
5. Run `terraform apply`.

## After apply

Wire the outputs into both clients:

- Next.js app:
  - API base URL
  - AWS region
  - Cognito user pool ID
  - Cognito web client ID
- Swift app:
  - API base URL
  - AWS region
  - Cognito user pool ID
  - Cognito iOS client ID

## Current limitation

The Lambda is intentionally a placeholder. `GET /health` returns a healthy response, while all other routes return `501 Not Implemented` until you add real backend handlers.
