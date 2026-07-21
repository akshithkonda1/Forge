#!/bin/bash
# Launch ForgeWatch on every booted watchOS Simulator.
# Xcode scheme post-action for ForgeSwift so phone + watch both open.
set -uo pipefail

BUNDLE_ID="${WATCH_BUNDLE_ID:-com.forge.ForgeSwift.watchkitapp}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "launch-watch-companion: xcrun missing — skip"
  exit 0
fi

python3 - <<PY
import json, subprocess, sys, time

bundle = "${BUNDLE_ID}"
try:
    raw = subprocess.check_output(
        ["xcrun", "simctl", "list", "devices", "booted", "-j"],
        text=True,
    )
except Exception as e:
    print(f"launch-watch-companion: simctl failed: {e}")
    sys.exit(0)

data = json.loads(raw)
watch_ids = []
for runtime, devices in data.get("devices", {}).items():
    if "watchos" not in runtime.lower():
        continue
    for d in devices:
        if d.get("state") == "Booted":
            watch_ids.append(d["udid"])

if not watch_ids:
    print(
        "launch-watch-companion: no booted Watch simulator.\n"
        "  → Window → Devices and Simulators → pair a Watch under your iPhone, boot it, re-run."
    )
    sys.exit(0)

for udid in watch_ids:
    def attempt():
        return subprocess.run(
            ["xcrun", "simctl", "launch", udid, bundle],
            capture_output=True,
            text=True,
        )

    r = attempt()
    if r.returncode != 0:
        time.sleep(2.0)
        r = attempt()
    if r.returncode == 0:
        print(f"launch-watch-companion: launched {bundle} on {udid}")
    else:
        err = (r.stderr or r.stdout or "").strip()
        print(f"launch-watch-companion: launch failed on {udid}: {err}")
        # Last resort: open the watch app via openurl (if registered)
        subprocess.run(
            ["xcrun", "simctl", "openurl", udid, "forgewatch://home"],
            capture_output=True,
            text=True,
        )
PY
