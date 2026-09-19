#!/bin/bash
# Erase a Forge iOS 27 simulator without hanging on a wedged CoreSimulator.
#
#   ./ForgeSwift/Scripts/reset-simulator.sh
#   ./ForgeSwift/Scripts/reset-simulator.sh 29B53C96-6BE3-4A79-991C-C652E44650FD
#   ./ForgeSwift/Scripts/reset-simulator.sh --unwedge
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PY="$SCRIPT_DIR/simctl_forge.py"

if [[ "${1:-}" == "--unwedge" ]]; then
  exec python3 "$PY" unwedge
fi

UDID="${1:-}"
if [[ -z "$UDID" ]]; then
  # Prefer the iPhone 17e this repo develops against; else first iOS 27 iPhone.
  UDID="$(python3 - <<'PY'
import json, subprocess, sys
try:
    raw = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "available", "-j"],
        capture_output=True, text=True, timeout=15,
    )
except subprocess.TimeoutExpired:
    print("simctl list timed out — pass a UDID or run --unwedge first", file=sys.stderr)
    sys.exit(124)
data = json.loads(raw.stdout or "{}")
preferred = None
fallback = None
for runtime, devices in data.get("devices", {}).items():
    if "ios-27" not in runtime.lower() and "iOS 27" not in runtime:
        continue
    for d in devices:
        name = d.get("name") or ""
        udid = d.get("udid")
        if not udid:
            continue
        if "iPhone 17e" in name:
            preferred = udid
            break
        if fallback is None and "iPhone" in name:
            fallback = udid
    if preferred:
        break
print(preferred or fallback or "")
PY
)"
fi

if [[ -z "$UDID" ]]; then
  echo "reset-simulator: no iOS 27 iPhone found. Pass a UDID." >&2
  exit 2
fi

echo "reset-simulator: erasing $UDID"
python3 "$PY" erase "$UDID"
echo "reset-simulator: done. Boot it from Xcode (iOS 27) and ⌘R ForgeSwift."
echo "  After erase, Connect Apple Health once — Test-Ready writes the pack then."
