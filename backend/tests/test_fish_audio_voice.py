"""Fish Audio speak path — flag-off default, mocked HTTP only, no live key."""

from __future__ import annotations

import ast
import base64
import json
import os
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from backend.ai.simrunner.aria_simrunner import nyx_voice_check  # noqa: E402
from handler import handler  # noqa: E402
from responses import RouteError  # noqa: E402
from security import PAID_AI_ROUTES  # noqa: E402
from services import fish_audio_voice  # noqa: E402
from test_backend_handler import body, event  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
FISH_SRC = REPO / "backend" / "infra" / "lambda" / "services" / "fish_audio_voice.py"
ARIA_ROUTE_SRC = REPO / "backend" / "infra" / "lambda" / "routes" / "aria.py"

FAKE_MP3 = b"ID3\x04fake-mp3-bytes"


class _FishFlag:
    def __init__(self, enabled, key=None):
        self.enabled = enabled
        self.key = key

    def __enter__(self):
        self._flag = os.environ.get("ARIA_FISH_VOICE_ENABLED")
        self._key = os.environ.get("FISH_AUDIO_API_KEY")
        if self.enabled is None:
            os.environ.pop("ARIA_FISH_VOICE_ENABLED", None)
        else:
            os.environ["ARIA_FISH_VOICE_ENABLED"] = self.enabled
        if self.key is None:
            os.environ.pop("FISH_AUDIO_API_KEY", None)
        else:
            os.environ["FISH_AUDIO_API_KEY"] = self.key
        return self

    def __exit__(self, *exc):
        if self._flag is None:
            os.environ.pop("ARIA_FISH_VOICE_ENABLED", None)
        else:
            os.environ["ARIA_FISH_VOICE_ENABLED"] = self._flag
        if self._key is None:
            os.environ.pop("FISH_AUDIO_API_KEY", None)
        else:
            os.environ["FISH_AUDIO_API_KEY"] = self._key


def _fake_http(test, *, message, key="sk_fish_test", audio=FAKE_MP3):
    calls: list[tuple] = []

    def fake_http(method, url, headers, raw):
        calls.append((method, url, headers, raw))
        test.assertEqual(method, "POST")
        test.assertEqual(url, "https://api.fish.audio/v1/tts")
        test.assertEqual(headers.get("Authorization"), f"Bearer {key}")
        test.assertEqual(headers.get("model"), "s2.1-pro-free")
        test.assertEqual(headers.get("Content-Type"), "application/json")
        payload = json.loads(raw.decode("utf-8"))
        test.assertEqual(payload, {"text": message, "format": "mp3"})
        test.assertEqual(set(payload), {"text", "format"})
        return 200, audio

    return fake_http, calls


class FishFlagAndRouteTests(unittest.TestCase):
    def setUp(self):
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def test_speak_is_on_the_paid_ai_allowlist(self):
        self.assertIn("/ai/voice/speak", PAID_AI_ROUTES)

    def test_unset_flag_is_false_and_needs_no_key(self):
        with _FishFlag(None, key=None):
            self.assertFalse(fish_audio_voice.fish_voice_enabled())
            fake_http, calls = _fake_http(self, message="hi")
            with self.assertRaises(RouteError) as raised:
                fish_audio_voice.speak({"message": "hi"}, http=fake_http)
            self.assertEqual(raised.exception.status_code, 503)
            self.assertEqual(raised.exception.code, "fish_disabled")
            self.assertEqual(calls, [])

    def test_empty_flag_is_false(self):
        with _FishFlag("", key="sk_should_not_be_read"):
            self.assertFalse(fish_audio_voice.fish_voice_enabled())
            fake_http, calls = _fake_http(self, message="hi")
            with self.assertRaises(RouteError) as raised:
                fish_audio_voice.speak({"message": "hi"}, http=fake_http)
            self.assertEqual(raised.exception.code, "fish_disabled")
            self.assertEqual(calls, [])

    def test_handler_flag_off_is_503_without_fish_http(self):
        with _FishFlag("false", key=None):
            fake_http, calls = _fake_http(self, message="already guarded")
            with patch.object(fish_audio_voice, "_stdlib_http", fake_http):
                response = handler(
                    event(
                        "POST",
                        "/ai/voice/speak",
                        {"message": "already guarded"},
                        user_id="user-1",
                    ),
                    None,
                )
        self.assertEqual(response["statusCode"], 503)
        payload = body(response)
        self.assertEqual(payload["code"], "fish_disabled")
        self.assertEqual(calls, [])
        blob = json.dumps(payload).lower()
        self.assertNotIn("sk_", blob)
        self.assertNotIn("fish_audio_api_key", blob)

    def test_flag_on_without_key_is_unconfigured_no_http(self):
        with _FishFlag("true", key=None):
            fake_http, calls = _fake_http(self, message="hi")
            with self.assertRaises(RouteError) as raised:
                fish_audio_voice.speak({"message": "hi"}, http=fake_http)
            self.assertEqual(raised.exception.code, "fish_unconfigured")
            self.assertEqual(calls, [])

    def test_flag_on_mocked_http_returns_mpeg_and_hides_key(self):
        message = nyx_voice_check.IRIS_LIFESTYLE_FIXTURES[0]
        key = "sk_super_secret_fish_do_not_ship"
        with _FishFlag("true", key=key):
            fake_http, calls = _fake_http(self, message=message, key=key)
            with patch.object(fish_audio_voice, "_stdlib_http", fake_http):
                response = handler(
                    event(
                        "POST",
                        "/ai/voice/speak",
                        {
                            "message": message,
                            "hobby": "pottery",
                            "meds": "ibuprofen",
                            "dig": {"secret": "no"},
                        },
                        user_id="user-1",
                    ),
                    None,
                )
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(response["headers"]["content-type"], "audio/mpeg")
        self.assertTrue(response["isBase64Encoded"])
        audio = base64.b64decode(response["body"])
        self.assertEqual(audio, FAKE_MP3)
        self.assertEqual(len(calls), 1)
        raw = json.loads(calls[0][3].decode("utf-8"))
        self.assertEqual(raw["text"], message)
        self.assertNotIn("hobby", raw)
        self.assertNotIn("meds", raw)
        self.assertNotIn("dig", raw)
        surface = json.dumps(
            {
                "headers": response["headers"],
                "statusCode": response["statusCode"],
                "isBase64Encoded": response["isBase64Encoded"],
                "body": response["body"],
            }
        )
        self.assertNotIn(key, surface)
        self.assertNotIn(key, response["body"])
        self.assertNotIn("Authorization", json.dumps(response["headers"]))

    def test_refuses_to_echo_the_api_key(self):
        key = "sk_leaky_fish"
        with _FishFlag("true", key=key):

            def leaky(_method, _url, _headers, _body):
                return 200, f"audio-{key}".encode("utf-8")

            with self.assertRaises(RouteError) as raised:
                fish_audio_voice.speak({"message": "hi"}, http=leaky)
            self.assertEqual(raised.exception.code, "fish_key_leak")

    def test_dummy_chat_path_untouched_when_flag_off(self):
        with _FishFlag("false", key=None):
            fake_http, calls = _fake_http(self, message="how did I sleep?")
            with patch.object(fish_audio_voice, "_stdlib_http", fake_http):
                response = handler(
                    event(
                        "POST",
                        "/ai/chat",
                        {"message": "how did I sleep?"},
                        user_id="user-1",
                    ),
                    None,
                )
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertTrue(payload.get("prose_summary") or payload.get("message"))
        self.assertEqual(calls, [])


