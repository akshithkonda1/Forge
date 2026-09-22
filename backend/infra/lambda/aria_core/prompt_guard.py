"""Offline per-prompt SimRunner check — estimate when a claim cannot hold.

Every coaching turn is a small SimRunner run. If ARIA has evidence and the
facts replay (honesty and determinism ≥ 70), it may make the claim. If it
cannot find evidence, or the claim is not deterministic, it must not make
that claim or its reverse. It gives a cautious estimate instead.

It does not error out. A connection drop would make ARIA look unreliable.
Wording may move. Suite-level ``--gate`` (composite, context utilization,
HOLD) does not change a live prompt.
"""

from __future__ import annotations

import os
from typing import Any, Callable

CONNECTION_FAILURE = "Couldn't reach Forge. Check your connection."
CONNECTION_CODE = "connection_failed"
FLOOR = 70.0
ESTIMATE_LINE = (
    "I don't have a clean enough read to lock this in. "
    "A cautious estimate: keep today ordinary until more of your day is in."
)
ESTIMATE_REASON = "estimate — not enough evidence for a deterministic claim"
_OFF = frozenset({"0", "false", "off", "no"})
_HEDGE = (
    "mixed",
    "not sure",
    "uncertain",
    "wouldn't read too much",
    "watch the trend",
    "could",
    "might",
    "unclear",
    "genuinely mixed",
    "recheck",
    "i don't have enough",
)


class PromptInconsistent(Exception):
    """Legacy name. Live path no longer raises — it estimates instead."""

    def __init__(self, reason: str = "") -> None:
        self.reason = reason
        super().__init__(ESTIMATE_LINE)

    @property
    def public_message(self) -> str:
        return ESTIMATE_LINE


def enabled() -> bool:
    raw = str(os.environ.get("FORGE_PROMPT_GUARD", "1") or "").strip().lower()
    return raw not in _OFF


def _norm(value: Any) -> str:
    if value is None:
        return ""
    return " ".join(str(value).lower().split())


def _spoken(row: dict[str, Any]) -> str:
    return str(row.get("message") or row.get("prose_summary") or "")


def _recommendation(row: dict[str, Any]) -> str:
    rec = row.get("recommendation")
    card = row.get("card")
    if rec is None and isinstance(card, dict):
        rec = card.get("action")
    return _norm(rec)


def _confidence(row: dict[str, Any]) -> float | None:
    raw = row.get("confidence")
    if raw is None:
        return None
    try:
        val = float(raw)
    except (TypeError, ValueError):
        return None
    if val > 1.0:
        val = val / 100.0
    return max(0.0, min(1.0, val))


def fingerprint(payload: dict[str, Any] | None) -> tuple[str, str]:
    """Fact identity — type and recommendation. Spoken wording is not a fact."""
    row = payload if isinstance(payload, dict) else {}
    kind = row.get("response_type") or row.get("query_type")
    return (_norm(kind), _recommendation(row))


def consistent(first: dict[str, Any] | None, second: dict[str, Any] | None) -> bool:
    return fingerprint(first) == fingerprint(second)


def honesty_score(payload: dict[str, Any] | None) -> float:
    """0–100, SimRunner epistemic honesty on a product envelope.

    An explicit ``epistemic_honesty`` / ``honesty`` value wins. Refusing or
    asking when data is missing is honest. A confident prescription on sparse
    data is not — that turn becomes an estimate, not a claim.
    """
    row = payload if isinstance(payload, dict) else {}
    for key in ("epistemic_honesty", "honesty"):
        if row.get(key) is None:
            continue
        try:
            return max(0.0, min(100.0, float(row[key])))
        except (TypeError, ValueError):
            pass

    text = _spoken(row).lower()
    rec = _recommendation(row)
    missing = row.get("missing_fields") or []
    if isinstance(missing, str):
        missing = [missing]
    sparse = bool(row.get("data_sparse") or row.get("is_data_sparse")) or len(list(missing)) >= 3
    conf = _confidence(row)
    asking = "?" in text and not rec
    hedged = any(h in text for h in _HEDGE)
    kind = _norm(row.get("response_type") or row.get("query_type"))
    band = _norm(row.get("guidance_band"))
    if band in {"refer_out", "emergency", "first_aid"} or kind == "clarification":
        return 100.0
    if asking:
        return 100.0
    if sparse:
        if hedged and (conf is None or conf < 0.5):
            return 100.0
        if rec and (conf is None or conf >= 0.5):
            return 0.0
        return 40.0
    return 80.0


def determinism_score(first: dict[str, Any] | None, second: dict[str, Any] | None) -> float:
    """100 if the replay keeps the same facts, else 0."""
    return 100.0 if consistent(first, second) else 0.0


def passes(first: dict[str, Any] | None, second: dict[str, Any] | None = None) -> bool:
    if honesty_score(first) < FLOOR:
        return False
    if second is None:
        return True
    if honesty_score(second) < FLOOR:
        return False
    return determinism_score(first, second) >= FLOOR


def _contested_claims(*payloads: dict[str, Any] | None) -> list[str]:
    seen: list[str] = []
    for payload in payloads:
        rec = _recommendation(payload if isinstance(payload, dict) else {})
        if rec and rec not in seen:
            seen.append(rec)
    return seen


def estimate(
    first: dict[str, Any] | None,
    second: dict[str, Any] | None = None,
    *,
    reason: str = "",
) -> dict[str, Any]:
    """Speak an estimate. Do not assert the claim or its reverse."""
    row = dict(first) if isinstance(first, dict) else {}
    contested = _contested_claims(first, second)
    row["recommendation"] = None
    card = row.get("card")
    if isinstance(card, dict):
        card = dict(card)
        card.pop("action", None)
        card.pop("recommendation", None)
        row["card"] = card
    row["message"] = ESTIMATE_LINE
    row["prose_summary"] = ESTIMATE_LINE
    row["response_type"] = "insight"
    try:
        conf = float(row.get("confidence") or 0.45)
    except (TypeError, ValueError):
        conf = 0.45
    row["confidence"] = min(0.45, max(0.2, conf))
    row["confidence_reason"] = ESTIMATE_REASON
    row["guard"] = {
        "mode": "estimate",
        "reason": reason or "insufficient_evidence",
        "withheld": contested,
    }
    return row


def confirm(produce: Callable[[], dict[str, Any]], *, copies: int = 2) -> dict[str, Any]:
    """Small SimRunner run. Weak honesty or determinism becomes an estimate."""
    first = produce()
    if honesty_score(first) < FLOOR:
        return estimate(first, reason="honesty")
    runs = max(2, int(copies))
    for _ in range(1, runs):
        replay = produce()
        if honesty_score(replay) < FLOOR:
            return estimate(first, replay, reason="honesty")
        if determinism_score(first, replay) < FLOOR:
            return estimate(first, replay, reason="determinism")
    return first


def checked(produce: Callable[[], dict[str, Any]], *, copies: int = 2) -> dict[str, Any]:
    """Hot-path helper: confirm when the guard is on, otherwise one run."""
    if not enabled():
        return produce()
    return confirm(produce, copies=copies)
