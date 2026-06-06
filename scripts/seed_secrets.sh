#!/usr/bin/env bash
# Seed Forge Secrets Manager values after the main Terraform stack is applied.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/infra/terraform"
AWS_REGION="${AWS_REGION:-us-east-1}"
ENVIRONMENT="${FORGE_ENVIRONMENT:-dev}"
PROJECT_NAME="${FORGE_PROJECT_NAME:-forge}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd aws
require_cmd terraform

PREFIX="${PROJECT_NAME}-${ENVIRONMENT}"
AI_SECRET="${PREFIX}/ai/provider"
TERRA_SECRET="${PREFIX}/integrations/terra"

if [[ -n "${ANTHROPIC_API_KEY:-}" || -n "${OPENAI_API_KEY:-}" ]]; then
  log "Seeding AI provider secret (${AI_SECRET})"
  PAYLOAD='{}'
  if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
    PAYLOAD="$(python3 -c 'import json,os; print(json.dumps({"ANTHROPIC_API_KEY": os.environ["ANTHROPIC_API_KEY"]}))')"
  elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
    PAYLOAD="$(python3 -c 'import json,os; print(json.dumps({"OPENAI_API_KEY": os.environ["OPENAI_API_KEY"]}))')"
  fi
  aws secretsmanager put-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${AI_SECRET}" \
    --secret-string "${PAYLOAD}"
else
  log "Skipping AI provider secret (set ANTHROPIC_API_KEY or OPENAI_API_KEY to seed)"
fi

if [[ -n "${TERRA_DEV_ID:-}" && -n "${TERRA_API_KEY:-}" && -n "${TERRA_WEBHOOK_SECRET:-}" ]]; then
  log "Seeding Terra middleware secret (${TERRA_SECRET})"
  TERRA_PAYLOAD="$(python3 -c 'import json,os; print(json.dumps({
    "dev_id": os.environ["TERRA_DEV_ID"],
    "api_key": os.environ["TERRA_API_KEY"],
    "webhook_secret": os.environ["TERRA_WEBHOOK_SECRET"],
  }))')"
  aws secretsmanager put-secret-value \
    --region "${AWS_REGION}" \
    --secret-id "${TERRA_SECRET}" \
    --secret-string "${TERRA_PAYLOAD}"
else
  log "Skipping Terra secret (set TERRA_DEV_ID, TERRA_API_KEY, TERRA_WEBHOOK_SECRET to seed)"
fi

if [[ -d "${TF_DIR}/.terraform" ]]; then
  WEBHOOK_URL="$(terraform -chdir="${TF_DIR}" output -raw terra_webhook_url 2>/dev/null || true)"
  if [[ -n "${WEBHOOK_URL}" ]]; then
    log "Register this webhook URL in the Terra dashboard:"
    printf '  %s\n' "${WEBHOOK_URL}"
  fi
fi

log "Secret seeding finished."