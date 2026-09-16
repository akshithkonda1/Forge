"""Shared redaction for companion memory and inbound lifestyle tokens.

Partner / cycle prefixes must never enter the personal model, recentPatterns,
persona persist, short-term memory, or an editable-memory view. Calendar titles
are busy-window / time only. Match iOS FakeCalendarPack deny list.
"""

from __future__ import annotations

import re
from typing import Any

DENIED_LIFESTYLE = re.compile(
    r"(?i)^(?:"
    r"partner_"
    r"|support_cycle:"
    r"|partner_name:"
    r"|partner_phase:"
    r"|partner_day:"
    r"|partner_cycle:"
    r"|cycle:fertile"
    r"|cycle:tww"
    r"|cycle:goal:trying"
    r"|cycle:bleeding"
    r"|cycle:condition"
    r")"
)

BUSY_WINDOW_LABEL = "Busy window"


def denied_lifestyle_token(token: str) -> bool:
    return bool(DENIED_LIFESTYLE.search(str(token or "").strip()))


def filter_lifestyle_tokens(values: Any) -> list[str]:
    if not isinstance(values, list):
        return []
    kept: list[str] = []
    for item in values:
        text = str(item).strip()
        if text and not denied_lifestyle_token(text):
            kept.append(text)
    return kept


def redact_memory_text(text: str) -> str | None:
    """Drop a single memory string if it is a denied lifestyle token.

    Free prose is kept; only prefix-matched partner/cycle chips are stripped.
    """
    cleaned = str(text or "").strip()
    if not cleaned or denied_lifestyle_token(cleaned):
        return None
    return cleaned


def redact_calendar_event_titles(events: Any) -> list[dict[str, Any]]:
    """Busy-window / time only — drop title, summary, and name."""
    if not isinstance(events, list):
        return []
    redacted: list[dict[str, Any]] = []
    for event in events:
        if not isinstance(event, dict):
            continue
        item = dict(event)
        item.pop("summary", None)
        item.pop("name", None)
        item["title"] = BUSY_WINDOW_LABEL
        redacted.append(item)
    return redacted
