from __future__ import annotations

from typing import Any

_CONNECTION_PRIVATE_FIELDS = frozenset(
    {
        "pk",
        "sk",
        "middleware",
        "terraUserId",
        "lastJobId",
        "lastSyncRequestedAt",
    }
)


def public_connection(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in _CONNECTION_PRIVATE_FIELDS}