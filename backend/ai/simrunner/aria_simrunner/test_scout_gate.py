"""Tests for the Scout query gate and client.

No network. FORGE_SCOUT_URL is unset in these tests, so the client is
fail-closed by construction. The gate is pure function + string matching.
"""

from __future__ import annotations

import time
import unittest

from .scout_client import ScoutClient
from .scout_gate import (
    ScoutGateDecision,
    ScoutMissionBrief,
    classify_query_for_scout,
)


class GateFiresTests(unittest.TestCase):
    def test_research_phrase_fires(self):
        d = classify_query_for_scout("How do I lose fat and gain muscle?", "training")
        self.assertTrue(d.active)
        self.assertEqual(d.reason, "research_phrase")
        assert d.brief is not None
        self.assertIn("training", d.brief.keywords)
        self.assertIn("lose", d.brief.keywords)
        self.assertIn("fat", d.brief.keywords)
        self.assertIn("muscle", d.brief.keywords)

    def test_aging_always_fires(self):
        d = classify_query_for_scout("What's my training age?", "lifestyle")
        self.assertTrue(d.active)
        self.assertEqual(d.reason, "aging")

    def test_fever_always_fires(self):
        d = classify_query_for_scout("I have a fever of 101", "body")
        self.assertTrue(d.active)
        self.assertEqual(d.reason, "fever")
        assert d.brief is not None
        self.assertEqual(d.brief.domain, "fever")

    def test_event_prep_fires(self):
        d = classify_query_for_scout("What should I wear to the wedding?", "lifestyle")
        self.assertTrue(d.active)
        self.assertEqual(d.reason, "event_prep")

    def test_wedding_wear_combo(self):
        d = classify_query_for_scout("dress for a wedding this weekend", "lifestyle")
        self.assertTrue(d.active)


class GateDoesNotFireTests(unittest.TestCase):
    def test_plain_readiness_no_fire(self):
        d = classify_query_for_scout("What's my readiness today?", "readiness")
        self.assertFalse(d.active)
        self.assertEqual(d.reason, "no_trigger")

    def test_companion_domain_never_fires(self):
        d = classify_query_for_scout("How are you feeling about us?", "companion")
        self.assertFalse(d.active)
        self.assertIn("domain_not_allowed", d.reason)

    def test_empty_message(self):
        d = classify_query_for_scout("", "lifestyle")
        self.assertFalse(d.active)

    def test_crisis_phrase_does_not_fire_scout(self):
        # Scout is not a crisis path. Safety owns that.
        d = classify_query_for_scout("I don't want to live anymore", "companion")
        self.assertFalse(d.active)


class MissionBriefTests(unittest.TestCase):
    def test_brief_shape(self):
        d = classify_query_for_scout("How much protein should I eat?", "nutrition")
        assert d.brief is not None
        b = d.brief
        self.assertIsInstance(b.keywords, tuple)
        self.assertTrue(b.keywords)
        self.assertLessEqual(len(b.keywords), 8)
        self.assertEqual(b.domain, "nutrition")
        self.assertEqual(len(b.cache_key), 16)
        # Question is capped.
        self.assertLessEqual(len(b.question), 500)

    def test_keywords_scrubbed(self):
        d = classify_query_for_scout("How do I train for a marathon?", "training")
        assert d.brief is not None
        for kw in d.brief.keywords:
            self.assertNotIn(" ", kw)
            self.assertTrue(kw.isalnum())

    def test_cache_key_stable(self):
        d1 = classify_query_for_scout("protein intake for runners", "nutrition")
        d2 = classify_query_for_scout("runners protein intake", "nutrition")
        # Same keyword set -> same cache key regardless of order in the message.
        assert d1.brief is not None and d2.brief is not None
        self.assertEqual(d1.brief.cache_key, d2.brief.cache_key)


class ClientTests(unittest.TestCase):
    def test_no_url_means_no_network(self):
        c = ScoutClient()  # FORGE_SCOUT_URL unset
        brief = ScoutMissionBrief(
            keywords=("training", "marathon"),
            question="How do I train for a marathon?",
            domain="training",
            cache_key="abc123",
        )
        self.assertIsNone(c.execute(brief))

    def test_cache_hit(self):
        calls = {"n": 0}

        def transport(url, payload, timeout):
            calls["n"] += 1
            return "From CDC: run 150 minutes a week."

        c = ScoutClient(transport=transport)
        brief = ScoutMissionBrief(
            keywords=("training", "run"),
            question="How often should I run?",
            domain="training",
            cache_key="key1",
        )
        t1 = c.execute(brief)
        t2 = c.execute(brief)
        self.assertEqual(t1, t2)
        self.assertEqual(calls["n"], 1)

    def test_cache_expires(self):
        calls = {"n": 0}

        def transport(url, payload, timeout):
            calls["n"] += 1
            return f"brief-{calls['n']}"

        c = ScoutClient(transport=transport)
        brief = ScoutMissionBrief(
            keywords=("x",), question="q", domain="training", cache_key="k2"
        )
        c.execute(brief)
        # Force expiry.
        c._cache["k2"].expires_at = time.monotonic() - 1
        c.execute(brief)
        self.assertEqual(calls["n"], 2)

    def test_timeout_fail_closed(self):
        def transport(url, payload, timeout):
            raise TimeoutError("slow box")

        c = ScoutClient(transport=transport)
        brief = ScoutMissionBrief(
            keywords=("x",), question="q", domain="training", cache_key="k3"
        )
        self.assertIsNone(c.execute(brief))

    def test_bad_status_fail_closed(self):
        def transport(url, payload, timeout):
            return None  # simulates non-200

        c = ScoutClient(transport=transport)
        brief = ScoutMissionBrief(
            keywords=("x",), question="q", domain="training", cache_key="k4"
        )
        self.assertIsNone(c.execute(brief))

    def test_response_capped(self):
        def transport(url, payload, timeout):
            return "A" * 10_000

        c = ScoutClient(transport=transport)
        brief = ScoutMissionBrief(
            keywords=("x",), question="q", domain="training", cache_key="k5"
        )
        text = c.execute(brief)
        assert text is not None
        self.assertEqual(len(text), 4000)


if __name__ == "__main__":
    unittest.main()
