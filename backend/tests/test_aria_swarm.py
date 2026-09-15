"""ARIA Swarm — background wearable read/evaluate/write, no model."""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from services import aria_swarm
from services.aria_engine import (
    ARIAContext,
    ActivityContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)
from storage import dynamodb  # noqa: F401  — local store for persist tests
from services.aria_context import CoachContextEngine


def _ctx(**kwargs) -> ARIAContext:
    return ARIAContext(
        sleep=SleepContext(
            duration_minutes=kwargs.get("sleep_minutes", 450),
            hrv=kwargs.get("hrv", 55),
        ),
        readiness=ReadinessContext(
            recovery_score=kwargs.get("recovery", 72),
            hrv_7day_trend=kwargs.get("hrv_trend", 0),
        ),
        activity=ActivityContext(steps_3day_avg=kwargs.get("steps", 8000)),
        training=TrainingContext(
            last_workout_type=kwargs.get("workout", "strength"),
            hours_since_last_workout=kwargs.get("hours_since", 20),
        ),
    )


class CanonicalSourceTests(unittest.TestCase):
    def test_rra_and_watch_aliases(self):
        self.assertEqual(aria_swarm.canonical_source("RRA"), "oura")
        self.assertEqual(aria_swarm.canonical_source("oura"), "oura")
        self.assertEqual(aria_swarm.canonical_source("Apple Watch"), "apple-watch")
        self.assertEqual(aria_swarm.canonical_source("apple-health"), "apple-watch")
        self.assertEqual(aria_swarm.canonical_source("WHOOP"), "whoop")
        self.assertIsNone(aria_swarm.canonical_source("simrunner"))
        self.assertIsNone(aria_swarm.canonical_source(""))


