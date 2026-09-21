"""Pause-aware elapsed time for a practice session.

Python port of ForgeCore's ``SessionClock.swift``. Each transition returns a
new clock so a caller cannot half-apply one. WidgetKit / Watch haptics stay
on the client.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone


def _epoch(dt: datetime) -> float:
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.timestamp()


@dataclass(frozen=True)
class SessionClock:
    accumulated: float = 0.0
    segment_started_at: datetime | None = None

    @property
    def is_running(self) -> bool:
        return self.segment_started_at is not None

    def elapsed(self, at: datetime) -> float:
        if self.segment_started_at is None:
            return self.accumulated
        return self.accumulated + max(0.0, _epoch(at) - _epoch(self.segment_started_at))

    def remaining(self, at: datetime, planned: float) -> float:
        return max(0.0, planned - self.elapsed(at))

    def is_complete(self, at: datetime, planned: float) -> bool:
        return self.elapsed(at) >= planned

    @staticmethod
    def started(at: datetime) -> SessionClock:
        return SessionClock(accumulated=0.0, segment_started_at=at)

    def paused(self, at: datetime) -> SessionClock:
        if not self.is_running:
            return self
        return SessionClock(accumulated=self.elapsed(at), segment_started_at=None)

    def resumed(self, at: datetime) -> SessionClock:
        if self.is_running:
            return self
        return SessionClock(accumulated=self.accumulated, segment_started_at=at)

    def stopped(self, at: datetime) -> SessionClock:
        return SessionClock(accumulated=self.elapsed(at), segment_started_at=None)

    def completed(self, planned: float) -> SessionClock:
        return SessionClock(accumulated=planned, segment_started_at=None)
