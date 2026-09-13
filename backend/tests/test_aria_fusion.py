"""Locks the hybrid-fusion hot path: one BodyModel + persona truth.

Chat used to template ``generate_response`` off the client bag while observe
ran BodyModel without a persona. These tests fail if that split returns, if
stance does not change the shipped plan/session, or if a persona load failure
is silently relabeled as a cold start.
"""

from __future__ import annotations

import json
import unittest
from datetime import datetime, timedelta, timezone
from unittest.mock import patch

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from services import aria_engine, contextual_learner, fusion  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    LifestyleContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)
from storage import dynamodb, keys  # noqa: E402

BASE = datetime(2026, 6, 10, tzinfo=timezone.utc)


def _event(path: str, body: dict, *, user_id: str) -> dict:
    return {
        "requestContext": {
            "http": {"method": "POST", "path": path},
            "authorizer": {"jwt": {"claims": {"sub": user_id}}},
        },
        "body": json.dumps(body),
    }


def _post(path: str, body: dict, *, user_id: str) -> tuple[int, dict]:
    resp = handler(_event(path, body, user_id=user_id), None)
    return resp["statusCode"], json.loads(resp["body"])


def _sleep_hrv_samples(*, duration_min: float = 300, hrv_start: float = 42) -> list[dict]:
    samples = []
    for day in range(8):
        ts = (BASE + timedelta(days=day)).isoformat()
        samples.append(
            {"type": "hrv", "value": hrv_start - day, "unit": "ms", "timestamp": ts, "source": "oura"}
        )
    samples.append(
        {
            "type": "sleep",
            "value": duration_min,
            "unit": "min",
            "timestamp": (BASE + timedelta(days=7)).isoformat(),
            "source": "oura",
        }
    )
    samples.append(
        {
            "type": "resting-heart-rate",
            "value": 62,
            "unit": "bpm",
            "timestamp": (BASE + timedelta(days=7)).isoformat(),
            "source": "apple-health",
        }
    )
    return samples


def _ready_ctx(**kwargs) -> ARIAContext:
    return ARIAContext(
        sleep=SleepContext(
            duration_minutes=kwargs.get("sleep_minutes", 450),
            deep_minutes=95,
            rem_minutes=100,
            efficiency=0.90,
            hrv=60,
            nights_available=7,
        ),
        readiness=ReadinessContext(
            hrv_7day_trend=kwargs.get("hrv_trend", 2.0),
            hrv_30day_baseline=60,
            recovery_score=kwargs.get("recovery", 78),
            hrv_days_available=7,
        ),
        training=TrainingContext(
            last_workout_type="strength",
            last_workout_name="Tuesday Leg Day",
            hours_since_last_workout=kwargs.get("hours_since", 20),
        ),
        lifestyle=LifestyleContext(tags=list(kwargs.get("tags", []))),
    )


class OverlayAndPersistTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_body_model_domains_win_over_conflicting_client_bag(self):
        client = ARIAContext.from_payload(
            {"context": {"sleep": {"durationMinutes": 480}, "readiness": {"recoveryScore": 90}}}
        )
        body = ARIAContext.from_payload(
            {"context": {"sleep": {"durationMinutes": 300}, "readiness": {"recoveryScore": 44}}}
        )
        merged = fusion.overlay_context(client, body, ["sleep", "readiness"])
        self.assertEqual(merged.sleep.duration_minutes, 300)
        self.assertEqual(merged.readiness.recovery_score, 44)

    def test_observe_persists_snapshot_chat_refuses_stale_client_sleep(self):
        uid = "fuse-chat-user"
        samples = _sleep_hrv_samples(duration_min=300)
        status, observed = _post(
            "/ai/observe",
            {"user_id": uid, "samples": samples, "include_stored": False},
            user_id=uid,
        )
        self.assertEqual(status, 200)
        self.assertEqual(observed["fusion"]["source"], "body_model")
        stored = dynamodb.get_item(**keys.aria_body_snapshot_key(uid))
        self.assertIsNotNone(stored)
        observed_sleep = observed["aria_context"]["sleep"]["duration_minutes"]
        self.assertAlmostEqual(observed_sleep, 300, places=0)

        status, chat = _post(
            "/ai/chat",
            {
                "user_id": uid,
                "message": "should I train today?",
                "context": {
                    "sleep": {"durationMinutes": 480, "nightsAvailable": 7},
                    "readiness": {"recoveryScore": 92, "hrv7DayTrend": 8},
                },
            },
            user_id=uid,
        )
        self.assertEqual(status, 200)
        self.assertEqual(chat["fusion"]["source"], "persisted")
        self.assertIn("sleep", chat["fusion"]["owned_domains"])
        self.assertNotEqual(chat["fusion"]["source"], "payload")
        # Client asked for a green-light 8h night; ingested truth is the short night.
        self.assertEqual(chat["fusion"]["stance"], "protect")
        action = (chat.get("card") or {}).get("action") or chat["fusion"].get("action") or ""
        self.assertTrue(action)
        self.assertNotIn("Green light", action)

    def test_chat_and_observe_share_the_same_body_for_one_turn(self):
        uid = "fuse-share-user"
        samples = _sleep_hrv_samples(duration_min=430, hrv_start=55)
        _, observed = _post(
            "/ai/observe",
            {"user_id": uid, "samples": samples, "include_stored": False, "message": "how am I recovering?"},
            user_id=uid,
        )
        _, chat = _post(
            "/ai/chat",
            {"user_id": uid, "message": "how am I recovering?", "include_stored": False},
            user_id=uid,
        )
        self.assertEqual(chat["fusion"]["source"], "persisted")
        obs_rec = observed["aria_context"]["readiness"]["recovery_score"]
        # Chat must not invent a second recovery number from an empty client bag.
        self.assertIsNotNone(obs_rec)
        self.assertIn(chat["fusion"]["persona_status"], ("loaded", "cold_start"))
        self.assertNotEqual(chat["fusion"]["persona_status"], "skipped")


