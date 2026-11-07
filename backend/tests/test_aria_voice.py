"""ARIA voice — Kokoro only. Hex never synthesizes. TTS text stays on the phone."""

from __future__ import annotations

import json
import os
import socket
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from security import PAID_AI_ROUTES  # noqa: E402
from services import provider_secrets  # noqa: E402

from test_backend_handler import body, event  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SWIFT_VOICE = REPO / "ForgeSwift" / "ForgeSwift" / "AriaCharacterVoice.swift"
SWIFT_SESSION = REPO / "ForgeSwift" / "ForgeSwift" / "AriaVoiceSession.swift"
SWIFT_SPOKEN = REPO / "ForgeSwift" / "ForgeSwift" / "AriaSpokenVoice.swift"
SWIFT_PRESENCE = REPO / "ForgeSwift" / "ForgeSwift" / "AriaPresence.swift"
KOKORO_CORE = (
    REPO
    / "ForgeSwift"
    / "ForgeCore"
    / "Sources"
    / "ForgeCore"
    / "Intelligence"
    / "AriaKokoroVoice.swift"
)
KOKORO_PY = REPO / "backend" / "infra" / "lambda" / "services" / "kokoro_voice.py"


class _BlockedNetwork:
    def __enter__(self):
        def blocked(*_a, **_k):
            raise AssertionError("network must stay blocked for Kokoro-only voice")

        self._socket = patch.object(socket, "socket", side_effect=blocked)
        self._create = patch.object(socket, "create_connection", side_effect=blocked)
        self._socket.start()
        self._create.start()
        return self

    def __exit__(self, *_exc):
        self._create.stop()
        self._socket.stop()
        return False


class VoiceStackConsolidationTests(unittest.TestCase):
    def test_cloud_vendor_modules_are_gone(self):
        services = REPO / "backend" / "infra" / "lambda" / "services"
        self.assertFalse((services / "fish_audio_voice.py").exists())
        self.assertFalse((services / "polly_voice.py").exists())
        self.assertFalse((services / "elevenlabs_voice.py").exists())
        self.assertTrue(KOKORO_PY.exists())
        src = KOKORO_PY.read_text(encoding="utf-8")
        self.assertIn("af_heart", src)
        self.assertIn("Apache-2.0", src)
        self.assertNotIn("https://", src)

    def test_removed_routes_are_not_found(self):
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        gone = (
            ("GET", "/ai/voice/bootstrap"),
            ("POST", "/ai/voice/tool"),
            ("POST", "/ai/voice/design"),
            ("POST", "/ai/voice/fish-tts"),
            ("POST", "/ai/voice/speak"),
        )
        for method, path in gone:
            response = handler(event(method, path, {} if method != "GET" else None, user_id="user-1"), None)
            self.assertEqual(response["statusCode"], 404, path)
        self.assertNotIn("/ai/voice/speak", PAID_AI_ROUTES)

    def test_dummy_session_file_mentions_dummy_first(self):
        session = SWIFT_SESSION.read_text(encoding="utf-8")
        self.assertIn("AriaVoiceTransport.resolveCurrent", session)
        self.assertIn("shouldUseTestReadyDummy", SWIFT_VOICE.read_text(encoding="utf-8"))
        self.assertNotIn("api.elevenlabs.io", SWIFT_VOICE.read_text(encoding="utf-8"))
        self.assertNotIn("api.fish.audio", SWIFT_VOICE.read_text(encoding="utf-8"))

    def test_ios_mouth_is_kokoro_only(self):
        voice = SWIFT_VOICE.read_text(encoding="utf-8")
        presence = SWIFT_PRESENCE.read_text(encoding="utf-8")
        core = KOKORO_CORE.read_text(encoding="utf-8")
        self.assertIn("shouldEnqueueKokoro", voice)
        self.assertIn("AriaKokoroEngine.speak", presence)
        self.assertNotIn("speakViaFishAudio", presence)
        self.assertNotIn("ForgeAPI.send", presence)
        self.assertIn("kokoro-82m", core)
        self.assertIn("af_heart", core)
        self.assertIn("Apache-2.0", core)
        self.assertNotIn("s2.1-pro-free", core)
        self.assertNotIn("Bearer", core)
        self.assertNotIn("sk_", core)


