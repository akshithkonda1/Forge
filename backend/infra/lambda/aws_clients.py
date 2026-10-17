"""Shared botocore client configuration for Lambda AWS SDK calls.

Connect and read timeouts plus a small retry budget are chosen so a hung AWS
call cannot eat the whole 15s Lambda timeout. Voice credential loaders
(ElevenLabs / Fish Audio in ``provider_secrets``) keep their own clients.
"""

from __future__ import annotations

from typing import Any

CONNECT_TIMEOUT_SECONDS = 2
READ_TIMEOUT_SECONDS = 5
MAX_ATTEMPTS = 3


def client_config(
    *,
    connect_timeout: float = CONNECT_TIMEOUT_SECONDS,
    read_timeout: float = READ_TIMEOUT_SECONDS,
    retries: dict[str, Any] | None = None,
):
    """Return a ``botocore.config.Config`` for boto3 clients and resources."""
    from botocore.config import Config

    return Config(
        connect_timeout=connect_timeout,
        read_timeout=read_timeout,
        retries=retries if retries is not None else {"mode": "standard", "max_attempts": MAX_ATTEMPTS},
    )
