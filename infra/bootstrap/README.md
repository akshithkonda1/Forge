# Forge bootstrap

One-time AWS resources for CI/CD and Terraform remote state:

- Versioned S3 bucket for Terraform state
- DynamoDB table for state locking
- GitHub Actions OIDC provider + deploy IAM role (scoped to `production` environment)

Run via the repo root script (does not deploy the Forge API stack):

```bash
./scripts/wire_production.sh
```

Or manually:

```bash
cd infra/bootstrap
terraform init
terraform apply
terraform output
```