"""ARIA-only kill switch. Mock SSM — never call AWS.

Gated routes return 503 ``{"error":"aria_paused",...}`` before the router or
Dynamo. Voice, /health, and non-ARIA routes stay up. SSM errors fail paused
unless ARIA_PAUSE_FAIL_MODE=open.
"""

from __future__ import annotations

import json
import os
import unittest
from unittest.mock import MagicMock, patch

import _bootstrap  # noqa: F401

import aria_pause  # noqa: E402
from handler import handler  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402


def event(method, path, body=None, *, user_id="pause-user"):
    payload = {
        "requestContext": {"http": {"method": method, "path": path}},
        "queryStringParameters": {},
        "headers": {},
    }
    if user_id:
        payload["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": user_id}}}
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def body(response):
    return json.loads(response["body"])


class _FakeSSM:
    def __init__(self, *, value=None, error=None):
        self.value = value
        self.error = error
        self.calls = 0

    def get_parameter(self, **_kwargs):
        self.calls += 1
        if self.error is not None:
            raise self.error
        return {"Parameter": {"Value": self.value}}


class AriaPauseTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        aria_pause.reset_cache()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        os.environ["ARIA_PAUSED_PARAMETER_NAME"] = "/forge-test/ai/ARIA_PAUSED"
        os.environ.pop("ARIA_PAUSE_FAIL_MODE", None)
        os.environ.pop("ARIA_BEDROCK_ENABLED", None)
        self.ssm = _FakeSSM(value="false")
        self._ssm_patch = patch("aria_pause._ssm_client", return_value=self.ssm)
        self._ssm_patch.start()

    def tearDown(self):
        self._ssm_patch.stop()
        aria_pause.reset_cache()
        os.environ.pop("ARIA_PAUSED_PARAMETER_NAME", None)
        os.environ.pop("ARIA_PAUSE_FAIL_MODE", None)

    def test_paused_returns_503_without_router_or_dynamo(self):
        self.ssm.value = "true"
        with (
            patch("ai_router.AIRouter") as router,
            patch("storage.dynamodb.put_item") as put_item,
            patch("storage.dynamodb.query_prefix") as query_prefix,
            patch("routes.aria.handle_post_ai_chat") as chat,
            patch("routes.coach.handle_post_coach_message") as coach,
        ):
            router_resp = handler(
                event("POST", "/ai/router", {"question": "summarize my data"}),
                None,
            )
            chat_resp = handler(
                event("POST", "/ai/chat", {"message": "hi"}),
                None,
            )
            messages_resp = handler(
                event(
                    "POST",
                    "/chat/threads/current/messages",
                    {"content": "How should I train today?"},
                ),
                None,
            )
            coach_resp = handler(
                event("POST", "/coach/messages", {"message": "plan tomorrow"}),
                None,
            )

        for response in (router_resp, chat_resp, messages_resp, coach_resp):
            self.assertEqual(response["statusCode"], 503)
            payload = body(response)
            self.assertEqual(payload["error"], "aria_paused")
            self.assertEqual(payload["message"], "ARIA is paused")
            self.assertNotIn("code", payload)

        router.assert_not_called()
        put_item.assert_not_called()
        query_prefix.assert_not_called()
        chat.assert_not_called()
        coach.assert_not_called()
        self.assertGreaterEqual(self.ssm.calls, 1)

    def test_unpaused_passes_through(self):
        self.ssm.value = "false"
        response = handler(
            event("POST", "/ai/router", {"question": "summarize my data"}),
            None,
        )
        self.assertEqual(response["statusCode"], 503)
        payload = body(response)
        self.assertNotEqual(payload.get("error"), "aria_paused")
        self.assertIn("ARIA_BEDROCK_ENABLED", payload["message"])
        self.assertEqual(self.ssm.calls, 1)

    def test_ssm_error_fails_paused_by_default(self):
        self.ssm.error = RuntimeError("ssm timeout")
        with patch("ai_router.AIRouter") as router:
            response = handler(
                event("POST", "/ai/router", {"question": "hi"}),
                None,
            )
        self.assertEqual(response["statusCode"], 503)
        self.assertEqual(body(response)["error"], "aria_paused")
        router.assert_not_called()

    def test_ssm_error_fails_open_when_fail_mode_open(self):
        os.environ["ARIA_PAUSE_FAIL_MODE"] = "open"
        self.ssm.error = RuntimeError("ssm timeout")
        response = handler(
            event("POST", "/ai/router", {"question": "hi"}),
            None,
        )
        self.assertEqual(response["statusCode"], 503)
        payload = body(response)
        self.assertNotEqual(payload.get("error"), "aria_paused")
        self.assertIn("ARIA_BEDROCK_ENABLED", payload["message"])

    def test_ssm_error_fails_paused_when_fail_mode_paused(self):
        os.environ["ARIA_PAUSE_FAIL_MODE"] = "paused"
        self.ssm.error = RuntimeError("ssm timeout")
        with patch("ai_router.AIRouter") as router:
            response = handler(
                event("POST", "/ai/router", {"question": "hi"}),
                None,
            )
        self.assertEqual(response["statusCode"], 503)
        self.assertEqual(body(response)["error"], "aria_paused")
        router.assert_not_called()

    def test_voice_routes_are_ungated(self):
        self.ssm.value = "true"
        response = handler(event("GET", "/ai/voice"), None)
        self.assertEqual(response["statusCode"], 200)
        payload = body(response)
        self.assertNotEqual(payload.get("error"), "aria_paused")
        self.assertEqual(payload.get("source"), "kokoro")
        self.assertEqual(self.ssm.calls, 0)

    def test_health_is_ungated(self):
        self.ssm.value = "true"
        response = handler(event("GET", "/health", user_id=None), None)
        self.assertEqual(response["statusCode"], 200)
        self.assertEqual(body(response)["status"], "ok")
        self.assertEqual(self.ssm.calls, 0)

    def test_health_and_voice_stay_up_when_ssm_errors_fail_paused(self):
        self.ssm.error = RuntimeError("ssm timeout")
        health = handler(event("GET", "/health", user_id=None), None)
        voice = handler(event("GET", "/ai/voice"), None)
        self.assertEqual(health["statusCode"], 200)
        self.assertEqual(body(health)["status"], "ok")
        self.assertNotEqual(body(voice).get("error"), "aria_paused")
        self.assertEqual(body(voice).get("source"), "kokoro")
        self.assertEqual(self.ssm.calls, 0)

    def test_unset_env_fails_open_without_ssm(self):
        os.environ.pop("ARIA_PAUSED_PARAMETER_NAME")
        self.ssm.error = RuntimeError("should not be called")
        self.assertFalse(aria_pause.is_aria_paused())
        self.assertEqual(self.ssm.calls, 0)


class AriaPauseRouteListTests(unittest.TestCase):
    def test_feedback_and_coach_prefixes_are_gated(self):
        from handler import _is_aria_gated_route

        gated = [
            ("POST", "/ai/chat"),
            ("POST", "/ai/router"),
            ("POST", "/ai/archetype"),
            ("POST", "/ai/weekly-review"),
            ("POST", "/ai/observe"),
            ("POST", "/ai/feedback/reaction"),
            ("POST", "/ai/feedback/plan-outcome"),
            ("POST", "/chat/threads/current/messages"),
            ("POST", "/coach/messages"),
            ("POST", "/coach/workout-plan"),
            ("POST", "/coach/sleep-insight"),
            ("POST", "/coach/progress-review"),
        ]
        ungated = [
            ("GET", "/health"),
            ("GET", "/ai/voice"),
            ("PUT", "/ai/voice"),
            ("GET", "/chat/threads/current"),
            ("GET", "/dashboard/today"),
            ("POST", "/watch/aria/suggest"),
        ]
        for method, path in gated:
            self.assertTrue(_is_aria_gated_route(method, path), (method, path))
        for method, path in ungated:
            self.assertFalse(_is_aria_gated_route(method, path), (method, path))
