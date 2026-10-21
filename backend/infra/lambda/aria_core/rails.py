"""Deterministic output validation against ARIA rails.

Cheap checks run before any verifier model: soul sanitize, banned tokens,
positive-framing shaming language. The result is what every tier ships.
"""

from __future__ import annotations

from typing import Any

from .soul import soul_breaks_rails, soul_sanitize

_MEDICAL_CLAIM = (
    "you have",
    "you probably have",
    "this is a diagnosis",
    "start metformin",
    "take 1000 mg",
    "i diagnose",
    "i prescribe",
)


def validate_output(text: str) -> str:
    """Return rails-safe user-visible text. Never raises."""
    return soul_sanitize(text or "")


def needs_model_verifier(text: str) -> bool:
    """True only when cheap sanitize still left a rails break."""
    cleaned = soul_sanitize(text or "")
    if soul_breaks_rails(cleaned):
        return True
    lower = cleaned.lower()
    return any(token in lower for token in _MEDICAL_CLAIM)


def apply_to_envelope(row: dict[str, Any]) -> dict[str, Any]:
    """Sanitize spoken fields on a chat/router envelope."""
    out = dict(row)
    for key in ("answer", "finalAnswer", "message", "prose_summary", "recommendation"):
        value = out.get(key)
        if isinstance(value, str) and value.strip():
            out[key] = validate_output(value)
    card = out.get("card")
    if isinstance(card, dict):
        card = dict(card)
        for key in ("action", "why", "interpretation", "title"):
            value = card.get(key)
            if isinstance(value, str) and value.strip():
                card[key] = validate_output(value)
        out["card"] = card
    return out
