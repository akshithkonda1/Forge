#!/bin/bash
# Install + launch ForgeWatch on every booted watchOS Simulator.
# Xcode scheme post-action for ForgeSwift / ForgeCompanion so phone + watch
# both open and WatchConnectivity can connect.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export FORGE_SCRIPTS_DIR="$SCRIPT_DIR"

export WATCH_BUNDLE_ID="${WATCH_BUNDLE_ID:-com.forge.ForgeSwift.watchkitapp}"
export WATCH_LAUNCH_WAIT_SEC="${WATCH_LAUNCH_WAIT_SEC:-25}"
export WATCH_LAUNCH_RETRY_SEC="${WATCH_LAUNCH_RETRY_SEC:-2}"
# Prefer explicit app path when Xcode post-action provides build products.
export BUILT_PRODUCTS_DIR="${BUILT_PRODUCTS_DIR:-}"
export TARGET_BUILD_DIR="${TARGET_BUILD_DIR:-}"
export SRCROOT="${SRCROOT:-}"

if ! command -v xcrun >/dev/null 2>&1; then
  echo "launch-watch-companion: xcrun missing — skip"
  exit 0
fi

# Resolve ForgeWatch.app from Xcode post-action env (preferred) or DerivedData.
WATCH_APP_CANDIDATES=()
if [[ -n "${BUILT_PRODUCTS_DIR:-}" ]]; then
  # Embed Watch Content copies the watch product next to the iPhone product:
  #   .../Debug-iphonesimulator/ForgeWatch.app
  WATCH_APP_CANDIDATES+=(
    "${BUILT_PRODUCTS_DIR}/ForgeWatch.app"
    "${BUILT_PRODUCTS_DIR}/../Debug-watchsimulator/ForgeWatch.app"
  )
fi
if [[ -n "${TARGET_BUILD_DIR:-}" ]]; then
  WATCH_APP_CANDIDATES+=(
    "${TARGET_BUILD_DIR}/Watch/ForgeWatch.app"
    "${TARGET_BUILD_DIR}/ForgeSwift.app/Watch/ForgeWatch.app"
  )
fi
if [[ -n "${SRCROOT:-}" ]]; then
  # Last-resort scan of this project's DerivedData products.
  while IFS= read -r p; do
    WATCH_APP_CANDIDATES+=("$p")
  done < <(
    find "${HOME}/Library/Developer/Xcode/DerivedData" \
      -path "*/Build/Products/Debug-watchsimulator/ForgeWatch.app" \
      -type d 2>/dev/null | head -5
  )
fi

export WATCH_APP_CANDIDATES_JSON
WATCH_APP_CANDIDATES_JSON="$(printf '%s\n' "${WATCH_APP_CANDIDATES[@]:-}" | python3 -c 'import json,sys; print(json.dumps([l.strip() for l in sys.stdin if l.strip()]))')"

python3 - <<'PY'
import json, os, subprocess, sys, time

HERE = os.environ.get("FORGE_SCRIPTS_DIR") or os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
from simctl_forge import SimctlTimeout, list_booted, simctl  # noqa: E402

bundle = os.environ.get("WATCH_BUNDLE_ID", "com.forge.ForgeSwift.watchkitapp")
max_wait = int(os.environ.get("WATCH_LAUNCH_WAIT_SEC", "25"))
retry_delay = float(os.environ.get("WATCH_LAUNCH_RETRY_SEC", "2"))
candidates = json.loads(os.environ.get("WATCH_APP_CANDIDATES_JSON", "[]"))
SIMCTL_TIMEOUT = float(os.environ.get("SIMCTL_TIMEOUT", "12"))


def booted_watch_udids():
    try:
        return [
            d["udid"]
            for d in list_booted(runtime_substr="watchos", timeout=SIMCTL_TIMEOUT)
        ]
    except SimctlTimeout as e:
        print(f"launch-watch-companion: {e}")
        print("  → CoreSimulator hung. ForgeSwift/Scripts/reset-simulator.sh --unwedge")
        return []
    except Exception as e:
        print(f"launch-watch-companion: simctl failed: {e}")
        return []


def resolve_watch_app():
    for path in candidates:
        if path and os.path.isdir(path) and path.endswith(".app"):
            return path
    # Prefer newest Debug-watchsimulator product if candidates missed.
    try:
        raw = subprocess.check_output(
            [
                "find",
                os.path.expanduser("~/Library/Developer/Xcode/DerivedData"),
                "-path",
                "*/Build/Products/Debug-watchsimulator/ForgeWatch.app",
                "-type",
                "d",
            ],
            text=True,
            stderr=subprocess.DEVNULL,
        )
        paths = [p for p in raw.splitlines() if p]
        if not paths:
            return None
        paths.sort(key=lambda p: os.path.getmtime(p), reverse=True)
        return paths[0]
    except Exception:
        return None


def run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=SIMCTL_TIMEOUT)
    except subprocess.TimeoutExpired:
        print(f"launch-watch-companion: timed out: {' '.join(cmd)}")
        return subprocess.CompletedProcess(cmd, 124, "", "simctl timeout")


# Wait for a booted watch sim (paired destinations boot async).
deadline = time.time() + max_wait
watch_ids = booted_watch_udids()
while not watch_ids and time.time() < deadline:
    time.sleep(retry_delay)
    watch_ids = booted_watch_udids()

if not watch_ids:
    print(
        "launch-watch-companion: no booted Watch simulator after "
        f"{max_wait}s.\n"
        "  → Window → Devices and Simulators → pair a Watch under your iPhone, boot it, re-run.\n"
        "  → Destination must be a *paired* iPhone (not Any iOS Device)."
    )
    sys.exit(0)

watch_app = resolve_watch_app()
if watch_app:
    print(f"launch-watch-companion: using {watch_app}")
else:
    print(
        "launch-watch-companion: ForgeWatch.app not found — will try launch only "
        "(install may already be present from a prior run)."
    )

for udid in watch_ids:
    if watch_app:
        try:
            inst = simctl("install", udid, watch_app, timeout=SIMCTL_TIMEOUT)
        except SimctlTimeout:
            print(f"launch-watch-companion: install timed out on {udid} — skip")
            continue
        if inst.returncode == 0:
            print(f"launch-watch-companion: installed on {udid}")
        else:
            err = (inst.stderr or inst.stdout or "").strip()
            print(f"launch-watch-companion: install warning on {udid}: {err}")

    success = False
    last_err = ""
    for _ in range(max(1, int(max_wait / retry_delay))):
        try:
            r = simctl("launch", udid, bundle, timeout=SIMCTL_TIMEOUT)
        except SimctlTimeout:
            last_err = "simctl launch timed out"
            break
        if r.returncode == 0:
            print(f"launch-watch-companion: launched {bundle} on {udid}")
            success = True
            break
        last_err = (r.stderr or r.stdout or "").strip()
        # If not installed yet, re-try install once more mid-loop.
        if watch_app and "not installed" in last_err.lower():
            try:
                simctl("install", udid, watch_app, timeout=SIMCTL_TIMEOUT)
            except SimctlTimeout:
                break
        time.sleep(retry_delay)

    if not success:
        print(f"launch-watch-companion: launch failed on {udid}: {last_err}")
        try:
            simctl("openurl", udid, "forgewatch://home", timeout=SIMCTL_TIMEOUT)
            print(f"launch-watch-companion: openurl fallback attempted on {udid}")
        except SimctlTimeout:
            print(f"launch-watch-companion: openurl timed out on {udid}")
PY
