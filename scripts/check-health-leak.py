#!/usr/bin/env python3
"""Standing health-leak gate: static scan, canary tests, local store scan.

Watches for health data being sent to or stored on Forge servers.
Destroy stays dry-run unless FORGE_HEALTH_LEAK_APPLY=1 (Akshith has
not said go). Never touches live AWS from this script.

Exit 1 on any finding so a `needs:` job fails the pipeline.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

CLIENT_SEND = [
    (ROOT / "ForgeSwift/ForgeSwift/Services/BiometricsObserveService.swift", r"/ai/observe"),
    (ROOT / "ForgeSwift/ForgeSwift/Services/ForgeCloudSync.swift", r"health/batch"),
    (ROOT / "ForgeSwift/ForgeSwift/ARIACoachService.swift", r"image_base64"),
    (ROOT / "ForgeSwift/ForgeWatch/Managers/ARIAWatchService.swift", r"heartRateSettleBPM"),
]

# These files may mention the paths only as comments or rejectors.
CLIENT_ALLOW_MENTION = {
    ROOT / "ForgeSwift/ForgeSwift/Services/BiometricsObserveService.swift": re.compile(
        r"backfill to `/ai/observe`|That path is gone"
    ),
}

PERSIST_PATTERNS = [
    (
        ROOT / "backend/infra/lambda/routes/health.py",
        re.compile(r"put_item\(|METRIC#"),
        "health batch must not write METRIC#",
    ),
    (
        ROOT / "backend/infra/lambda/routes/biometrics.py",
        re.compile(r"persist\s*=\s*True|save_body_snapshot"),
        "observe must not persist a body snapshot",
    ),
]


def read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def strip_comments_swift(text: str) -> str:
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def fail(message: str) -> None:
    print(f"health-leak: {message}", file=sys.stderr)
    raise SystemExit(1)


def scan_client() -> None:
    for path, needle in CLIENT_SEND:
        raw = read(path)
        code = strip_comments_swift(raw)
        if needle == "/ai/observe" and "/ai/observe" in code:
            fail(f"{path}: still posts /ai/observe")
        if needle == "health/batch" and re.search(r'["\']health/batch["\']', code):
            fail(f"{path}: still posts /health/batch")
        if needle == "image_base64" and "image_base64" in code:
            fail(f"{path}: still sends image_base64")
        if needle == "heartRateSettleBPM":
            # Allowed as a discarded parameter; must not be encoded.
            if re.search(r"heartRateSettleBPM\s*:", code) and "encode" in code.lower():
                if "DebriefRequest" in code and "heartRate" in strip_comments_swift(
                    code.split("struct DebriefRequest")[-1].split("}")[0]
                ):
                    fail(f"{path}: Watch debrief still encodes heart rate")


def scan_persist() -> None:
    health = read(ROOT / "backend/infra/lambda/routes/health.py")
    if "put_item" in health:
        fail("routes/health.py still calls put_item")
    bio = read(ROOT / "backend/infra/lambda/routes/biometrics.py")
    if re.search(r"persist\s*=\s*True", bio):
        fail("routes/biometrics.py still persist=True")
    if "save_body_snapshot" in bio:
        fail("routes/biometrics.py still saves a body snapshot")
    form = read(ROOT / "backend/infra/lambda/routes/form_check.py")
    if "generate_coach_vision" in form or "image_bytes" in form:
        fail("form_check still forwards a frame to a model")
    cycle = read(ROOT / "backend/infra/lambda/routes/cycle.py")
    if 'application/pdf' in cycle and "octet-stream" not in cycle:
        fail("cycle report still mints a plaintext PDF content type")


def run_canary_tests() -> None:
    env = os.environ.copy()
    env.setdefault("FORGE_HEALTH_LEAK_DESTROY", "0")
    env.setdefault("FORGE_HEALTH_LEAK_APPLY", "0")
    env.setdefault("FORGE_HEALTH_LEAK_QUARANTINE", "0")
    proc = subprocess.run(
        [
            sys.executable,
            "-m",
            "unittest",
            "test_health_leak_gate",
            "test_health_never_persisted",
            "-v",
        ],
        cwd=ROOT / "backend/tests",
        env=env,
    )
    if proc.returncode != 0:
        fail("canary / leak-gate unit tests failed")


def scan_stores() -> None:
    sys.path.insert(0, str(ROOT))
    from backend._paths import ensure_lambda_on_path

    ensure_lambda_on_path()
    from storage import dynamodb
    from services import health_leak_guard

    dynamodb.clear_local_store()
    reports = health_leak_guard.scan_local_store()
    if reports:
        fail(f"local store still held health after a clean scan: {reports}")
    if health_leak_guard.writes_blocked():
        fail("quarantine block is set; deploy/update refused")


def deploy_gate() -> None:
    sys.path.insert(0, str(ROOT))
    from backend._paths import ensure_lambda_on_path

    ensure_lambda_on_path()
    from services import health_leak_guard

    health_leak_guard.deploy_gate()


def main(argv: list[str]) -> int:
    mode = argv[1] if len(argv) > 1 else "all"
    if mode in {"all", "static"}:
        scan_client()
        scan_persist()
        print("health-leak: static scan clean")
    if mode in {"all", "tests"}:
        run_canary_tests()
        print("health-leak: canary tests clean")
    if mode in {"all", "stores"}:
        scan_stores()
        print("health-leak: local store scan clean")
    if mode in {"all", "deploy"}:
        deploy_gate()
        print("health-leak: deploy gate clear")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main(sys.argv))
    except SystemExit:
        raise
    except Exception as exc:  # noqa: BLE001
        fail(str(exc))
