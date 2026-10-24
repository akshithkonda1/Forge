"""ARIA voice — Fish Audio only. Dummy stays local; the key never leaves Lambda."""

from __future__ import annotations

import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from responses import RouteError  # noqa: E402
from services import fish_audio_voice  # noqa: E402
from services import provider_secrets  # noqa: E402
from security import PAID_AI_ROUTES  # noqa: E402

from test_backend_handler import body, event  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SWIFT_VOICE = REPO / "ForgeSwift" / "ForgeSwift" / "AriaCharacterVoice.swift"
SWIFT_SESSION = REPO / "ForgeSwift" / "ForgeSwift" / "AriaVoiceSession.swift"
SWIFT_SPOKEN = REPO / "ForgeSwift" / "ForgeSwift" / "AriaSpokenVoice.swift"
ELEVEN = REPO / "backend" / "infra" / "lambda" / "services" / "elevenlabs_voice.py"


class VoiceStackConsolidationTests(unittest.TestCase):
    def test_elevenlabs_slot_is_disabled_not_the_live_mouth(self):
        self.assertTrue(ELEVEN.exists())
        src = ELEVEN.read_text(encoding="utf-8")
        self.assertIn("ARIA_ELEVENLABS_VOICE_ENABLED", src)
        self.assertIn("reserved", src.lower())
        self.assertNotIn("https://", src)
        os.environ.pop("ARIA_ELEVENLABS_VOICE_ENABLED", None)
        from services import elevenlabs_voice
        from responses import RouteError

        self.assertFalse(elevenlabs_voice.voice_enabled())
        with self.assertRaises(RouteError) as raised:
            elevenlabs_voice.synthesize("I'm ARIA.")
        self.assertEqual(raised.exception.code, "elevenlabs_disabled")

    def test_removed_routes_are_not_found(self):
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        gone = (
            ("GET", "/ai/voice/bootstrap"),
            ("POST", "/ai/voice/tool"),
            ("POST", "/ai/voice/design"),
            ("POST", "/ai/voice/fish-tts"),
        )
        for method, path in gone:
            response = handler(event(method, path, {} if method != "GET" else None, user_id="user-1"), None)
            self.assertEqual(response["statusCode"], 404, path)

    def test_dummy_session_file_mentions_dummy_first(self):
        session = SWIFT_SESSION.read_text(encoding="utf-8")
        self.assertIn("AriaVoiceTransport.resolveCurrent", session)
        self.assertIn("shouldUseTestReadyDummy", SWIFT_VOICE.read_text(encoding="utf-8"))
        self.assertNotIn("api.elevenlabs.io", SWIFT_VOICE.read_text(encoding="utf-8"))

    def test_fish_audio_hex_path_uses_the_single_speak_route(self):
        voice = SWIFT_VOICE.read_text(encoding="utf-8")
        presence = (
            REPO / "ForgeSwift" / "ForgeSwift" / "AriaPresence.swift"
        ).read_text(encoding="utf-8")
        core = (
            REPO
            / "ForgeSwift"
            / "ForgeCore"
            / "Sources"
            / "ForgeCore"
            / "Intelligence"
            / "AriaFishAudioVoice.swift"
        ).read_text(encoding="utf-8")
        self.assertIn("shouldEnqueueFishAudioViaBackend", voice)
        self.assertIn("speakViaFishAudioBackend", presence)
        self.assertIn("ForgeAPI.send", presence)
        self.assertIn("ai/voice/speak", core)
        self.assertNotIn("ai/voice/fish-tts", core)
        self.assertIn("dummy-offline", core)
        self.assertIn("s2.1-pro-free", core)
        self.assertIn("s2.1-pro", core)
        self.assertNotIn('"s1"', core)
        self.assertIn("Bearer", core)
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
            "TestFlight Dummy-offline has no ConvAI — Release fill-in must run",
        )
        self.assertIn("return transport.usesOnDeviceBrain", mouth)

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
                "ELEVENLABS_ARIA_VOICE_ID",
                "ELEVENLABS_ARIA_AGENT_ID",
                "FISH_AUDIO_API_KEY",
                "FISH_AUDIO_MODEL",
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

    def test_env_key_is_used_without_boto(self):
        os.environ["ELEVENLABS_API_KEY"] = "sk_test_live_key"
        creds = provider_secrets.load_ai_provider_secret(
            get_secret_value=lambda _arn: '{"ELEVENLABS_API_KEY":"from-secret"}'
        )
        self.assertEqual(creds["ELEVENLABS_API_KEY"], "sk_test_live_key")

    def test_secret_fills_when_env_empty(self):
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ["AI_PROVIDER_SECRET_ARN"] = "arn:aws:secretsmanager:us-east-1:1:secret:ai"
        creds = provider_secrets.load_ai_provider_secret(
            get_secret_value=lambda _arn: json.dumps(
                {
                    "ELEVENLABS_API_KEY": "from-secret",
                    "ELEVENLABS_ARIA_VOICE_ID": "voice_aria",
                    "ELEVENLABS_ARIA_AGENT_ID": "agent_aria",
                }
            )
        )
        self.assertEqual(creds["ELEVENLABS_API_KEY"], "from-secret")
        self.assertEqual(creds["ELEVENLABS_ARIA_VOICE_ID"], "voice_aria")

    def test_fish_audio_env_key_is_used_without_boto(self):
        os.environ["FISH_AUDIO_API_KEY"] = "fish_test_live_key"
        os.environ["FISH_AUDIO_MODEL"] = "s2.1-pro-free"
        creds = provider_secrets.load_ai_provider_secret(
            get_secret_value=lambda _arn: '{"FISH_AUDIO_API_KEY":"from-secret"}'
        )
        self.assertEqual(creds["FISH_AUDIO_API_KEY"], "fish_test_live_key")
        self.assertEqual(creds["FISH_AUDIO_MODEL"], "s2.1-pro-free")
        self.assertEqual(
            provider_secrets._PARAMETER_ENV["FISH_AUDIO_API_KEY"],
            "FISH_AUDIO_API_KEY_PARAMETER_NAME",
        )

    def test_fish_audio_secret_fills_when_env_empty(self):
        os.environ.pop("FISH_AUDIO_API_KEY", None)
        os.environ.pop("FISH_AUDIO_MODEL", None)
        os.environ["AI_PROVIDER_SECRET_ARN"] = "arn:aws:secretsmanager:us-east-1:1:secret:ai"
        creds = provider_secrets.load_ai_provider_secret(
            get_secret_value=lambda _arn: json.dumps(
                {
                    "FISH_AUDIO_API_KEY": "from-secret-fish",
                    "FISH_AUDIO_MODEL": "s2.1-pro-free",
                }
            )
        )
        self.assertEqual(creds["FISH_AUDIO_API_KEY"], "from-secret-fish")
        self.assertEqual(creds["FISH_AUDIO_MODEL"], "s2.1-pro-free")


