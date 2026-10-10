"""Per-model Converse request shape in ai_router.BedrockGateway.

Claude Opus 4.7/4.8 and every Claude 5.x model reject `temperature` with a
400, so sending it made every live call to them fall back to the deterministic
envelope. The 5.x models also think on every turn: effort is the control and
the token cap needs room for the thinking.
"""

from __future__ import annotations

import os
import unittest

import _bootstrap  # noqa: F401

import ai_router  # noqa: E402
from ai_router import BedrockGateway, converse_request_shape  # noqa: E402


class _ValidationError(Exception):
    def __init__(self):
        super().__init__("ValidationException: extraneous key [output_config]")
        self.response = {"Error": {"Code": "ValidationException", "Message": "extraneous key"}}


class _FakeClient:
    def __init__(self, fail_on_additional: bool = False):
        self.calls: list[dict] = []
        self.fail_on_additional = fail_on_additional

    def converse(self, **kwargs):
        self.calls.append(kwargs)
        if self.fail_on_additional and "additionalModelRequestFields" in kwargs:
            raise _ValidationError()
        return {
            "output": {"message": {"content": [
                {"reasoningContent": {"reasoningText": {"text": "private"}}},
                {"text": "Keep today easy."},
            ]}},
            "usage": {"inputTokens": 10, "outputTokens": 20},
            "stopReason": "end_turn",
        }


class _Env:
    def __init__(self, **values):
        self.values = values

    def __enter__(self):
        self.saved = {k: os.environ.get(k) for k in self.values}
        for k, v in self.values.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v

    def __exit__(self, *exc):
        for k, v in self.saved.items():
            if v is None:
                os.environ.pop(k, None)
            else:
                os.environ[k] = v


def _gateway(client: _FakeClient) -> BedrockGateway:
    gateway = BedrockGateway(region_name="us-east-1")
    gateway._bedrock_clients[gateway._timeout_key(None)] = client
    return gateway


def _call(gateway: BedrockGateway, model_id: str) -> dict:
    return gateway.converse(
        model_id=model_id, system_prompt="s", user_prompt="u", max_tokens=700, temperature=0.3
    )


class RequestShapeTests(unittest.TestCase):
    def test_claude_5_5_gets_no_temperature_and_low_effort(self):
        for model in ("global.anthropic.claude-opus-5-5", "us.anthropic.claude-sonnet-5-5", "anthropic.claude-haiku-5-5"):
            inference, additional = converse_request_shape(model, max_tokens=700, temperature=0.3)
            self.assertNotIn("temperature", inference, model)
            self.assertEqual(inference["maxTokens"], 700 + ai_router.THINKING_TOKEN_HEADROOM, model)
            self.assertEqual(additional, {"output_config": {"effort": "low"}}, model)

    def test_opus_4_7_and_4_8_get_no_temperature(self):
        for model in ("anthropic.claude-opus-4-7", "anthropic.claude-opus-4-8"):
            inference, additional = converse_request_shape(model, max_tokens=700, temperature=0.3)
            self.assertEqual(inference, {"maxTokens": 700}, model)
            self.assertIsNone(additional)

    def test_models_that_accept_sampling_keep_it(self):
        for model in ("anthropic.claude-sonnet-4-6", "anthropic.claude-haiku-4-5", "global.xai.grok-4.6"):
            inference, additional = converse_request_shape(model, max_tokens=700, temperature=0.3)
            self.assertEqual(inference, {"maxTokens": 700, "temperature": 0.3}, model)
            self.assertIsNone(additional)

    def test_effort_is_configurable_and_validated(self):
        with _Env(ARIA_BEDROCK_EFFORT="medium"):
            _, additional = converse_request_shape("global.anthropic.claude-opus-5-5", max_tokens=1, temperature=0)
        self.assertEqual(additional["output_config"]["effort"], "medium")
        with _Env(ARIA_BEDROCK_EFFORT="turbo"):
            _, additional = converse_request_shape("global.anthropic.claude-opus-5-5", max_tokens=1, temperature=0)
        self.assertEqual(additional["output_config"]["effort"], ai_router.DEFAULT_BEDROCK_EFFORT)


class GatewayConverseTests(unittest.TestCase):
    def test_sends_the_model_specific_shape_and_reads_only_text(self):
        client = _FakeClient()
        with _Env(ARIA_BEDROCK_ENABLED="true", ARIA_BEDROCK_EFFORT=None):
            out = _call(_gateway(client), "global.anthropic.claude-opus-5-5")
        sent = client.calls[0]
        self.assertNotIn("temperature", sent["inferenceConfig"])
        self.assertEqual(sent["additionalModelRequestFields"], {"output_config": {"effort": "low"}})
        self.assertEqual(out["answer"], "Keep today easy.")  # reasoning never leaks

    def test_retries_without_extra_fields_on_validation_error(self):
        client = _FakeClient(fail_on_additional=True)
        with _Env(ARIA_BEDROCK_ENABLED="true"):
            out = _call(_gateway(client), "global.anthropic.claude-sonnet-5-5")
        self.assertEqual(len(client.calls), 2)
        self.assertNotIn("additionalModelRequestFields", client.calls[1])
        self.assertNotIn("temperature", client.calls[1]["inferenceConfig"])
        self.assertEqual(out["answer"], "Keep today easy.")

    def test_grok_request_is_unchanged(self):
        client = _FakeClient()
        with _Env(ARIA_BEDROCK_ENABLED="true"):
            _call(_gateway(client), "global.xai.grok-4.6")
        self.assertEqual(client.calls[0]["inferenceConfig"], {"maxTokens": 700, "temperature": 0.3})
        self.assertNotIn("additionalModelRequestFields", client.calls[0])


class DefaultModelTests(unittest.TestCase):
    def test_router_and_chat_default_to_claude_5_5(self):
        from services import aria_engine

        models = ai_router.default_models()
        self.assertEqual(models[0].model_id, "global.anthropic.claude-sonnet-5-5")
        self.assertEqual(models[1].model_id, "global.anthropic.claude-opus-5-5")
        self.assertEqual(models[2].model_id, "global.xai.grok-4.6")
        self.assertEqual(aria_engine.LIVE_MODEL_IDS[aria_engine.MODEL_PRIMARY], "global.anthropic.claude-opus-5-5")
        self.assertEqual(aria_engine.LIVE_MODEL_IDS[aria_engine.MODEL_FAST], "global.anthropic.claude-sonnet-5-5")
        for model in models[:2]:
            self.assertFalse(ai_router.accepts_sampling_params(model.model_id))


if __name__ == "__main__":
    unittest.main()
