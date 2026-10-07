"""Typed open loops: one path between vault Events and STM.

Vault Events is the durable note. STM is the same row with a TTL index
(``vault_id`` + ``folder=events``). Expiry / forget drops STM only.

Dummy-offline. Bedrock off. Writes go through ``sanitize_user_memory_text``
(inbound) plus phone / med-dose strips so those never land in either store.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Any

from aria_core import guidance
from aria_core import workout_suggestion
from services import editable_memory
from services.aria_context import CoachContextEngine, MemoryItem, _slug, _utcnow

EVENTS_FOLDER = "events"
OPEN_LOOP_CATEGORY = "open_loop"

_KIND_ALIASES = {
    "wedding": "wedding",
    "game": "game",
    "match": "game",
    "travel": "travel",
    "trip": "travel",
    "flight": "flight",
}

_KIND_RE = re.compile(
    r"\b(wedding|game|match|travel|trip|flight)\b",
    re.I,
)
_WEEKS_RE = re.compile(
    r"\b(?:in\s+)?(\d+|a|one|two|three|four|five|six|seven|eight|nine|ten)\s+weeks?\b",
    re.I,
)
_DAYS_RE = re.compile(
    r"\b(?:in\s+)?(\d+|a|one|two|three|four|five|six|seven|eight|nine|ten)\s+days?\b",
    re.I,
)
_PHONE_RE = re.compile(
    r"(?:\+?1[\s.\-]?)?\(?\d{3}\)?[\s.\-]\d{3}[\s.\-]\d{4}"
)
_EMAIL_RE = re.compile(r"[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}", re.I)
_DOSE_RE = guidance._DOSE_RE
_MED_NAME_RE = re.compile(
    r"(?i)\b(?:"
    r"ibuprofen|tylenol|aspirin|advil|acetaminophen|paracetamol|"
    r"insulin|xanax|adderall|zoloft|lexapro|prozac|vicodin|oxycodone|"
    r"meds?:|medication|medicine"
    r")\b"
)
_SPELLED = {
    "a": 1,
    "one": 1,
    "two": 2,
    "three": 3,
    "four": 4,
    "five": 5,
    "six": 6,
    "seven": 7,
    "eight": 8,
    "nine": 9,
    "ten": 10,
}
_VAULT_DUMP_RE = re.compile(
    r"(?i)\b(?:from (?:your )?(?:notes|memory|the vault)|in (?:your|the) vault|"
    r"stored (?:note|memory)|according to (?:your|the) notes)\b"
)


@dataclass(frozen=True)
class OpenLoop:
    """Kind + days-until. Same id in vault Events and STM."""

    id: str
    kind: str
    days_until: int
    text: str
    event_at: datetime
    folder: str = EVENTS_FOLDER
    vault_id: str = ""
    stm_active: bool = False
    source: str = "conversation"

    def __post_init__(self) -> None:
        if not self.vault_id:
            object.__setattr__(self, "vault_id", self.id)

    @property
    def speak(self) -> str:
        return coach_speak(self.kind, self.days_until)

    @property
    def horizon_tag(self) -> str:
        return f"calendar:horizon:{self.kind}:{self.days_until}"

    def to_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "kind": self.kind,
            "days_until": self.days_until,
            "text": self.text,
            "event_at": self.event_at.isoformat(),
            "folder": self.folder,
            "vault_id": self.vault_id or self.id,
            "stm_active": self.stm_active,
            "source": self.source,
            "speak": self.speak,
        }


def _as_number(raw: str) -> int | None:
    key = str(raw or "").strip().lower()
    if key in _SPELLED:
        return _SPELLED[key]
    try:
        return max(0, int(key))
    except ValueError:
        return None


def parse_days_until(text: str) -> int | None:
    lower = str(text or "").lower()
    if re.search(r"\b(?:today|tonight)\b", lower):
        return 0
    if re.search(r"\btomorrow\b", lower):
        return 1
    if re.search(r"\bin two weeks\b", lower) or re.search(r"\bin 2 weeks\b", lower):
        return 14
    weeks = _WEEKS_RE.search(lower)
    if weeks:
        n = _as_number(weeks.group(1))
        if n is not None:
            return max(1, n * 7)
    days = _DAYS_RE.search(lower)
    if days:
        n = _as_number(days.group(1))
        if n is not None:
            return max(0, n)
    return None


def parse_kind(text: str) -> str | None:
    match = _KIND_RE.search(str(text or ""))
    if not match:
        return None
    return _KIND_ALIASES.get(match.group(1).lower())


def typed_text(kind: str, days_until: int) -> str:
    label = "Trip" if kind == "travel" else kind.capitalize()
    if days_until <= 0:
        return f"{label} today"
    if days_until == 1:
        return f"{label} tomorrow"
    return f"{label} in {days_until} days"


def coach_speak(kind: str, days_until: int) -> str:
    if kind == "wedding":
        return workout_suggestion.wedding_plan(days_until).reason
    if kind == "game":
        return workout_suggestion.game_plan(days_until).reason
    if kind in {"travel", "flight"}:
        return workout_suggestion.travel_plan(kind, days_until).reason
    label = typed_text(kind, days_until)
    return f"{label} — train around that window."


def sanitize_open_loop_text(raw: str) -> str:
    """Inbound vault sanitizer, then drop phones / leftover emails / meds."""
    from routes.aria import sanitize_user_memory_text

    cleaned = sanitize_user_memory_text(str(raw or ""))
    if not cleaned:
        return ""
    cleaned = _EMAIL_RE.sub(" ", cleaned)
    cleaned = _PHONE_RE.sub(" ", cleaned)
    cleaned = _DOSE_RE.sub(" ", cleaned)
    cleaned = _MED_NAME_RE.sub(" ", cleaned)
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip(" ,;:—–-")
    if not cleaned:
        return ""
    if any(
        token.startswith(("partner_", "cycle:", "support_cycle:", "meds:"))
        for token in cleaned.lower().split()
    ):
        return ""
    return sanitize_user_memory_text(cleaned)


def parse_open_loop(raw: str, *, now: datetime | None = None) -> OpenLoop | None:
    now = now or _utcnow()
    cleaned = sanitize_open_loop_text(raw)
    if not cleaned:
        return None
    kind = parse_kind(cleaned)
    days = parse_days_until(cleaned)
    if kind is None or days is None:
        return None
    text = sanitize_open_loop_text(typed_text(kind, days))
    if not text:
        return None
    event_at = now + timedelta(days=days)
    loop_id = _slug(f"{OPEN_LOOP_CATEGORY}:{kind}:{event_at.date().isoformat()}")
    return OpenLoop(
        id=loop_id,
        kind=kind,
        days_until=days,
        text=text,
        event_at=event_at,
        vault_id=loop_id,
        stm_active=False,
        source="conversation",
    )


def _settings_allow_file(settings: editable_memory.CompanionMemorySettings | None) -> bool:
    row = settings if settings is not None else editable_memory.offline_default()
    if not editable_memory.auto_ingest_allowed(row):
        return False
    return EVENTS_FOLDER not in (row.disabled_folders or [])


def file_open_loop(
    engine: CoachContextEngine,
    user_id: str,
    raw: str,
    *,
    now: datetime | None = None,
    settings: editable_memory.CompanionMemorySettings | None = None,
    safety_lock: bool = False,
    source: str = "conversation",
) -> OpenLoop | None:
    """Write vault Events + STM together. Neither store on lock / remember-me off."""
    if safety_lock or not user_id:
        return None
    if not _settings_allow_file(settings):
        return None
    now = now or _utcnow()
    draft = parse_open_loop(raw, now=now)
    if draft is None:
        return None
    vault = engine.put_vault_note(
        user_id,
        EVENTS_FOLDER,
        {
            "id": draft.id,
            "kind": draft.kind,
            "days_until": draft.days_until,
            "text": draft.text,
            "source": source,
            "created_at": now.isoformat(),
            "event_at": draft.event_at.isoformat(),
            "folder": EVENTS_FOLDER,
        },
    )
    if not vault:
        return None
    stm = engine.remember_short_term(
        user_id,
        draft.text,
        source=source,
        category=OPEN_LOOP_CATEGORY,
        expires_at=draft.event_at + timedelta(days=1),
        event_at=draft.event_at,
        mem_id=draft.id,
        now=now,
        vault_id=draft.id,
        folder=EVENTS_FOLDER,
    )
    return OpenLoop(
        id=draft.id,
        kind=draft.kind,
        days_until=draft.days_until,
        text=draft.text,
        event_at=draft.event_at,
        vault_id=draft.id,
        stm_active=stm is not None and stm.is_active(now),
        source=source,
    )


def _loop_from_vault(
    note: dict[str, Any],
    stm: MemoryItem | None,
    *,
    now: datetime,
) -> OpenLoop | None:
    kind = str(note.get("kind") or parse_kind(str(note.get("text") or "")) or "").strip()
    if kind not in _KIND_ALIASES.values():
        return None
    try:
        days = int(note.get("days_until"))
    except (TypeError, ValueError):
        parsed = parse_days_until(str(note.get("text") or ""))
        if parsed is None:
            return None
        days = parsed
    event_at = _parse_event_at(note.get("event_at"), now, days)
    note_id = str(note.get("id") or "").strip()
    if not note_id:
        return None
    text = sanitize_open_loop_text(str(note.get("text") or typed_text(kind, days)))
    if not text:
        return None
    return OpenLoop(
        id=note_id,
        kind=kind,
        days_until=days,
        text=text,
        event_at=event_at,
        vault_id=str(note.get("id") or note_id),
        stm_active=stm is not None and stm.is_active(now),
        source=str(note.get("source") or "conversation"),
    )


def _parse_event_at(value: Any, now: datetime, days: int) -> datetime:
    if isinstance(value, datetime):
        return value if value.tzinfo else value.replace(tzinfo=timezone.utc)
    if isinstance(value, str) and value.strip():
        try:
            parsed = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
            return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    return now + timedelta(days=days)


def list_open_loops(
    engine: CoachContextEngine,
    user_id: str,
    *,
    now: datetime | None = None,
) -> list[OpenLoop]:
    """Read vault Events, attach STM activity. One path — not two stores."""
    now = now or _utcnow()
    notes = engine.vault_notes(user_id, EVENTS_FOLDER)
    stm_items = [
        item
        for item in engine.short_term_memories(user_id, now=now, include_expired=True)
        if item.category == OPEN_LOOP_CATEGORY or item.folder == EVENTS_FOLDER
    ]
    stm_by_id = {(item.vault_id or item.id): item for item in stm_items}
    loops: list[OpenLoop] = []
    seen: set[str] = set()
    for note in notes:
        loop = _loop_from_vault(note, stm_by_id.get(str(note.get("id") or "")), now=now)
        if loop is None or loop.id in seen:
            continue
        seen.add(loop.id)
        loops.append(loop)
    loops.sort(key=lambda row: (row.event_at, row.id))
    return loops


def scrub_vault_dump(speak: str) -> str:
    """Coach words only — drop raw vault-cite phrases from spoken text."""
    text = str(speak or "").strip()
    if not text:
        return ""
    return _VAULT_DUMP_RE.sub("", text).strip()
