#!/usr/bin/env python3
"""Local HTTP server wrapping the Lambda handler — runs at http://127.0.0.1:3001."""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

LAMBDA_DIR = Path(__file__).resolve().parents[1] / "infra" / "terraform" / "lambda"
sys.path.insert(0, str(LAMBDA_DIR))

from handler import handler  # noqa: E402

PORT = int(os.getenv("PORT", "3001"))
HOST = os.getenv("HOST", "127.0.0.1")


class ForgeDevHandler(BaseHTTPRequestHandler):
    def log_message(self, format: str, *args) -> None:  # noqa: A003
        sys.stdout.write(f"[dev] {self.address_string()} - {format % args}\n")

    def _dispatch(self) -> None:
        length = int(self.headers.get("Content-Length", "0") or 0)
        raw_body = self.rfile.read(length) if length else b""
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        event = {
            "requestContext": {"http": {"method": self.command, "path": path}},
            "headers": {k.lower(): v for k, v in self.headers.items()},
            "queryStringParameters": {},
        }
        if parsed.query:
            from urllib.parse import parse_qs

            event["queryStringParameters"] = {
                key: values[0] for key, values in parse_qs(parsed.query).items() if values
            }
        if raw_body:
            event["body"] = raw_body.decode("utf-8")

        response = handler(event, None)
        status = int(response.get("statusCode", 500))
        body = response.get("body", "{}")
        headers = response.get("headers") or {}

        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(body.encode("utf-8") if isinstance(body, str) else body)

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch()

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch()

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch()

    def do_PATCH(self) -> None:  # noqa: N802
        self._dispatch()

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch()


def main() -> None:
    server = ThreadingHTTPServer((HOST, PORT), ForgeDevHandler)
    print(f"Forge dev server listening on http://{HOST}:{PORT}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()


if __name__ == "__main__":
    main()