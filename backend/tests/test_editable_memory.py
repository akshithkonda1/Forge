"""Stub persistence for Rowan's editable-memory settings bag.

Does not implement view/edit/delete/off of memory facts. Privacy gates stay
on the existing chat ingest path (test_aria_context_privacy). Bedrock off.
Dummy stays default-on and does not import this module.
"""

from __future__ import annotations

import os
import unittest

import _bootstrap  # noqa: F401

from services import editable_memory as mem  # noqa: E402
from storage import dynamodb, keys  # noqa: E402

USER = "memory-stub-0001"


class SettingsStubTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_missing_row_is_dummy_offline_default(self):
        settings = mem.get_settings(USER)
        self.assertTrue(settings.enabled)
        self.assertIsNone(settings.persona)
        self.assertIsNone(settings.tone)
        self.assertIsNone(settings.check_in)
        self.assertIsNone(dynamodb.get_item(**keys.aria_memory_settings_key(USER)))

    def test_offline_default_does_not_need_a_table(self):
        self.assertTrue(
            "APP_DATA_TABLE_NAME" not in os.environ or not os.environ.get("APP_DATA_TABLE_NAME")
        )
        default = mem.offline_default()
        self.assertTrue(default.enabled)
        self.assertIsNone(default.to_dict()["persona"])

    def test_patch_round_trips_placeholder_fields_and_unknown_extras(self):
        saved = mem.patch_settings(
            USER,
            {
                # TODO(rowan): real vocab. Opaque until the contract lands.
                "persona": {"id": "placeholder"},
                "tone": "placeholder",
                "check_in": {"enabled": True},
                "future_field": "passthrough",
            },
        )
        self.assertEqual(saved.persona, {"id": "placeholder"})
        self.assertEqual(saved.tone, "placeholder")
        self.assertEqual(saved.check_in, {"enabled": True})
        self.assertEqual(saved.extra.get("future_field"), "passthrough")
        again = mem.get_settings(USER)
        self.assertEqual(again.to_dict()["future_field"], "passthrough")
        self.assertTrue(again.enabled)


class DummyDefaultTests(unittest.TestCase):
    def test_dummy_orchestrator_does_not_import_editable_memory(self):
        import backend.ai.simrunner.aria_simrunner.dummy_orchestrator as dummy

        self.assertNotIn("services.editable_memory", dummy.__dict__)
        self.assertTrue(mem.offline_default().enabled)


if __name__ == "__main__":
    unittest.main()
