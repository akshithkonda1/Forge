"""Stub storage for Rowan's editable-memory contract.

Iris holds existing privacy gates (partner/cycle chips, calendar titles) on
the chat ingest path until Rowan posts the contract. This module does **not**
implement view/edit/delete/off of memory facts, and CoachContextEngine does
not consult it.

Dummy / offline: ``offline_default()`` is in-process and enabled-on. Persistence
uses ``storage.dynamodb``, which is the local dict when ``APP_DATA_TABLE_NAME``
is unset. Bedrock stays off. Dummy must not import this on the speak path.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from storage import dynamodb, keys

# Named placeholders only. Rowan owns the real vocab; extra keys round-trip.
_KNOWN_SETTINGS_KEYS = frozenset({"enabled", "persona", "tone", "check_in"})


@dataclass
class CompanionMemorySettings:
    """Opaque settings bag awaiting Rowan.

    TODO(rowan): ``enabled`` — memory off contract (not wired into ingest/inject).
    TODO(rowan): ``persona`` — user-chosen companion persona.
    TODO(rowan): ``tone`` — user-chosen speaking tone.
    TODO(rowan): ``check_in`` — daily check-in preference.
    TODO(rowan): remaining contract fields persist in ``extra``.
    """

    enabled: bool = True
    persona: Any = None
    tone: Any = None
    check_in: Any = None
    extra: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "enabled": bool(self.enabled),
            "persona": self.persona,
            "tone": self.tone,
            "check_in": self.check_in,
        }
        for key, value in self.extra.items():
            if key not in _KNOWN_SETTINGS_KEYS:
                payload[key] = value
        return payload

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> CompanionMemorySettings:
        raw = dict(data or {})
        extra = {k: v for k, v in raw.items() if k not in _KNOWN_SETTINGS_KEYS}
        enabled = raw.get("enabled", True)
        if isinstance(enabled, str):
            enabled = enabled.strip().lower() not in {"0", "false", "off", "no"}
        return cls(
            enabled=bool(enabled),
            persona=raw.get("persona"),
            tone=raw.get("tone"),
            check_in=raw.get("check_in"),
            extra=extra,
        )


def offline_default() -> CompanionMemorySettings:
    """Dummy / simrunner / tests: in-process default. No Dynamo, no Bedrock."""
    return CompanionMemorySettings()


def get_settings(user_id: str) -> CompanionMemorySettings:
    """Read the stub row. Missing → default (no write on read)."""
    uid = (user_id or "").strip()
    if not uid:
        return offline_default()
    key = keys.aria_memory_settings_key(uid)
    item = dynamodb.get_item(key["pk"], key["sk"])
    if not item:
        return offline_default()
    payload = item.get("payload") if isinstance(item, dict) else None
    if not isinstance(payload, dict):
        payload = {k: v for k, v in (item or {}).items() if k not in ("pk", "sk")}
    return CompanionMemorySettings.from_dict(payload)


def put_settings(user_id: str, settings: CompanionMemorySettings) -> CompanionMemorySettings:
    uid = (user_id or "").strip()
    if not uid:
        return settings
    key = keys.aria_memory_settings_key(uid)
    dynamodb.put_item({**key, "payload": settings.to_dict(), "user_id": uid})
    return settings


def patch_settings(user_id: str, updates: dict[str, Any]) -> CompanionMemorySettings:
    """Merge unknown keys into ``extra`` so Rowan can land fields without a migration."""
    current = get_settings(user_id)
    if not isinstance(updates, dict):
        return put_settings(user_id, current)
    merged = current.to_dict()
    merged.update(updates)
    return put_settings(user_id, CompanionMemorySettings.from_dict(merged))
