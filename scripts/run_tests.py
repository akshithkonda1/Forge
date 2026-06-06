#!/usr/bin/env python3
"""Run Forge backend unit tests without pytest installed.

Imports resolve against backend/api (same package Terraform deploys to Lambda).
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TESTS = ROOT / "tests"
API_DIR = ROOT / "backend" / "api"

# Mirror Lambda's module layout before discovery imports test modules.
sys.path[:0] = [str(API_DIR), str(TESTS)]


def main() -> int:
    suite = unittest.defaultTestLoader.discover(str(TESTS), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    sys.exit(main())