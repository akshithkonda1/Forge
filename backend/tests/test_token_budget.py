"""Per-user daily Bedrock request/token caps and safe Converse caching."""

from __future__ import annotations

import os
import unittest
from unittest.mock import MagicMock, patch

import _bootstrap  # noqa: F401

import aria_pause  # noqa: E402
from ai_router import (  # noqa: E402
    HARD_MAX_TOKENS,
    BedrockGateway,
    RouteSettings,
    RoutingError,
    reset_response_cache,
)
from storage import dynamodb as dynamodb_store  # noqa: E402
from token_budget import reserve, set_user  # noqa: E402
from responses import RouteError  # noqa: E402


class TokenBudgetTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        set_user("budget-user")
        os.environ["ARIA_DAILY_REQUEST_CAP"] = "2"
        os.environ["ARIA_DAILY_TOKEN_CAP"] = "600"

    def tearDown(self):
        set_user(None)
        os.environ.pop("ARIA_DAILY_REQUEST_CAP", None)
        os.environ.pop("ARIA_DAILY_TOKEN_CAP", None)
        dynamodb_store.clear_local_store()

    def test_second_request_is_allowed_and_third_is_429(self):
        reserve(tokens=100)
        reserve(tokens=100)
        with self.assertRaises(RouteError) as ctx:
            reserve(tokens=100)
        self.assertEqual(ctx.exception.status_code, 429)
        self.assertEqual(ctx.exception.code, "aria_daily_request_cap")

    def test_token_cap_blocks_before_converse(self):
        reserve(tokens=400)
        with self.assertRaises(RouteError) as ctx:
            reserve(tokens=300)
        self.assertEqual(ctx.exception.status_code, 429)
        self.assertEqual(ctx.exception.code, "aria_daily_token_cap")

    def test_zero_caps_disable_enforcement(self):
        os.environ["ARIA_DAILY_REQUEST_CAP"] = "0"
        os.environ["ARIA_DAILY_TOKEN_CAP"] = "0"
        for _ in range(5):
            reserve(tokens=10_000)

    def test_client_max_tokens_are_hard_capped(self):
        settings = RouteSettings.from_payload({"maxTokens": 50_000})
        self.assertEqual(settings.max_tokens, HARD_MAX_TOKENS)


class ResponseCacheTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        reset_response_cache()
        aria_pause.reset_cache()
        set_user("cache-user")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        os.environ.pop("ARIA_PAUSED_PARAMETER_NAME", None)
        os.environ["ARIA_DAILY_REQUEST_CAP"] = "0"
        os.environ["ARIA_DAILY_TOKEN_CAP"] = "0"
        self.bedrock = MagicMock()
        self.bedrock.converse.return_value = {
            "output": {"message": {"content": [{"text": "cached-answer"}]}},
            "usage": {"inputTokens": 3, "outputTokens": 4},
            "stopReason": "end_turn",
        }
        self._client_patch = patch("ai_router.BedrockGateway._get_bedrock_client", return_value=self.bedrock)
        self._client_patch.start()

    def tearDown(self):
        self._client_patch.stop()
        reset_response_cache()
        aria_pause.reset_cache()
        set_user(None)
        os.environ.pop("ARIA_BEDROCK_ENABLED", None)
        os.environ.pop("ARIA_PAUSED_PARAMETER_NAME", None)
        os.environ.pop("ARIA_DAILY_REQUEST_CAP", None)
        os.environ.pop("ARIA_DAILY_TOKEN_CAP", None)

    def test_identical_converse_hits_cache_not_bedrock(self):
        gateway = BedrockGateway(region_name="us-east-1")
        first = gateway.converse(
            model_id="global.anthropic.claude-sonnet-5-5",
            system_prompt="s",
            user_prompt="same",
            max_tokens=128,
            temperature=0.2,
        )
        second = gateway.converse(
            model_id="global.anthropic.claude-sonnet-5-5",
            system_prompt="s",
            user_prompt="same",
            max_tokens=128,
            temperature=0.2,
        )
        self.assertEqual(first["answer"], "cached-answer")
        self.assertEqual(second["answer"], "cached-answer")
        self.assertEqual(self.bedrock.converse.call_count, 1)

    def test_paused_skips_cache_and_bedrock(self):
        os.environ["ARIA_PAUSED_PARAMETER_NAME"] = "/forge-test/ai/ARIA_PAUSED"
        ssm = MagicMock()
        ssm.get_parameter.return_value = {"Parameter": {"Value": "true"}}
        with patch("aria_pause._ssm_client", return_value=ssm):
            aria_pause.reset_cache()
            gateway = BedrockGateway(region_name="us-east-1")
            with self.assertRaises(RoutingError):
                gateway.converse(
                    model_id="global.anthropic.claude-sonnet-5-5",
                    system_prompt="s",
                    user_prompt="same",
                    max_tokens=128,
                    temperature=0.2,
                )
        self.bedrock.converse.assert_not_called()
        os.environ.pop("ARIA_PAUSED_PARAMETER_NAME", None)
