#!/usr/bin/env python3
"""Start the Dummy Lambda wrapper with the loadtest guard installed.

Binds 127.0.0.1 only. Refuses to start unless ARIA_BEDROCK_ENABLED and
ARIA_VOICE_ENABLED are exactly ``false``. Adds GET /__loadtest/guards so the
k6 teardown can prove Bedrock, ElevenLabs, and Fish Audio were never touched.
"""

from __future__ import annotations

import json
import logging
import os
import sys
from pathlib import Path
from urllib.parse import urlparse

LOADTEST_DIR = Path(__file__).resolve().parent
REPO_ROOT = LOADTEST_DIR.parents[1]
sys.path.insert(0, str(LOADTEST_DIR))

from guard import install, persist, snapshot, total  # noqa: E402
from preflight import assert_disabled_flags, assert_loopback_host  # noqa: E402

install()

sys.path.insert(0, str(REPO_ROOT))
from backend.dev_server import ForgeDevHandler, HOST, PORT  # noqa: E402
from http.server import ThreadingHTTPServer  # noqa: E402


class LoadtestHandler(ForgeDevHandler):
    def _dispatch(self) -> None:
        parsed = urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"
        if self.command == "GET" and path == "/__loadtest/guards":
            payload = {
                "ok": total() == 0,
                "counts": persist(),
                "total": total(),
            }
            body = json.dumps(payload).encode("utf-8")
            self.send_response(200)
            self.send_header("content-type", "application/json")
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return
        super()._dispatch()


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(name)s: %(message)s")
    try:
        assert_disabled_flags(os.environ)
        assert_loopback_host(HOST)
    except ValueError as exc:
        print(f"loadtest server refused to start: {exc}", file=sys.stderr)
        raise SystemExit(2) from exc

    persist()
    server = ThreadingHTTPServer((HOST, PORT), LoadtestHandler)
    print(f"Forge loadtest Dummy server listening on http://{HOST}:{PORT}")
    print(f"Guard counters: {snapshot()}")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down.")
        server.server_close()
        print(f"Guard counters at exit: {persist()} total={total()}")


if __name__ == "__main__":
    main()