def _called_or_imported(source: str) -> set[str]:
    tree = ast.parse(source)
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.update(alias.name.split(".")[-1] for alias in node.names)
        elif isinstance(node, ast.ImportFrom):
            if node.module:
                names.add(node.module.split(".")[-1])
            names.update(alias.name for alias in node.names)
        elif isinstance(node, ast.Call):
            func = node.func
            if isinstance(func, ast.Name):
                names.add(func.id)
            elif isinstance(func, ast.Attribute):
                names.add(func.attr)
    return names


class SpeakMemoryPinTests(unittest.TestCase):
    def test_module_does_not_import_memory_or_guard(self):
        forbidden = {
            "fuse_turn",
            "remember_short_term",
            "guard_speak",
            "provider_secrets",
            "CoachContextEngine",
        }
        src = FISH_SRC.read_text(encoding="utf-8")
        names = _called_or_imported(src)
        self.assertTrue(forbidden.isdisjoint(names), names & forbidden)
        # Env-only key. SSM / Secrets Manager stay on Pike's PR.
        self.assertNotIn("boto3", names)
        self.assertNotIn("load_ai_provider_secret", names)
        route = ARIA_ROUTE_SRC.read_text(encoding="utf-8")
        speak_fn = route.split("def handle_post_ai_voice_speak", 1)[1].split("\ndef ", 1)[0]
        route_names = _called_or_imported(
            "def handle_post_ai_voice_speak" + speak_fn
        )
        self.assertTrue(forbidden.isdisjoint(route_names), route_names & forbidden)

    def test_speak_does_not_call_fuse_or_memory(self):
        message = "already guarded line"
        with _FishFlag("true", key="sk_pin"):
            fake_http, calls = _fake_http(self, message=message, key="sk_pin")
            with (
                patch("services.fusion.fuse_turn") as fuse,
                patch(
                    "services.aria_context.CoachContextEngine.remember_short_term"
                ) as remember,
            ):
                audio = fish_audio_voice.speak({"message": message}, http=fake_http)
            fuse.assert_not_called()
            remember.assert_not_called()
        self.assertEqual(audio, FAKE_MP3)
        self.assertEqual(len(calls), 1)


class NyxVoiceCheckStubTests(unittest.TestCase):
    def test_iris_lifestyle_fixtures_pass(self):
        self.assertEqual(len(nyx_voice_check.IRIS_LIFESTYLE_FIXTURES), 4)
        self.assertEqual(nyx_voice_check.iris_fixture_failures(), [])
        for line in nyx_voice_check.IRIS_LIFESTYLE_FIXTURES:
            self.assertEqual(nyx_voice_check.voice_check_failures(line), [], line)

    def test_fail_pins_reject_recovery_vitals_disclaimer_and_dose(self):
        self.assertTrue(nyx_voice_check.voice_check_failures("Your recovery looks low."))
        self.assertTrue(
            nyx_voice_check.voice_check_failures("readiness 88 and HRV 32 ms tonight")
        )
        self.assertTrue(nyx_voice_check.voice_check_failures("I'm not a doctor, but rest."))
        self.assertTrue(
            nyx_voice_check.named_dose_failures("maybe 200mg ibuprofen after dinner")
        )
        self.assertTrue(
            nyx_voice_check.voice_check_failures("take 200mg ibuprofen after dinner")
        )
        self.assertEqual(
            nyx_voice_check.voice_check_failures(
                nyx_voice_check.IRIS_LIFESTYLE_FIXTURES[3]
            ),
            [],
        )


if __name__ == "__main__":
    unittest.main()
