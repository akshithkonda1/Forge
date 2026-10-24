"""Kokoro catalog — local presets, no sockets, no cloud speak."""

from __future__ import annotations

import os
import socket
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from responses import RouteError  # noqa: E402
from security import PAID_AI_ROUTES  # noqa: E402
from services import kokoro_voice  # noqa: E402
from services import voice_provider  # noqa: E402

from test_backend_handler import body, event  # noqa: E402

REPO = Path(__file__).resolve().parents[2]


class _BlockedNetwork:
    def __enter__(self):
        def blocked(*_a, **_k):
            raise AssertionError("Kokoro catalog must not open a socket")

        self._socket = patch.object(socket, "socket", side_effect=blocked)
        self._create = patch.object(socket, "create_connection", side_effect=blocked)
        self._socket.start()
        self._create.start()
        return self

    def __exit__(self, *_exc):
        self._create.stop()
        self._socket.stop()
        return False


class KokoroCatalogTests(unittest.TestCase):
    def setUp(self):
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def test_aria_preset_and_licenses(self):
        self.assertEqual(kokoro_voice.ARIA_PRESET, "af_heart")
        self.assertEqual(kokoro_voice.MODEL, "kokoro-82m")
        self.assertEqual(kokoro_voice.LICENSE, "Apache-2.0")
        self.assertEqual(kokoro_voice.PACKAGE, "mattmireles/kokoro-coreml")
        self.assertEqual(kokoro_voice.WEIGHTS, "hexgrad/Kokoro-82M")
        self.assertEqual(kokoro_voice.STARTER_BUNDLE_MB, 210)
        self.assertTrue(kokoro_voice.labels_avoid_trademarked_characters())
        self.assertEqual(kokoro_voice.sanitize_preset("s2.1-pro"), "af_heart")
        self.assertEqual(kokoro_voice.sanitize_preset("af_bella"), "af_bella")

    def test_catalog_and_persist_with_network_blocked(self):
        with _BlockedNetwork():
            listed = handler(event("GET", "/ai/voice", user_id="user-1"), None)
            self.assertEqual(listed["statusCode"], 200)
            payload = body(listed)
            self.assertEqual(payload["source"], "kokoro")
            self.assertEqual(payload["selected"]["voice_id"], "af_heart")
            saved = handler(
                event(
                    "PUT",
                    "/ai/voice",
                    {"profile_id": "ember"},
                    user_id="user-1",
                ),
                None,
            )
            self.assertEqual(saved["statusCode"], 200)
            self.assertEqual(body(saved)["selected"]["voice_id"], "af_bella")
            again = handler(event("GET", "/ai/voice", user_id="user-1"), None)
            self.assertEqual(body(again)["selected"]["profile_id"], "ember")

    def test_unknown_profile_is_400(self):
        with self.assertRaises(RouteError) as raised:
            kokoro_voice.save_profile("user-1", {"profile_id": "toph"})
        self.assertEqual(raised.exception.code, "kokoro_unknown_profile")

    def test_speak_is_not_a_paid_route(self):
        self.assertNotIn("/ai/voice/speak", PAID_AI_ROUTES)
        self.assertEqual(voice_provider.resolve_mouth(dummy=True), "kokoro")

    def test_source_files_never_call_fish_or_polly(self):
        src = (REPO / "backend" / "infra" / "lambda" / "services" / "kokoro_voice.py").read_text(
            encoding="utf-8"
        )
        self.assertNotIn("urllib", src)
        self.assertNotIn("boto3", src)
        self.assertNotIn("fish.audio", src)
        self.assertNotIn("synthesize", src)


if __name__ == "__main__":
    unittest.main()
