#!/usr/bin/env bash
# Wire Forge API + Cognito into the web and iOS clients.
#
# Offline (no AWS):  ./scripts/wire_clients.sh --offline
# Live (after apply): ./scripts/wire_clients.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TF_DIR="${ROOT}/terraform"
CONFIG_JSON="${ROOT}/client-configuration.json"
EXAMPLE_CONFIG="${ROOT}/client-configuration.example.json"
WEB_ORIGIN="${WEB_ORIGIN:-}"
OFFLINE=0
API_URL=""
HEALTH_URL=""

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

for arg in "$@"; do
  case "${arg}" in
    --offline) OFFLINE=1 ;;
    --live) OFFLINE=0 ;;
    -h|--help)
      cat <<'EOF'
Usage: wire_clients.sh [--offline | --live]

  --offline  Use client-configuration.example.json (no AWS/Terraform). Default when
             terraform/backend.hcl is missing.
  --live     Export client_configuration from Terraform state (requires AWS deploy).
EOF
      exit 0
      ;;
  esac
done

require_cmd python3

if [[ "${OFFLINE}" -eq 0 && ! -f "${TF_DIR}/backend.hcl" ]]; then
  log "terraform/backend.hcl not found — wiring clients offline"
  OFFLINE=1
fi

if [[ "${OFFLINE}" -eq 1 ]]; then
  [[ -f "${EXAMPLE_CONFIG}" ]] || die "missing ${EXAMPLE_CONFIG}"
  cp "${EXAMPLE_CONFIG}" "${CONFIG_JSON}"
  API_URL="$(python3 -c 'import json; print(json.load(open("'"${CONFIG_JSON}"'"))["apiBaseUrl"])')"
  HEALTH_URL="${API_URL}/health"
else
  require_cmd terraform
  log "Exporting Terraform client_configuration"
  pushd "${TF_DIR}" >/dev/null
  terraform init -backend-config=backend.hcl -input=false -reconfigure >/dev/null
  terraform output -json client_configuration > "${CONFIG_JSON}"
  API_URL="$(terraform output -raw api_base_url)"
  HEALTH_URL="$(terraform output -raw healthcheck_url)"
  popd >/dev/null
fi

log "Generating web and iOS production client files"
python3 "${ROOT}/backend/tools/generate_client_config.py" --input "${CONFIG_JSON}"

MODE_LABEL="live"
[[ "${OFFLINE}" -eq 1 ]] && MODE_LABEL="offline (placeholder — re-run without --offline after AWS deploy)"

log "Client wiring complete (${MODE_LABEL})"
cat <<EOF

Generated (gitignored):
  clients/web/.env.production.local
  ForgeSwift/Config/Forge-Production.xcconfig

API target:
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

Local dev against deployed API (after AWS is live):
  cp clients/web/.env.production.local clients/web/.env.local
  # Remove NEXT_PUBLIC_ALLOW_DEMO_FALLBACK from .env.local for real auth

When AWS is online:
  npm run wire:production && gh workflow run deploy-chain.yml -f run_deploy=true
  npm run wire:clients:live
EOF

if [[ -n "${WEB_ORIGIN}" ]]; then
  log "WEB_ORIGIN=${WEB_ORIGIN} — add this to terraform/terraform.tfvars allowed_origins and re-apply for CORS"
fi