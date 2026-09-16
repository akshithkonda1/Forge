"""Capability registry: Dummy default, Bedrock off, no fake Grok-on-Bedrock."""
import os
import unittest

import _bootstrap  # noqa: F401

from ai_router import default_models  # noqa: E402
from services import aria_engine  # noqa: E402
from services import provider_capabilities as caps  # noqa: E402


class ProviderCapabilitiesTests(unittest.TestCase):
    def test_dummy_offline_is_default_and_bedrock_is_off(self):
        self.assertEqual(caps.DEFAULT_PATH, "dummy_lambda_fused")
        self.assertFalse(caps.BEDROCK_KILL_SWITCH_DEFAULT)
        self.assertEqual(caps.DEFAULT_AWS_REGION, "us-east-1")
        self.assertEqual(caps.SPEAK_STAGES, ("truth", "personal_model", "stance", "speak"))
        self.assertFalse(caps.runtime_snapshot()["public_bedrock_docs_in_tree"])

    def test_verified_invoke_is_anthropic_only(self):
        self.assertEqual(caps.VERIFIED_BEDROCK_PROVIDERS, frozenset({"anthropic"}))
        self.assertTrue(caps.is_verified_bedrock_invoke("anthropic.claude-sonnet-4-6"))
        self.assertTrue(caps.is_verified_bedrock_invoke("anthropic.claude-opus-4-8"))
        self.assertTrue(caps.iam_allows_model_id("anthropic.claude-opus-4-7"))
        self.assertTrue(caps.is_verified_bedrock_invoke("us.anthropic.claude-sonnet-4-6"))

    def test_grok_is_unverified_and_not_iam_allowed(self):
        grok = "global.xai.grok-4.6"
        self.assertIn(grok, caps.UNVERIFIED_CONFIG_MODEL_IDS)
        self.assertFalse(caps.is_verified_bedrock_invoke(grok))
        self.assertFalse(caps.iam_allows_model_id(grok))
        self.assertEqual(caps.provider_of(grok), "xai")
        slot3 = caps.router_slot(3)
        self.assertEqual(slot3.model_id, grok)
        self.assertFalse(slot3.verified_bedrock_invoke)

    def test_chat_live_ids_are_the_verified_anthropic_pair(self):
        self.assertEqual(
            aria_engine.LIVE_MODEL_IDS,
            {
                aria_engine.MODEL_PRIMARY: "anthropic.claude-opus-4-8",
                aria_engine.MODEL_FAST: "anthropic.claude-sonnet-4-6",
            },
        )
        self.assertEqual(aria_engine.LIVE_MODEL_IDS, caps.CHAT_LIVE_MODEL_IDS)

    def test_router_defaults_keep_historical_ids_without_claiming_grok(self):
        models = default_models()
        self.assertEqual(
            [m.model_id for m in models],
            [
                "anthropic.claude-sonnet-4-6",
                "anthropic.claude-opus-4-7",
                "global.xai.grok-4.6",
            ],
        )
        self.assertNotIn("Bedrock", models[2].responsibility)
        self.assertIn("Unverified", models[2].responsibility)

    def test_iam_arns_stay_anthropic_only(self):
        self.assertTrue(all("anthropic" in arn for arn in caps.IAM_BEDROCK_RESOURCE_ARNS))
        self.assertFalse(any("xai" in arn or "grok" in arn for arn in caps.IAM_BEDROCK_RESOURCE_ARNS))

    def test_must_verify_later_does_not_encode_grok_support(self):
        blob = " ".join(caps.MUST_VERIFY_LATER).lower()
        self.assertIn("whether xai grok is offered", blob)
        self.assertNotIn("grok is available", blob)

    def test_process_env_kill_switch_defaults_off(self):
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ.pop("ARIA_BEDROCK_ENABLED", None)
        try:
            self.assertFalse(aria_engine.bedrock_enabled())
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous


if __name__ == "__main__":
    unittest.main()
