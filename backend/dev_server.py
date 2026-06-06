#!/usr/bin/env python3
"""Local Forge API dev server — mirrors API Gateway + Lambda for frontend development."""

from __future__ import annotations

import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

API_DIR = Path(__file__).resolve().parent / "api"
sys.path.insert(0, str(API_DIR))

from handler import handler  # noqa: E402

HOST = os.environ.get("FORGE_DEV_HOST", "127.0.0.1")
PORT = int(os.environ.get("FORGE_DEV_PORT", "3001"))
TEST_USER = os.environ.get("FORGE_TEST_USER_ID", "test-user-00000000")

os.environ.setdefault("FORGE_TEST_USER_ID", TEST_USER)
os.environ.setdefault("ENVIRONMENT", "development")


class ForgeDevHandler(BaseHTTPRequestHandler):
    server_version = "ForgeDev/1.0"

    def log_message(self, format: str, *args) -> None:  # noqa: A003
        sys.stdout.write("%s - %s\n" % (self.address_string(), format % args))

    def _cors_headers(self) -> dict[str, str]:
        return {
            "Access-Control-Allow-Origin": "*",
            "Access-Control-Allow-Headers": "authorization,content-type",
            "Access-Control-Allow-Methods": "DELETE,GET,OPTIONS,PATCH,POST,PUT",
        }

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(204)
        for key, value in self._cors_headers().items():
            self.send_header(key, value)
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        self._dispatch("GET")

    def do_POST(self) -> None:  # noqa: N802
        self._dispatch("POST")

    def do_PUT(self) -> None:  # noqa: N802
        self._dispatch("PUT")

    def do_PATCH(self) -> None:  # noqa: N802
        self._dispatch("PATCH")

    def do_DELETE(self) -> None:  # noqa: N802
        self._dispatch("DELETE")

    def _dispatch(self, method: str) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        query = {k: v[-1] for k, v in parse_qs(parsed.query).items()}

        content_length = int(self.headers.get("Content-Length", 0))
        raw_body = self.rfile.read(content_length) if content_length else b""
        body = raw_body.decode("utf-8") if raw_body else None

        event = {
            "requestContext": {"http": {"method": method, "path": path}},
            "queryStringParameters": query,
            "headers": {k.lower(): v for k, v in self.headers.items()},
        }
        if body:
            event["body"] = body

        result = handler(event, None)
        status = int(result.get("statusCode", 500))
        headers = {**self._cors_headers(), **(result.get("headers") or {})}
        payload = result.get("body", "{}")

        self.send_response(status)
        for key, value in headers.items():
            self.send_header(key, value)
        self.end_headers()
        if isinstance(payload, str):
            self.wfile.write(payload.encode("utf-8"))
        else:
            self.wfile.write(json.dumps(payload).encode("utf-8"))


def main() -> None:
    httpd = ThreadingHTTPServer((HOST, PORT), ForgeDevHandler)
    print(f"Forge dev API running at http://{HOST}:{PORT}")
    print(f"Test user: {TEST_USER}")
    print("Press Ctrl+C to stop.")
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        httpd.server_close()


if __name__ == "__main__":
    main()
