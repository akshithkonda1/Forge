"""Shared test helpers for the Forge Python backend under backend/api."""

from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
API_DIR = REPO_ROOT / "backend" / "api"
BACKEND_DIR = REPO_ROOT / "backend"


def ensure_api_on_path() -> Path:
    """Insert backend/api at the front of sys.path for Lambda module imports."""
    api_path = str(API_DIR)
    if api_path not in sys.path:
        sys.path.insert(0, api_path)
    return API_DIR


def ensure_backend_on_path() -> Path:
    """Insert backend/ for top-level backend utilities such as organize_users."""
    backend_path = str(BACKEND_DIR)
    if backend_path not in sys.path:
        sys.path.insert(0, backend_path)
    return BACKEND_DIR