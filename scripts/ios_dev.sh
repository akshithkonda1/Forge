#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKSPACE="${ROOT}/Forge.xcworkspace"
BACKEND_PORT="${FORGE_BACKEND_PORT:-3001}"
BACKEND_PID_FILE="${TMPDIR:-/tmp}/forge-backend-${BACKEND_PORT}.pid"
SIMULATOR_NAME="${FORGE_IOS_SIMULATOR:-iPhone 17}"

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

preflight_build() {
  if ! command -v xcodebuild >/dev/null 2>&1; then
    echo "Warning: xcodebuild not found — install Xcode before running the iOS app." >&2
    return
  fi

  echo "Preflight: building ForgeSwift for iOS Simulator (${SIMULATOR_NAME})..."
  if xcodebuild build \
    -workspace "${WORKSPACE}" \
    -scheme ForgeSwift \
    -destination "platform=iOS Simulator,name=${SIMULATOR_NAME}" \
    -quiet; then
    echo "Preflight build succeeded."
  else
    echo "Preflight build failed. Fix compile/signing errors above before pressing Run in Xcode." >&2
    exit 1
  fi
}

open_xcode() {
  if [[ ! -d "${WORKSPACE}" ]]; then
    echo "Workspace not found: ${WORKSPACE}" >&2
    exit 1
  fi
  open "${WORKSPACE}"
  echo "Opened ${WORKSPACE}"
  echo ""
  echo "In Xcode:"
  echo "  1. Scheme: ForgeSwift (not ForgeWidgetExtension)"
  echo "  2. Destination: an iPhone simulator (e.g. ${SIMULATOR_NAME}) — not My Mac"
  echo "  3. Press Run (⌘R)"
  echo ""
  echo "Do NOT open clients/ios/... — that project is deprecated."
}

case "${1:-open}" in
  backend)
    start_backend
    ;;
  build)
    preflight_build
    ;;
  open)
    start_backend
    preflight_build
    open_xcode
    ;;
  *)
    echo "Usage: $0 [open|backend|build]" >&2
    exit 1
    ;;
esac