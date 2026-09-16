"""Storage hooks for user-editable companion memory (view/edit/delete/off).

Rowan owns the HTTP contract. These tests pin the persistence bag + the off
switch against the in-memory store. Bedrock stays off. Dummy stays default-on.
"""

from __future__ import annotations

import os
import unittest
from datetime import datetime, timedelta, timezone

import _bootstrap  # noqa: F401

from services import editable_memory as mem  # noqa: E402
from services.aria_context import CoachContextEngine  # noqa: E402
from services.memory_privacy import (  # noqa: E402
    BUSY_WINDOW_LABEL,
    denied_lifestyle_token,
    redact_calendar_event_titles,
)
from storage import dynamodb, keys  # noqa: E402

NOW = datetime(2026, 6, 1, 9, 0, tzinfo=timezone.utc)
USER = "memory-user-0001"


class SettingsPersistenceTests(unittest.TestCase):
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
        self.assertTrue("APP_DATA_TABLE_NAME" not in os.environ or not os.environ.get("APP_DATA_TABLE_NAME"))
        default = mem.offline_default()
        self.assertTrue(default.enabled)
        self.assertEqual(default.to_dict()["persona"], None)

    def test_patch_round_trips_rowan_fields_and_unknown_extras(self):
        saved = mem.patch_settings(
            USER,
            {
                "enabled": True,
                # TODO(rowan): real vocab. Opaque until the contract lands.
                "persona": {"id": "calm-companion"},
                "tone": "direct",
                "check_in": {"enabled": False, "cadence": "daily"},
                "future_field": "passthrough",
            },
        )
        self.assertEqual(saved.persona, {"id": "calm-companion"})
        self.assertEqual(saved.tone, "direct")
        self.assertEqual(saved.check_in["cadence"], "daily")
        self.assertEqual(saved.extra.get("future_field"), "passthrough")
        again = mem.get_settings(USER)
        self.assertEqual(again.to_dict()["future_field"], "passthrough")
        self.assertEqual(again.to_dict()["tone"], "direct")

    def test_off_and_delete_settings(self):
        mem.set_enabled(USER, False)
        self.assertFalse(mem.is_enabled(USER))
        reset = mem.delete_settings(USER)
        self.assertTrue(reset.enabled)
        self.assertTrue(mem.get_settings(USER).enabled)


class ViewEditDeleteTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        self.engine = CoachContextEngine()

    def test_view_edit_delete_life_facts(self):
        self.engine.record_life_fact(USER, "Training for a first 10k")
        snapshot = mem.view_editable_memory(USER)
        self.assertIn("Training for a first 10k", snapshot["life_facts"])
        mem.edit_life_fact(USER, "Training for a first 10k", "Training for a half marathon")
        snapshot = mem.view_editable_memory(USER)
        self.assertEqual(snapshot["life_facts"], ["Training for a half marathon"])
        mem.delete_life_fact(USER, "Training for a half marathon")
        self.assertEqual(mem.view_editable_memory(USER)["life_facts"], [])

    def test_delete_short_term_and_clear_keeps_relationship(self):
        self.engine.update_context(USER, {"relationship_level": 4})
        item = self.engine.remember_short_term(USER, "Feeling stressed about work", now=NOW)
        self.assertIsNotNone(item)
        mem.delete_short_term(USER, item.id)
        self.assertEqual(self.engine.short_term_memories(USER, now=NOW), [])
        self.engine.record_life_fact(USER, "Sister's wedding matters")
        mem.clear_content(USER)
        snapshot = mem.view_editable_memory(USER)
        self.assertEqual(snapshot["life_facts"], [])
        self.assertEqual(snapshot["short_term"], [])
        self.assertEqual(snapshot["relationship_level"], 4)

    def test_delete_all_resets_settings_too(self):
        mem.set_enabled(USER, False)
        self.engine.record_life_fact(USER, "a fact", force=True)
        mem.delete_all(USER)
        snapshot = mem.view_editable_memory(USER)
        self.assertTrue(snapshot["settings"]["enabled"])
        self.assertEqual(snapshot["life_facts"], [])


class OffSwitchTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        self.engine = CoachContextEngine()

    def test_off_blocks_automatic_write_and_inject(self):
        self.engine.record_life_fact(USER, "Training for a first 10k")
        mem.set_enabled(USER, False)
        self.assertIsNone(self.engine.remember_short_term(USER, "new note", now=NOW))
        ctx = self.engine.record_life_fact(USER, "should not land")
        self.assertNotIn("should not land", ctx.life_facts)
        self.assertEqual(
            self.engine.ingest_calendar_events(
                USER,
                [{"title": "Sister's wedding", "start": "2026-06-10T00:00:00+00:00"}],
                now=NOW,
            ),
            [],
        )
        self.assertEqual(self.engine.memory_prompt_block(USER, now=NOW), "")
        self.assertIsNone(self.engine.daily_checkin(USER, now=NOW))
        self.assertIsNone(self.engine.memory_reference(USER, "I am exhausted"))
        # User-initiated edit still works while off.
        mem.edit_life_fact(USER, "Training for a first 10k", "Training for a 5k")
        self.assertEqual(mem.view_editable_memory(USER)["life_facts"], ["Training for a 5k"])

    def test_off_does_not_inject_on_chat_path_helpers(self):
        mem.set_enabled(USER, False)
        review = self.engine.evaluate_memory(USER, now=NOW)
        self.assertEqual(review.forgotten, [])
        self.assertEqual(review.graduated, [])
        self.engine.add_insight(USER, "should not persist")
        self.assertEqual(self.engine.get_or_create_context(USER).last_insights, [])

    def test_chat_route_respects_memory_off(self):
        import json
        from routes.aria import handle_post_ai_chat

        uid = "route-memory-off"
        mem.set_enabled(uid, False)
        soon = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
        result = handle_post_ai_chat(
            {
                "message": "hey",
                "recent_metrics": {"readiness": 80},
                "calendar_events": [{"title": "Sister's wedding", "start": soon}],
            },
            user_id=uid,
        )
        self.assertEqual(result["statusCode"], 200)
        out = json.loads(result["body"])
        self.assertEqual(out["calendar_ingested"], [])
        self.assertIsNone(out["checkin"])
        self.assertIsNone(out["memory"])
        self.assertEqual(CoachContextEngine().short_term_memories(uid), [])


class RedactionTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        self.engine = CoachContextEngine()

    def test_partner_cycle_tokens_never_persist_or_view(self):
        self.assertTrue(denied_lifestyle_token("partner_name:sam"))
        self.assertTrue(denied_lifestyle_token("partner_cycle:day14"))
        ctx = self.engine.record_life_fact(USER, "partner_name:sam")
        self.assertEqual(ctx.life_facts, [])
        self.assertIsNone(self.engine.remember_short_term(USER, "cycle:fertile_window", now=NOW))
        self.engine.update_context(USER, {"life_facts": ["partner_phase:luteal", "late_caffeine"]})
        snapshot = mem.view_editable_memory(USER)
        blob = " ".join(snapshot["life_facts"]).lower()
        self.assertNotIn("partner_phase", blob)
        self.assertIn("late_caffeine", snapshot["life_facts"])

    def test_calendar_titles_stay_busy_window(self):
        events = redact_calendar_event_titles(
            [{"title": "Sister's wedding", "start": "2026-06-10T00:00:00+00:00", "name": "PII"}]
        )
        self.assertEqual(events[0]["title"], BUSY_WINDOW_LABEL)
        self.assertNotIn("name", events[0])
        ingested = self.engine.ingest_calendar_events(
            USER,
            [{"title": "Sister's wedding", "start": "2026-06-10T00:00:00+00:00"}],
            now=NOW,
        )
        self.assertEqual(len(ingested), 1)
        self.assertNotIn("wedding", ingested[0].text.lower())
        self.assertIn("Busy window", ingested[0].text)


class DummyDefaultTests(unittest.TestCase):
    def test_dummy_orchestrator_does_not_import_editable_memory(self):
        import backend.ai.simrunner.aria_simrunner.dummy_orchestrator as dummy

        self.assertNotIn("services.editable_memory", dummy.__dict__)
        self.assertTrue(mem.offline_default().enabled)


if __name__ == "__main__":
    unittest.main()
