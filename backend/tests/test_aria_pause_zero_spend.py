"""Pause equals zero Bedrock spend.

Mock the Bedrock runtime client. While ARIA_PAUSED is true, or SSM fails
paused, no route may invoke Converse — including voice tool, form-check
briefing, and sleep environment-check. /health and voice bootstrap stay up.
"""

from __future__ import annotations

import json
import os
import unittest
from unittest.mock import MagicMock, patch

import _bootstrap  # noqa: F401

import aria_pause  # noqa: E402
from ai_router import BedrockGateway, RoutingError, reset_response_cache  # noqa: E402
from handler import handler  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402
from token_budget import set_user  # noqa: E402


TINY_JPEG_B64 = __import__("base64").b64encode(b"\xff\xd8\xff\xdb\x00fake-jpeg-bytes").decode("ascii")


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


class PauseZeroSpendTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        aria_pause.reset_cache()
        reset_response_cache()
        set_user(None)
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"
        os.environ["ARIA_PAUSED_PARAMETER_NAME"] = "/forge-test/ai/ARIA_PAUSED"
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        os.environ.pop("ARIA_PAUSE_FAIL_MODE", None)
        self.ssm = _FakeSSM(value="true")
        self.bedrock = MagicMock()
        self.bedrock.converse.return_value = {
            "output": {"message": {"content": [{"text": "should never run"}]}},
            "usage": {"inputTokens": 1, "outputTokens": 1},
            "stopReason": "end_turn",
        }
        self._ssm_patch = patch("aria_pause._ssm_client", return_value=self.ssm)
        self._client_patch = patch("ai_router.BedrockGateway._get_bedrock_client", return_value=self.bedrock)
        self._ssm_patch.start()
        self._client_patch.start()

    def tearDown(self):
        self._client_patch.stop()
        self._ssm_patch.stop()
        aria_pause.reset_cache()
        reset_response_cache()
        set_user(None)
        os.environ.pop("ARIA_BEDROCK_ENABLED", None)
        os.environ.pop("ARIA_PAUSED_PARAMETER_NAME", None)
        os.environ.pop("ARIA_PAUSE_FAIL_MODE", None)

    def test_gateway_converse_does_not_touch_bedrock_when_paused(self):
        gateway = BedrockGateway(region_name="us-east-1")
        with self.assertRaises(RoutingError) as ctx:
            gateway.converse(
                model_id="global.anthropic.claude-sonnet-5-5",
                system_prompt="s",
                user_prompt="u",
                max_tokens=128,
                temperature=0.2,
            )
        self.assertEqual(ctx.exception.status_code, 503)
        self.bedrock.converse.assert_not_called()

    def test_ssm_error_fail_paused_does_not_touch_bedrock(self):
        self.ssm.error = RuntimeError("ssm timeout")
        aria_pause.reset_cache()
        gateway = BedrockGateway(region_name="us-east-1")
        with self.assertRaises(RoutingError) as ctx:
            gateway.converse(
                model_id="global.anthropic.claude-sonnet-5-5",
                system_prompt="s",
                user_prompt="u",
                max_tokens=128,
                temperature=0.2,
            )
        self.assertEqual(ctx.exception.status_code, 503)
        self.bedrock.converse.assert_not_called()

    def test_gated_routes_return_503_with_zero_bedrock_calls(self):
        for method, path, payload in (
            ("POST", "/ai/chat", {"message": "hi"}),
            ("POST", "/ai/router", {"question": "summarize my data"}),
            ("POST", "/coach/messages", {"message": "plan tomorrow"}),
        ):
            self.bedrock.converse.reset_mock()
            response = handler(event(method, path, payload), None)
            self.assertEqual(response["statusCode"], 503, path)
            self.assertEqual(body(response)["error"], "aria_paused")
            self.bedrock.converse.assert_not_called()

    def test_ungated_model_surfaces_still_do_not_call_bedrock(self):
        form = handler(
            event("POST", "/workouts/form-check", {"mode": "briefing", "snapshot": "squat set 3"}),
            None,
        )
        sleep = handler(
            event("POST", "/sleep/environment-check", {"image_base64": TINY_JPEG_B64}),
            None,
        )
        voice = handler(event("GET", "/ai/voice"), None)
        self.assertNotEqual(body(form).get("error"), "should never run")
        self.assertNotEqual(body(sleep).get("error"), "should never run")
        self.assertEqual(voice["statusCode"], 200)
        self.assertEqual(body(voice).get("source"), "fallback")
        self.bedrock.converse.assert_not_called()

    def test_health_and_voice_bootstrap_stay_up(self):
        health = handler(event("GET", "/health", user_id=None), None)
        voice = handler(event("GET", "/ai/voice"), None)
        self.assertEqual(health["statusCode"], 200)
        self.assertEqual(body(health)["status"], "ok")
        self.assertNotEqual(body(voice).get("error"), "aria_paused")
        self.bedrock.converse.assert_not_called()
