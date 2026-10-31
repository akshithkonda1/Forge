#!/usr/bin/env python3
"""ForgeSwift launch stability gate (simulator, no app changes, no UI test target).

Scenarios, each on a freshly installed app:
  cold          fresh install, cold launch
  kill_relaunch launch, SIGKILL 1s in (a crash mid-launch), cold relaunch
  prep_wedge    crash-surviving AriaForgePrep handoff flag set, then launch

Checks (thresholds in thresholds.env only):
  alive         app process exists at every checkpoint (launch crash)
  first_frame   non-blank screenshot within FIRST_FRAME_MAX_S (blank-screen hang)
  main_thread   `sample` of the main thread: time outside the idle run-loop
                wait per window <= MAIN_THREAD_BLOCK_MAX_S (main thread hang)
  memory        phys_footprint peak <= MEMORY_MAX_MB, early->steady growth
                <= MEMORY_GROWTH_MAX_MB
  prep_watchdog (prep_wedge only) handoff flag no longer pending by
                PREP_WATCHDOG_S (stuck in AriaForgePrep / relaunch wedge)

Any failed check, or any measurement that cannot be taken, fails the gate.
"""
import json, os, re, struct, subprocess, sys, time, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
BUNDLE = "com.forge.ForgeSwift"
OUT = os.environ.get("LAUNCH_GATE_OUT", "/tmp/launch-gate")
# Only the kernel traps themselves; wrappers (mach_msg_overwrite, mach_msg2_internal)
# sit above the trap in the same stack and would double-count idle.
IDLE_FRAMES = ("mach_msg2_trap", "mach_msg_trap")
RUNLOOP_WAIT = ("__CFRunLoopServiceMachPort", "CFRunLoopRun", "__CFRunLoopRun")


def load_thresholds():
    t = {}
    for line in open(os.path.join(HERE, "thresholds.env")):
        line = line.strip()
        if line and not line.startswith("#"):
            k, v = line.split("=", 1)
            t[k] = float(v)
    return t


T = load_thresholds()


def sh(*args, check=True, timeout=120):
    r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"{' '.join(args)} -> {r.returncode}: {r.stderr.strip()}")
    return r


def simctl(*a, **kw):
    return sh("xcrun", "simctl", *a, **kw)


