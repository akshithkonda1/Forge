"""Hobby Fit v1 — mentality speak + a small hobbies list.

Hung off the existing hobby path (social band, people-energy, working
tendency). The stable coach_context field is the enum. Speech, prompt
blocks, vault notes, and recentPatterns use the speak phrase only.

Lifestyle coach. Not a diagnosis. A dismissal never becomes copy.
"""

from __future__ import annotations

import re
from typing import Any

from . import hobby_path as hp
from . import user_working_model as uwm

QUIET = "quiet"
OPEN = "open"
DRAINED_SOCIAL = "drained_social"
RESTORED = "restored"
SIGNALS = (QUIET, OPEN, DRAINED_SOCIAL, RESTORED)

SPEAK = {
    QUIET: "quiet stretch",
    OPEN: "up for a little more",
    DRAINED_SOCIAL: "lots on lately",
    RESTORED: "a calmer patch",
}

KINDS = ("creative", "social", "outdoor", "solo", "learning")
INTERESTS = ("low", "medium", "high")

_LIVING = {
    "cooking": ("creative", "medium", "Cooking"),
    "making": ("creative", "medium", "Making things"),
    "music": ("creative", "medium", "Music"),
    "outdoors": ("outdoor", "medium", "Being outside"),
    "reading": ("solo", "medium", "Reading"),
    "rest": ("solo", "low", "Resting at home"),
    "games": ("solo", "medium", "Games"),
    "gym": ("solo", "medium", "The gym"),
}

_QUIET_LINE = (
    "It's been a quieter stretch. Want to try something low-key with one "
    "other person this week, or keep it solo for now? Both count."
)
_CURIOUS_LINE = (
    "Quiet stretch lately, and honestly it suits you. If you get curious, "
    "pottery nights tend to be small, and nobody judges a lumpy bowl. "
    "No pressure either way."
)
_DRAINED_LINE = (
    "Lots on lately. Something solo might hit better tonight, like cooking "
    "just for you, a good book or a headphones walk."
)
_SKIP_GROUPS_LINE = (
    "You've had a lot on. Want me to skip group stuff for now and pick "
    "one quiet thing for tonight?"
)
_OPEN_LINE = (
    "Up for a little more, if you want it. A small plan with one person "
    "counts — so does keeping it light."
)
_RESTORED_LINE = (
    "A calmer patch. Keep the free-day you already like, or leave the "
    "calendar alone. Both count."
)

_BAD_LABEL = re.compile(r"(@|https?://|\d)")
_DATE = re.compile(r"^\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}(?::\d{2})?Z?)?$")
_SAFE_ID = re.compile(r"^[a-z0-9_]{1,32}$")
_MEMORY_TOKEN = re.compile(
    r"(?i)^(?:mentality(?:_signal)?|hobby_row):"
)
_DENIED = re.compile(
    r"(?i)^(?:partner_|support_cycle:|partner_name:|partner_phase:|"
    r"partner_day:|partner_cycle:|cycle:)"
)
_BANNED_SPEECH = (
    "introvert",
    "isolated",
    "anxious",
    "feeling steadier",
    "social tank",
    "restorative",
    "energy's higher",
    "energys higher",
    "drained_social",
    "mentality_signal",
)


def mentality_signal(
    social_band: str,
    people_energy: str,
    working: uwm.Snapshot,
) -> str:
    """Map the hobby path already computed. Does not invent a second model."""
    if social_band == hp.BURNED_OUT:
        return DRAINED_SOCIAL
    if social_band == hp.RESERVED:
        return QUIET
    if working.tendency == uwm.REBUILDING or working.stance == uwm.REBUILD_TRUST:
        return RESTORED
    if people_energy == hp.OPEN or social_band == hp.SOCIABLE:
        return OPEN
    if people_energy == hp.THIN and (
        working.predicted_feel == uwm.FLAT
        or working.tendency in (uwm.OVERREACHER, uwm.WEEKEND_DROP)
    ):
        return DRAINED_SOCIAL
    if people_energy == hp.THIN:
        return QUIET
    return RESTORED


def speak(signal: str) -> str:
    return SPEAK.get(signal, SPEAK[RESTORED])


def speech_is_clean(text: str) -> bool:
    lower = str(text or "").lower()
    if any(needle in lower for needle in _BANNED_SPEECH):
        return False
    if re.search(r"\brestored\b", lower):
        return False
    return True


def canon_line(signal: str, *, curious: bool = False, skip_groups: bool = False) -> str:
    if signal == DRAINED_SOCIAL and skip_groups:
        return _SKIP_GROUPS_LINE
    if signal == QUIET and curious:
        return _CURIOUS_LINE
    if signal == QUIET:
        return _QUIET_LINE
    if signal == DRAINED_SOCIAL:
        return _DRAINED_LINE
    if signal == OPEN:
        return _OPEN_LINE
    return _RESTORED_LINE


def cool_down_line(label: str) -> str:
    """Only after a cool-down. A dismissal must call ``on_dismissal`` instead."""
    clean = sanitize_label(label)
    if not clean:
        return ""
    if clean.lower() == "hike club":
        return (
            "Hike club's still around if you ever want another look. "
            "It's not going anywhere."
        )
    return (
        f"{clean}'s still around if you ever want another look. "
        "It's not going anywhere."
    )


def on_dismissal(_label: str = "") -> str:
    """A dismissal never counts against the user and is never cited."""
    return ""


def blocked_memory_token(token: str) -> bool:
    """Enum rows stay out of recentPatterns, vault, and memory blocks."""
    return bool(_MEMORY_TOKEN.match(str(token or "").strip()))


