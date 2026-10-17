"""Adaptive ARIA context store — Python twin of AriaContextMemoryTests."""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import aria_context_memory as acm  # noqa: E402

NOW = 1_700_000_000.0


def _item(item_id: str, text: str, domain: str) -> dict:
    return {
        "id": item_id,
        "text": text,
        "domain": domain,
        "confidence": 0.55,
        "updatedAt": NOW,
        "signals": {},
        "userLocked": False,
    }


class AriaContextMemoryAdaptiveTests(unittest.TestCase):
    def test_two_engagement_histories_rank_and_retain_differently(self):
        pottery = _item("p", "pottery nights", "lifestyle_hobbies")
        dream = _item("d", "I dreamed of water", "sleep_dreams")
        hobbies_items = [dict(pottery), dict(dream)]
        dreams_items = [dict(pottery), dict(dream)]
        hobbies_stats: dict = {
            "lifestyle_hobbies": {"mentions": 1},
            "sleep_dreams": {"mentions": 1},
        }
        dreams_stats: dict = {
            "lifestyle_hobbies": {"mentions": 1},
            "sleep_dreams": {"mentions": 1},
        }

        for _ in range(4):
            hobbies_items[0], hobbies_stats = acm.record(hobbies_items[0], hobbies_stats, "replied")
            hobbies_items[0], hobbies_stats = acm.record(hobbies_items[0], hobbies_stats, "acted")
            hobbies_items[1], hobbies_stats = acm.record(hobbies_items[1], hobbies_stats, "ignored")
            dreams_items[1], dreams_stats = acm.record(dreams_items[1], dreams_stats, "replied")
            dreams_items[0], dreams_stats = acm.record(dreams_items[0], dreams_stats, "ignored")

        self.assertGreater(
            acm.retention_priority("lifestyle_hobbies", hobbies_stats),
            acm.retention_priority("lifestyle_hobbies", dreams_stats),
        )
        self.assertGreater(
            acm.retention_priority("sleep_dreams", dreams_stats),
            acm.retention_priority("sleep_dreams", hobbies_stats),
        )
        self.assertEqual(acm.granularity("lifestyle_hobbies", hobbies_stats), "fine")
        self.assertEqual(acm.granularity("lifestyle_hobbies", dreams_stats), "coarse")
        self.assertGreater(
            acm.decay_half_life_days("lifestyle_hobbies", hobbies_stats),
            acm.decay_half_life_days("lifestyle_hobbies", dreams_stats),
        )
        self.assertGreater(
            acm.item_decay_half_life_days(hobbies_items[0], hobbies_stats),
            acm.item_decay_half_life_days(dreams_items[0], dreams_stats),
        )

        hobby_rank = acm.rank(hobbies_items, hobbies_stats, NOW)
        dream_rank = acm.rank(dreams_items, dreams_stats, NOW)
        self.assertEqual(hobby_rank[0]["domain"], "lifestyle_hobbies")
        self.assertEqual(dream_rank[0]["domain"], "sleep_dreams")
        self.assertNotEqual([row["id"] for row in hobby_rank], [row["id"] for row in dream_rank])

        hobby_top = acm.explain(hobby_rank[0], hobbies_stats, NOW)
        hobby_second = acm.explain(hobby_rank[1], hobbies_stats, NOW)
        self.assertGreater(hobby_top["learnedRelevance"], hobby_second["learnedRelevance"])
        self.assertEqual(hobby_top["formula"], acm.RANK_FORMULA)

        kept_hobbies = acm.retain(hobbies_items, hobbies_stats, NOW, cap=1)
        kept_dreams = acm.retain(dreams_items, dreams_stats, NOW, cap=1)
        self.assertEqual(len(kept_hobbies), 1)
        self.assertEqual(len(kept_dreams), 1)
        self.assertEqual(kept_hobbies[0]["domain"], "lifestyle_hobbies")
        self.assertEqual(kept_dreams[0]["domain"], "sleep_dreams")
        self.assertNotEqual(kept_hobbies[0]["id"], kept_dreams[0]["id"])
        self.assertTrue(acm.BEDROCK_OFF)
        self.assertTrue(acm.BACKUP_EXCLUDED)

    def test_user_delete_overrides_learned_relevance(self):
        item = _item("p", "pottery nights", "lifestyle_hobbies")
        stats: dict = {"lifestyle_hobbies": {"mentions": 1}}
        for _ in range(6):
            item, stats = acm.record(item, stats, "acted")
        payload = {"items": [item]}
        tombstones = [{"id": "p", "fingerprint": acm.fingerprint("lifestyle_hobbies", "pottery nights")}]
        cleared = acm.apply_tombstones(payload, tombstones)
        self.assertEqual(cleared["items"], [])
        ranked = acm.rank(cleared["items"], stats, NOW)
        self.assertEqual(ranked, [])

    def test_locked_edit_survives_retention(self):
        locked = _item("h", "I like hiking", "lifestyle_hobbies")
        locked["userLocked"] = True
        popular = _item("d", "I dreamed of water", "sleep_dreams")
        stats: dict = {
            "lifestyle_hobbies": {"mentions": 1},
            "sleep_dreams": {"mentions": 1},
        }
        for _ in range(8):
            popular, stats = acm.record(popular, stats, "acted")
        kept = acm.retain([locked, popular], stats, NOW, cap=1)
        ids = {row["id"] for row in kept}
        self.assertIn("h", ids)
        self.assertEqual(next(row["text"] for row in kept if row["id"] == "h"), "I like hiking")
