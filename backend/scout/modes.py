"""Scout dummy: the same Scout agent, run inside the Dummy, in switchable modes.

    offline  fixtures only, no network — tests, CI, SimRunner (default)
    local    keyless public search (Wikipedia, DuckDuckGo, MedlinePlus, PubMed),
             rules brain, no server, no cloud model
    remote   the deployed Scout server (``POST /scout/research``) — the caller
             owns that HTTP call; this module only names the mode
    off      no Scout

Set with ``FORGE_SCOUT_MODE``. The iOS twin (``AriaScoutDummy``) uses the
same four names. In-process Scouts are built once per mode and keep their
brief cache, so a prompt-guard replay never searches twice.
"""

from __future__ import annotations

import os

from .agent import BriefCache, Scout
from .brain import RulesBrain
from .fixtures import FixtureSearcher, fixture_fetch
from .keyless import KeylessSearcher, snippet_fetch

OFFLINE = "offline"
LOCAL = "local"
REMOTE = "remote"
OFF = "off"
MODES = (OFFLINE, LOCAL, REMOTE, OFF)

# Local briefs come back in a few seconds; keep the Dummy turn snappy.
LOCAL_BUDGET_SECONDS = 12.0

_SCOUTS: dict[str, Scout] = {}


def scout_mode(env: dict | None = None) -> str:
    raw = ((env if env is not None else os.environ).get("FORGE_SCOUT_MODE") or "").strip().lower()
    return raw if raw in MODES else OFFLINE


def in_process_scout(mode: str, *, topic: str = "") -> Scout | None:
    """A Scout that runs inside the Dummy, or None for remote / off."""
    if mode == OFFLINE:
        # The fixture searcher is topic-aware, so it is cheap to build per call;
        # the cache is shared per mode.
        cache = _SCOUTS.setdefault(OFFLINE, Scout(brain=RulesBrain(), cache=BriefCache())).cache
        return Scout(brain=RulesBrain(), searcher=FixtureSearcher(topic), fetch=fixture_fetch, cache=cache, synth_reserve_seconds=0.5)
    if mode == LOCAL:
        if LOCAL not in _SCOUTS:
            _SCOUTS[LOCAL] = Scout(
                brain=RulesBrain(),
                searcher=KeylessSearcher(),
                fetch=snippet_fetch,
                cache=BriefCache(),
                synth_reserve_seconds=1.0,
            )
        return _SCOUTS[LOCAL]
    return None


def research(query: str, *, topic: str = "", mode: str | None = None) -> dict | None:
    """Run the in-process Scout. Returns a brief dict, or None (remote/off/empty)."""
    mode = mode or scout_mode()
    scout = in_process_scout(mode, topic=topic)
    if scout is None:
        return None
    budget = LOCAL_BUDGET_SECONDS if mode == LOCAL else 5.0
    brief = scout.research(query, topic=topic, budget_seconds=budget)
    if not brief.get("answer"):
        return None
    brief["mode"] = mode
    return brief


def reset_for_tests() -> None:
    _SCOUTS.clear()
