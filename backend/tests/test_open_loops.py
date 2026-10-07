"""Slice 3: typed open loops round-trip vault Events ↔ STM on one path.

Dummy / local Dynamo only. Bedrock off. SAFETY_LOCK and remember-me off
write neither store. STM expiry must not wipe the vault Events note.
"""

from __future__ import annotations

import json
import os
import unittest
from datetime import datetime, timedelta, timezone

import _bootstrap  # noqa: F401

from routes.aria import handle_post_ai_chat  # noqa: E402
from services import editable_memory as mem  # noqa: E402
from services import open_loops  # noqa: E402
from services.aria_context import CoachContextEngine  # noqa: E402
from storage import dynamodb, keys  # noqa: E402

NOW = datetime(2026, 6, 1, 9, 0, tzinfo=timezone.utc)
USER = "open-loop-user-0001"


def _chat(uid: str, message: str, **extra) -> dict:
    body = {"user_id": uid, "message": message, "recent_metrics": {"readiness": 72}}
    body.update(extra)
    result = handle_post_ai_chat(body, user_id=uid)
    assert result["statusCode"] == 200, result
    return json.loads(result["body"])


class OpenLoopRoundTripTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        self.engine = CoachContextEngine()
        os.environ.pop("ARIA_BEDROCK_ENABLED", None)

    def test_file_writes_same_id_to_vault_events_and_stm(self):
        loop = open_loops.file_open_loop(
            self.engine,
            USER,
            "I have a wedding in 3 weeks",
            now=NOW,
            settings=mem.offline_default(),
        )
        self.assertIsNotNone(loop)
        self.assertEqual(loop.kind, "wedding")
        self.assertEqual(loop.days_until, 21)
        self.assertEqual(loop.folder, "events")
        self.assertEqual(loop.id, loop.vault_id)
        self.assertTrue(loop.stm_active)
        self.assertEqual(loop.text, "Wedding in 21 days")

        vault = self.engine.get_vault_note(USER, "events", loop.id)
        stm = self.engine.short_term_memories(USER, now=NOW)
        self.assertIsNotNone(vault)
        self.assertEqual(vault["id"], loop.id)
        self.assertEqual(vault["folder"], "events")
        self.assertEqual(vault["text"], loop.text)
        self.assertEqual(len(stm), 1)
        self.assertEqual(stm[0].id, loop.id)
        self.assertEqual(stm[0].vault_id, loop.id)
        self.assertEqual(stm[0].folder, "events")
        self.assertEqual(stm[0].category, "open_loop")
        self.assertEqual(stm[0].text, vault["text"])
        listed = open_loops.list_open_loops(self.engine, USER, now=NOW)
        self.assertEqual(len(listed), 1)
        self.assertEqual(listed[0].id, loop.id)
        self.assertTrue(listed[0].stm_active)

    def test_stm_expiry_does_not_wipe_vault_events_note(self):
        loop = open_loops.file_open_loop(
            self.engine,
            USER,
            "There's a game in 2 days",
            now=NOW,
            settings=mem.offline_default(),
        )
        self.assertIsNotNone(loop)
        later = NOW + timedelta(days=5)
        review = self.engine.evaluate_memory(USER, now=later)
        self.assertIn(loop.text, review.forgotten)
        self.assertEqual(self.engine.short_term_memories(USER, now=later), [])
        vault = self.engine.get_vault_note(USER, "events", loop.id)
        self.assertIsNotNone(vault)
        self.assertEqual(vault["text"], loop.text)
        listed = open_loops.list_open_loops(self.engine, USER, now=later)
        self.assertEqual(len(listed), 1)
        self.assertEqual(listed[0].id, loop.id)
        self.assertFalse(listed[0].stm_active)
        stm_key = keys.aria_short_term_key(USER, loop.id)
        vault_key = keys.aria_vault_note_key(USER, "events", loop.id)
        self.assertIsNone(dynamodb.get_item(stm_key["pk"], stm_key["sk"]))
        self.assertIsNotNone(dynamodb.get_item(vault_key["pk"], vault_key["sk"]))

    def test_sanitizer_strips_phone_email_partner_and_meds(self):
        loop = open_loops.file_open_loop(
            self.engine,
            USER,
            (
                "wedding in 3 weeks call 555-123-4567 or sam@example.com "
                "partner_cycle:day14 take 200 mg ibuprofen"
            ),
            now=NOW,
            settings=mem.offline_default(),
        )
        self.assertIsNotNone(loop)
        blob = f"{loop.text} {json.dumps(self.engine.get_vault_note(USER, 'events', loop.id))}"
        stm = self.engine.short_term_memories(USER, now=NOW)[0].text
        for surface in (blob, stm, loop.text):
            low = surface.lower()
            self.assertNotIn("555-123-4567", low)
            self.assertNotIn("sam@example.com", low)
            self.assertNotIn("partner_cycle", low)
            self.assertNotIn("ibuprofen", low)
            self.assertNotIn("200 mg", low)
        self.assertEqual(loop.text, "Wedding in 21 days")

    def test_safety_lock_writes_neither_store(self):
        loop = open_loops.file_open_loop(
            self.engine,
            USER,
            "I have a wedding in 3 weeks and chest pain — not breathing",
            now=NOW,
            settings=mem.offline_default(),
            safety_lock=True,
        )
        self.assertIsNone(loop)
        self.assertEqual(self.engine.vault_notes(USER, "events"), [])
        self.assertEqual(self.engine.short_term_memories(USER, now=NOW), [])

    def test_remember_me_off_stops_auto_file_and_deletes_nothing(self):
        kept = open_loops.file_open_loop(
            self.engine,
            USER,
            "flight in 5 days",
            now=NOW,
            settings=mem.offline_default(),
        )
        self.assertIsNotNone(kept)
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=False))
        skipped = open_loops.file_open_loop(
            self.engine,
            USER,
            "wedding in 2 weeks",
            now=NOW,
            settings=mem.get_settings(USER),
        )
        self.assertIsNone(skipped)
        self.assertIsNotNone(self.engine.get_vault_note(USER, "events", kept.id))
        self.assertEqual(len(self.engine.short_term_memories(USER, now=NOW)), 1)
        self.assertEqual(self.engine.short_term_memories(USER, now=NOW)[0].id, kept.id)
        self.assertIsNone(
            self.engine.get_vault_note(
                USER,
                "events",
                open_loops.parse_open_loop("wedding in 2 weeks", now=NOW).id,
            )
        )

    def test_chat_round_trip_is_coach_words_not_vault_dump(self):
        out = _chat(USER, "I have a wedding in 3 weeks")
        loop = out.get("open_loop") or {}
        self.assertEqual(loop.get("kind"), "wedding")
        self.assertEqual(loop.get("days_until"), 21)
        self.assertEqual(loop.get("folder"), "events")
        self.assertTrue(loop.get("stm_active"))
        speak = loop.get("speak") or ""
        self.assertIn("Wedding in 21 days", speak)
        self.assertNotRegex(speak, r"(?i)\bvault\b")
        spoken = f"{out.get('message') or ''} {out.get('prose_summary') or ''}"
        self.assertNotRegex(spoken, r"(?i)\b(?:from your notes|in the vault|stored note)\b")
        self.assertNotIn("partner_cycle", spoken.lower())
        engine = CoachContextEngine()
        vault = engine.vault_notes(USER, "events")
        stm = engine.short_term_memories(USER)
        self.assertEqual(len(vault), 1)
        self.assertEqual(len(stm), 1)
        self.assertEqual(vault[0]["id"], stm[0].id)

    def test_chat_safety_lock_band_writes_neither(self):
        out = _chat(USER, "he's not breathing — wedding in 3 weeks")
        self.assertTrue(out.get("safety_lock"))
        self.assertNotIn("open_loop", out)
        self.assertEqual(CoachContextEngine().vault_notes(USER, "events"), [])
        self.assertEqual(CoachContextEngine().short_term_memories(USER), [])

    def test_chat_remember_me_off_does_not_auto_file(self):
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=False))
        out = _chat(USER, "I have a wedding in 3 weeks")
        self.assertNotIn("open_loop", out)
        self.assertEqual(CoachContextEngine().vault_notes(USER, "events"), [])
        self.assertEqual(CoachContextEngine().short_term_memories(USER), [])


if __name__ == "__main__":
    unittest.main()
