"""ARIA soul — personalities plus rails that no model or style may override.

Coach, Friend, and Drill Sergeant are flavors. Fusion may blend them. An
explicit pick is an anchor. Rails are identical on every tier of the
Sonnet → Grok → Opus → ensemble ladder: lifestyle coach not a doctor, never
diagnose/treat/prescribe, never the word "recovery", never shame, never past
comfort, name real progress when it is real.

This module is stdlib-only so SimRunner and the Lambda share one copy.
``services.coach_context`` re-exports the same symbols.
"""

from __future__ import annotations

import re
from typing import Any

ARIA_SOUL_VERSION = "1"
ARIA_SOUL_RAILS = (
    "Lifestyle coach, not a doctor.",
    "Never diagnose, treat, prescribe, or cure.",
    "Never say recovery.",
    "Never shame.",
    "Never push past comfort or safety.",
    "Name real progress when it is real.",
    "Anything medical, suggest a doctor.",
)

PERSONALITIES = ("Coach", "Friend", "Drill Sergeant")

# Internal coaching_style values from the profile payload → spoken flavor.
_STYLE_TO_PERSONALITY = {
    "coach": "Coach",
    "balanced": "Coach",
    "data-driven": "Coach",
    "friend": "Friend",
    "patient": "Friend",
    "drill": "Drill Sergeant",
    "drill sergeant": "Drill Sergeant",
    "drill-sergeant": "Drill Sergeant",
    "push-hard": "Drill Sergeant",
    "sergeant": "Drill Sergeant",
}

_SOUL_BANNED = (
    "you failed",
    "you did it wrong",
    "you messed up",
    "your fault",
    "recovery",
    "diagnos",
    "prescribe",
    "shame on you",
    "push through the pain",
)

_REPLACEMENTS = (
    ("you failed", "we can solve this"),
    ("you did it wrong", "here's what can help"),
    ("you messed up", "we can solve this"),
    ("your fault", "here's what can help"),
    ("shame on you", ""),
    ("push through the pain", "stay inside comfort"),
    ("recovery", "readiness"),
)


def personality_from_style(style: Any) -> str:
    """Map a profile coaching_style / explicit pick onto a named flavor."""
    raw = str(style or "").strip()
    if not raw:
        return "Coach"
    if raw in PERSONALITIES:
        return raw
    return _STYLE_TO_PERSONALITY.get(raw.lower(), "Coach")


def fusion_label(*, coach: float = 0.0, friend: float = 0.0, drill: float = 0.0, anchor: str | None = None) -> str:
    """Describe a blend. An explicit anchor wins; otherwise the heaviest weight."""
    if anchor:
        return personality_from_style(anchor)
    weights = (("Coach", coach), ("Friend", friend), ("Drill Sergeant", drill))
    return max(weights, key=lambda item: item[1])[0] if any(w for _, w in weights) else "Coach"


def soul_directive(style: str = "coach") -> str:
    dominant = personality_from_style(style)
    return (
        f"ARIA soul v{ARIA_SOUL_VERSION}. Dominant: {dominant}. Rails: "
        + " ".join(ARIA_SOUL_RAILS)
    )


def soul_sanitize(line: str) -> str:
    """Spoken output. Style never overrides the rails."""
    lowered = line or ""
    for src, dst in _REPLACEMENTS:
        if " " in src:
            pattern = re.compile(re.escape(src), re.IGNORECASE)
        else:
            pattern = re.compile(rf"\b{re.escape(src)}\b", re.IGNORECASE)
        lowered = pattern.sub(dst, lowered)
    lowered = re.sub(r"(?i)\bdiagnos\w*", "notice", lowered)
    lowered = re.sub(r"(?i)\bprescribe\w*", "suggest with a doctor", lowered)
    return re.sub(r" {2,}", " ", lowered).strip()


def soul_breaks_rails(line: str) -> bool:
    """True when user-visible text still carries a banned token after stripping rail copy."""
    lower = (line or "").lower()
    for rail in ARIA_SOUL_RAILS:
        lower = lower.replace(rail.lower(), "")
    return any(token in lower for token in _SOUL_BANNED)


def rails_block() -> str:
    """Prompt fragment appended to every live system prompt, every tier."""
    return (
        "SOUL RAILS (mandatory, every personality, every model):\n"
        + "\n".join(f"- {rail}" for rail in ARIA_SOUL_RAILS)
        + "\nPositive framing: name what they can do, not what they failed."
    )
