"""Optional local-only Dummy chat HTTP server.

Refused unless ``ARIA_LOCAL_CHAT=1`` (or ``FORGE_ARIA_LOCAL_CHAT=1``) and the
environment is not production-like. Not registered in Terraform, API Gateway,
or the Lambda handler.
"""

from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from urllib.parse import urlparse

from backend._paths import ensure_lambda_on_path

ensure_lambda_on_path()

from responses import RouteError  # noqa: E402
from security import is_production_like  # noqa: E402

from .session import run_local_chat_turn


def local_dummy_chat_allowed() -> bool:
    if is_production_like():
        return False
    raw = (
        os.getenv("ARIA_LOCAL_CHAT") or os.getenv("FORGE_ARIA_LOCAL_CHAT") or ""
    ).strip().lower()
    return raw in {"1", "true", "yes", "on"}


def handle_post_ai_chat_local(body: dict[str, Any], *, user_id: str = "local") -> dict[str, Any]:
    """In-process adapter. Raises ``RouteError(403)`` when the local flag is off."""
    if not local_dummy_chat_allowed():
        raise RouteError(403, "Local Dummy chat is off. Set ARIA_LOCAL_CHAT=1.")
    return run_local_chat_turn(body if isinstance(body, dict) else {}, user_id=user_id)


class _LocalChatHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt: str, *args: Any) -> None:  # noqa: A003
        return

    def _send(self, status: int, payload: dict[str, Any]) -> None:
        raw = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path not in {"/ai/chat/local", "/chat"}:
            self._send(404, {"error": "not found"})
            return
        if not local_dummy_chat_allowed():
            self._send(403, {"error": "Local Dummy chat is off. Set ARIA_LOCAL_CHAT=1."})
            return
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b"{}"
        try:
            body = json.loads(raw.decode("utf-8") or "{}")
        except json.JSONDecodeError:
            self._send(400, {"error": "invalid json"})
            return
        try:
            result = handle_post_ai_chat_local(body, user_id="local")
        except RouteError as exc:
            self._send(int(getattr(exc, "status_code", 403) or 403), {"error": str(exc)})
            return
        except Exception as exc:  # noqa: BLE001
            self._send(500, {"error": str(exc)})
            return
        self._send(200, result)


SERVE_HOST = "127.0.0.1"


def serve(host: str = SERVE_HOST, port: int = 8765) -> None:
    """Block on a local HTTP server. Refuses to bind when the flag is off.

    Binds ``127.0.0.1`` only. Any other ``--host`` is refused.
    """
    if not local_dummy_chat_allowed():
        raise SystemExit("refused: set ARIA_LOCAL_CHAT=1 (and not a production-like ENVIRONMENT)")
    bind = (host or "").strip()
    if bind != SERVE_HOST:
        raise SystemExit(f"refused: --serve binds {SERVE_HOST} only")
    server = ThreadingHTTPServer((SERVE_HOST, port), _LocalChatHandler)
    print(f"ARIA Dummy local chat on http://{SERVE_HOST}:{port}/ai/chat/local")
    server.serve_forever()
