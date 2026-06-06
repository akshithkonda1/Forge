#!/usr/bin/env bash
# Wire Forge production deploy: bootstrap AWS state/OIDC, GitHub secrets, local tfvars.
# Does NOT run terraform apply on the main stack.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BOOTSTRAP_DIR="${ROOT}/infra/bootstrap"
TF_DIR="${ROOT}/infra/terraform"
GITHUB_REPO="${GITHUB_REPO:-akshithkonda1/Forge}"
GITHUB_ENV="${GITHUB_ENV:-production}"
AWS_REGION="${AWS_REGION:-us-east-1}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd aws
require_cmd terraform
require_cmd gh
require_cmd openssl

log "Checking AWS credentials"
ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text 2>/dev/null)" \
  || die "AWS credentials not configured. Run: aws configure (or export AWS_PROFILE)"

log "Bootstrapping remote state + GitHub OIDC role (infra/bootstrap)"
pushd "${BOOTSTRAP_DIR}" >/dev/null
terraform init -input=false
terraform apply -auto-approve -input=false
ROLE_ARN="$(terraform output -raw github_actions_deploy_role_arn)"
STATE_BUCKET="$(terraform output -raw terraform_state_bucket)"
LOCK_TABLE="$(terraform output -raw terraform_lock_table)"
popd >/dev/null

log "Writing Terraform backend config"
cat > "${TF_DIR}/backend.hcl" <<EOF
bucket         = "${STATE_BUCKET}"
key            = "forge/dev/terraform.tfstate"
region         = "${AWS_REGION}"
dynamodb_table = "${LOCK_TABLE}"
encrypt        = true
EOF

if [[ ! -f "${TF_DIR}/terraform.tfvars" ]]; then
  OPS_TOKEN="$(openssl rand -hex 32)"
  log "Creating ${TF_DIR}/terraform.tfvars from example"
  cp "${TF_DIR}/terraform.tfvars.example" "${TF_DIR}/terraform.tfvars"
  printf '\nops_self_heal_token = "%s"\n' "${OPS_TOKEN}" >> "${TF_DIR}/terraform.tfvars"
else
  log "Keeping existing ${TF_DIR}/terraform.tfvars"
fi

log "Initializing main Terraform stack with remote backend (no apply)"
pushd "${TF_DIR}" >/dev/null
terraform init -backend-config=backend.hcl -input=false -reconfigure
popd >/dev/null

log "Setting GitHub production environment secrets and variables"
gh secret set AWS_ROLE_ARN \
  --env "${GITHUB_ENV}" \
  --repo "${GITHUB_REPO}" \
  --body "${ROLE_ARN}"

gh variable set TF_STATE_BUCKET \
  --env "${GITHUB_ENV}" \
  --repo "${GITHUB_REPO}" \
  --body "${STATE_BUCKET}"

gh variable set TF_STATE_LOCK_TABLE \
  --env "${GITHUB_ENV}" \
  --repo "${GITHUB_REPO}" \
  --body "${LOCK_TABLE}"

log "Wiring complete (deploy not run)."
cat <<EOF

Next steps (manual):
  1. Deploy when ready:
       gh workflow run deploy-chain.yml --repo ${GITHUB_REPO} -f run_deploy=true
  2. After first apply, seed runtime secrets:
       TERRA_DEV_ID=... TERRA_API_KEY=... TERRA_WEBHOOK_SECRET=... \\
         ./scripts/seed_secrets.sh
  3. Register webhook in Terra dashboard:
       cd infra/terraform && terraform output -raw terra_webhook_url

Bootstrap outputs:
  account_id: ${ACCOUNT_ID}
  state_bucket: ${STATE_BUCKET}
  lock_table: ${LOCK_TABLE}
  deploy_role_arn: ${ROLE_ARN}
EOF