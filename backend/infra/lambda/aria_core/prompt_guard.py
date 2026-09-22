"""Offline per-prompt consistency check — SimRunner as a live gate.

Every coaching turn is generated twice with the same inputs. If the two
answers disagree on facts (type, recommendation, spoken body), the turn is
killed. Callers surface that as a connection failure so a wobbly coach
never reaches a person.

This is not the suite-level determinism report (``determinism_checker``).
That grades a sample of prompts after the fact. This is the hot path:
one prompt, two copies, fail closed.
"""

from __future__ import annotations

import os
from typing import Any, Callable

CONNECTION_FAILURE = "Couldn't reach Forge. Check your connection."
CONNECTION_CODE = "connection_failed"
_OFF = frozenset({"0", "false", "off", "no"})


class PromptInconsistent(Exception):
    """Replay did not match. ``str(self)`` is the public connection line."""

    def __init__(self, reason: str = "") -> None:
        self.reason = reason
        super().__init__(CONNECTION_FAILURE)

    @property
    def public_message(self) -> str:
        return CONNECTION_FAILURE


def enabled() -> bool:
    raw = str(os.environ.get("FORGE_PROMPT_GUARD", "1") or "").strip().lower()
    return raw not in _OFF


def _norm(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).lower().split())


def fingerprint(payload: dict[str, Any] | None) -> tuple[str, str, str, str]:
    """Fact identity of one turn — not latency, not orchestration metadata."""
    row = payload if isinstance(payload, dict) else {}
    rec = row.get("recommendation")
    card = row.get("card")
    if rec is None and isinstance(card, dict):
        rec = card.get("action")
    spoken = row.get("message") or row.get("prose_summary") or ""
    return (
        _norm(row.get("response_type")),
        _norm(rec),
        _norm(row.get("agent") or row.get("query_type")),
        _norm(spoken),
    )


def consistent(first: dict[str, Any] | None, second: dict[str, Any] | None) -> bool:
    return fingerprint(first) == fingerprint(second)


def confirm(produce: Callable[[], dict[str, Any]], *, copies: int = 2) -> dict[str, Any]:
    """Run ``produce`` at least twice. Same fingerprint or raise."""
    runs = max(2, int(copies))
    first = produce()
    first_fp = fingerprint(first)
    for _ in range(1, runs):
        replay = produce()
        if fingerprint(replay) != first_fp:
            raise PromptInconsistent("replay mismatch")
    return first


def checked(produce: Callable[[], dict[str, Any]], *, copies: int = 2) -> dict[str, Any]:
    """Hot-path helper: confirm when the guard is on, otherwise one run."""
    if not enabled():
        return produce()
    return confirm(produce, copies=copies)
