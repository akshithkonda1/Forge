"""HabitStreak — consecutive-day qualifying check-off run.

Python port of ForgeCore's ``HabitStreak.swift``. Pure over dates so iOS
and a future Kotlin client share one definition of "the streak" via this
backend. UserDefaults / SharedPreferences stay on the phone.

A day *qualifies* when enough of that day's habits were done. The streak is
the run of qualifying days ending today. Until today qualifies, the run
ending yesterday still counts, so the number does not drop to zero every
morning before the first check-off.

Stdlib only. Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta
from typing import Iterable

QUALIFYING_SHARE = 0.6
RETAINED_DAYS = 120


def _as_date(value: date | datetime | str) -> date:
    if isinstance(value, datetime):
        return value.date()
    if isinstance(value, date):
        return value
    text = str(value).strip()
    if "T" in text:
        text = text.split("T", 1)[0]
    return date.fromisoformat(text[:10])


def qualifies(completed: int, total: int) -> bool:
    """Mirrors ``HabitStreak.qualifies(completed:total:)``."""
    if total <= 0:
        return False
    return (completed / total) >= QUALIFYING_SHARE


def length(
    qualifying_days: Iterable[date | datetime | str],
    *,
    today: date | datetime | str | None = None,
) -> int:
    """Length of the consecutive qualifying run ending today, or yesterday
    if today has not qualified yet."""
    days = {_as_date(item) for item in qualifying_days}
    start = _as_date(today) if today is not None else date.today()
    cursor = start
    if cursor not in days:
        cursor = start - timedelta(days=1)
        if cursor not in days:
            return 0
    count = 0
    while cursor in days:
        count += 1
        cursor = cursor - timedelta(days=1)
    return count


def recording(
    day: date | datetime | str,
    qualifies: bool,
    days: Iterable[date | datetime | str],
) -> list[date]:
    """Add or remove ``day``, de-duplicate, sort oldest-first, trim to
    ``RETAINED_DAYS``."""
    target = _as_date(day)
    bucket = {_as_date(item) for item in days}
    if qualifies:
        bucket.add(target)
    else:
        bucket.discard(target)
    sorted_days = sorted(bucket)
    return sorted_days[-RETAINED_DAYS:]
