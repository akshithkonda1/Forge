#!/usr/bin/env python3
"""Timed simctl for Forge.

CoreSimulatorService can block `xcrun simctl` forever. Every Forge script that
talks to Simulator must go through here so Xcode post-actions and resets
cannot hang the machine.
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time

DEFAULT_TIMEOUT = 15.0
UNWEDGE_WAIT_SEC = 2.0
CORESIM_PROCESS = "com.apple.CoreSimulator.CoreSimulatorService"


class SimctlTimeout(RuntimeError):
    pass


def simctl(
    *args: str,
    timeout: float = DEFAULT_TIMEOUT,
    check: bool = False,
) -> subprocess.CompletedProcess[str]:
    cmd = ["xcrun", "simctl", *args]
    try:
        result = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired as exc:
        raise SimctlTimeout(
            f"simctl {' '.join(args)} timed out after {timeout:.0f}s "
            "(CoreSimulator is often wedged — reset-simulator.sh --unwedge)"
        ) from exc
    if check and result.returncode != 0:
        err = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(err or f"simctl {' '.join(args)} failed ({result.returncode})")
    return result


def unwedge() -> None:
    """Kill the stuck CoreSimulator service. It relaunches on the next simctl."""
    subprocess.run(
        ["killall", "-9", CORESIM_PROCESS],
        capture_output=True,
        text=True,
        timeout=5,
    )
    time.sleep(UNWEDGE_WAIT_SEC)


def erase(udid: str, *, timeout: float = 45.0, unwedge_on_timeout: bool = True) -> None:
    """Shutdown (best-effort) then erase. Retry once after unwedge if hung."""
    try:
        simctl("shutdown", udid, timeout=min(timeout, 20.0))
    except SimctlTimeout:
        if unwedge_on_timeout:
            unwedge()
        else:
            raise
    except RuntimeError:
        pass

    try:
        simctl("erase", udid, timeout=timeout, check=True)
        return
    except SimctlTimeout:
        if not unwedge_on_timeout:
            raise
        unwedge()
        simctl("erase", udid, timeout=timeout, check=True)


def list_booted(*, runtime_substr: str | None = None, timeout: float = 12.0) -> list[dict]:
    import json

    raw = simctl("list", "devices", "booted", "-j", timeout=timeout, check=True)
    data = json.loads(raw.stdout or "{}")
    found: list[dict] = []
    needle = (runtime_substr or "").lower()
    for runtime, devices in data.get("devices", {}).items():
        if needle and needle not in runtime.lower():
            continue
        for device in devices:
            if device.get("state") == "Booted":
                row = dict(device)
                row["runtime"] = runtime
                found.append(row)
    return found


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Timed simctl for Forge Simulator work")
    parser.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    sub = parser.add_subparsers(dest="cmd", required=True)

    erase_p = sub.add_parser("erase", help="shutdown + erase a simulator")
    erase_p.add_argument("udid")
    erase_p.add_argument("--no-unwedge", action="store_true")

    sub.add_parser("unwedge", help="kill wedged CoreSimulatorService")

    boot_p = sub.add_parser("booted", help="list booted devices (JSON lines)")
    boot_p.add_argument("--runtime", default="")

    args = parser.parse_args(argv)
    try:
        if args.cmd == "erase":
            erase(args.udid, timeout=max(args.timeout, 45.0), unwedge_on_timeout=not args.no_unwedge)
            print(f"erased {args.udid}")
            return 0
        if args.cmd == "unwedge":
            unwedge()
            print("CoreSimulatorService restarted")
            return 0
        if args.cmd == "booted":
            import json
            print(json.dumps(list_booted(runtime_substr=args.runtime or None, timeout=args.timeout)))
            return 0
    except SimctlTimeout as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 124
    except Exception as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 1
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