def sanitize_label(raw: str) -> str:
    text = " ".join(str(raw or "").split())
    if not text or _BAD_LABEL.search(text):
        return ""
    kept = [tok for tok in text.split() if not _DENIED.match(tok)]
    text = " ".join(kept).strip()
    if len(text) > 48:
        text = text[:48].rstrip()
    if not text or _BAD_LABEL.search(text):
        return ""
    return text


def _slug(label: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "_", label.lower()).strip("_")
    return slug[:32]


def _kind_for(label: str, hinted: str | None) -> str:
    if hinted in KINDS:
        return hinted
    lower = label.lower()
    if any(word in lower for word in ("hike", "trail", "outdoor", "outside", "walk")):
        return "outdoor"
    if any(word in lower for word in ("class", "course", "learn", "study", "language")):
        return "learning"
    if any(word in lower for word in ("club", "group", "team", "friends")):
        return "social"
    if any(word in lower for word in ("read", "book", "solo", "alone", "home")):
        return "solo"
    return "creative"


def _interest(raw: Any) -> str:
    key = str(raw or "").strip().lower()
    return key if key in INTERESTS else "medium"


def _engaged(raw: Any) -> str | None:
    text = str(raw or "").strip()
    if text and _DATE.match(text):
        return text
    return None


def _row(item_id: str, label: str, kind: str, interest: str, engaged: str | None) -> dict[str, Any]:
    row = {
        "id": item_id,
        "label": label,
        "kind": kind,
        "interest": interest,
    }
    if engaged:
        row["last_engaged_at"] = engaged
    return row


def normalize_hobbies(raw: Any) -> list[dict[str, Any]]:
    """Structured hobbies only. Labels are sanitized; bad rows drop."""
    if not isinstance(raw, list):
        return []
    out: list[dict[str, Any]] = []
    seen: set[str] = set()
    for item in raw:
        if isinstance(item, str):
            label = sanitize_label(item)
            if not label:
                continue
            item_id = _slug(label)
            kind = _kind_for(label, None)
            interest = "medium"
            engaged = None
        elif isinstance(item, dict):
            label = sanitize_label(str(item.get("label") or item.get("name") or ""))
            if not label:
                continue
            hinted_id = str(item.get("id") or "").strip().lower()
            item_id = hinted_id if _SAFE_ID.match(hinted_id) else _slug(label)
            kind = _kind_for(label, str(item.get("kind") or "").strip().lower() or None)
            interest = _interest(item.get("interest"))
            engaged = _engaged(item.get("last_engaged_at") or item.get("lastEngagedAt"))
        else:
            continue
        if not item_id or item_id in seen:
            continue
        seen.add(item_id)
        out.append(_row(item_id, label, kind, interest, engaged))
        if len(out) >= 8:
            break
    return out


def hobbies_from_living(slugs: list[str] | None) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    for slug in slugs or []:
        key = str(slug or "").strip().lower()
        spec = _LIVING.get(key)
        if spec is None or any(row["id"] == key for row in out):
            continue
        kind, interest, label = spec
        out.append(_row(key, label, kind, interest, None))
        if len(out) >= 8:
            break
    return out


def mentality_from_tokens(tokens: list[str] | None) -> str | None:
    """Read hobby-path tags the client already sent. Missing tags stay None."""
    band = None
    energy = None
    tendency = None
    stance = None
    feel = None
    for token in tokens or []:
        text = str(token or "")
        if text.startswith("hobby_social:"):
            band = text.split(":", 1)[1]
        elif text.startswith("hobby_people:"):
            energy = text.split(":", 1)[1]
        elif text.startswith("working:feel:"):
            feel = text.split(":")[-1]
        elif text.startswith("working:") and not text.startswith(
            ("working:feel:", "working:confidence:")
        ):
            parts = text.split(":")
            if len(parts) >= 3:
                tendency, stance = parts[1], parts[2]
    if band is None and energy is None:
        return None
    working = uwm.Snapshot(
        tendency=tendency or uwm.UNKNOWN,
        stance=stance or uwm.KEEP_RHYTHM,
        predicted_feel=feel or uwm.MIXED,
        confidence="low",
        drivers=[],
        steering_line="",
    )
    return mentality_signal(band or hp.MIXED, energy or hp.ENOUGH, working)


def is_hobby_question(message: str) -> bool:
    lower = str(message or "").lower()
    phrases = (
        "hobby",
        "hobbies",
        "free day",
        "free time",
        "something besides training",
        "quiet hobby",
        "people-energy",
        "people energy",
    )
    return any(phrase in lower for phrase in phrases)


def chat_line(message: str, tokens: list[str] | None) -> str | None:
    """Spoken line for Dummy / Chat. None when this turn is not a hobby ask."""
    if not is_hobby_question(message):
        return None
    signal = mentality_from_tokens(tokens)
    if signal is None:
        return None
    lower = str(message or "").lower()
    line = canon_line(
        signal,
        curious=("curious" in lower or "pottery" in lower),
        skip_groups=("skip group" in lower or "group stuff" in lower),
    )
    line += _named_person_suffix(signal, tokens)
    if not speech_is_clean(line):
        return None
    return line


def _named_person_suffix(signal: str, tokens: list[str] | None) -> str:
    """First name + label only, same suffix the hobby path already uses."""
    path = hp.OPEN_GENTLY if signal == QUIET else hp.RESTORE_QUIET if signal == DRAINED_SOCIAL else ""
    if not path:
        return ""
    people: list[dict[str, str]] = []
    for token in tokens or []:
        parts = str(token).split(":")
        if len(parts) < 3 or parts[0] != "people" or parts[1] == "count":
            continue
        name = parts[1]
        if not name or "@" in name or any(ch.isdigit() for ch in name):
            continue
        people.append({"firstName": name, "relation": parts[2]})
        break
    return hp._people_suffix(path, people)
