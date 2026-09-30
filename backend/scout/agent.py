"""Scout's agent loop: plan → search → rank → read → synthesize → cross-check.

One call is one research job with a wall-clock budget (default 24 s:
plan 3.5 + search 5 + read 6.5 + synthesize 9), under API Gateway's 29 s
integration ceiling. Every stage degrades rather
than fails: no search hits → empty brief, unreadable pages → search
snippets, Grok unavailable → rules brain. The caller always gets JSON.

Results are cached by (scrubbed query, topic) so the same question from
many users costs one Bedrock call, not many — minimal cost by design.
"""

from __future__ import annotations

import threading
import time
from collections import OrderedDict
from concurrent.futures import ThreadPoolExecutor, wait
from typing import Callable

from .brain import RulesBrain, Synthesis
from .privacy import scrub_query
from .reader import Fetcher, read_pages
from .search import SearchHit, SearxngClient, rank_hits

DEFAULT_BUDGET_SECONDS = 24.0
SYNTH_RESERVE_SECONDS = 9.5
MAX_PAGES = 5
CACHE_TTL_SECONDS = 6 * 3600
CACHE_MAX_ENTRIES = 512


class BriefCache:
    def __init__(self, *, ttl: float = CACHE_TTL_SECONDS, max_entries: int = CACHE_MAX_ENTRIES, clock=time.monotonic) -> None:
        self._ttl = ttl
        self._max = max_entries
        self._clock = clock
        self._rows: OrderedDict[tuple[str, str], tuple[float, dict]] = OrderedDict()
        self._lock = threading.Lock()

    def get(self, key: tuple[str, str]) -> dict | None:
        with self._lock:
            row = self._rows.get(key)
            if row is None:
                return None
            stored, brief = row
            if self._clock() - stored > self._ttl:
                del self._rows[key]
                return None
            self._rows.move_to_end(key)
            return dict(brief)

    def put(self, key: tuple[str, str], brief: dict) -> None:
        with self._lock:
            self._rows[key] = (self._clock(), dict(brief))
            self._rows.move_to_end(key)
            while len(self._rows) > self._max:
                self._rows.popitem(last=False)


class Scout:
    def __init__(
        self,
        *,
        brain=None,
        searcher: SearxngClient | None = None,
        fetch: Fetcher | None = None,
        cache: BriefCache | None = None,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.brain = brain or RulesBrain()
        self.searcher = searcher or SearxngClient()
        self.fetch = fetch
        self.cache = cache if cache is not None else BriefCache()
        self.clock = clock

    def research(self, query: str, *, topic: str = "", budget_seconds: float = DEFAULT_BUDGET_SECONDS) -> dict:
        started = self.clock()
        safe = scrub_query(query)
        topic = scrub_query(topic).split(" ")[0] if topic else ""
        if not safe:
            return _empty_brief("", topic, reason="empty_query")
        key = (safe, topic)
        cached = self.cache.get(key)
        if cached is not None:
            cached["cached"] = True
            return cached

        def left() -> float:
            return max(0.0, budget_seconds - (self.clock() - started))

        queries = self.brain.plan(safe, topic=topic) or [safe]
        hits = self._search_all(queries, timeout=max(0.5, min(5.0, left() - SYNTH_RESERVE_SECONDS - 1.0)))
        ranked = rank_hits(hits, limit=MAX_PAGES)
        if not ranked:
            return _empty_brief(safe, topic, reason="no_results", queries=queries)
        pages = read_pages(ranked, fetch=self.fetch, deadline_seconds=max(0.5, min(6.5, left() - SYNTH_RESERVE_SECONDS)))
        if not pages:
            return _empty_brief(safe, topic, reason="unreadable", queries=queries)
        synthesis: Synthesis = self.brain.synthesize(safe, pages)
        if not synthesis.answer:
            synthesis = RulesBrain().synthesize(safe, pages)
        if not synthesis.answer:
            return _empty_brief(safe, topic, reason="no_answer", queries=queries)
        cited = {s for point in synthesis.points for s in point.sources}
        brief = {
            "query": safe,
            "topic": topic,
            "answer": synthesis.answer,
            "points": [p.as_dict() for p in synthesis.points],
            "caveats": list(synthesis.caveats),
            "confidence": synthesis.confidence,
            "sources": [p.as_source() for p in pages if p.id in cited],
            "queries": queries,
            "engines": sorted({e for h in hits for e in h.engines}),
            "brain": synthesis.brain,
            "untrusted": True,
            "cached": False,
            "elapsed_ms": int((self.clock() - started) * 1000),
        }
        self.cache.put(key, brief)
        return brief

    def _search_all(self, queries: list[str], *, timeout: float) -> list[SearchHit]:
        results: list[list[SearchHit]] = [[] for _ in queries]

        def one(index: int, q: str) -> None:
            results[index] = self.searcher.search(q, timeout=timeout)

        pool = ThreadPoolExecutor(max_workers=max(1, len(queries)))
        try:
            futures = [pool.submit(one, i, q) for i, q in enumerate(queries)]
            wait(futures, timeout=timeout + 0.5)
        finally:
            pool.shutdown(wait=False, cancel_futures=True)
        merged: list[SearchHit] = []
        # Interleave so the first query's best hit is not starved by later ones.
        for rank in range(max((len(r) for r in results), default=0)):
            for row in results:
                if rank < len(row):
                    merged.append(row[rank])
        return merged


def _empty_brief(query: str, topic: str, *, reason: str, queries: list[str] | None = None) -> dict:
    return {
        "query": query,
        "topic": topic,
        "answer": "",
        "points": [],
        "caveats": [],
        "confidence": 0.0,
        "sources": [],
        "queries": list(queries or []),
        "engines": [],
        "brain": "none",
        "untrusted": True,
        "cached": False,
        "reason": reason,
    }
