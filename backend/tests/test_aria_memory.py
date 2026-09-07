"""Tests for ARIA's two-tier memory + companion engine (services.aria_context).

ARIA remembers like a person: a durable long-term store ("what it knows about
you") and a transient short-term store ("what you're telling it now", e.g. a
wedding in three weeks) that expires on its own. It ingests calendar events,
evaluates its own memory day to day, and checks in once a day. These tests pin
that behavior deterministically against the in-memory storage layer.
"""

from __future__ import annotations

import unittest
from datetime import datetime, timedelta, timezone

import _bootstrap  # noqa: F401

from storage import dynamodb  # noqa: E402
from services.aria_context import (  # noqa: E402
    CheckinPrompt,
    CoachContextEngine,
    MemoryItem,
    MemoryReview,
    _humanize_when,
)

NOW = datetime(2026, 6, 1, 9, 0, tzinfo=timezone.utc)
USER = "test-user-00000000"


class MemoryEngineTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        self.engine = CoachContextEngine()

    # --- long-term memory ------------------------------------------------
    def test_record_life_fact_dedupes_and_persists(self):
        self.engine.record_life_fact(USER, "Training for a first 10k")
        self.engine.record_life_fact(USER, "training for a first 10k")  # dup (case-insensitive)
        self.engine.record_life_fact(USER, "Sister's wedding matters to them")
        # New engine instance -> proves it persisted through storage.
        ctx = CoachContextEngine().get_or_create_context(USER)
        self.assertEqual(len(ctx.life_facts), 2)  # case-insensitive dedupe
        self.assertEqual(ctx.life_facts[0], "Sister's wedding matters to them")  # newest first
        self.assertIn("10k", ctx.life_facts[1].lower())

    def test_life_facts_capped(self):
        for i in range(60):
            self.engine.record_life_fact(USER, f"fact {i}", cap=50)
        ctx = self.engine.get_or_create_context(USER)
        self.assertEqual(len(ctx.life_facts), 50)

    # --- short-term memory ----------------------------------------------
    def test_remember_and_read_short_term(self):
        self.engine.remember_short_term(
            USER, "Feeling stressed about work", now=NOW
        )
        items = self.engine.short_term_memories(USER, now=NOW)
        self.assertEqual(len(items), 1)
        self.assertEqual(items[0].text, "Feeling stressed about work")
        self.assertEqual(items[0].source, "conversation")

    def test_short_term_default_expiry_and_ttl(self):
        item = self.engine.remember_short_term(USER, "note", now=NOW)
        self.assertIsNotNone(item.expires_at)
        # Stored item carries a DynamoDB ttl epoch attribute.
        raw = dynamodb.get_item(*_stm_key(USER, item.id))
        self.assertIn("ttl", raw)
        self.assertEqual(raw["ttl"], int(item.expires_at.timestamp()))

    def test_expired_items_filtered_on_read(self):
        self.engine.remember_short_term(
            USER, "old thing", expires_at=NOW - timedelta(days=1), now=NOW - timedelta(days=10)
        )
        self.assertEqual(self.engine.short_term_memories(USER, now=NOW), [])
        # include_expired surfaces it (for the evaluation pass).
        self.assertEqual(
            len(self.engine.short_term_memories(USER, now=NOW, include_expired=True)), 1
        )

    def test_short_term_sorted_by_soonest_event(self):
        self.engine.remember_short_term(
            USER, "later", category="event", event_at=NOW + timedelta(days=30),
            expires_at=NOW + timedelta(days=31), now=NOW,
        )
        self.engine.remember_short_term(
            USER, "sooner", category="event", event_at=NOW + timedelta(days=3),
            expires_at=NOW + timedelta(days=4), now=NOW,
        )
        texts = [m.text for m in self.engine.short_term_memories(USER, now=NOW)]
        self.assertEqual(texts, ["sooner", "later"])

    def test_forget_short_term(self):
        item = self.engine.remember_short_term(USER, "temp", now=NOW)
        self.engine.forget_short_term(USER, item.id)
        self.assertEqual(self.engine.short_term_memories(USER, now=NOW), [])

    # --- calendar ingestion ---------------------------------------------
    def test_ingest_calendar_events_provider_agnostic(self):
        events = [
            {"title": "Wedding", "start": "2026-06-22T15:00:00+00:00", "end": "2026-06-22T23:00:00+00:00"},
            {"summary": "Dentist", "start": "2026-06-05T08:00:00+00:00"},  # google-style 'summary'
            {"name": "Trip", "start": "2026-06-10T00:00:00+00:00"},        # 'name'
        ]
        ingested = self.engine.ingest_calendar_events(USER, events, now=NOW)
        self.assertEqual(len(ingested), 3)
        # Sorted soonest first: Dentist (6/5), Trip (6/10), Wedding (6/22)
        self.assertEqual([m.text for m in ingested][0], "Dentist on 2026-06-05")
        for m in ingested:
            self.assertEqual(m.source, "calendar")
            self.assertEqual(m.category, "event")

    def test_ingest_skips_past_and_far_events(self):
        events = [
            {"title": "Past", "start": "2026-05-01T00:00:00+00:00", "end": "2026-05-01T01:00:00+00:00"},
            {"title": "TooFar", "start": "2026-12-01T00:00:00+00:00"},  # beyond 120d horizon
            {"title": "Good", "start": "2026-06-15T00:00:00+00:00"},
        ]
        ingested = self.engine.ingest_calendar_events(USER, events, now=NOW, horizon_days=120)
        self.assertEqual([m.text for m in ingested], ["Good on 2026-06-15"])

    def test_ingest_dedupes_on_reingest(self):
        events = [{"title": "Wedding", "start": "2026-06-22T15:00:00+00:00"}]
        self.engine.ingest_calendar_events(USER, events, now=NOW)
        self.engine.ingest_calendar_events(USER, events, now=NOW)  # same event again
        items = self.engine.short_term_memories(USER, now=NOW)
        self.assertEqual(len(items), 1)

    def test_ingest_ignores_bad_events(self):
        events = ["nope", {"title": "", "start": "2026-06-10T00:00:00+00:00"}, {"title": "NoStart"}]
        self.assertEqual(self.engine.ingest_calendar_events(USER, events, now=NOW), [])

    # --- daily self-evaluation ------------------------------------------
    def test_evaluate_memory_forgets_keeps_graduates(self):
        # expired -> forgotten
        self.engine.remember_short_term(
            USER, "done deal", expires_at=NOW - timedelta(days=1), now=NOW - timedelta(days=5)
        )
        # active note -> kept
        self.engine.remember_short_term(USER, "still relevant", now=NOW)
        # trait -> graduate to long-term
        self.engine.remember_short_term(
            USER, "prefers morning workouts", category="trait", now=NOW
        )
        review = self.engine.evaluate_memory(USER, now=NOW)
        self.assertIsInstance(review, MemoryReview)
        self.assertIn("done deal", review.forgotten)
        self.assertIn("still relevant", review.kept)
        self.assertIn("prefers morning workouts", review.graduated)
        # graduated fact now in long-term, gone from short-term
        ctx = self.engine.get_or_create_context(USER)
        self.assertIn("prefers morning workouts", ctx.life_facts)
        remaining = [m.text for m in self.engine.short_term_memories(USER, now=NOW)]
        self.assertEqual(remaining, ["still relevant"])

    def test_needs_daily_evaluation(self):
        self.assertTrue(self.engine.needs_daily_evaluation(USER, now=NOW))
        self.engine.evaluate_memory(USER, now=NOW)
        self.assertFalse(self.engine.needs_daily_evaluation(USER, now=NOW))
        # next day -> due again
        self.assertTrue(
            self.engine.needs_daily_evaluation(USER, now=NOW + timedelta(days=1))
        )

    # --- daily check-in --------------------------------------------------
    def test_daily_checkin_once_per_day(self):
        first = self.engine.daily_checkin(USER, now=NOW)
        self.assertIsInstance(first, CheckinPrompt)
        self.assertIn("Anything new", first.text)
        # same day -> None
        self.assertIsNone(self.engine.daily_checkin(USER, now=NOW + timedelta(hours=2)))
        # next day -> checks in again
        self.assertIsNotNone(self.engine.daily_checkin(USER, now=NOW + timedelta(days=1)))

    def test_daily_checkin_references_upcoming_event(self):
        self.engine.ingest_calendar_events(
            USER, [{"title": "Wedding", "start": "2026-06-04T15:00:00+00:00"}], now=NOW
        )
        checkin = self.engine.daily_checkin(USER, now=NOW)
        self.assertIn("Wedding", checkin.text)
        self.assertIn("in 3 days", checkin.text)
        self.assertEqual(len(checkin.upcoming), 1)

    # --- prompt block ----------------------------------------------------
    def test_memory_prompt_block_empty_when_nothing(self):
        self.assertEqual(self.engine.memory_prompt_block(USER, now=NOW), "")

    def test_memory_prompt_block_includes_both_tiers(self):
        self.engine.record_life_fact(USER, "Training for a first 10k")
        self.engine.ingest_calendar_events(
            USER, [{"title": "Race day", "start": "2026-06-08T07:00:00+00:00"}], now=NOW
        )
        block = self.engine.memory_prompt_block(USER, now=NOW)
        self.assertIn("[MEMORY — long term]", block)
        self.assertIn("Training for a first 10k", block)
        self.assertIn("[MEMORY — short term / coming up]", block)
        self.assertIn("Race day", block)

    # --- determinism -----------------------------------------------------
    def test_deterministic_ids_across_instances(self):
        a = CoachContextEngine().remember_short_term(
            USER, "same text", category="event", event_at=NOW + timedelta(days=2),
            expires_at=NOW + timedelta(days=3), now=NOW,
        )
        dynamodb.clear_local_store()
        b = CoachContextEngine().remember_short_term(
            USER, "same text", category="event", event_at=NOW + timedelta(days=2),
            expires_at=NOW + timedelta(days=3), now=NOW,
        )
        self.assertEqual(a.id, b.id)