class SwarmReadEvaluateWriteTests(unittest.TestCase):
    def test_context_only_splits_across_whoop_watch_oura(self):
        picture = aria_swarm.run_swarm(context=_ctx(sleep_minutes=300, recovery=40))
        self.assertEqual(picture["name"], "swarm")
        self.assertEqual(picture["slot_name"], "Grok")
        self.assertTrue(picture["agentic"])
        self.assertIsNone(picture["model"])
        self.assertEqual(picture["stages"], ["read", "evaluate", "write"])
        ids = [s["id"] for s in picture["sources"] if s["present"]]
        self.assertIn("whoop", ids)
        self.assertIn("oura", ids)
        self.assertIn("apple-watch", ids)
        kinds = {(a["source"], a["kind"]) for a in picture["agents"]}
        self.assertIn(("whoop", "recovery"), kinds)
        self.assertIn(("oura", "sleep"), kinds)
        self.assertIn(("apple-watch", "activity"), kinds)
        self.assertEqual(picture["picture"]["stance"], "protect")
        self.assertTrue(picture["picture"]["headline"])
        self.assertTrue(picture["picture"]["writes"])

    def test_headline_never_dumps_vitals(self):
        picture = aria_swarm.run_swarm(context=_ctx(sleep_minutes=300, hrv=38, recovery=41))
        blob = f"{picture['picture']['headline']} " + " ".join(
            w["summary"] for w in picture["picture"]["writes"]
        )
        self.assertNotRegex(blob, r"\d+\s?(ms|bpm|%)")
        self.assertNotIn("HRV", blob)
        self.assertNotIn("Readiness", blob)

    def test_samples_keep_vendor_attribution(self):
        samples = [
            {"type": "sleep", "value": 480, "unit": "min", "source": "rra"},
            {"type": "hrv", "value": 40, "unit": "ms", "source": "whoop"},
            {"type": "steps", "value": 9000, "unit": "count", "source": "apple-health"},
        ]
        picture = aria_swarm.run_swarm(context=_ctx(), samples=samples)
        by_id = {s["id"]: s for s in picture["sources"]}
        self.assertTrue(by_id["oura"]["present"])
        self.assertTrue(by_id["whoop"]["present"])
        self.assertTrue(by_id["apple-watch"]["present"])
        oura_sleep = next(a for a in picture["agents"] if a["id"] == "oura-sleep")
        self.assertNotEqual(oura_sleep["stance"], "missing")
        self.assertEqual(oura_sleep["ops"], ["read", "evaluate", "write"])

    def test_untagged_simrunner_samples_are_attributed(self):
        samples = [
            {"type": "sleep", "value": 300, "unit": "min", "source": "simrunner"},
            {"type": "hrv", "value": 42, "unit": "ms", "source": "simrunner"},
            {"type": "steps", "value": 4000, "unit": "count"},
        ]
        picture = aria_swarm.run_swarm(samples=samples, context=_ctx(sleep_minutes=300, recovery=40))
        present = {s["id"] for s in picture["sources"] if s["present"]}
        self.assertIn("oura", present)
        self.assertIn("whoop", present)
        self.assertIn("apple-watch", present)

    def test_missing_wearables_are_honest(self):
        picture = aria_swarm.run_swarm(context=ARIAContext())
        self.assertEqual(picture["picture"]["stance"], "clarify")
        blob = picture["picture"]["headline"].lower()
        self.assertTrue("won't pretend" in blob or "no wearable" in blob)
        for agent in picture["agents"]:
            self.assertEqual(agent["stance"], "missing")
            self.assertIn("read", agent["ops"])

    def test_determinism(self):
        a = aria_swarm.run_swarm(context=_ctx(sleep_minutes=420, recovery=70))
        b = aria_swarm.run_swarm(context=_ctx(sleep_minutes=420, recovery=70))
        self.assertEqual(a, b)

    def test_persist_writes_actionable_picture(self):
        dynamodb.clear_local_store()
        engine = CoachContextEngine()
        uid = "swarm-user"
        picture = aria_swarm.run_swarm(
            context=_ctx(sleep_minutes=300, recovery=38),
            persist_to=engine,
            user_id=uid,
        )
        self.assertTrue(picture["wrote"])
        stored = engine.get_or_create_context(uid)
        self.assertTrue(stored.last_insights)
        self.assertEqual(stored.last_insights[0], picture["picture"]["headline"])

    def test_never_calls_a_model(self):
        from pathlib import Path

        src = Path(aria_swarm.__file__).read_text(encoding="utf-8")
        imports = [
            line.strip()
            for line in src.splitlines()
            if line.strip().startswith(("import ", "from "))
        ]
        blob = "\n".join(imports).lower()
        for needle in ("boto3", "botocore", "bedrock", "converse", "generate_response_live"):
            self.assertNotIn(needle, blob, needle)
        self.assertNotIn("generate_response_live", src)


class SwarmChatWireTests(unittest.TestCase):
    def test_chat_attaches_swarm_without_bedrock(self):
        import json
        from routes.aria import handle_post_ai_chat

        dynamodb.clear_local_store()
        uid = "swarm-chat"
        result = handle_post_ai_chat(
            {
                "user_id": uid,
                "message": "What should I train today?",
                "samples": [
                    {"type": "hrv", "value": 40, "unit": "ms", "source": "whoop"},
                    {"type": "sleep", "value": 300, "unit": "min", "source": "oura"},
                    {"type": "steps", "value": 8000, "unit": "count", "source": "apple-health"},
                ],
                "context": {
                    "sleep": {"durationMinutes": 300, "hrv": 40},
                    "readiness": {"recoveryScore": 42},
                },
            },
            user_id=uid,
        )
        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        swarm = body["swarm"]
        self.assertEqual(swarm["name"], "swarm")
        self.assertEqual(swarm["slot_name"], "Grok")
        self.assertIsNone(swarm["model"])
        self.assertTrue(swarm["picture"]["headline"])
        self.assertNotIn("HRV", body.get("prose_summary") or "")


if __name__ == "__main__":
    unittest.main()
