"""Dummy-offline settings row for Rowan's locked editable-memory contract.

Stores ONLY:

- ``memory_enabled`` — Remember me. Off ≠ delete stored facts.
- ``disabled_folders`` — folder-off (scoped). Stable ids match iOS #307
  ``AriaKnowledgeCategory.managedCases``.
- ``persona_enabled`` — off ≠ clear the living persona.
- ``tone`` — check-in | space | patterns | honest peer
- ``check_in`` — off | weekly | daily

No live HTTP API. CoachContextEngine is not consulted. Auto-ingest must stop
when ``memory_enabled`` is false — see ``auto_ingest_allowed``; chat ingest is
not gated yet. Privacy stays on the existing sanitizer / iOS AriaFactPrivacy.

Dummy: ``offline_default()`` is in-process. Persistence uses ``storage.dynamodb``
(local dict when ``APP_DATA_TABLE_NAME`` is unset). Bedrock off.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from storage import dynamodb, keys

# iOS #307 AriaKnowledgeCategory.managedCases raw values.
# healthHistory is the Body notes / Health History vault folder.
MEMORY_FOLDERS: tuple[str, ...] = (
    "goals",
    "identity",
    "lifestyle",
    "preferences",
    "events",
    "healthHistory",
    "mood",
)

# Persist hyphenated contract strings; accept iOS #307 Codable raw values on input.
TONE_CHECK_IN = "check-in"
TONE_SPACE = "space"
TONE_PATTERNS = "patterns"
TONE_HONEST_PEER = "honest peer"
TONES: tuple[str, ...] = (
    TONE_CHECK_IN,
    TONE_SPACE,
    TONE_PATTERNS,
    TONE_HONEST_PEER,
)
_TONE_ALIASES = {
    "check-in": TONE_CHECK_IN,
    "checkin": TONE_CHECK_IN,
    "check_in": TONE_CHECK_IN,
    "checkIn": TONE_CHECK_IN,
    "space": TONE_SPACE,
    "patterns": TONE_PATTERNS,
    "honest peer": TONE_HONEST_PEER,
    "honest_peer": TONE_HONEST_PEER,
    "honestpeer": TONE_HONEST_PEER,
    "peer": TONE_HONEST_PEER,  # iOS AriaCompanionTone.peer
}

CHECK_IN_OFF = "off"
CHECK_IN_WEEKLY = "weekly"
CHECK_IN_DAILY = "daily"
CHECK_INS: tuple[str, ...] = (CHECK_IN_OFF, CHECK_IN_WEEKLY, CHECK_IN_DAILY)

_FOLDER_ALIASES = {
    "goals": "goals",
    "identity": "identity",
    "lifestyle": "lifestyle",
    "preferences": "preferences",
    "events": "events",
    "healthhistory": "healthHistory",
    "health_history": "healthHistory",
    "health-history": "healthHistory",
    "bodynotes": "healthHistory",
    "body_notes": "healthHistory",
    "body-notes": "healthHistory",
    "mood": "mood",
}

_PAYLOAD_KEYS = (
    "memory_enabled",
    "disabled_folders",
    "persona_enabled",
    "tone",
    "check_in",
)


def _as_bool(value: Any, default: bool) -> bool:
    if value is None:
        return default
    if isinstance(value, str):
        return value.strip().lower() not in {"0", "false", "off", "no"}
    return bool(value)


def _normalize_tone(value: Any) -> str:
    if value is None:
        return TONE_CHECK_IN
    key = str(value).strip()
    mapped = _TONE_ALIASES.get(key) or _TONE_ALIASES.get(key.lower().replace(" ", ""))
    if mapped:
        return mapped
    lowered = key.lower()
    return _TONE_ALIASES.get(lowered, TONE_CHECK_IN)


def _normalize_check_in(value: Any) -> str:
    if value is None:
        return CHECK_IN_WEEKLY
    key = str(value).strip().lower().replace("-", "_")
    if key in {"checkincadence", "check_in_cadence"}:
        return CHECK_IN_WEEKLY
    if key in CHECK_INS:
        return key
    return CHECK_IN_WEEKLY


def _normalize_folders(value: Any) -> list[str]:
    if not isinstance(value, list):
        return []
    seen: set[str] = set()
    out: list[str] = []
    for item in value:
        raw = str(item or "").strip()
        if not raw:
            continue
        key = raw.replace(" ", "").replace("-", "_").lower()
        folder = _FOLDER_ALIASES.get(key) or _FOLDER_ALIASES.get(raw)
        if folder is None and raw in MEMORY_FOLDERS:
            folder = raw
        if folder is None or folder not in MEMORY_FOLDERS or folder in seen:
            continue
        seen.add(folder)
        out.append(folder)
    return [fid for fid in MEMORY_FOLDERS if fid in seen]


@dataclass
class CompanionMemorySettings:
    """Locked contract. Off switches do not delete stored facts or persona."""

    memory_enabled: bool = True
    disabled_folders: list[str] = field(default_factory=list)
    persona_enabled: bool = True
    tone: str = TONE_CHECK_IN
    check_in: str = CHECK_IN_WEEKLY

    def to_dict(self) -> dict[str, Any]:
        return {
            "memory_enabled": bool(self.memory_enabled),
            "disabled_folders": list(self.disabled_folders),
            "persona_enabled": bool(self.persona_enabled),
            "tone": self.tone,
            "check_in": self.check_in,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any] | None) -> CompanionMemorySettings:
        raw = dict(data or {})
        # iOS #307 camelCase aliases on read only — persist snake_case.
        memory_enabled = raw.get("memory_enabled", raw.get("memoryEnabled", True))
        persona_enabled = raw.get("persona_enabled", raw.get("personaEnabled", True))
        folders = raw.get("disabled_folders", raw.get("disabledCategories"))
        tone = raw.get("tone")
        check_in = raw.get("check_in", raw.get("checkInCadence"))
        return cls(
            memory_enabled=_as_bool(memory_enabled, True),
            disabled_folders=_normalize_folders(folders),
            persona_enabled=_as_bool(persona_enabled, True),
            tone=_normalize_tone(tone),
            check_in=_normalize_check_in(check_in),
        )


def offline_default() -> CompanionMemorySettings:
    """Dummy / tests: Remember me on, all folders on, check-in weekly. No Dynamo."""
    return CompanionMemorySettings()


def auto_ingest_allowed(settings: CompanionMemorySettings | None = None) -> bool:
    """True when automatic ingest/inject may run.

    When False, calendar ingest, daily evaluate, and prompt injection must stop.
    Stored facts stay (off ≠ delete). Not wired into CoachContextEngine yet.
    """
    row = settings if settings is not None else offline_default()
    return bool(row.memory_enabled)


def get_settings(user_id: str) -> CompanionMemorySettings:
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
    """Replace known contract fields only. Unknown keys are dropped."""
    current = get_settings(user_id).to_dict()
    if not isinstance(updates, dict):
        return put_settings(user_id, CompanionMemorySettings.from_dict(current))
    allowed = {k: v for k, v in updates.items() if k in _PAYLOAD_KEYS}
    # Accept iOS #307 names on write, persist snake_case.
    if "memoryEnabled" in updates and "memory_enabled" not in allowed:
        allowed["memory_enabled"] = updates["memoryEnabled"]
    if "personaEnabled" in updates and "persona_enabled" not in allowed:
        allowed["persona_enabled"] = updates["personaEnabled"]
    if "disabledCategories" in updates and "disabled_folders" not in allowed:
        allowed["disabled_folders"] = updates["disabledCategories"]
    if "checkInCadence" in updates and "check_in" not in allowed:
        allowed["check_in"] = updates["checkInCadence"]
    current.update(allowed)
    return put_settings(user_id, CompanionMemorySettings.from_dict(current))
