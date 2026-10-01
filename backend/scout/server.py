"""Scout's HTTP surface. Stdlib ThreadingHTTPServer behind Caddy (TLS).

The process stays up. It does not search until gate.evaluate says the turn
is a lookup. The mission brief is scrubbed keywords only. Pages and the
mission are dumped when the run ends. Query text is never logged.

Routes:
  POST /gate       {prompt|query} -> activate decision, no search
  POST /research   {prompt|query, topic?} -> brief, or activate=false
  GET  /healthz
"""

from __future__ import annotations

import hmac
import json
import logging
import os
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

from .agent import Scout
from .gate import evaluate
from .retention import working_set

_log = logging.getLogger("forge.scout")

MAX_BODY_BYTES = 4096
MAX_CONCURRENT_JOBS = 4
PER_USER_PER_HOUR = 30


class RateLimiter:
    def __init__(self, *, per_hour: int = PER_USER_PER_HOUR, concurrent: int = MAX_CONCURRENT_JOBS, clock=time.monotonic) -> None:
        self._per_hour = per_hour
        self._clock = clock
        self._hits: dict[str, list[float]] = {}
        self._lock = threading.Lock()
        self._slots = threading.BoundedSemaphore(concurrent)

    def allow(self, user: str) -> bool:
        now = self._clock()
        with self._lock:
            window = [t for t in self._hits.get(user, []) if now - t < 3600]
            if len(window) >= self._per_hour:
                self._hits[user] = window
                return False
            window.append(now)
            self._hits[user] = window
            return True

    def acquire(self) -> bool:
        return self._slots.acquire(blocking=False)

    def release(self) -> None:
        self._slots.release()


def authorized(header_value: str | None, expected: str | None) -> bool:
    if not expected or not header_value:
        return False
    return hmac.compare_digest(header_value.encode(), expected.encode())


def make_handler(scout: Scout, limiter: RateLimiter, shared_key: str | None, brain_name: str):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ForgeScout/1.1"

        def log_message(self, fmt: str, *args) -> None:
            _log.info("%s %s", self.command, self.path.split("?", 1)[0])

        def _send(self, status: int, payload: dict) -> None:
            body = json.dumps(payload).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self) -> None:
            if self.path == "/healthz":
                self._send(200, {"ok": True, "brain": brain_name})
                return
            self._send(404, {"message": "Not found."})

        def _read_body(self) -> dict | None:
            try:
                length = int(self.headers.get("Content-Length") or 0)
            except ValueError:
                length = -1
            if length <= 0 or length > MAX_BODY_BYTES:
                self._send(400, {"message": "Body must be JSON under 4 KB."})
                return None
            try:
                body = json.loads(self.rfile.read(length).decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                self._send(400, {"message": "Body must be JSON."})
                return None
            if not isinstance(body, dict):
                self._send(400, {"message": "Body must be a JSON object."})
                return None
            return body

        def _prompt(self, body: dict) -> str | None:
            raw = body.get("prompt") if isinstance(body.get("prompt"), str) else body.get("query")
            if not isinstance(raw, str) or not raw.strip():
                self._send(400, {"message": "Body must include a 'prompt' or 'query' string."})
                return None
            return raw

        def do_POST(self) -> None:
            path = self.path.split("?", 1)[0]
            if path not in ("/research", "/gate"):
                self._send(404, {"message": "Not found."})
                return
            if not authorized(self.headers.get("x-scout-key"), shared_key):
                self._send(401, {"message": "Unauthorized."})
                return
            user = (self.headers.get("x-forge-user") or "anonymous").strip()[:128]
            body = self._read_body()
            if body is None:
                return
            prompt = self._prompt(body)
            if prompt is None:
                return
            decision = evaluate(prompt)
            if path == "/gate" or not decision.activate or decision.mission is None:
                self._send(200, decision.as_dict())
                return
            if not limiter.allow(user):
                self._send(429, {"message": "Scout is resting — try again later."})
                return
            if not limiter.acquire():
                self._send(429, {"message": "Scout is busy — try again shortly."})
                return
            try:
                started = time.monotonic()
                with working_set() as held:
                    held.mission = decision.mission.question
                    brief = scout.research(held.mission, topic=str(body.get("topic") or ""))
                brief["activate"] = True
                brief["reason"] = decision.reason
                brief["mission"] = decision.mission.as_dict()
                _log.info(
                    "research brain=%s sources=%d cached=%s ms=%d",
                    brief.get("brain"), len(brief.get("sources") or []), brief.get("cached"),
                    int((time.monotonic() - started) * 1000),
                )
                self._send(200, brief)
            except Exception:
                _log.exception("research failed")
                self._send(502, {"message": "Scout could not finish that lookup."})
            finally:
                limiter.release()

    return Handler


def serve(host: str = "0.0.0.0", port: int | None = None) -> None:
    from .brain import default_brain

    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
    shared_key = os.getenv("SCOUT_SHARED_KEY") or None
    if not shared_key:
        _log.warning("SCOUT_SHARED_KEY is unset — every /research call will be refused (fail-closed).")
    brain = default_brain()
    scout = Scout(brain=brain)
    handler = make_handler(scout, RateLimiter(), shared_key, getattr(brain, "name", "rules"))
    port = port or int(os.getenv("SCOUT_PORT") or 8088)
    httpd = ThreadingHTTPServer((host, port), handler)
    _log.info("Scout listening on %s:%d (brain=%s)", host, port, getattr(brain, "name", "rules"))
    httpd.serve_forever()
