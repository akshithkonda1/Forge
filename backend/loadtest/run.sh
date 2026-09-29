#!/usr/bin/env bash
# Run a Dummy-local k6 scenario. Refuses unless BASE_URL is loopback and
# ARIA_BEDROCK_ENABLED=ARIA_VOICE_ENABLED=false. Does not talk to AWS.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SCENARIO="${1:-}"
if [[ "$SCENARIO" != "baseline" && "$SCENARIO" != "stress" ]]; then
  echo "usage: $0 baseline|stress" >&2
  exit 2
fi

export BASE_URL="${BASE_URL:-http://127.0.0.1:3001}"
export ARIA_BEDROCK_ENABLED="${ARIA_BEDROCK_ENABLED:-}"
export ARIA_VOICE_ENABLED="${ARIA_VOICE_ENABLED:-}"
export ENVIRONMENT="${ENVIRONMENT:-local}"
export FORGE_ALLOW_ANON_TEST_USER="${FORGE_ALLOW_ANON_TEST_USER:-true}"
export FORGE_TEST_USER_ID="${FORGE_TEST_USER_ID:-loadtest-user}"
export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-3001}"
export LOADTEST_RESULTS_DIR="${LOADTEST_RESULTS_DIR:-backend/loadtest/results}"
export FORGE_LOADTEST_GUARD_FILE="${FORGE_LOADTEST_GUARD_FILE:-/tmp/forge-loadtest-guard.json}"
export PYTHONPATH="${ROOT}/backend/loadtest${PYTHONPATH:+:$PYTHONPATH}"

python3 - <<'PY'
import os
import sys
from preflight import validate_run_env
try:
    print("BASE_URL", validate_run_env(os.environ))
except ValueError as exc:
    print(exc, file=sys.stderr)
    raise SystemExit(2)
PY

mkdir -p "$LOADTEST_RESULTS_DIR"

STARTED_SERVER=0
if ! curl -sf "$BASE_URL/health" >/dev/null; then
  python3 backend/loadtest/run_server.py >"$LOADTEST_RESULTS_DIR/server.log" 2>&1 &
  echo $! >"$LOADTEST_RESULTS_DIR/server.pid"
  STARTED_SERVER=1
  ready=0
  for _ in $(seq 1 50); do
    if curl -sf "$BASE_URL/health" >/dev/null; then
      ready=1
      break
    fi
    sleep 0.2
  done
  if [[ "$ready" -ne 1 ]]; then
    echo "Dummy backend failed to become ready on $BASE_URL" >&2
    tail -n 80 "$LOADTEST_RESULTS_DIR/server.log" >&2 || true
    exit 1
  fi
fi

cleanup() {
  if [[ "$STARTED_SERVER" -eq 1 && -f "$LOADTEST_RESULTS_DIR/server.pid" ]]; then
    kill "$(cat "$LOADTEST_RESULTS_DIR/server.pid")" 2>/dev/null || true
  fi
}
trap cleanup EXIT

k6 run \
  --env "BASE_URL=$BASE_URL" \
  --env "ARIA_BEDROCK_ENABLED=$ARIA_BEDROCK_ENABLED" \
  --env "ARIA_VOICE_ENABLED=$ARIA_VOICE_ENABLED" \
  --env "LOADTEST_RESULTS_DIR=$LOADTEST_RESULTS_DIR" \
  "backend/loadtest/k6/${SCENARIO}.js"

python3 backend/loadtest/summarize.py \
  --scenario "$SCENARIO" \
  --base-url "$BASE_URL" \
  --results-dir "$LOADTEST_RESULTS_DIR"

echo "Wrote $LOADTEST_RESULTS_DIR/summary.json and $LOADTEST_RESULTS_DIR/summary.md"
