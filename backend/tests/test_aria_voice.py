"""ARIA character voice — dummy stays local; live bootstrap is not the API key."""

from __future__ import annotations

import json
import os
import re
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from responses import RouteError  # noqa: E402
from services import elevenlabs_voice  # noqa: E402
from services import provider_secrets  # noqa: E402

from test_backend_handler import body, event  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
SWIFT_VOICE = REPO / "ForgeSwift" / "ForgeSwift" / "AriaCharacterVoice.swift"
SWIFT_SESSION = REPO / "ForgeSwift" / "ForgeSwift" / "AriaVoiceSession.swift"


def _swift_string(name: str) -> str:
    text = SWIFT_VOICE.read_text(encoding="utf-8")
    match = re.search(
        rf'static let {name} = """\n(.*?)"""',
        text,
        re.S,
    )
    if not match:
        raise AssertionError(f"{name} not found in AriaCharacterVoice.swift")
    raw = match.group(1)
    lines = raw.split("\n")
    # Swift strips the indent of the closing delimiter from every line.
    indent = re.match(r"[ \t]*", lines[-1] if lines else "")
    prefix = indent.group(0) if indent else ""
    stripped = []
    for line in lines:
        if line.endswith("\n"):
            line = line[:-1]
        if prefix and line.startswith(prefix):
            line = line[len(prefix) :]
        stripped.append(line)
    if stripped and stripped[-1] == "":
        stripped.pop()
    return "\n".join(stripped)


class VoiceDesignPromptTests(unittest.TestCase):
    def test_locked_prompt_matches_ios(self):
        self.assertEqual(elevenlabs_voice.ARIA_DESIGN_PROMPT, _swift_string("designPrompt"))
        self.assertEqual(
            elevenlabs_voice.ARIA_DESIGN_PREVIEW_TEXT, _swift_string("designPreviewText")
        )
        self.assertEqual(elevenlabs_voice.ARIA_VOICE_NAME, "ARIA")
        self.assertEqual(elevenlabs_voice.TTS_MODEL_ID, "eleven_v3_conversational")
        self.assertEqual(elevenlabs_voice.ASR_PROVIDER, "scribe_realtime")
        self.assertEqual(elevenlabs_voice.TURN_MODEL, "turn_v3")
        self.assertEqual(elevenlabs_voice.VOICE_DESIGN_MODEL_ID, "eleven_ttv_v3")
        self.assertEqual(elevenlabs_voice.CONVAI_LLM, "claude-sonnet-4-6")
        swift = SWIFT_VOICE.read_text(encoding="utf-8")
        self.assertIn(f'static let liveTTSModel = "{elevenlabs_voice.TTS_MODEL_ID}"', swift)
        self.assertIn(f'static let liveASRProvider = "{elevenlabs_voice.ASR_PROVIDER}"', swift)
        self.assertIn(f'static let liveTurnModel = "{elevenlabs_voice.TURN_MODEL}"', swift)
        self.assertIn(f'static let liveVoiceDesignModel = "{elevenlabs_voice.VOICE_DESIGN_MODEL_ID}"', swift)
        self.assertIn(f'static let liveConvAILLM = "{elevenlabs_voice.CONVAI_LLM}"', swift)
        self.assertIn("not a customer-service agent", elevenlabs_voice.ARIA_DESIGN_PROMPT)
        self.assertIn("GPS", elevenlabs_voice.ARIA_DESIGN_PROMPT)
        self.assertNotIn("tiffany", elevenlabs_voice.ARIA_DESIGN_PROMPT.lower())

    def test_dummy_session_file_mentions_dummy_first(self):
        session = SWIFT_SESSION.read_text(encoding="utf-8")
        self.assertIn("AriaVoiceTransport.resolveCurrent", session)
        self.assertIn("shouldUseTestReadyDummy", SWIFT_VOICE.read_text(encoding="utf-8"))
        self.assertNotIn("api.elevenlabs.io", SWIFT_VOICE.read_text(encoding="utf-8"))