class VoiceMustRunContractTests(unittest.TestCase):
    """Dummy-offline / Voice-mode start must actually produce a mouth."""

    def test_dummy_fill_in_is_not_debug_gated(self):
        voice = SWIFT_VOICE.read_text(encoding="utf-8")
        start = voice.index("static func allowsDummyFillIn")
        end = voice.index("static func shouldEnqueueAppleUtterance")
        mouth = voice[start:end]
        self.assertNotIn(
            "guard isDebugBuild",
            mouth,
            "TestFlight Dummy-offline has no cloud mouth — Release Kokoro must run",
        )
        self.assertIn("return true", mouth)

    def test_new_voice_session_unmutes_so_the_mouth_can_run(self):
        spoken = SWIFT_SPOKEN.read_text(encoding="utf-8")
        session = SWIFT_SESSION.read_text(encoding="utf-8")
        self.assertIn("shouldUnmuteForNewSession", spoken)
        self.assertIn("unmuteBecauseVoiceSessionStarted", spoken)
        self.assertIn("!isResumingExistingSession", spoken)
        self.assertIn("unmuteBecauseVoiceSessionStarted()", session)
        self.assertIn("shouldUnmuteForNewSession(isResumingExistingSession: resuming)", session)


class ProviderSecretTests(unittest.TestCase):
    def setUp(self):
        provider_secrets.reset_cache()
        self._saved = {
            key: os.environ.get(key)
            for key in (
                "ELEVENLABS_API_KEY",
                "FISH_AUDIO_API_KEY",
                "AI_PROVIDER_SECRET_ARN",
            )
        }

    def tearDown(self):
        provider_secrets.reset_cache()
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_voice_vendor_keys_are_not_loaded(self):
        os.environ["ELEVENLABS_API_KEY"] = "sk_test_live_key"
        os.environ["FISH_AUDIO_API_KEY"] = "fish_test_live_key"
        creds = provider_secrets.load_ai_provider_secret(
            get_secret_value=lambda _arn: json.dumps(
                {
                    "ELEVENLABS_API_KEY": "from-secret",
                    "FISH_AUDIO_API_KEY": "from-secret-fish",
                }
            )
        )
        self.assertNotIn("ELEVENLABS_API_KEY", creds)
        self.assertNotIn("FISH_AUDIO_API_KEY", creds)
        self.assertNotIn("FISH_AUDIO_API_KEY", provider_secrets._PARAMETER_ENV)
        self.assertNotIn("ELEVENLABS_API_KEY", provider_secrets._KEYS)


class VoiceRouteTests(unittest.TestCase):
    def setUp(self):
        provider_secrets.reset_cache()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ.pop("FISH_AUDIO_API_KEY", None)
        os.environ.pop("AI_PROVIDER_SECRET_ARN", None)
        os.environ.pop("ARIA_FISH_VOICE_ENABLED", None)

    def tearDown(self):
        provider_secrets.reset_cache()
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ.pop("FISH_AUDIO_API_KEY", None)

    def test_catalog_is_kokoro_presets_with_network_blocked(self):
        with _BlockedNetwork():
            response = handler(event("GET", "/ai/voice", user_id="user-1"), None)
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["source"], "kokoro")
        self.assertEqual(payload["model"], "kokoro-82m")
        self.assertEqual(payload["aria_preset"], "af_heart")
        self.assertEqual(payload["featured"][0]["voice_id"], "af_heart")
        self.assertNotIn("bearer", json.dumps(payload).lower())
        self.assertNotIn("fish", json.dumps(payload).lower())

    def test_speak_route_is_gone_with_network_blocked(self):
        with _BlockedNetwork():
            response = handler(
                event("POST", "/ai/voice/speak", {"text": "I'm ARIA."}, user_id="user-1"),
                None,
            )
        self.assertEqual(response["statusCode"], 404)


if __name__ == "__main__":
    unittest.main()
