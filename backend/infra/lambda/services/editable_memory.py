"""Storage hooks for user-editable companion memory.

Rowan owns the HTTP/API contract (view / edit / delete / off plus
persona / tone / check-in). This module persists the truth bag those
operations will call. It does not define routes or client UI.

Dummy / offline: ``offline_default()`` is in-process and enabled-on.
``get_settings`` / ``put_settings`` use ``storage.dynamodb``, which is the
local dict when ``APP_DATA_TABLE_NAME`` is unset — never a cloud SDK from
Dummy. Do not import this module from Dummy's speak path.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from services.memory_privacy import filter_lifestyle_tokens, redact_memory_text
from storage import dynamodb, keys

# Known settings keys Rowan has named. Everything else round-trips in ``extra``
# so a later contract field can land without a storage migration.
_KNOWN_SETTINGS_KEYS = frozenset({"enabled", "persona", "tone", "check_in"})


@dataclass
class CompanionMemorySettings:
    """User-facing memory controls.

    Field vocab below is a stub until Rowan lands the contract. ``enabled`` is
    the off switch (False = ARIA must not ingest or inject companion memory).
    ``persona``, ``tone``, and ``check_in`` are opaque passthroughs.
    """

    enabled: bool = True
    # TODO(rowan): persona — user-chosen companion persona id / name / blob.
    persona: Any = None
    # TODO(rowan): tone — user-chosen speaking tone preference.
    tone: Any = None
    # TODO(rowan): check_in — on/off/cadence for daily "anything new?" prompts.
    check_in: Any = None
    # TODO(rowan): remaining contract fields. Unknown keys persist here.
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
    """Dummy / simrunner / tests: enabled-on, no Dynamo, no Bedrock."""
    return CompanionMemorySettings()


def get_settings(user_id: str) -> CompanionMemorySettings:
    """View settings. Missing row → default enabled-on (no write on read)."""
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
    """Edit settings. Unknown keys land in ``extra`` for Rowan."""
    current = get_settings(user_id)
    if not isinstance(updates, dict):
        return put_settings(user_id, current)
    merged = current.to_dict()
    merged.update(updates)
    return put_settings(user_id, CompanionMemorySettings.from_dict(merged))


def delete_settings(user_id: str) -> CompanionMemorySettings:
    """Delete the settings row. Next read is the Dummy/offline default."""
    uid = (user_id or "").strip()
    if uid:
        key = keys.aria_memory_settings_key(uid)
        dynamodb.delete_item(key["pk"], key["sk"])
    return offline_default()


def set_enabled(user_id: str, enabled: bool) -> CompanionMemorySettings:
    """Off switch. Does not wipe stored facts — pair with ``clear_content``."""
    return patch_settings(user_id, {"enabled": bool(enabled)})


def is_enabled(user_id: str) -> bool:
    return get_settings(user_id).enabled


def _engine():
    from services.aria_context import CoachContextEngine

    return CoachContextEngine()


def view_editable_memory(user_id: str) -> dict[str, Any]:
    """Snapshot Rowan can serve for a GET-style view. Not an HTTP contract.

    Redacts partner/cycle chips. Calendar STM is already busy-window labels.
    """
    engine = _engine()
    ctx = engine.get_or_create_context(user_id)
    stm = [m.to_dict() for m in engine.short_term_memories(user_id)]
    return {
        "settings": get_settings(user_id).to_dict(),
        "life_facts": filter_lifestyle_tokens(list(ctx.life_facts)),
        "current_goals": filter_lifestyle_tokens(list(ctx.current_goals)),
        "constraints": filter_lifestyle_tokens(list(ctx.constraints)),
        "recent_patterns": filter_lifestyle_tokens(list(ctx.recent_patterns)),
        "last_insights": filter_lifestyle_tokens(list(ctx.last_insights)),
        "short_term": stm,
        # Read-only system bond. TODO(rowan): whether this is user-editable.
        "relationship_level": ctx.relationship_level,
    }


def edit_life_fact(user_id: str, old: str, new: str) -> dict[str, Any]:
    """Replace one long-term fact. User-initiated — works even when off."""
    engine = _engine()
    cleaned = redact_memory_text(new)
    engine.forget_life_fact(user_id, old)
    if cleaned:
        engine.record_life_fact(user_id, cleaned, force=True)
    return view_editable_memory(user_id)


def delete_life_fact(user_id: str, fact: str) -> dict[str, Any]:
    _engine().forget_life_fact(user_id, fact)
    return view_editable_memory(user_id)


def delete_short_term(user_id: str, mem_id: str) -> dict[str, Any]:
    _engine().forget_short_term(user_id, mem_id)
    return view_editable_memory(user_id)


def clear_content(user_id: str) -> dict[str, Any]:
    """Delete user-visible memory content. Keeps settings and relationship_level."""
    _engine().clear_user_memory(user_id)
    return view_editable_memory(user_id)


def delete_all(user_id: str) -> dict[str, Any]:
    """Full delete: content + settings row (back to Dummy/offline default)."""
    _engine().clear_user_memory(user_id)
    delete_settings(user_id)
    return view_editable_memory(user_id)