class ProviderSecretTests(unittest.TestCase):
    def setUp(self):
        provider_secrets.reset_cache()
        self._saved = {
            key: os.environ.get(key)
            for key in (
                "ELEVENLABS_API_KEY",
                "ELEVENLABS_ARIA_VOICE_ID",
                "ELEVENLABS_ARIA_AGENT_ID",
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


class VoiceRouteTests(unittest.TestCase):
    def setUp(self):
        provider_secrets.reset_cache()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ.pop("ELEVENLABS_ARIA_AGENT_ID", None)
        os.environ.pop("ELEVENLABS_ARIA_VOICE_ID", None)
        os.environ.pop("AI_PROVIDER_SECRET_ARN", None)

    def tearDown(self):
        provider_secrets.reset_cache()
        os.environ.pop("ELEVENLABS_API_KEY", None)
        os.environ.pop("ELEVENLABS_ARIA_AGENT_ID", None)
        os.environ.pop("ELEVENLABS_ARIA_VOICE_ID", None)

    def test_bootstrap_without_key_is_unconfigured(self):
        response = handler(event("GET", "/ai/voice/bootstrap", user_id="user-1"), None)
        self.assertEqual(response["statusCode"], 503)
        payload = body(response)
        self.assertEqual(payload["code"], "elevenlabs_unconfigured")
        self.assertNotIn("xi-api-key", json.dumps(payload).lower())

    def test_bootstrap_signed_url_is_not_the_api_key(self):
        os.environ["ELEVENLABS_API_KEY"] = "sk_super_secret_do_not_ship"
        os.environ["ELEVENLABS_ARIA_AGENT_ID"] = "agent_aria_test"
        os.environ["ELEVENLABS_ARIA_VOICE_ID"] = "voice_aria_test"
        provider_secrets.reset_cache()

        def fake_http(method, url, headers, _body):
            self.assertEqual(method, "GET")
            self.assertIn("get-signed-url", url)
            self.assertIn("agent_aria_test", url)
            self.assertEqual(headers.get("xi-api-key"), "sk_super_secret_do_not_ship")
            return 200, {
                "signed_url": (
                    "wss://api.elevenlabs.io/v1/convai/conversation"
                    "?agent_id=agent_aria_test&conversation_signature=short_lived"
                )
            }

        payload = elevenlabs_voice.mint_signed_url(
            user_id="user-1", http=fake_http
        )
        self.assertEqual(payload["transport"], "live")
        self.assertTrue(payload["signed_url"].startswith("wss://"))
        self.assertNotEqual(payload["signed_url"], "sk_super_secret_do_not_ship")
        self.assertNotIn("sk_super_secret_do_not_ship", payload["signed_url"])
        self.assertNotIn("xi-api-key", payload["signed_url"].lower())
        self.assertEqual(payload["voice_name"], "ARIA")
        self.assertIn("You are ARIA", payload["prompt_context"])
        self.assertEqual(payload["models"]["tts"], "eleven_v3_conversational")
        self.assertEqual(payload["models"]["asr"], "scribe_realtime")
        self.assertEqual(payload["models"]["llm"], "claude-sonnet-4-6")

    def test_bootstrap_refuses_to_echo_the_api_key(self):
        os.environ["ELEVENLABS_API_KEY"] = "sk_leaky"
        os.environ["ELEVENLABS_ARIA_AGENT_ID"] = "agent_x"
        provider_secrets.reset_cache()

        def fake_http(_method, _url, _headers, _body):
            return 200, {"signed_url": "sk_leaky"}

        with self.assertRaises(RouteError) as raised:
            elevenlabs_voice.mint_signed_url(user_id="user-1", http=fake_http)
        self.assertEqual(raised.exception.code, "elevenlabs_key_leak")

    def test_tool_uses_aria_engine_not_elevenlabs(self):
        response = handler(
            event(
                "POST",
                "/ai/voice/tool",
                {"message": "how did I sleep?", "voice_mode": True},
                user_id="user-1",
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertTrue(payload.get("prose_summary") or payload.get("result"))
        self.assertEqual(payload.get("result"), payload.get("prose_summary") or payload.get("result"))
        blob = json.dumps(payload).lower()
        self.assertNotIn("elevenlabs", blob)
        self.assertNotIn("zoe", blob)

    def test_design_is_blocked_in_production_like(self):
        os.environ["ENVIRONMENT"] = "production"
        os.environ.pop("FORGE_VOICE_DESIGN_ENABLED", None)
        os.environ["ELEVENLABS_API_KEY"] = "sk_x"
        provider_secrets.reset_cache()
        response = handler(
            event("POST", "/ai/voice/design", {}, user_id="user-1"),
            None,
        )
        self.assertEqual(response["statusCode"], 403)
        self.assertEqual(body(response)["code"], "voice_design_disabled")
        os.environ["ENVIRONMENT"] = "test"

    def test_design_saves_aria_and_returns_seed_ids(self):
        os.environ["ELEVENLABS_API_KEY"] = "sk_design"
        os.environ["ENVIRONMENT"] = "test"
        provider_secrets.reset_cache()
        calls: list[str] = []

        def fake_http(method, url, headers, raw):
            calls.append(url)
            self.assertEqual(headers.get("xi-api-key"), "sk_design")
            if url.endswith("/v1/text-to-voice/design"):
                payload = json.loads(raw.decode("utf-8"))
                self.assertEqual(payload["voice_description"], elevenlabs_voice.ARIA_DESIGN_PROMPT)
                self.assertEqual(payload["model_id"], "eleven_ttv_v3")
                return 200, {
                    "previews": [
                        {"generated_voice_id": "gen_1", "duration_secs": 4.2, "media_type": "audio/mpeg"}
                    ]
                }
            if url.endswith("/v1/text-to-voice"):
                payload = json.loads(raw.decode("utf-8"))
                self.assertEqual(payload["voice_name"], "ARIA")
                self.assertEqual(payload["generated_voice_id"], "gen_1")
                return 200, {"voice_id": "voice_saved"}
            if url.endswith("/v1/convai/agents/create"):
                payload = json.loads(raw.decode("utf-8"))
                tts = payload["conversation_config"]["tts"]
                asr = payload["conversation_config"]["asr"]
                turn = payload["conversation_config"]["turn"]
                prompt = payload["conversation_config"]["agent"]["prompt"]
                self.assertEqual(tts["voice_id"], "voice_saved")
                self.assertEqual(tts["model_id"], "eleven_v3_conversational")
                self.assertTrue(tts["expressive_mode"])
                self.assertEqual(asr["provider"], "scribe_realtime")
                self.assertIn("HRV", asr["keywords"])
                self.assertEqual(turn["turn_model"], "turn_v3")
                self.assertEqual(prompt["llm"], "claude-sonnet-4-6")
                self.assertEqual(payload["name"], "ARIA")
                tools = prompt["tools"]
                self.assertEqual(tools[0]["name"], "forge_coach")
                self.assertEqual(tools[0]["type"], "client")
                return 200, {"agent_id": "agent_saved"}
            self.fail(url)

        designed = elevenlabs_voice.design_aria(http=fake_http)
        self.assertEqual(designed["voice_id"], "voice_saved")
        self.assertEqual(designed["agent_id"], "agent_saved")
        self.assertEqual(designed["voice_name"], "ARIA")
        self.assertEqual(designed["design_prompt"], elevenlabs_voice.ARIA_DESIGN_PROMPT)
        self.assertEqual(designed["seed_secret"]["ELEVENLABS_ARIA_VOICE_ID"], "voice_saved")
        self.assertTrue(any("text-to-voice/design" in url for url in calls))
        self.assertTrue(any("agents/create" in url for url in calls))
        self.assertEqual(designed["models"]["tts"], "eleven_v3_conversational")
        self.assertEqual(designed["models"]["voice_design"], "eleven_ttv_v3")

    def test_design_patches_existing_agent_instead_of_creating_another(self):
        os.environ["ELEVENLABS_API_KEY"] = "sk_design"
        os.environ["ELEVENLABS_ARIA_AGENT_ID"] = "agent_existing"
        os.environ["ENVIRONMENT"] = "test"
        provider_secrets.reset_cache()
        calls: list[str] = []

        def fake_http(method, url, headers, raw):
            calls.append(f"{method} {url}")
            if url.endswith("/v1/text-to-voice/design"):
                return 200, {"previews": [{"generated_voice_id": "gen_1"}]}
            if url.endswith("/v1/text-to-voice"):
                return 200, {"voice_id": "voice_saved"}
            if url.endswith("/v1/convai/agents/agent_existing"):
                self.assertEqual(method, "PATCH")
                payload = json.loads(raw.decode("utf-8"))
                self.assertEqual(
                    payload["conversation_config"]["tts"]["model_id"],
                    "eleven_v3_conversational",
                )
                return 200, {"agent_id": "agent_existing"}
            self.fail(url)

        designed = elevenlabs_voice.design_aria(http=fake_http)
        self.assertEqual(designed["agent_id"], "agent_existing")
        self.assertTrue(any(call.startswith("PATCH ") for call in calls))
        self.assertFalse(any("agents/create" in call for call in calls))


if __name__ == "__main__":
    unittest.main()
