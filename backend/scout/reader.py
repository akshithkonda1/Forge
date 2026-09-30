"""Read search results through the ingest path's SSRF-safe fetcher.

``services.web_ingest.fetch_https`` already enforces https-only, public-IP
DNS checks on every redirect hop, a byte cap, and a content-type allowlist.
Scout reuses it rather than growing a second fetcher with weaker rules.

Page text is untrusted data. Sentences that address an assistant ("ignore
previous instructions", "you are …") are dropped here, before any model
sees them.
"""

from __future__ import annotations

import re
from concurrent.futures import ThreadPoolExecutor, wait
from dataclasses import dataclass
from typing import Callable

from backend._paths import ensure_lambda_on_path

ensure_lambda_on_path()

from services import web_ingest  # noqa: E402

from .search import SearchHit, trust_for_host  # noqa: E402

MAX_PAGE_CHARS = 4000
READ_TIMEOUT_SECONDS = 7.0
_SENTENCES = re.compile(r"(?<=[.!?])\s+")


@dataclass
class Page:
    id: str
    url: str
    host: str
    title: str
    text: str
    trust: float

    def as_source(self) -> dict:
        return {"id": self.id, "title": self.title, "url": self.url, "host": self.host, "trust": round(self.trust, 2)}


def strip_injection(text: str) -> str:
    kept = [
        part.strip()
        for part in _SENTENCES.split(str(text or ""))
        if part.strip() and not web_ingest._is_assistant_addressed(part)
    ]
    return " ".join(kept)


Fetcher = Callable[[str], tuple[str, str, str]]


def _default_fetch(url: str) -> tuple[str, str, str]:
    """Return ``(final_url, title, readable_text)``; raises on any failure."""
    response = web_ingest.fetch_https(url, timeout=READ_TIMEOUT_SECONDS, deadline_seconds=READ_TIMEOUT_SECONDS + 1)
    extracted = web_ingest.extract_from_html(response.body, source_url=response.url)
    return response.url, str(extracted.get("title") or ""), str(extracted.get("readableText") or "")


def read_pages(
    hits: list[SearchHit],
    *,
    fetch: Fetcher | None = None,
    deadline_seconds: float = READ_TIMEOUT_SECONDS + 2,
    workers: int = 4,
) -> list[Page]:
    """Fetch pages in parallel; slow or failed pages are skipped, never fatal.

    Falls back to the search snippet when a page cannot be read, so a
    blocked site still contributes what the engine already showed.
    """
    fetch = fetch or _default_fetch
    pages: list[Page | None] = [None] * len(hits)

    def one(index: int, hit: SearchHit) -> None:
        try:
            final_url, title, text = fetch(hit.url)
        except Exception:
            final_url, title, text = hit.url, hit.title, ""
        body = strip_injection(text)[:MAX_PAGE_CHARS] or strip_injection(hit.snippet)
        if not body:
            return
        host = web_ingest.page_host(final_url) or hit.host
        pages[index] = Page(
            id=f"S{index + 1}",
            url=final_url,
            host=host,
            title=(title or hit.title or host)[:200],
            text=body,
            trust=trust_for_host(host),
        )

    if not hits:
        return []
    pool = ThreadPoolExecutor(max_workers=max(1, min(workers, len(hits))))
    try:
        futures = [pool.submit(one, i, hit) for i, hit in enumerate(hits)]
        wait(futures, timeout=deadline_seconds)
    finally:
        pool.shutdown(wait=False, cancel_futures=True)
    return [page for page in pages if page is not None]
