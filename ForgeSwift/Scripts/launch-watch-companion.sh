#!/bin/bash
# Install + launch ForgeWatch on every booted watchOS Simulator.
# Xcode scheme post-action for ForgeSwift / ForgeCompanion so phone + watch
# both open and WatchConnectivity can connect.
set -uo pipefail

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

bundle = os.environ.get("WATCH_BUNDLE_ID", "com.forge.ForgeSwift.watchkitapp")
max_wait = int(os.environ.get("WATCH_LAUNCH_WAIT_SEC", "25"))
retry_delay = float(os.environ.get("WATCH_LAUNCH_RETRY_SEC", "2"))
candidates = json.loads(os.environ.get("WATCH_APP_CANDIDATES_JSON", "[]"))


def booted_watch_udids():
    try:
        raw = subprocess.check_output(
            ["xcrun", "simctl", "list", "devices", "booted", "-j"],
            text=True,
        )
    except Exception as e:
        print(f"launch-watch-companion: simctl failed: {e}")
        return []
    data = json.loads(raw)
    ids = []
    for runtime, devices in data.get("devices", {}).items():
        if "watchos" not in runtime.lower():
            continue
        for d in devices:
            if d.get("state") == "Booted":
                ids.append(d["udid"])
    return ids


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
    return subprocess.run(cmd, capture_output=True, text=True)


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
        inst = run(["xcrun", "simctl", "install", udid, watch_app])
        if inst.returncode == 0:
            print(f"launch-watch-companion: installed on {udid}")
        else:
            err = (inst.stderr or inst.stdout or "").strip()
            print(f"launch-watch-companion: install warning on {udid}: {err}")

    success = False
    last_err = ""
    for _ in range(max(1, int(max_wait / retry_delay))):
        r = run(["xcrun", "simctl", "launch", udid, bundle])
        if r.returncode == 0:
            print(f"launch-watch-companion: launched {bundle} on {udid}")
            success = True
            break
        last_err = (r.stderr or r.stdout or "").strip()
        # If not installed yet, re-try install once more mid-loop.
        if watch_app and "not installed" in last_err.lower():
            run(["xcrun", "simctl", "install", udid, watch_app])
        time.sleep(retry_delay)

    if not success:
        print(f"launch-watch-companion: launch failed on {udid}: {last_err}")
        run(["xcrun", "simctl", "openurl", udid, "forgewatch://home"])
        print(f"launch-watch-companion: openurl fallback attempted on {udid}")
PY
