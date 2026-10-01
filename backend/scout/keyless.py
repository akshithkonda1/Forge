"""Keyless public search for the Scout dummy's ``local`` mode.

No SearXNG, no API key, no Forge server: four free public endpoints a
laptop (or, in the Swift twin, an iPhone) can call directly.

* Wikipedia — search with plain-text intro extracts;
* DuckDuckGo Instant Answer — an abstract plus its source URL;
* MedlinePlus health-topic search (NLM) — plain-language summaries;
* PubMed E-utilities — the most relevant paper titles.

Each hit carries a rich snippet, so ``local`` mode reads snippets instead of
downloading whole pages (fast, small, nothing large pulled onto the device).
Every source fails soft: an error or odd payload is simply no hits.
"""

from __future__ import annotations

import json
import re
import xml.etree.ElementTree as ET
from concurrent.futures import ThreadPoolExecutor, wait
from html import unescape
from typing import Callable
from urllib.parse import urlencode
from urllib.request import Request, urlopen

from .search import SearchHit

KEYLESS_TIMEOUT_SECONDS = 6.0
_TAG = re.compile(r"<[^>]+>")
_WS = re.compile(r"\s+")

Transport = Callable[[str, float], bytes]


def _default_transport(url: str, timeout: float) -> bytes:
    request = Request(url, headers={"User-Agent": "Forge-ARIA-Scout/1.0", "Accept": "application/json, application/xml"})
    with urlopen(request, timeout=timeout) as response:  # noqa: S310 — fixed public https endpoints
        if response.status != 200:
            raise OSError(f"status {response.status}")
        return response.read(1024 * 1024)


def _plain(text: str, limit: int = 900) -> str:
    return _WS.sub(" ", unescape(_TAG.sub(" ", unescape(str(text or ""))))).strip()[:limit]


# --- parsers (pure) ---------------------------------------------------------


def parse_wikipedia(body: bytes, query: str = "") -> list[SearchHit]:
    try:
        pages = json.loads(body)["query"]["pages"]
    except (ValueError, KeyError, TypeError):
        return []
    rows = sorted(pages.values(), key=lambda p: p.get("index", 99)) if isinstance(pages, dict) else []
    hits = []
    for page in rows:
        url = str(page.get("fullurl") or "")
        extract = _plain(page.get("extract") or "")
        if url.startswith("https://") and extract:
            hits.append(SearchHit(url=url, title=str(page.get("title") or ""), snippet=extract, engines=["wikipedia"], query=query))
    return hits


def parse_duckduckgo(body: bytes, query: str = "") -> list[SearchHit]:
    try:
        data = json.loads(body)
    except (ValueError, TypeError):
        return []
    if not isinstance(data, dict):
        return []
    url = str(data.get("AbstractURL") or "")
    text = _plain(data.get("AbstractText") or "")
    if not (url.startswith("https://") and text):
        return []
    title = str(data.get("Heading") or data.get("AbstractSource") or "")
    return [SearchHit(url=url, title=title, snippet=text, engines=["duckduckgo"], query=query)]


def parse_medlineplus(body: bytes, query: str = "") -> list[SearchHit]:
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        return []
    hits = []
    for doc in root.iter("document"):
        fields = {c.get("name"): "".join(c.itertext()) for c in doc.findall("content")}
        url = doc.get("url") or ""
        title = _plain(fields.get("title") or "", 160)
        text = _plain(fields.get("FullSummary") or fields.get("snippet") or "")
        if url.startswith("https://") and title and text:
            hits.append(SearchHit(url=url, title=title, snippet=text, engines=["medlineplus"], query=query))
    return hits


def parse_pubmed(ids_body: bytes, summary_body: bytes, query: str = "") -> list[SearchHit]:
    try:
        result = json.loads(summary_body)["result"]
        uids = result["uids"]
    except (ValueError, KeyError, TypeError):
        return []
    hits = []
    for uid in uids:
        row = result.get(uid) or {}
        title = _plain(row.get("title") or "", 300)
        if not title or not str(uid).isdigit():
            continue
        journal = str(row.get("source") or "")
        year = str(row.get("pubdate") or "")[:4]
        snippet = f"{title} Published in {journal} ({year})." if journal else title
        hits.append(SearchHit(url=f"https://pubmed.ncbi.nlm.nih.gov/{uid}/", title=title, snippet=snippet, engines=["pubmed"], query=query))
    return hits


def pubmed_ids(body: bytes) -> list[str]:
    try:
        ids = json.loads(body)["esearchresult"]["idlist"]
    except (ValueError, KeyError, TypeError):
        return []
    return [str(i) for i in ids if str(i).isdigit()][:3]


# --- searcher ---------------------------------------------------------------


class KeylessSearcher:
    """Same ``search(query, timeout=)`` shape as ``SearxngClient``."""

    def __init__(self, *, transport: Transport | None = None) -> None:
        self._get = transport or _default_transport

    def _fetch(self, url: str, timeout: float) -> bytes | None:
        try:
            return self._get(url, timeout)
        except Exception:
            return None

    def _wikipedia(self, q: str, t: float) -> list[SearchHit]:
        body = self._fetch("https://en.wikipedia.org/w/api.php?" + urlencode({
            "action": "query", "format": "json", "generator": "search", "gsrsearch": q, "gsrlimit": 3,
            "prop": "extracts|info", "exintro": 1, "explaintext": 1, "exchars": 900, "inprop": "url",
        }), t)
        return parse_wikipedia(body, q) if body else []

    def _duckduckgo(self, q: str, t: float) -> list[SearchHit]:
        body = self._fetch("https://api.duckduckgo.com/?" + urlencode({
            "q": q, "format": "json", "no_html": 1, "skip_disambig": 1,
        }), t)
        return parse_duckduckgo(body, q) if body else []

    def _medlineplus(self, q: str, t: float) -> list[SearchHit]:
        body = self._fetch("https://wsearch.nlm.nih.gov/ws/query?" + urlencode({
            "db": "healthTopics", "retmax": 3, "term": q,
        }), t)
        return parse_medlineplus(body, q) if body else []

    def _pubmed(self, q: str, t: float) -> list[SearchHit]:
        ids_body = self._fetch("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?" + urlencode({
            "db": "pubmed", "term": q, "retmax": 3, "retmode": "json", "sort": "relevance",
        }), t)
        ids = pubmed_ids(ids_body) if ids_body else []
        if not ids:
            return []
        summary = self._fetch("https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?" + urlencode({
            "db": "pubmed", "id": ",".join(ids), "retmode": "json",
        }), t)
        return parse_pubmed(ids_body, summary, q) if summary else []

    def search(self, query: str, *, timeout: float = KEYLESS_TIMEOUT_SECONDS) -> list[SearchHit]:
        query = (query or "").strip()
        if not query:
            return []
        sources = (self._medlineplus, self._wikipedia, self._duckduckgo, self._pubmed)
        results: list[list[SearchHit]] = [[] for _ in sources]

        def run(i: int, fn) -> None:
            results[i] = fn(query, timeout)

        pool = ThreadPoolExecutor(max_workers=len(sources))
        try:
            futures = [pool.submit(run, i, fn) for i, fn in enumerate(sources)]
            wait(futures, timeout=timeout + 1)
        finally:
            pool.shutdown(wait=False, cancel_futures=True)
        return [hit for rows in results for hit in rows]


def snippet_fetch(url: str) -> tuple[str, str, str]:
    """Read nothing extra: the reader falls back to each hit's own snippet."""
    return url, "", ""
