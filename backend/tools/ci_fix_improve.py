#!/usr/bin/env python3
"""Phase 2 of the deploy chain — validate, package, and improve artifacts before deploy."""

from __future__ import annotations

import compileall
import subprocess
import sys
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
BACKEND_ROOT = REPO_ROOT / "backend"
APP_DIR = BACKEND_ROOT / "app"
TF_DIR = REPO_ROOT / "terraform"
ZIP_PATH = TF_DIR / "build" / "forge-backend.zip"
PACKAGE_SCRIPT = BACKEND_ROOT / "tools" / "package_lambda.py"


def run(command: list[str], *, cwd: Path | None = None) -> None:
    print(f"+ {' '.join(command)}")
    subprocess.run(command, cwd=cwd or REPO_ROOT, check=True)


def check(label: str, ok: bool, detail: str = "") -> None:
    status = "PASS" if ok else "FAIL"
    suffix = f" — {detail}" if detail else ""
    print(f"[{status}] {label}{suffix}")
    if not ok:
        raise SystemExit(1)


def main() -> int:
    print("Phase 2: Fix / Improve\n")

    if not APP_DIR.is_dir():
        check("backend/app exists", False, str(APP_DIR))
    check("backend/app exists", True)

    if not compileall.compile_dir(str(APP_DIR), quiet=1):
        check("Python compileall", False, "syntax errors in backend/app")
    check("Python compileall", True)

    run([sys.executable, str(PACKAGE_SCRIPT)])

    if not ZIP_PATH.is_file():
        check("Lambda zip created", False, str(ZIP_PATH))
    check("Lambda zip created", True, str(ZIP_PATH))

    with zipfile.ZipFile(ZIP_PATH) as archive:
        names = set(archive.namelist())
        for required in ("handler.py", "core/auth.py", "routes/__init__.py"):
            check(f"zip contains {required}", required in names)

    fmt = subprocess.run(
        ["terraform", "fmt", "-check", "-recursive", "-no-color"],
        cwd=TF_DIR,
        capture_output=True,
        text=True,
    )
    if fmt.returncode != 0:
        print(fmt.stdout)
        print(fmt.stderr, file=sys.stderr)
        check("terraform fmt", False, "run 'terraform fmt -recursive' in terraform")
    check("terraform fmt", True)

    init = subprocess.run(
        [
            "terraform",
            "init",
            "-backend=false",
            "-input=false",
            "-lockfile=readonly",
            "-no-color",
        ],
        cwd=TF_DIR,
        capture_output=True,
        text=True,
    )
    if init.returncode != 0:
        print(init.stderr, file=sys.stderr)
        check("terraform init", False)
    check("terraform init", True)

    validate = subprocess.run(
        ["terraform", "validate", "-no-color"],
        cwd=TF_DIR,
        capture_output=True,
        text=True,
    )
    if validate.returncode != 0:
        print(validate.stderr, file=sys.stderr)
        check("terraform validate", False)
    check("terraform validate", True)

    print("\nPhase 2 complete — artifacts ready for deploy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())