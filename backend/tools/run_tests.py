#!/usr/bin/env python3
"""Run Forge backend unit tests without pytest installed.

Imports resolve against backend/app (same package Terraform deploys to Lambda).
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parents[1]
TESTS = BACKEND_ROOT / "tests"
APP_DIR = BACKEND_ROOT / "app"

TOOLS = BACKEND_ROOT / "tools"
sys.path[:0] = [str(APP_DIR), str(TESTS), str(TOOLS)]


def main() -> int:
    suite = unittest.defaultTestLoader.discover(str(TESTS), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())