class StanceChangesPlanTests(unittest.TestCase):
    def test_protect_vs_proceed_changes_card_action_and_session(self):
        proceed_ctx = _ready_ctx(tags=[])
        protect_ctx = _ready_ctx(tags=["calendar:kind:wedding", "calendar:evening:busy", "calendar:busy:4"])
        proceed = aria_engine.generate_response("What should I train today?", proceed_ctx)
        protect = aria_engine.generate_response("What should I train today?", protect_ctx)
        self.assertEqual(proceed["response_type"], "recommendation")
        self.assertEqual(protect["response_type"], "recommendation")
        self.assertEqual(protect["fusion"]["stance"], "protect")
        self.assertNotEqual(proceed["fusion"]["stance"], "protect")
        self.assertNotEqual(proceed["card"]["action"], protect["card"]["action"])
        self.assertTrue(proceed.get("session"))
        self.assertTrue(protect.get("session"))
        self.assertEqual(protect["session"]["region"], "core")
        self.assertNotEqual(proceed["session"]["region"], protect["session"]["region"])

    def test_personal_sleep_baseline_changes_the_plan(self):
        ctx = _ready_ctx(sleep_minutes=420, recovery=72, hrv_trend=1.0, hours_since=48)
        population = aria_engine.generate_response("should I train today?", ctx)
        baselines = fusion.PersonalBaselines(
            sleep_duration_min=8.5 * 60,
            sleep_duration_n=14,
            sleep_n=14,
            robust=True,
        )
        personal = aria_engine.generate_response("should I train today?", ctx, baselines=baselines)
        self.assertEqual(personal["fusion"]["baseline_kind"], "personal")
        self.assertEqual(personal["fusion"]["stance"], "protect")
        self.assertNotEqual(population["card"]["action"], personal["card"]["action"])
        self.assertIn("usual", (personal.get("prose_summary") or "").lower() + (personal["card"].get("rationale") or "").lower())


class PersonaErrorAndInsightTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_persona_load_failure_is_named_not_cold_start(self):
        uid = "fuse-load-fail"
        with patch.object(contextual_learner, "load", side_effect=RuntimeError("ddb down")):
            status, chat = _post(
                "/ai/chat",
                {"user_id": uid, "message": "should I train today?", "recent_metrics": {"readiness": 70}},
                user_id=uid,
            )
        self.assertEqual(status, 200)
        self.assertEqual(chat["fusion"]["persona_status"], "load_failed")
        self.assertIn("RuntimeError", chat["fusion"].get("persona_error") or "")
        self.assertNotEqual(chat["fusion"]["persona_status"], "cold_start")

    def test_insight_mode_reads_fused_stance_but_does_not_commit(self):
        """Documented exception: insight tabs consume fused truth + current stance,
        and do not write the learner or bump relationship."""
        uid = "fuse-insight"
        state = contextual_learner.PersonaState()
        state.n_chat = 6
        state.last_stance = "proceed"
        contextual_learner.save(uid, state)
        _post(
            "/ai/observe",
            {"user_id": uid, "samples": _sleep_hrv_samples(duration_min=440), "include_stored": False},
            user_id=uid,
        )
        status, chat = _post(
            "/ai/chat",
            {
                "user_id": uid,
                "message": "Analyze my lifestyle today in 2-3 sentences.",
                "mode": "insight",
                "recent_metrics": {"readiness": 72},
            },
            user_id=uid,
        )
        self.assertEqual(status, 200)
        self.assertEqual(chat.get("context_updates"), {})
        self.assertEqual(chat.get("reasoning_source"), "deterministic")
        self.assertEqual(chat["fusion"]["source"], "persisted")
        self.assertIn(chat["fusion"]["stance"], contextual_learner.STANCES)
        reloaded = contextual_learner.load(uid)
        self.assertEqual(reloaded.last_stance, "proceed")
        self.assertEqual(reloaded.n_chat, 6)


class SnapshotKeyTests(unittest.TestCase):
    def test_body_snapshot_key_is_not_companion_memory(self):
        key = keys.aria_body_snapshot_key("u1")
        self.assertEqual(key["sk"], "ARIA#BODY_SNAPSHOT")
        self.assertNotEqual(key["sk"], keys.aria_context_key("u1")["sk"])
        self.assertNotEqual(key["sk"], keys.aria_persona_key("u1")["sk"])


if __name__ == "__main__":
    unittest.main()
