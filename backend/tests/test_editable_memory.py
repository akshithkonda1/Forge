"""Locked Rowan editable-memory settings schema. Dummy-offline. Bedrock off.

Does not add live APIs or gate CoachContextEngine ingest. Privacy stays on
``routes.aria.sanitize_inbound_chat_payload`` / iOS AriaFactPrivacy.
"""

from __future__ import annotations

import os
import unittest

import _bootstrap  # noqa: F401

from services import editable_memory as mem  # noqa: E402
from storage import dynamodb, keys  # noqa: E402

USER = "memory-contract-0001"


class SettingsSchemaTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_offline_default_matches_ios_307_defaults(self):
        self.assertTrue(
            "APP_DATA_TABLE_NAME" not in os.environ or not os.environ.get("APP_DATA_TABLE_NAME")
        )
        row = mem.offline_default()
        self.assertTrue(row.memory_enabled)
        self.assertEqual(row.disabled_folders, [])
        self.assertTrue(row.persona_enabled)
        self.assertEqual(row.tone, mem.TONE_CHECK_IN)
        self.assertEqual(row.check_in, mem.CHECK_IN_WEEKLY)
        self.assertEqual(
            set(row.to_dict()),
            {"memory_enabled", "disabled_folders", "persona_enabled", "tone", "check_in"},
        )
        self.assertNotIn("extra", row.to_dict())
        self.assertNotIn("persona", row.to_dict())
        self.assertNotIn("enabled", row.to_dict())

    def test_missing_row_does_not_write(self):
        settings = mem.get_settings(USER)
        self.assertTrue(settings.memory_enabled)
        self.assertIsNone(dynamodb.get_item(**keys.aria_memory_settings_key(USER)))

    def test_seven_folder_ids_match_ios_307(self):
        self.assertEqual(
            mem.MEMORY_FOLDERS,
            (
                "goals",
                "identity",
                "lifestyle",
                "preferences",
                "events",
                "healthHistory",
                "mood",
            ),
        )

    def test_patch_round_trips_contract_fields_only(self):
        saved = mem.patch_settings(
            USER,
            {
                "memory_enabled": False,
                "disabled_folders": ["goals", "healthHistory", "mood"],
                "persona_enabled": False,
                "tone": "honest peer",
                "check_in": "daily",
                "future_field": "must-not-persist",
                "persona": {"id": "invented"},
                "extra": {"nope": True},
            },
        )
        payload = saved.to_dict()
        self.assertFalse(payload["memory_enabled"])
        self.assertEqual(payload["disabled_folders"], ["goals", "healthHistory", "mood"])
        self.assertFalse(payload["persona_enabled"])
        self.assertEqual(payload["tone"], "honest peer")
        self.assertEqual(payload["check_in"], "daily")
        self.assertNotIn("future_field", payload)
        self.assertNotIn("persona", payload)
        self.assertNotIn("extra", payload)
        again = mem.get_settings(USER)
        self.assertEqual(again.to_dict(), payload)
        # off ≠ delete: settings row still exists with flags, not a wipe.
        raw = dynamodb.get_item(**keys.aria_memory_settings_key(USER))
        self.assertIsNotNone(raw)
        self.assertFalse(raw["payload"]["memory_enabled"])

    def test_tone_and_check_in_enums_and_ios_aliases(self):
        self.assertEqual(mem.CompanionMemorySettings.from_dict({"tone": "checkIn"}).tone, "check-in")
        self.assertEqual(mem.CompanionMemorySettings.from_dict({"tone": "peer"}).tone, "honest peer")
        self.assertEqual(mem.CompanionMemorySettings.from_dict({"tone": "space"}).tone, "space")
        self.assertEqual(mem.CompanionMemorySettings.from_dict({"tone": "patterns"}).tone, "patterns")
        self.assertEqual(
            mem.CompanionMemorySettings.from_dict({"check_in": "off"}).check_in, "off"
        )
        self.assertEqual(
            mem.CompanionMemorySettings.from_dict({"checkInCadence": "weekly"}).check_in,
            "weekly",
        )
        bogus = mem.CompanionMemorySettings.from_dict({"tone": "clinician", "check_in": "hourly"})
        self.assertEqual(bogus.tone, "check-in")
        self.assertEqual(bogus.check_in, "weekly")

    def test_disabled_folders_drop_unknown_and_keep_stable_order(self):
        row = mem.CompanionMemorySettings.from_dict(
            {"disabled_folders": ["mood", "body_notes", "invented", "goals", "goals"]}
        )
        self.assertEqual(row.disabled_folders, ["goals", "healthHistory", "mood"])

    def test_auto_ingest_allowed_is_false_when_memory_off_not_wired(self):
        on = mem.offline_default()
        self.assertTrue(mem.auto_ingest_allowed(on))
        off = mem.CompanionMemorySettings(memory_enabled=False)
        self.assertFalse(mem.auto_ingest_allowed(off))
        # Low-level EventKit ingest still redacts titles. Chat auto-ingest is
        # gated separately via auto_ingest_allowed.
        from services.aria_context import CoachContextEngine
        from datetime import datetime, timezone

        engine = CoachContextEngine()
        mem.put_settings(USER, off)
        ingested = engine.ingest_calendar_events(
            USER,
            [{"title": "Sister's wedding", "start": "2026-06-10T00:00:00+00:00"}],
            now=datetime(2026, 6, 1, 9, tzinfo=timezone.utc),
        )
        self.assertEqual(len(ingested), 1)
        self.assertIn("Busy window", ingested[0].text)
        self.assertNotIn("wedding", ingested[0].text.lower())

    def test_chat_skips_new_insights_when_memory_off(self):
        from routes.aria import handle_post_ai_chat
        from services.aria_context import CoachContextEngine
        import json

        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=False))
        engine = CoachContextEngine()
        before = list(engine.get_or_create_context(USER).last_insights)
        result = handle_post_ai_chat({"message": "how did I sleep last night?"}, user_id=USER)
        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertTrue(body.get("message"))
        after = list(engine.get_or_create_context(USER).last_insights)
        self.assertEqual(after, before)


class DummyDefaultTests(unittest.TestCase):
    def test_dummy_orchestrator_does_not_import_editable_memory(self):
        import backend.ai.simrunner.aria_simrunner.dummy_orchestrator as dummy

        self.assertNotIn("services.editable_memory", dummy.__dict__)
        self.assertTrue(mem.offline_default().memory_enabled)
        self.assertTrue(mem.auto_ingest_allowed(mem.offline_default()))


if __name__ == "__main__":
    unittest.main()
