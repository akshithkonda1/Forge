"""Scout client — the only egress surface to the Scout box.

Contract:

- In-memory 6-hour keyword-hash cache. The hash is the only survivor of a
  run; the content is not stored.
- 6-second timeout. A slow or wedged fetch degrades to a missed lookup.
- Fail-closed: timeout, bad status, or any error returns None. The caller
  keeps its local generation — nil means "show the local read," never a
  fake citation.
- No durable storage. No database. No logs of query content. The box
  dumps everything when the run ends.
- Stdlib only. No requests, no boto3, no cloud SDK.

The box itself (SearXNG + Bedrock synthesis) is not in this repo — it is
infrastructure owned separately. This client is the contract: scrubbed
keywords in, cited brief out, nothing retained.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request
from dataclasses import dataclass

_TIMEOUT_SECONDS = 6.0
_CACHE_TTL_SECONDS = 6 * 3600


@dataclass
class _CacheEntry:
    brief: str
    expires_at: float


class ScoutClient:
    """Talks to the Scout box. Construct with no arguments for production
    shape; tests construct with a fake transport."""

    def __init__(
        self,
        base_url: str | None = None,
        timeout: float = _TIMEOUT_SECONDS,
        transport=None,
    ) -> None:
        self._base_url = (base_url if base_url is not None else os.getenv("FORGE_SCOUT_URL") or "").strip().rstrip("/")
        self._timeout = timeout
        self._transport = transport  # callable(url, payload, timeout) -> str | None
        self._cache: dict[str, _CacheEntry] = {}

    # -- cache -----------------------------------------------------------

    def _purge(self) -> None:
        now = time.monotonic()
        dead = [k for k, v in self._cache.items() if v.expires_at <= now]
        for k in dead:
            del self._cache[k]

    def cached(self, cache_key: str) -> str | None:
        self._purge()
        entry = self._cache.get(cache_key)
        if entry is None:
            return None
        return entry.brief

    def _store(self, cache_key: str, brief: str) -> None:
        self._purge()
        self._cache[cache_key] = _CacheEntry(
            brief=brief, expires_at=time.monotonic() + _CACHE_TTL_SECONDS
        )

    # -- egress ----------------------------------------------------------

    def execute(self, brief) -> str | None:
        """Run the mission brief. Returns the cited brief text, or None.

        ``brief`` is a ScoutMissionBrief from scout_gate. The only thing
        that leaves this process is the scrubbed keyword tuple + question;
        the returned text is treated as untrusted by the caller."""
        from .scout_gate import ScoutMissionBrief  # local import: no cycle

        if not isinstance(brief, ScoutMissionBrief):
            return None
        if not self._base_url and self._transport is None:
            # No box configured — SimRunner's default. Fail closed, no network.
            return None

        hit = self.cached(brief.cache_key)
        if hit is not None:
            return hit

        payload = {
            "keywords": list(brief.keywords),
            "question": brief.question,
            "domain": brief.domain,
            "cache_key": brief.cache_key,
        }

        if self._transport is not None:
            try:
                text = self._transport(self._base_url, payload, self._timeout)
            except Exception:
                return None
        else:
            text = self._post(payload)

        if not text:
            return None
        self._store(brief.cache_key, text)
        return text

    def _post(self, payload: dict) -> str | None:
        url = f"{self._base_url}/v1/research"
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(
            url,
            data=data,
            headers={
                "Content-Type": "application/json",
                "User-Agent": "Forge-ScoutClient/1.0",
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=self._timeout) as resp:
                if resp.status != 200:
                    return None
                raw = resp.read()
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError, OSError, ValueError):
            return None
        try:
            parsed = json.loads(raw.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError):
            return None
        if not isinstance(parsed, dict):
            return None
        text = parsed.get("brief")
        if not isinstance(text, str) or not text.strip():
            return None
        # Cap so a runaway box cannot stuff the prompt.
        return text.strip()[:4000]
