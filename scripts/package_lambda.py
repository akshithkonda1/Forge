#!/usr/bin/env python3
"""Package backend/api into a Lambda zip (same layout Terraform uses)."""

from __future__ import annotations

import argparse
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
API_DIR = ROOT / "backend" / "api"
DEFAULT_OUTPUT = ROOT / "terraform" / "build" / "forge-backend.zip"

SKIP_DIRS = {"__pycache__", ".pytest_cache", ".mypy_cache"}
SKIP_SUFFIXES = {".pyc", ".pyo"}


def package_api(source_dir: Path, output_path: Path) -> int:
    if not source_dir.is_dir():
        print(f"error: backend package not found at {source_dir}", file=sys.stderr)
        return 1

    output_path.parent.mkdir(parents=True, exist_ok=True)
    files = [
        path
        for path in source_dir.rglob("*")
        if path.is_file()
        and path.suffix not in SKIP_SUFFIXES
        and not any(part in SKIP_DIRS for part in path.parts)
    ]

    with zipfile.ZipFile(output_path, "w", compression=zipfile.ZIP_DEFLATED) as archive:
        for path in sorted(files):
            archive.write(path, arcname=path.relative_to(source_dir).as_posix())

    print(f"Packaged {len(files)} files from {source_dir}")
    print(f"Wrote {output_path}")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--source",
        type=Path,
        default=API_DIR,
        help="Lambda source directory (default: backend/api)",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help="Zip output path (default: terraform/build/forge-backend.zip)",
    )
    args = parser.parse_args()
    return package_api(args.source.resolve(), args.output.resolve())


if __name__ == "__main__":
    sys.exit(main())