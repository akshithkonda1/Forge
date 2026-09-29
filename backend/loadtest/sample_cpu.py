#!/usr/bin/env python3
"""Sample host and Dummy-process CPU while a loadtest scenario runs.

Writes JSONL samples to --out, then a summary JSON on SIGTERM/SIGINT or
when the watched pid exits.
"""

from __future__ import annotations

import argparse
import json
import os
import signal
import time
from pathlib import Path


def _cpu_times() -> tuple[int, int]:
    parts = Path("/proc/stat").read_text(encoding="utf-8").splitlines()[0].split()
    nums = [int(x) for x in parts[1:]]
    idle = nums[3] + (nums[4] if len(nums) > 4 else 0)
    return idle, sum(nums)


def _proc_jiffies(pid: int) -> int | None:
    try:
        parts = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8").split()
        return int(parts[13]) + int(parts[14])
    except (FileNotFoundError, IndexError, ValueError, OSError):
        return None


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--summary", required=True)
    parser.add_argument("--interval", type=float, default=1.0)
    args = parser.parse_args()

    samples: list[dict] = []
    stop = False

    def _stop(_signum, _frame):
        nonlocal stop
        stop = True

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    clk = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
    prev_idle, prev_total = _cpu_times()
    prev_proc = _proc_jiffies(args.pid)
    prev_t = time.time()
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    with out_path.open("w", encoding="utf-8") as handle:
        while not stop:
            time.sleep(args.interval)
            now = time.time()
            idle, total = _cpu_times()
            proc = _proc_jiffies(args.pid)
            dt = max(now - prev_t, 1e-6)
            d_total = max(total - prev_total, 1)
            d_idle = max(idle - prev_idle, 0)
            host_pct = max(0.0, min(100.0, (1.0 - d_idle / d_total) * 100.0))
            proc_pct = None
            if proc is not None and prev_proc is not None:
                proc_pct = max(0.0, ((proc - prev_proc) / clk) / dt * 100.0)
            row = {
                "t": now,
                "host_cpu_pct": host_pct,
                "backend_cpu_pct": proc_pct,
                "backend_alive": proc is not None,
            }
            samples.append(row)
            handle.write(json.dumps(row) + "\n")
            handle.flush()
            prev_idle, prev_total, prev_proc, prev_t = idle, total, proc, now
            if proc is None:
                break

    host = [s["host_cpu_pct"] for s in samples]
    proc_vals = [s["backend_cpu_pct"] for s in samples if s["backend_cpu_pct"] is not None]
    summary = {
        "samples": len(samples),
        "interval_seconds": args.interval,
        "backend_pid": args.pid,
        "host_cpu_pct": {
            "avg": (sum(host) / len(host)) if host else None,
            "max": max(host) if host else None,
            "min": min(host) if host else None,
        },
        "backend_cpu_pct": {
            "avg": (sum(proc_vals) / len(proc_vals)) if proc_vals else None,
            "max": max(proc_vals) if proc_vals else None,
            "min": min(proc_vals) if proc_vals else None,
            "note": "percent of one CPU (100 = one core fully used)",
        },
    }
    Path(args.summary).write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
