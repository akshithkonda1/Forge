"""Spoken-output rails that every model (and Dummy) must satisfy.

Lifestyle coach, not a doctor. Never diagnose, treat, prescribe, or cure.
Never say the word "recovery". Never shame. Positive framing — misses become
the next honest step.

These rails are applied to user-visible text after generation. Prompt
directives live in ``soul_directive`` so a style (Coach / Friend / Drill
Sergeant) cannot override them.

Stdlib-only. ``speak_guard`` and ``coach_context`` both call this module so
there is one rewrite path, not two.
"""

from __future__ import annotations

import re
from typing import Any, Iterable

SOUL_VERSION = "1"
SOUL_RAILS = (
    "Lifestyle coach, not a doctor.",
    "Never diagnose, treat, prescribe, or cure.",
    "Never say recovery.",
    "Never shame.",
    "Never push past comfort or safety.",
    "Name real progress when it is real.",
    "Anything medical, suggest a doctor.",
)

PERSONALITIES = ("coach", "friend", "drill_sergeant")

_BANNED_SPOKEN = (
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

_RECOVERY_WORD = re.compile(r"(?i)\brecover(?:y|ies|ed|ing)?\b")
_DIAGNOSE_WORD = re.compile(r"(?i)\bdiagnos\w*")
_PRESCRIBE_WORD = re.compile(r"(?i)\bprescribe\w*")
_TREAT_CURE = re.compile(r"(?i)\b(?:treat(?:ment)?|cure)\b")


def soul_directive(style: str = "coach") -> str:
    """Prompt-side law. Style is a flavor; these rails cannot be overridden."""
    dominant = _normalize_style(style)
    return (
        f"ARIA soul v{SOUL_VERSION}. Dominant: {dominant}. Rails: "
        + " ".join(SOUL_RAILS)
    )


def blend_soul(
    *,
    style: str | None = None,
    experience: str | None = None,
    explicit: str | None = None,
) -> dict[str, Any]:
    """Coach / Friend / Drill Sergeant fusion. Explicit pick wins.

    Beginner / new → Coach + Friend (no Drill Sergeant).
    Athletic / PR / race / elite → Drill Sergeant + Coach.
    Everyday → Coach + Friend; engagement can add Drill Sergeant later.
    """
    pick = _normalize_style(explicit or style or "")
    exp = (experience or "").strip().lower()
    if pick in PERSONALITIES:
        weights = {name: 0.15 for name in PERSONALITIES}
        weights[pick] = 0.7
        return {"dominant": pick, "weights": weights, "source": "explicit"}
    if any(token in exp for token in ("beginner", "new", "first")):
        return {
            "dominant": "coach",
            "weights": {"coach": 0.6, "friend": 0.4, "drill_sergeant": 0.0},
            "source": "beginner",
        }
    if any(token in exp for token in ("athletic", "elite", "race", "pr", "competitor")):
        return {
            "dominant": "drill_sergeant",
            "weights": {"coach": 0.35, "friend": 0.1, "drill_sergeant": 0.55},
            "source": "athletic",
        }
    return {
        "dominant": "coach",
        "weights": {"coach": 0.5, "friend": 0.4, "drill_sergeant": 0.1},
        "source": "everyday",
    }


def soul_sanitize(line: str) -> str:
    """Rewrite a spoken line so style cannot break the rails."""
    text = str(line or "")
    for src, dst in _REPLACEMENTS:
        text = re.compile(re.escape(src), re.IGNORECASE).sub(dst, text)
    text = _DIAGNOSE_WORD.sub("notice", text)
    text = _PRESCRIBE_WORD.sub("suggest with a doctor", text)
    text = _RECOVERY_WORD.sub("readiness", text)
    return re.sub(r" {2,}", " ", text).strip()


def soul_breaks_rails(line: str) -> bool:
    """True when spoken text still contains a banned token after accounting for the rails themselves."""
    lower = (line or "").lower()
    for rail in SOUL_RAILS:
        lower = lower.replace(rail.lower(), "")
    if _RECOVERY_WORD.search(lower):
        return True
    return any(token in lower for token in _BANNED_SPOKEN)


def violations(text: str) -> tuple[str, ...]:
    """Named rail hits in user-visible text. Empty means the line is clean."""
    raw = text or ""
    if not raw.strip():
        return ()
    hits: list[str] = []
    if _RECOVERY_WORD.search(raw):
        hits.append("recovery")
    if _DIAGNOSE_WORD.search(raw):
        hits.append("diagnose")
    if _PRESCRIBE_WORD.search(raw):
        hits.append("prescribe")
    lowered = raw.lower()
    for token in ("you failed", "you did it wrong", "shame on you", "push through the pain"):
        if token in lowered:
            hits.append(token)
    return tuple(hits)


def apply_rails(text: str) -> str:
    """Sanitize then fail closed: if a rail still fires, drop the offending sentence."""
    cleaned = soul_sanitize(text)
    if not violations(cleaned) and not soul_breaks_rails(cleaned):
        return cleaned
    kept: list[str] = []
    for part in re.split(r"(?<=[.!?])\s+", cleaned):
        sentence = part.strip()
        if not sentence:
            continue
        rewritten = soul_sanitize(sentence)
        if violations(rewritten) or soul_breaks_rails(rewritten):
            continue
        kept.append(rewritten)
    return " ".join(kept).strip()


def apply_to_envelope(envelope: dict[str, Any]) -> dict[str, Any]:
    """Run rails on every user-visible field of a response envelope."""
    row = envelope if isinstance(envelope, dict) else {}
    for key in ("prose_summary", "message", "recommendation"):
        if row.get(key):
            row[key] = apply_rails(str(row[key]))
    card = row.get("card")
    if isinstance(card, dict):
        guarded = dict(card)
        for key in ("action", "why", "rationale", "timing", "recommendation", "interpretation"):
            if guarded.get(key):
                guarded[key] = apply_rails(str(guarded[key]))
        row["card"] = guarded
    return row


def critic_verdict(text: str, *, facts: Iterable[str] | None = None) -> dict[str, Any]:
    """Local critic: safety rails + optional fact-presence check.

    Structured so a live critic (Grok) can return the same shape. Local is
    the default — a Bedrock critic is an escalation, not a tax on every turn.
    """
    spoken = apply_rails(text)
    rail_hits = violations(text)
    missing: list[str] = []
    blob = (spoken or "").lower()
    for fact in facts or ():
        token = str(fact or "").strip().lower()
        if token and token not in blob and token not in (text or "").lower():
            missing.append(token)
    return {
        "safe": not rail_hits,
        "answer": spoken,
        "violations": list(rail_hits),
        "consistent": not missing,
        "missing_facts": missing,
        "source": "local",
    }


def _normalize_style(raw: str) -> str:
    key = (raw or "").strip().lower().replace(" ", "_").replace("-", "_")
    aliases = {
        "drill": "drill_sergeant",
        "drillsergeant": "drill_sergeant",
        "sergeant": "drill_sergeant",
        "push_hard": "drill_sergeant",
        "balanced": "coach",
        "patient": "friend",
        "data_driven": "coach",
        "check_in": "friend",
        "honest_peer": "friend",
    }
    key = aliases.get(key, key)
    return key if key in PERSONALITIES else "coach"