class HumanizeWhenTests(unittest.TestCase):
    def test_relative_phrasing(self):
        self.assertEqual(_humanize_when(None, NOW), "sometime")
        self.assertEqual(_humanize_when(NOW, NOW), "today")
        self.assertEqual(_humanize_when(NOW + timedelta(days=1), NOW), "tomorrow")
        self.assertEqual(_humanize_when(NOW + timedelta(days=3), NOW), "in 3 days")
        self.assertEqual(_humanize_when(NOW + timedelta(days=21), NOW), "in 3 weeks")
        self.assertEqual(_humanize_when(NOW + timedelta(days=90), NOW), "in 3 months")
        self.assertEqual(_humanize_when(NOW - timedelta(days=2), NOW), "recently")


class MemoryItemSerializationTests(unittest.TestCase):
    def test_round_trip(self):
        item = MemoryItem(
            id="abc", text="wedding", source="calendar", category="event",
            created_at=NOW, expires_at=NOW + timedelta(days=5), event_at=NOW + timedelta(days=4),
        )
        restored = MemoryItem.from_item(item.to_item(USER))
        self.assertEqual(restored.id, "abc")
        self.assertEqual(restored.text, "wedding")
        self.assertEqual(restored.category, "event")
        self.assertEqual(restored.event_at, item.event_at)


