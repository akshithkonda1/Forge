"""SearXNG metasearch client + source ranking.

SearXNG runs beside Scout on the same host (``SCOUT_SEARXNG_URL``, default
``http://searxng:8080`` on the private compose network — never exposed).
One query fans out to Google, Bing, DuckDuckGo, Brave, Wikipedia and the
rest of its engine list; SearXNG returns merged JSON.

Google often rate-limits data-center IPs. That is expected: SearXNG keeps
answering from the other engines, and ``engines`` on each hit records who
actually returned it.
"""

from __future__ import annotations

import json
import os
from dataclasses import dataclass, field
from typing import Callable
from urllib.parse import urlencode, urlparse
from urllib.request import Request, urlopen

DEFAULT_SEARXNG_URL = "http://searxng:8080"
SEARCH_TIMEOUT_SECONDS = 6.0
MAX_RESULTS_PER_QUERY = 8

# (suffix or host, weight). Public health and research first; commerce and
# social last. A hit's trust is the best matching rule.
_TRUST_RULES: tuple[tuple[str, float], ...] = (
    (".gov", 1.0),
    ("nih.gov", 1.0),
    ("who.int", 1.0),
    ("cochranelibrary.com", 0.95),
    ("pubmed.ncbi.nlm.nih.gov", 1.0),
    (".edu", 0.9),
    ("mayoclinic.org", 0.9),
    ("clevelandclinic.org", 0.9),
    ("nhs.uk", 0.95),
    ("hopkinsmedicine.org", 0.9),
    ("harvard.edu", 0.9),
    ("acsm.org", 0.9),
    ("nsca.com", 0.85),
    ("examine.com", 0.8),
    ("bmj.com", 0.9),
    ("nature.com", 0.85),
    ("wikipedia.org", 0.6),
)
_LOW_TRUST = (
    "amazon.", "ebay.", "walmart.", "etsy.", "aliexpress.",
    "pinterest.", "facebook.", "instagram.", "tiktok.", "x.com", "twitter.com",
    "reddit.com", "quora.com",
)
DEFAULT_TRUST = 0.45


@dataclass
class SearchHit:
    url: str
    title: str
    snippet: str
    engines: list[str] = field(default_factory=list)
    query: str = ""

    @property
    def host(self) -> str:
        return (urlparse(self.url).hostname or "").lower()

    @property
    def trust(self) -> float:
        return trust_for_host(self.host)


def trust_for_host(host: str) -> float:
    host = (host or "").lower().strip(".")
    if not host:
        return 0.0
    if any(bad in host for bad in _LOW_TRUST):
        return 0.15
    best = 0.0
    for rule, weight in _TRUST_RULES:
        if rule.startswith("."):
            matched = host.endswith(rule)
        else:
            matched = host == rule or host.endswith("." + rule)
        if matched:
            best = max(best, weight)
    return best or DEFAULT_TRUST


Transport = Callable[[str, float], bytes]


def _default_transport(url: str, timeout: float) -> bytes:
    request = Request(url, headers={"Accept": "application/json", "User-Agent": "ForgeScout/1.0"})
    with urlopen(request, timeout=timeout) as response:  # noqa: S310 — private SearXNG URL
        return response.read(2 * 1024 * 1024)


class SearxngClient:
    def __init__(self, base_url: str | None = None, *, transport: Transport | None = None) -> None:
        self.base_url = (base_url or os.getenv("SCOUT_SEARXNG_URL") or DEFAULT_SEARXNG_URL).rstrip("/")
        self._transport = transport or _default_transport

    def search(self, query: str, *, timeout: float = SEARCH_TIMEOUT_SECONDS) -> list[SearchHit]:
        """Return hits for one query; ``[]`` on any failure (never raises)."""
        query = (query or "").strip()
        if not query:
            return []
        url = f"{self.base_url}/search?" + urlencode(
            {"q": query, "format": "json", "language": "en", "safesearch": "1"}
        )
        try:
            payload = json.loads(self._transport(url, timeout).decode("utf-8", errors="replace"))
        except Exception:
            return []
        hits: list[SearchHit] = []
        for row in payload.get("results") or []:
            if not isinstance(row, dict):
                continue
            link = str(row.get("url") or "").strip()
            if not link.startswith("https://"):
                continue
            engines = row.get("engines") or ([row["engine"]] if row.get("engine") else [])
            hits.append(
                SearchHit(
                    url=link,
                    title=str(row.get("title") or "").strip()[:200],
                    snippet=str(row.get("content") or "").strip()[:500],
                    engines=[str(e) for e in engines if e],
                    query=query,
                )
            )
            if len(hits) >= MAX_RESULTS_PER_QUERY:
                break
        return hits


def rank_hits(hits: list[SearchHit], *, limit: int) -> list[SearchHit]:
    """Dedupe by URL, one page per host, trust first, then engine agreement."""
    seen_urls: set[str] = set()
    seen_hosts: set[str] = set()
    scored: list[tuple[float, int, SearchHit]] = []
    for order, hit in enumerate(hits):
        key = hit.url.split("#", 1)[0].rstrip("/")
        if key in seen_urls:
            continue
        seen_urls.add(key)
        agreement = min(len(set(hit.engines)), 4) * 0.05
        scored.append((hit.trust + agreement, -order, hit))
    scored.sort(key=lambda item: (item[0], item[1]), reverse=True)
    ranked: list[SearchHit] = []
    for _score, _order, hit in scored:
        if hit.host in seen_hosts:
            continue
        seen_hosts.add(hit.host)
        ranked.append(hit)
        if len(ranked) >= limit:
            break
    return ranked
