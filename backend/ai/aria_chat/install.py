"""Per-install pseudonym for Dummy chat keys and logs.

Never derived from a real uid. Generated once, stored in the local chat
config dir, reused so replay can recompute ``turn_seed`` / ``phrase_key``.
"""

from __future__ import annotations

import json
import os
import uuid
from pathlib import Path

from backend._paths import REPO_ROOT


def default_config_dir() -> Path:
    env = (os.getenv("ARIA_CHAT_CONFIG_DIR") or os.getenv("ARIA_CHAT_LOG_DIR") or "").strip()
    if env:
        return Path(env).expanduser()
    home = Path.home() / ".forge" / "aria_chat"
    if home.parent.exists() or os.getenv("HOME"):
        return home
    return REPO_ROOT / "backend" / "ai" / "chat_sessions"


def install_path(config_dir: Path | None = None) -> Path:
    directory = Path(config_dir) if config_dir is not None else default_config_dir()
    directory.mkdir(parents=True, exist_ok=True)
    return directory / "install.json"


def load_or_create_pseudonym(config_dir: Path | None = None) -> str:
    """Random per-install id. Not a user id and not hashed from one."""
    path = install_path(config_dir)
    if path.is_file():
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            data = {}
        existing = str((data or {}).get("pseudonym") or "").strip()
        if existing:
            return existing
    pseudonym = f"inst-{uuid.uuid4().hex}"
    path.write_text(
        json.dumps({"pseudonym": pseudonym}, indent=2) + "\n",
        encoding="utf-8",
    )
    return pseudonym
