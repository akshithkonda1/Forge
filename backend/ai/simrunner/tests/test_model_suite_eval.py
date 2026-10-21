"""Quality + cost eval for the three-model suite vs the old package-size race.

Offline. No Bedrock. Dummy `engine="lambda"` (real fuse_turn + generate_response)
and Nyx voice-check fixtures. Cost is the policy's weighted Converse units,
not a live bill.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")
os.environ.pop("ENVIRONMENT", None)

from backend._paths import ensure_lambda_on_path  # noqa: E402
from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner.nyx_voice_check import (  # noqa: E402
    IRIS_LIFESTYLE_FIXTURES,
    voice_check_failures,
)

ensure_lambda_on_path()

from aria_core.model_suite import (  # noqa: E402
    classify_intent,
    estimate_cost_units,
    legacy_fanout_cost,
    plan_route,
)
from aria_core.safety_rails import apply_rails, violations  # noqa: E402
from aria_core.speak_guard import spoken_ban_hits  # noqa: E402


# Mixed production-like questions. Sizes match the old router's cheap/huge bands.
_EVAL_CASES: tuple[tuple[str, int], ...] = (
    ("hi", 800),
    ("How was my sleep last night?", 1200),
    ("Should I train today?", 2048),
    ("What's the move this afternoon?", 2048),
    ("Plan my week of training around work", 4096),
    ("Summarize this month's progress", 8192),
    ("I have chest pain", 512),
    ("Summarize the uploaded health data.", 9 * 1024 * 1024 * 1024),
)


def _legacy_cost(size: int) -> float:
    units = legacy_fanout_cost(size, consensus=False)
    # Old policy ran a consensus Converse whenever 2+ producers launched.
    launched = 1 if units <= 1.01 else 2 if units <= 3.6 else 3
    return legacy_fanout_cost(size, consensus=launched >= 2)


def _new_cost(question: str) -> float:
    plan = plan_route(question)
    return estimate_cost_units([plan.primary.role], consensus=False)


class ModelSuiteEvalTests(unittest.TestCase):
    def test_cost_per_request_equal_or_lower(self):
        old_total = sum(_legacy_cost(sz) for _, sz in _EVAL_CASES)
        new_total = sum(_new_cost(q) for q, _ in _EVAL_CASES)
        old_avg = old_total / len(_EVAL_CASES)
        new_avg = new_total / len(_EVAL_CASES)
        # Scout=1.0, Reasoner=2.5. Mixed set: old 1.575 → new 1.375 (−13%).
        self.assertAlmostEqual(old_avg, 1.575, places=3)
        self.assertAlmostEqual(new_avg, 1.375, places=3)
        self.assertLessEqual(new_avg, old_avg)
        self.assertEqual(max(len(plan_route(q).initial_slots) for q, _ in _EVAL_CASES), 1)

    def test_dummy_lambda_quality_meets_rails_and_voice_check(self):
        os.environ.setdefault("ARIA_BEDROCK_ENABLED", "")
        replies: list[str] = []
        for query in (
            "Should I train today?",
            "How was my sleep last night?",
            "I feel wiped, what should I do?",
        ):
            result = dummy.respond(query, engine="lambda", seed=1)
            text = str(result.get("message") or result.get("prose_summary") or "")
            replies.append(text)
            self.assertFalse(violations(text), (query, text, violations(text)))
            self.assertFalse(spoken_ban_hits(text), (query, text, spoken_ban_hits(text)))
            self.assertFalse(voice_check_failures(text), (query, text, voice_check_failures(text)))

        for fixture in IRIS_LIFESTYLE_FIXTURES:
            cleaned = apply_rails(fixture)
            self.assertFalse(violations(cleaned), (fixture, cleaned))
            self.assertFalse(voice_check_failures(cleaned), cleaned)

        self.assertTrue(all(replies))

    def test_intent_assignment_matches_roles(self):
        self.assertEqual(classify_intent("Plan my week"), "plan")
        self.assertEqual(plan_route("Plan my week").primary.role, "reasoner")
        self.assertEqual(plan_route("hi").primary.role, "scout")
        self.assertEqual(plan_route("I have chest pain").intent, "safety")
