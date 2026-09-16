"""Design-stub registry: Dummy default, Bedrock off, await Quill ID table."""
import os
import pathlib
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine  # noqa: E402
from services import provider_capabilities as caps  # noqa: E402


class ProviderCapabilitiesStubTests(unittest.TestCase):
    def test_dummy_offline_is_default_and_bedrock_is_off(self):
        self.assertEqual(caps.DEFAULT_PATH, "dummy_lambda_fused")
        self.assertFalse(caps.BEDROCK_KILL_SWITCH_DEFAULT)
        self.assertTrue(caps.DO_NOT_INVOKE)
        self.assertTrue(caps.AWAIT_QUILL_TABLE)
        self.assertEqual(caps.DIRECTION, "grok_plus_latest_claude")
        self.assertFalse(caps.invoke_now_allowed())
        self.assertEqual(caps.SPEAK_STAGES, ("truth", "personal_model", "stance", "speak"))

    def test_snapshot_has_no_model_id_table(self):
        snap = caps.runtime_snapshot()
        self.assertTrue(snap["await_quill_table"])
        self.assertTrue(snap["do_not_invoke"])
        self.assertFalse(snap["bedrock_kill_switch_default"])
        self.assertEqual(snap["path"], "dummy_lambda_fused")
        blob = str(snap).lower()
        for needle in ("xai.grok", "anthropic.claude", "us-west-2", "foundation"):
            self.assertNotIn(needle, blob, needle)

    def test_stub_source_does_not_encode_ids_or_call_bedrock(self):
        src = pathlib.Path(caps.__file__).read_text(encoding="utf-8")
        for needle in (
            "InvokeModel",
            "list_foundation_models",
            "boto3",
            "converse(",
            "xai.grok",
            "anthropic.claude",
            "global.xai",
            "us.xai",
        ):
            self.assertNotIn(needle, src, needle)
        self.assertIn("Await Quill", src)

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
