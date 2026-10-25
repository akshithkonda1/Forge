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
IDLE_FRAMES = ("mach_msg2_trap", "mach_msg_trap", "mach_msg_overwrite")


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
def png_pixels(path, step=8):
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
    counts, i = {}, 0
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
    return counts


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


def main_thread_busy_s(pid, window, tag):
    path = f"{OUT}/sample-{tag}.txt"
    r = sh("sample", str(pid), str(int(window)), "1", "-mayDie", "-file", path,
           check=False, timeout=window + 60)
    if not os.path.exists(path):
        raise RuntimeError(f"sample produced no output (rc={r.returncode}): {r.stderr.strip()}")
    text = open(path).read()
    # Main thread block runs until the next top-level "Thread_" line.
    m = re.search(r"^\s*\d+ Thread_\d+.*?(?:com\.apple\.main-thread|Main Thread).*?$", text, re.M)
    if not m:
        raise RuntimeError("main thread not found in sample output")
    total = int(m.group(0).split()[0])
    rest = text[m.end():]
    nxt = re.search(r"^\s*\d+ Thread_\d+", rest, re.M)
    block = rest[:nxt.start()] if nxt else rest
    # Idle = leaf samples in the run loop's mach_msg wait. A leaf line is the
    # deepest frame; sum sample counts of lines naming an idle trap.
    idle = 0
    for line in block.splitlines():
        if any(f in line for f in IDLE_FRAMES) and "(in libsystem_kernel.dylib)" in line:
            mm = re.match(r"\s*[+!:| ]*(\d+)\s", line)
            if mm:
                idle += int(mm.group(1))
    busy_samples = max(0, total - idle)
    # ~1 sample per ms requested; normalise by observed total over the window.
    return busy_samples / total * window if total else window, total, idle


# ---------- scenario ----------
def fresh_install(udid, app):
    simctl("terminate", udid, BUNDLE, check=False)
    simctl("uninstall", udid, BUNDLE, check=False)
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

    pid, t0 = launch(udid)
    el = lambda: time.monotonic() - t0

    # first frame
    frame_at, share = None, None
    while el() < T["FIRST_FRAME_MAX_S"]:
        shot = f"{OUT}/{name}-frame.png"
        if simctl("io", udid, "screenshot", shot, check=False).returncode == 0:
            share = dominant_share(shot)
            if share < T["BLANK_DOMINANT_SHARE"]:
                frame_at = el(); break
        time.sleep(0.5)
    check("alive@first_frame", pid_alive(pid), f"pid {pid}", "alive")
    check("first_frame", frame_at is not None,
          f"{frame_at:.2f}s" if frame_at else f"blank/none after {el():.1f}s (dominant {share})",
          f"<= {T['FIRST_FRAME_MAX_S']}s non-blank")
    if not pid_alive(pid):
        return res

    early, src = footprint_mb(pid)
    worst = 0.0
    for w in range(int(T["SAMPLE_WINDOWS"])):
        if not pid_alive(pid):
            break
        busy, total, idle = main_thread_busy_s(pid, T["SAMPLE_WINDOW_S"], f"{name}-{w}")
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
