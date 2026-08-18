"""Single place every Python entrypoint finds the Lambda package.

iOS and Android share this backend. Do not invent a second tree.
"""

from __future__ import annotations

import sys
from pathlib import Path

BACKEND_ROOT = Path(__file__).resolve().parent
REPO_ROOT = BACKEND_ROOT.parent
LAMBDA_DIR = BACKEND_ROOT / "infra" / "lambda"
INFRA_DIR = BACKEND_ROOT / "infra"


def ensure_lambda_on_path() -> Path:
    path = str(LAMBDA_DIR)
    if path not in sys.path:
        sys.path.insert(0, path)
    return LAMBDA_DIR
