"""Nothing Scout reads is allowed to stay.

A research run may hold pages and the mission in memory while it works.
``working_set`` dumps both when the run ends — success or failure. The only
survivor is a caller-owned cache of the scrubbed keyword hash, never the
raw prompt and never the page text.
"""

from __future__ import annotations

import hashlib
from contextlib import contextmanager
from typing import Iterator


def keyword_cache_key(scrubbed_query: str) -> str:
    """Stable id for a 6h brief cache. Input must already be scrubbed."""
    normalized = " ".join(str(scrubbed_query or "").lower().split())
    return hashlib.sha256(normalized.encode()).hexdigest()[:24]


class WorkingSet:
    def __init__(self) -> None:
        self.mission: str = ""
        self.pages: list[str] = []

    def dump(self) -> None:
        self.mission = ""
        self.pages.clear()


@contextmanager
def working_set() -> Iterator[WorkingSet]:
    held = WorkingSet()
    try:
        yield held
    finally:
        held.dump()