# ---------- PNG (8-bit RGB/RGBA, non-interlaced) ----------
def png_pixels(path, step=8, want_pixels=False):
    data = open(path, "rb").read()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", "not a PNG"
    pos, idat, hdr = 8, b"", None
    while pos < len(data):
        n, typ = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        if typ == b"IHDR":
            hdr = struct.unpack(">IIBBBBB", body)
        elif typ == b"IDAT":
            idat += body
        pos += 12 + n
    w, h, depth, ctype, _, _, interlace = hdr
    if depth != 8 or ctype not in (2, 6) or interlace:
        raise RuntimeError(f"unsupported PNG depth={depth} ctype={ctype} interlace={interlace}")
    bpp = 4 if ctype == 6 else 3
    raw = zlib.decompress(idat)
    stride = w * bpp
    prev = bytearray(stride)
    counts, pixels, i = {}, [], 0
    for y in range(h):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        for x in range(stride):
            a = line[x - bpp] if x >= bpp else 0
            b = prev[x]
            c = prev[x - bpp] if x >= bpp else 0
            if f == 1: line[x] = (line[x] + a) & 255
            elif f == 2: line[x] = (line[x] + b) & 255
            elif f == 3: line[x] = (line[x] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c; pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                pr = a if pa <= pb and pa <= pc else (b if pb <= pc else c)
                line[x] = (line[x] + pr) & 255
        prev = line
        if y % step == 0:
            for x in range(0, w, step):
                px = bytes(line[x * bpp:x * bpp + 3])
                counts[px] = counts.get(px, 0) + 1
                pixels.append(px)
    return (counts, pixels) if want_pixels else counts


def diff_share(path_a, path_b, tol=24):
    """Share of sampled pixels that differ (any channel > tol) between two shots."""
    _, a = png_pixels(path_a, want_pixels=True)
    _, b = png_pixels(path_b, want_pixels=True)
    if len(a) != len(b) or not a:
        raise RuntimeError(f"screenshot size mismatch {len(a)} vs {len(b)}")
    d = sum(1 for p, q in zip(a, b) if max(abs(x - y) for x, y in zip(p, q)) > tol)
    return d / len(a)


def shot(udid, path, timeout=30):
    """Screenshot + downscale (sips, fast) so decoding is cheap. Returns the
    small PNG path and the monotonic time the capture FINISHED."""
    simctl("io", udid, "screenshot", "--type=png", path, timeout=timeout)
    done = time.monotonic()
    small = path[:-4] + "-small.png"
    sh("sips", "-s", "format", "png", "-Z", str(int(T["SHOT_MAX_PX"])), path, "--out", small, timeout=30)
    return small, done


def ensure_booted(udid):
    """The sim can shut down under a long xcodebuild or a hung screenshot."""
    b = simctl("boot", udid, check=False)
    if b.returncode != 0 and "Booted" not in (b.stderr or "") and "Booted" not in (b.stdout or ""):
        raise RuntimeError(f"simctl boot failed: {(b.stderr or b.stdout).strip()}")
    simctl("bootstatus", udid, "-b", timeout=300)


def warmup_screenshot_io(udid):
    """First `simctl io screenshot` after a long xcodebuild is often 10–30s
    or times out, which blows the 8s first_frame window (2 consecutive
    captures). Burn that cost here, before any timed scenario. Thresholds
    stay unchanged."""
    path = f"{OUT}/warmup.png"
    successes, last_err = 0, None
    for attempt in range(1, 6):
        try:
            ensure_booted(udid)
            t0 = time.monotonic()
            simctl("io", udid, "screenshot", "--type=png", path, timeout=45)
            dt = time.monotonic() - t0
            successes += 1
            print(f"  warmup screenshot {attempt}: {dt:.1f}s", flush=True)
            if successes >= 2 and dt < 5:
                return
        except Exception as e:
            last_err = e
            print(f"  warmup screenshot {attempt} failed: {e}", flush=True)
            time.sleep(2)
    if successes >= 1:
        print("  warmup: screenshot IO works; continuing", flush=True)
        return
    raise RuntimeError(f"simulator screenshot IO never became ready: {last_err}")


def summarize(path, label):
    """Text summary of a screenshot for the job log: dominant RGB + share and
    an 8x8 grid of average colours (rows top->bottom)."""
    counts, px = png_pixels(path, step=1, want_pixels=True)
    dom, n = max(counts.items(), key=lambda kv: kv[1])
    w, h = _dims(path)
    print(f"  [frame] {label}: {w}x{h} dominant rgb{tuple(dom)} share {n / len(px):.4f}")
    for gy in range(8):
        row = []
        for gx in range(8):
            acc, k = [0, 0, 0], 0
            for y in range(gy * h // 8, (gy + 1) * h // 8):
                for x in range(gx * w // 8, (gx + 1) * w // 8):
                    p = px[y * w + x]
                    acc[0] += p[0]; acc[1] += p[1]; acc[2] += p[2]; k += 1
            row.append("%02x%02x%02x" % tuple(c // max(k, 1) for c in acc))
        print("    " + " ".join(row))


def _dims(path):
    d = open(path, "rb").read(24)
    return struct.unpack(">II", d[16:24])


def dominant_share(path):
    counts = png_pixels(path)
    return max(counts.values()) / sum(counts.values())


# ---------- process probes ----------
def pid_alive(pid):
    return subprocess.run(["kill", "-0", str(pid)], capture_output=True).returncode == 0


def footprint_mb(pid):
    r = sh("footprint", str(pid), check=False, timeout=60)
    m = re.search(r"phys_footprint:\s*([\d.]+)\s*([KMG]B)", r.stdout)
    if m:
        v = float(m.group(1)); u = m.group(2)
        return v / 1024 if u == "KB" else v * 1024 if u == "GB" else v, "phys_footprint"
    rss = sh("ps", "-o", "rss=", "-p", str(pid), check=False).stdout.strip()
    if rss:
        return int(rss) / 1024, "rss(footprint unavailable)"
    raise RuntimeError(f"could not read memory for pid {pid}: {r.stderr.strip()}")


def run_sample(pid, window, path, timeout):
    """`sample` with retries; a run that never yields a file is a failure."""
    last = ""
    for attempt in range(1, int(T["SAMPLE_RETRIES"]) + 1):
        if os.path.exists(path):
            os.remove(path)
        try:
            r = sh("sample", str(pid), str(int(window)), "1", "-mayDie", "-file", path,
                   check=False, timeout=timeout)
            if os.path.exists(path) and os.path.getsize(path) > 0:
                return open(path).read()
            last = f"rc={r.returncode}: {r.stderr.strip()}"
        except subprocess.TimeoutExpired:
            subprocess.run(["pkill", "-9", "-f", f"sample {pid} "], capture_output=True)
            last = f"timed out after {timeout:.0f}s"
        print(f"    sample attempt {attempt} failed ({last})", flush=True)
        if not pid_alive(pid):
            break
    raise RuntimeError(f"sample failed after retries: {last}")


def main_thread_busy_s(pid, window, tag, timeout):
    path = f"{OUT}/sample-{tag}.txt"
    text = run_sample(pid, window, path, timeout)
    # Main thread block runs until the next top-level "Thread_" line.
    m = re.search(r"^(\s*)(\d+) Thread_\d+.*?(?:com\.apple\.main-thread|Main Thread).*?$", text, re.M)
    if not m:
        raise RuntimeError("main thread not found in sample output")
    total = int(m.group(2))
    rest = text[m.end():]
    nxt = re.search(r"^\s*\d+ Thread_\d+", rest, re.M)
    block = rest[:nxt.start()] if nxt else rest
    # Parse the call tree: (indent column of the count, count, text).
    rows = []
    for line in block.splitlines():
        mm = re.match(r"^([\s+!:|]*)(\d+)\s+(.*)$", line)
        if mm:
            rows.append((len(mm.group(1)), int(mm.group(2)), mm.group(3)))
    # Idle = LEAF frames (no deeper child next) that are the kernel mach_msg
    # trap. Leaves never nest, so this cannot double-count.
    # The trap only counts as idle when its ancestors include the run loop's
    # port wait; a mach_msg/semaphore block from app code is a hang, not idle.
    idle, stack = 0, []
    for i, (ind, n, txt) in enumerate(rows):
        while stack and stack[-1][0] >= ind:
            stack.pop()
        stack.append((ind, txt))
        leaf = i + 1 >= len(rows) or rows[i + 1][0] <= ind
        if leaf and any(f in txt for f in IDLE_FRAMES) and \
                any(any(r in t for r in RUNLOOP_WAIT) for _, t in stack[:-1]):
            idle += n
    if total <= 0:
        raise RuntimeError("main thread total sample count is 0")
    if idle > total:
        raise RuntimeError(f"parser invariant broken: idle {idle} > main-thread total {total}")
    busy_samples = total - idle
    return busy_samples / total * window, total, idle


# ---------- scenario ----------
def fresh_install(udid, app):
    ensure_booted(udid)
    simctl("terminate", udid, BUNDLE, check=False)
    simctl("uninstall", udid, BUNDLE, check=False)
    try:
        simctl("install", udid, app)
    except RuntimeError as e:
        if "Shutdown" not in str(e) and "Current state" not in str(e):
            raise
        ensure_booted(udid)
        simctl("install", udid, app)


def launch(udid):
    out = simctl("launch", udid, BUNDLE).stdout
    m = re.search(r":\s*(\d+)", out)
    if not m:
        raise RuntimeError(f"no pid from simctl launch: {out!r}")
    return int(m.group(1)), time.monotonic()


def defaults_read(udid, key):
    r = simctl("spawn", udid, "defaults", "read", BUNDLE, key, check=False)
    return r.stdout.strip() if r.returncode == 0 else None


def run_scenario(name, udid, app):
    res = {"scenario": name, "checks": []}

    def check(cname, ok, measured, limit):
        res["checks"].append({"check": cname, "ok": bool(ok), "measured": measured, "limit": limit})
        print(f"  [{'PASS' if ok else 'FAIL'}] {name}/{cname}: {measured} (limit {limit})", flush=True)

    fresh_install(udid, app)
    if name == "kill_relaunch":
        pid, _ = launch(udid)
        time.sleep(1)
        subprocess.run(["kill", "-9", str(pid)])
        time.sleep(2)
    if name == "prep_wedge":
        simctl("spawn", udid, "defaults", "write", BUNDLE, "forge.onboarding.interviewComplete", "-bool", "YES")
        simctl("spawn", udid, "defaults", "write", BUNDLE, "forge.onboarding.completed", "-bool", "NO")
        simctl("spawn", udid, "defaults", "write", BUNDLE, "forge.auth.session.v1", "-bool", "YES")

    # Baseline: the screen with the app NOT running (terminate + settle), so a
    # leftover image from a previous/killed launch can't count as the frame.
    simctl("terminate", udid, BUNDLE, check=False)
    time.sleep(T["BASELINE_SETTLE_S"])
    base, _ = shot(udid, f"{OUT}/{name}-baseline.png")
    if dominant_share(base) >= T["BLANK_DOMINANT_SHARE"]:
        raise RuntimeError("baseline screenshot is blank; cannot tell app frame apart")

    pid, t0 = launch(udid)
    el = lambda: time.monotonic() - t0

    # first frame: FIRST_FRAME_CONSECUTIVE consecutive captures that are
    # non-blank AND >= FRAME_DIFF_MIN_SHARE changed vs baseline. Time = when
    # the first of them FINISHED capturing.
    frame_at, share, diff, streak, first_ok, last = None, None, None, 0, None, None
    while el() < T["FIRST_FRAME_MAX_S"]:
        small, done = shot(udid, f"{OUT}/{name}-frame.png")
        last = small
        share = dominant_share(small)
        diff = diff_share(base, small)
        if share < T["BLANK_DOMINANT_SHARE"] and diff >= T["FRAME_DIFF_MIN_SHARE"]:
            streak += 1
            first_ok = first_ok if streak > 1 else done - t0
            if streak >= T["FIRST_FRAME_CONSECUTIVE"]:
                frame_at = first_ok; break
        else:
            streak, first_ok = 0, None
    if last:
        summarize(last, f"{name} last frame @{el():.1f}s")
    summarize(base, f"{name} baseline")
    check("alive@first_frame", pid_alive(pid), f"pid {pid}", "alive")
    check("first_frame", frame_at is not None and frame_at <= T["FIRST_FRAME_MAX_S"],
          f"{frame_at:.2f}s x{int(T['FIRST_FRAME_CONSECUTIVE'])} frames (diff vs baseline {diff:.2f}, dominant {share:.3f})" if frame_at is not None
          else f"no app frame after {el():.1f}s (diff {diff}, dominant {share})",
          f"<= {T['FIRST_FRAME_MAX_S']}s, non-blank, >= {T['FRAME_DIFF_MIN_SHARE']} changed vs baseline")
    if not pid_alive(pid):
        return res

    early, src = footprint_mb(pid)
    worst = 0.0
    for w in range(int(T["SAMPLE_WINDOWS"])):
        if not pid_alive(pid):
            break
        tmo = T["SAMPLE_TIMEOUT_COLD_S"] if (name == "cold" and w == 0) else T["SAMPLE_TIMEOUT_S"]
        busy, total, idle = main_thread_busy_s(pid, T["SAMPLE_WINDOW_S"], f"{name}-{w}", tmo)
        worst = max(worst, busy)
        print(f"    sample {w}: main busy {busy:.2f}s (samples total={total} idle={idle})")
    check("main_thread", worst <= T["MAIN_THREAD_BLOCK_MAX_S"] and pid_alive(pid),
          f"worst {worst:.2f}s busy per {T['SAMPLE_WINDOW_S']:.0f}s window",
          f"<= {T['MAIN_THREAD_BLOCK_MAX_S']}s")

    while el() < T["MEMORY_STEADY_AT_S"] and pid_alive(pid):
        time.sleep(1)
    check("alive@steady", pid_alive(pid), f"{el():.0f}s", "alive")
    if pid_alive(pid):
        steady, _ = footprint_mb(pid)
        peak = max(early, steady)
        check("memory_peak", peak <= T["MEMORY_MAX_MB"], f"{peak:.0f}MB ({src})", f"<= {T['MEMORY_MAX_MB']:.0f}MB")
        check("memory_growth", steady - early <= T["MEMORY_GROWTH_MAX_MB"],
              f"{early:.0f}->{steady:.0f}MB", f"<= +{T['MEMORY_GROWTH_MAX_MB']:.0f}MB")

    if name == "prep_wedge":
        pending = True
        while el() < T["PREP_WATCHDOG_S"]:
            ic = defaults_read(udid, "forge.onboarding.interviewComplete")
            ob = defaults_read(udid, "forge.onboarding.completed")
            pending = ic == "1" and ob != "1"
            if not pending:
                break
            time.sleep(2)
        check("prep_watchdog", not pending and pid_alive(pid),
              f"{'still in AriaForgePrep' if pending else 'left prep'} at {el():.0f}s, alive={pid_alive(pid)}",
              f"left prep by {T['PREP_WATCHDOG_S']:.0f}s")
    simctl("io", udid, "screenshot", f"{OUT}/{name}-end.png", check=False)
    simctl("terminate", udid, BUNDLE, check=False)
    return res


def main():
    udid, app = sys.argv[1], sys.argv[2]
    os.makedirs(OUT, exist_ok=True)
    # The sim can be shut down under us during the long build; boot here.
    # "already booted" is the only boot error tolerated; bootstatus must pass.
    ensure_booted(udid)
    warmup_screenshot_io(udid)
    results, ok = [], True
    for name in ("cold", "kill_relaunch", "prep_wedge"):
        print(f"== scenario {name}", flush=True)
        try:
            r = run_scenario(name, udid, app)
        except Exception as e:  # a measurement we cannot take is a failure
            r = {"scenario": name, "checks": [{"check": "harness", "ok": False, "measured": str(e), "limit": "measurable"}]}
            print(f"  [FAIL] {name}/harness: {e}")
        results.append(r)
        ok &= all(c["ok"] for c in r["checks"])
    json.dump({"thresholds": T, "results": results}, open(f"{OUT}/results.json", "w"), indent=2)
    summ = os.environ.get("GITHUB_STEP_SUMMARY")
    if summ:
        with open(summ, "a") as f:
            f.write("## Launch stability gate\n\n| scenario | check | result | measured | limit |\n|---|---|---|---|---|\n")
            for r in results:
                for c in r["checks"]:
                    f.write(f"| {r['scenario']} | {c['check']} | {'✅' if c['ok'] else '❌'} | {c['measured']} | {c['limit']} |\n")
    if not ok:
        print("::error::Launch stability gate failed — see table above / results.json")
        sys.exit(1)
    print("Launch stability gate passed.")


if __name__ == "__main__":
    main()
