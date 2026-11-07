"""Live AWS stays off until an explicit TODO(aws) config is set.

Unset fails closed. Tests inject fakes. CI never sets this. Do not put
credentials here.
"""

from __future__ import annotations

import os

# TODO(aws): live AWS. Unset — no boto3 call, no credentials.
_ENV_KEYS = ("TODO_AWS", "TODO(aws)")


def aws_enabled() -> bool:
    for key in _ENV_KEYS:
        if (os.getenv(key) or "").strip():
            return True
    return False
