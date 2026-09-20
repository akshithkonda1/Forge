"""Tests for services.aria_user_model.build_user_model — the canonical
context builder that is not yet wired into any route (see its module
docstring for why). These tests pin its behavior in isolation so wiring it
in later starts from a known-correct function, not an untested one."""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from services import aria_engine  # noqa: E402
from services.aria_context import CoachContextEngine  # noqa: E402
from services.aria_user_model import build_user_model  # noqa: E402
from storage import dynamodb, keys  # noqa: E402

USER = "test-user-00000000"


def _seed_sleep(user_id: str, date: str, **fields) -> None:
    dynamodb.put_item({**keys.sleep_key(user_id, date, "manual"), **fields})


class BuildUserModelTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_empty_history_and_payload_does_not_crash(self):
        ctx, perms = build_user_model(user_id=USER)
        self.assertIsInstance(ctx, aria_engine.ARIAContext)
        self.assertIsInstance(perms, aria_engine.DataPermissions)

    def test_sleep_history_feeds_the_body_model(self):
        _seed_sleep(USER, "2026-06-01", totalHours=7.5, deepMinutes=80, remMinutes=95)
        ctx, _ = build_user_model(user_id=USER)
        self.assertIsNotNone(ctx.sleep.duration_minutes)
        self.assertAlmostEqual(ctx.sleep.duration_minutes, 7.5 * 60, places=1)

    def test_sleep_score_never_leaks_into_rem_minutes(self):
        """Regression test: a prior version mislabeled the sleep `score`
        field (0-100ish) as a SLEEP_REM observation (minutes), corrupting
        the REM series with garbage. A row with a score but no remMinutes
        must not populate rem_minutes at all."""
        _seed_sleep(USER, "2026-06-01", totalHours=7.0, score=82)
        ctx, _ = build_user_model(user_id=USER)
        self.assertIsNone(ctx.sleep.rem_minutes)

    def test_payload_overlays_history(self):
        _seed_sleep(USER, "2026-06-01", totalHours=6.0)
        payload = {
            "user_id": USER,
            "context": {"sleep": {"durationMinutes": 500}},
        }
        ctx, _ = build_user_model(payload, user_id=USER)
        self.assertEqual(ctx.sleep.duration_minutes, 500)

    def test_short_term_memory_becomes_a_lifestyle_tag(self):
        engine = CoachContextEngine()
        engine.remember_short_term(USER, "Wedding in three weeks", category="event")
        ctx, _ = build_user_model(user_id=USER)
        self.assertTrue(any(t.startswith("stm:") for t in ctx.lifestyle.tags))

    def test_life_facts_become_lifestyle_tags(self):
        engine = CoachContextEngine()
        engine.record_life_fact(USER, "Training for a first 10k")
        ctx, _ = build_user_model(user_id=USER)
        self.assertTrue(any(t.startswith("life:") for t in ctx.lifestyle.tags))

    def test_restricted_lifestyle_permission_skips_memory_tags(self):
        engine = CoachContextEngine()
        engine.remember_short_term(USER, "Wedding in three weeks", category="event")
        engine.record_life_fact(USER, "Training for a first 10k")
        perms = aria_engine.DataPermissions.from_payload({"deny": ["lifestyle"]})
        ctx, _ = build_user_model(user_id=USER, permissions=perms)
        self.assertFalse(any(t.startswith("stm:") or t.startswith("life:") for t in ctx.lifestyle.tags))

    def test_anon_user_id_falls_back_gracefully(self):
        ctx, _ = build_user_model({"context": {}})
        self.assertIsInstance(ctx, aria_engine.ARIAContext)


if __name__ == "__main__":
    unittest.main()
