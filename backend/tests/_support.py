"""Shared test helpers for the Forge Python backend."""

from __future__ import annotations

import os
import sys
from pathlib import Path

os.environ.setdefault("FORGE_ALLOW_SEED_FALLBACK", "true")

BACKEND_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = BACKEND_ROOT.parent
APP_DIR = BACKEND_ROOT / "app"
CLI_DIR = BACKEND_ROOT / "cli"


def ensure_api_on_path() -> Path:
    """Insert backend/app at the front of sys.path for Lambda module imports."""
    app_path = str(APP_DIR)
    if app_path not in sys.path:
        sys.path.insert(0, app_path)
    return APP_DIR


def ensure_backend_on_path() -> Path:
    """Insert backend/ for CLI utilities such as organize_users."""
    backend_path = str(BACKEND_ROOT)
    if backend_path not in sys.path:
        sys.path.insert(0, backend_path)
    return BACKEND_ROOT