#!/usr/bin/env bash
# Wire deployed Forge API + Cognito into the web and iOS clients.
# Run after terraform apply (local or via deploy-chain Phase 3).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
CONFIG_JSON="${ROOT}/client-configuration.json"
WEB_ORIGIN="${WEB_ORIGIN:-}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

require_cmd terraform
require_cmd python3

if [[ ! -f "${TF_DIR}/backend.hcl" ]]; then
  die "missing ${TF_DIR}/backend.hcl — run ./scripts/wire_production.sh first"
fi

log "Exporting Terraform client_configuration"
pushd "${TF_DIR}" >/dev/null
terraform init -backend-config=backend.hcl -input=false -reconfigure >/dev/null
terraform output -json client_configuration > "${CONFIG_JSON}"
API_URL="$(terraform output -raw api_base_url)"
HEALTH_URL="$(terraform output -raw healthcheck_url)"
popd >/dev/null

log "Generating web and iOS production client files"
python3 "${ROOT}/backend/tools/generate_client_config.py" --input "${CONFIG_JSON}"

log "Client wiring complete"
cat <<EOF

Generated (gitignored):
  clients/web/.env.production.local
  ForgeSwift/Config/Forge-Production.xcconfig

Deployed API:
  base:   ${API_URL}
  health: ${HEALTH_URL}

Next steps:
  1. Web production build:
       cd clients/web && npm install && npm run build
  2. iOS Release archive (uses Forge-Production.xcconfig via Forge-Release.xcconfig)
  3. Add your production web origin to terraform/terraform.tfvars allowed_origins, then re-apply:
       allowed_origins = ["http://localhost:3000", "https://your-app.example.com"]
  4. Smoke test with JWT after creating a Cognito user:
       FORGE_API_BASE_URL=${API_URL} FORGE_SMOKE_AUTH_TOKEN=<id_token> \\
         python3 backend/tools/smoke_test.py

Local dev against deployed API (optional):
  cp clients/web/.env.production.local clients/web/.env.local
  # Remove NEXT_PUBLIC_ALLOW_DEMO_FALLBACK from .env.local for real auth
EOF

if [[ -n "${WEB_ORIGIN}" ]]; then
  log "WEB_ORIGIN=${WEB_ORIGIN} — add this to terraform/terraform.tfvars allowed_origins and re-apply for CORS"
fi