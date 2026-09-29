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

if ! command -v k6 >/dev/null 2>&1; then
  if [[ -x /tmp/tools/k6-v2.3.0-linux-amd64/k6 ]]; then
    export PATH="/tmp/tools/k6-v2.3.0-linux-amd64:$PATH"
  fi
fi

export BASE_URL="${BASE_URL:-http://127.0.0.1:3001}"
export ARIA_BEDROCK_ENABLED="${ARIA_BEDROCK_ENABLED:-}"
export ARIA_VOICE_ENABLED="${ARIA_VOICE_ENABLED:-}"
export ENVIRONMENT="${ENVIRONMENT:-local}"
export FORGE_ALLOW_ANON_TEST_USER="${FORGE_ALLOW_ANON_TEST_USER:-true}"
export HOST="${HOST:-127.0.0.1}"
export PORT="${PORT:-3001}"
export LOADTEST_RESULTS_DIR="${LOADTEST_RESULTS_DIR:-backend/loadtest/results}"
export FORGE_LOADTEST_GUARD_FILE="${FORGE_LOADTEST_GUARD_FILE:-/tmp/forge-loadtest-guard.json}"
export PYTHONPATH="${ROOT}/backend/loadtest${PYTHONPATH:+:$PYTHONPATH}"

# Baseline keeps a shared test user. Stress must not: Dummy JWT identities
# (loadtest-<vu>-<iter>) only win when FORGE_TEST_USER_ID is unset.
if [[ "$SCENARIO" == "stress" ]]; then
  unset FORGE_TEST_USER_ID || true
else
  export FORGE_TEST_USER_ID="${FORGE_TEST_USER_ID:-loadtest-user}"
fi

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

kill_dummy() {
  if [[ -f "$LOADTEST_RESULTS_DIR/server.pid" ]]; then
    old="$(cat "$LOADTEST_RESULTS_DIR/server.pid" 2>/dev/null || true)"
    if [[ -n "${old:-}" ]]; then
      kill "$old" 2>/dev/null || true
      sleep 0.2
      kill -9 "$old" 2>/dev/null || true
    fi
    rm -f "$LOADTEST_RESULTS_DIR/server.pid"
  fi
  while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done < <(pgrep -f 'backend/loadtest/run_server.py' || true)
  sleep 0.3
}

start_dummy() {
  rm -f "$FORGE_LOADTEST_GUARD_FILE"
  if [[ "$SCENARIO" == "stress" ]]; then
    # Rate-limit counters live in storage.dynamodb._local_store (in-memory)
    # when APP_DATA_TABLE_NAME is unset. A new process clears that state.
    # Do not export FORGE_TEST_USER_ID — per-VU Bearer tokens must win.
    env -u FORGE_TEST_USER_ID \
      python3 backend/loadtest/run_server.py >"$LOADTEST_RESULTS_DIR/server.log" 2>&1 &
  else
    python3 backend/loadtest/run_server.py >"$LOADTEST_RESULTS_DIR/server.log" 2>&1 &
  fi
  echo $! >"$LOADTEST_RESULTS_DIR/server.pid"
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
}

STARTED_SERVER=0
if [[ "$SCENARIO" == "stress" ]]; then
  kill_dummy
  start_dummy
  STARTED_SERVER=1
elif ! curl -sf "$BASE_URL/health" >/dev/null; then
  start_dummy
  STARTED_SERVER=1
fi

CPU_PID=""
if [[ "$SCENARIO" == "stress" && -f "$LOADTEST_RESULTS_DIR/server.pid" ]]; then
  python3 backend/loadtest/sample_cpu.py \
    --pid "$(cat "$LOADTEST_RESULTS_DIR/server.pid")" \
    --out "$LOADTEST_RESULTS_DIR/cpu.jsonl" \
    --summary "$LOADTEST_RESULTS_DIR/cpu.json" \
    --interval 1 >/dev/null 2>&1 &
  CPU_PID=$!
fi

cleanup() {
  if [[ -n "${CPU_PID:-}" ]]; then
    kill "$CPU_PID" 2>/dev/null || true
    wait "$CPU_PID" 2>/dev/null || true
  fi
  if [[ "$STARTED_SERVER" -eq 1 && -f "$LOADTEST_RESULTS_DIR/server.pid" ]]; then
    kill "$(cat "$LOADTEST_RESULTS_DIR/server.pid")" 2>/dev/null || true
  fi
}
trap cleanup EXIT

set +e
k6 run \
  --out "json=${LOADTEST_RESULTS_DIR}/${SCENARIO}.k6.json" \
  --env "BASE_URL=$BASE_URL" \
  --env "ARIA_BEDROCK_ENABLED=$ARIA_BEDROCK_ENABLED" \
  --env "ARIA_VOICE_ENABLED=$ARIA_VOICE_ENABLED" \
  --env "LOADTEST_RESULTS_DIR=$LOADTEST_RESULTS_DIR" \
  "backend/loadtest/k6/${SCENARIO}.js"
k6_rc=$?
set -e

if [[ -n "${CPU_PID:-}" ]]; then
  kill "$CPU_PID" 2>/dev/null || true
  wait "$CPU_PID" 2>/dev/null || true
  CPU_PID=""
fi

if [[ ! -f "${LOADTEST_RESULTS_DIR}/summary.json" ]]; then
  echo "k6 exited $k6_rc and wrote no summary.json" >&2
  exit "$k6_rc"
fi

python3 backend/loadtest/summarize.py \
  --scenario "$SCENARIO" \
  --base-url "$BASE_URL" \
  --results-dir "$LOADTEST_RESULTS_DIR" \
  --k6-json "${LOADTEST_RESULTS_DIR}/${SCENARIO}.k6.json"

echo "Wrote $LOADTEST_RESULTS_DIR/${SCENARIO}.json and $LOADTEST_RESULTS_DIR/${SCENARIO}.md"