class RouteWiringTests(unittest.TestCase):
    """handle_post_ai_chat wires the companion engine in, lifestyle-gated."""

    def setUp(self):
        dynamodb.clear_local_store()

    def _chat(self, uid, body):
        import json
        from routes.aria import handle_post_ai_chat
        result = handle_post_ai_chat(body, user_id=uid)
        self.assertEqual(result["statusCode"], 200)
        return json.loads(result["body"])

    def test_chat_ingests_calendar_and_checks_in(self):
        uid = "route-user-1"
        # Route uses real wall-clock now(); pick a date inside the ingest horizon.
        soon = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
        body = {
            "message": "hey",
            "recent_metrics": {"readiness": 80},
            "calendar_events": [{"title": "Sister's wedding", "start": soon}],
        }
        out = self._chat(uid, body)
        self.assertTrue(out["calendar_ingested"])
        self.assertIsNotNone(out["checkin"])
        self.assertIn("Anything new", out["checkin"]["text"])
        self.assertIn("wedding", (out["memory"] or "").lower())
        # Second chat the same day -> already checked in.
        out2 = self._chat(uid, {"message": "again", "recent_metrics": {"readiness": 80}})
        self.assertIsNone(out2["checkin"])

    def test_lifestyle_restricted_suppresses_memory(self):
        uid = "route-user-2"
        soon = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
        body = {
            "message": "hey",
            "recent_metrics": {"readiness": 80},
            "permissions": {"deny": ["lifestyle"]},
            "calendar_events": [{"title": "Sister's wedding", "start": soon}],
        }
        out = self._chat(uid, body)
        self.assertEqual(out["calendar_ingested"], [])
        self.assertIsNone(out["checkin"])
        self.assertIsNone(out["memory"])
        # Nothing was persisted to the short-term store either.
        self.assertEqual(CoachContextEngine().short_term_memories(uid), [])


def _stm_key(user_id: str, mem_id: str):
    from storage import keys
    k = keys.aria_short_term_key(user_id, mem_id)
    return k["pk"], k["sk"]


if __name__ == "__main__":
    unittest.main()