class VoiceRouteTests(unittest.TestCase):
    def setUp(self):
        provider_secrets.reset_cache()
        fish_audio_voice.reset_cache()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ.pop("FISH_AUDIO_API_KEY", None)
        os.environ.pop("FISH_AUDIO_MODEL", None)
        os.environ.pop("FISH_AUDIO_USE_PAID", None)
        os.environ.pop("AI_PROVIDER_SECRET_ARN", None)
        os.environ.pop("ARIA_FISH_VOICE_ENABLED", None)

    def tearDown(self):
        provider_secrets.reset_cache()
        fish_audio_voice.reset_cache()
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ.pop("FISH_AUDIO_API_KEY", None)
        os.environ.pop("FISH_AUDIO_MODEL", None)
        os.environ.pop("FISH_AUDIO_USE_PAID", None)
        os.environ.pop("ARIA_FISH_VOICE_ENABLED", None)

    def test_catalog_without_key_is_fallback_not_a_key_leak(self):
        response = handler(event("GET", "/ai/voice", user_id="user-1"), None)
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["source"], "fallback")
        self.assertEqual(payload["model"], "s2.1-pro-free")
        self.assertNotIn("bearer", json.dumps(payload).lower())

    def test_speak_without_key_is_unconfigured(self):
        os.environ["ARIA_FISH_VOICE_ENABLED"] = "true"
        response = handler(
            event("POST", "/ai/voice/speak", {"text": "I'm ARIA."}, user_id="user-1"),
            None,
        )
        self.assertEqual(response["statusCode"], 503)
        payload = body(response)
        self.assertEqual(payload["code"], "fish_unconfigured")
        blob = json.dumps(payload).lower()
        self.assertNotIn("bearer", blob)
        self.assertNotIn("authorization", blob)
        self.assertIn("/ai/voice/speak", PAID_AI_ROUTES)

    def test_speak_empty_text_is_rejected(self):
        os.environ["ARIA_FISH_VOICE_ENABLED"] = "true"
        os.environ["FISH_AUDIO_API_KEY"] = "fish_test_never_echo"
        provider_secrets.reset_cache()
        response = handler(
            event("POST", "/ai/voice/speak", {"text": "   "}, user_id="user-1"),
            None,
        )
        self.assertEqual(response["statusCode"], 400)
        self.assertEqual(body(response)["code"], "fish_audio_empty_text")

    def test_speak_uses_bearer_and_free_model_and_never_echoes_the_key(self):
        import base64

        os.environ["ARIA_FISH_VOICE_ENABLED"] = "true"
        os.environ["FISH_AUDIO_API_KEY"] = "fish_test_never_echo"
        os.environ["FISH_AUDIO_MODEL"] = "s2.1-pro-free"
        provider_secrets.reset_cache()
        audio = b"ID3fake-mp3"

        def fake_http(method, url, headers, raw):
            self.assertEqual(method, "POST")
            self.assertEqual(url, fish_audio_voice.FISH_TTS_URL)
            self.assertEqual(headers.get("Authorization"), "Bearer fish_test_never_echo")
            self.assertEqual(headers.get("model"), "s2.1-pro-free")
            self.assertEqual(headers.get("Content-Type"), "application/json")
            payload = json.loads(raw.decode("utf-8"))
            self.assertEqual(payload["text"], "I'm ARIA.")
            self.assertEqual(payload["format"], "mp3")
            return 200, audio

        synthesized = fish_audio_voice.synthesize("  I'm ARIA.  ", http=fake_http)
        self.assertEqual(synthesized, audio)

        with patch.object(fish_audio_voice, "_stdlib_http", fake_http):
            response = handler(
                event(
                    "POST",
                    "/ai/voice/speak",
                    {"text": "I'm ARIA.", "voice_id": "voice-warm-1"},
                    user_id="user-1",
                ),
                None,
            )

        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertEqual(payload["format"], "mp3")
        self.assertEqual(payload["model"], "s2.1-pro-free")
        self.assertEqual(payload["voice_id"], "voice-warm-1")
        self.assertEqual(payload["audio_base64"], base64.b64encode(audio).decode("ascii"))
        blob = json.dumps(payload)
        self.assertNotIn("fish_test_never_echo", blob)
        self.assertNotIn("Authorization", blob)
        self.assertNotIn("Bearer", blob)

    def test_unknown_model_and_s1_fall_back_to_free_tier(self):
        self.assertEqual(fish_audio_voice.sanitize_model("not-a-model"), "s2.1-pro-free")
        self.assertEqual(fish_audio_voice.sanitize_model(None), "s2.1-pro-free")
        self.assertEqual(fish_audio_voice.sanitize_model("s1"), "s2.1-pro-free")
        self.assertEqual(fish_audio_voice.DEFAULT_MODEL, "s2.1-pro-free")
        headers = fish_audio_voice.build_headers("fish_test_never_echo", "garbage")
        self.assertEqual(headers["Authorization"], "Bearer fish_test_never_echo")
        self.assertEqual(headers["model"], "s2.1-pro-free")

    def test_preview_uses_the_sample_line(self):
        seen: list[str] = []

        def fake_http(_method, _url, _headers, raw):
            seen.append(json.loads(raw.decode("utf-8"))["text"])
            return 200, b"ID3"

        os.environ["ARIA_FISH_VOICE_ENABLED"] = "true"
        os.environ["FISH_AUDIO_API_KEY"] = "fish_test_never_echo"
        spoken = fish_audio_voice.speak(
            {"preview": True, "voice_id": "voice-warm-1"},
            user_id="user-1",
            http=fake_http,
        )
        self.assertEqual(seen, [fish_audio_voice.PREVIEW_TEXT])
        self.assertTrue(spoken["preview"])


if __name__ == "__main__":
    unittest.main()
