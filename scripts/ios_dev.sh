#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${ROOT}/Forge.xcworkspace"
BACKEND_PORT="${FORGE_BACKEND_PORT:-3001}"
BACKEND_PID_FILE="${TMPDIR:-/tmp}/forge-backend-${BACKEND_PORT}.pid"

start_backend() {
  if curl -fsS "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1; then
    echo "Backend already running on http://127.0.0.1:${BACKEND_PORT}"
    return
  fi

  echo "Starting Forge backend on port ${BACKEND_PORT}..."
  (
    cd "${ROOT}"
    FORGE_API_BASE_URL="http://127.0.0.1:${BACKEND_PORT}" python3 backend/dev_server.py
  ) &
  echo $! >"${BACKEND_PID_FILE}"

  for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:${BACKEND_PORT}/health" >/dev/null 2>&1; then
      echo "Backend ready at http://127.0.0.1:${BACKEND_PORT}"
      return
    fi
    sleep 0.5
  done

  echo "Warning: backend did not respond on /health — open Xcode anyway." >&2
}

open_xcode() {
  if [[ ! -d "${WORKSPACE}" ]]; then
    echo "Workspace not found: ${WORKSPACE}" >&2
    exit 1
  fi
  open "${WORKSPACE}"
  echo "Opened ${WORKSPACE}"
  echo "Select the ForgeSwift scheme and an iPhone simulator, then press Run (⌘R)."
}

case "${1:-open}" in
  backend)
    start_backend
    ;;
  open)
    start_backend
    open_xcode
    ;;
  *)
    echo "Usage: $0 [open|backend]" >&2
    exit 1
    ;;
esac