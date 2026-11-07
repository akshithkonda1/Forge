"""Quin: derived health conclusions never land on the server persona.

Health samples, readiness, HRV, and sleep hours may shape this turn's
coach copy. They must not be written to ARIA#PERSONA.
"""

from __future__ import annotations

import json
import os
import unittest
from datetime import datetime, timezone

import _bootstrap  # noqa: F401

from aria_core import contextual_learner, health_privacy
from aria_core.aria_engine import ARIAContext, ReadinessContext, SleepContext
from handler import handler
from storage import dynamodb, keys


CANARY_HRV = 188
CANARY_SLEEP_H = 11.7
CANARY_READINESS = 27


def _event(method, path, body, user):
    return {
        "requestContext": {
            "http": {"method": method, "path": path},
            "authorizer": {"jwt": {"claims": {"sub": user}}},
        },
        "body": json.dumps(body),
    }


def _post(path, body, user):
    resp = handler(_event("POST", path, body, user), None)
    return resp["statusCode"], json.loads(resp["body"])


class QuinPersonaPrivacyTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"

    def _persona_blob(self, uid: str) -> str:
        item = dynamodb.get_item(**keys.aria_persona_key(uid))
        return json.dumps(item or {})

    def test_silent_observe_does_not_write_persona(self):
        uid = "quin-observe-silent"
        before = contextual_learner.load(uid).as_dict()
        status, payload = _post(
            "/ai/observe",
            {
                "user_id": uid,
                "samples": [
                    {
                        "type": "hrv",
                        "value": CANARY_HRV,
                        "unit": "ms",
                        "timestamp": datetime.now(timezone.utc).isoformat(),
                    }
                ],
                "recent_metrics": {
                    "readiness": CANARY_READINESS,
                    "sleepHours": CANARY_SLEEP_H,
                },
                "context": {
                    "readiness": {"recovery_score": CANARY_READINESS, "hrv_7day_trend": -12},
                    "sleep": {"duration_minutes": CANARY_SLEEP_H * 60},
                },
            },
            uid,
        )
        self.assertEqual(status, 200)
        self.assertEqual(payload["snapshot"], {})
        self.assertIsNone(dynamodb.get_item(**keys.aria_persona_key(uid)))
        self.assertEqual(contextual_learner.load(uid).as_dict(), before)
        blob = self._persona_blob(uid)
        self.assertNotIn(str(CANARY_HRV), blob)
        self.assertNotIn(str(CANARY_READINESS), blob)
        self.assertNotIn(str(CANARY_SLEEP_H), blob)

    def test_observe_message_strips_health_from_persona_plan(self):
        uid = "quin-observe-msg"
        status, _payload = _post(
            "/ai/observe",
            {
                "user_id": uid,
                "message": "What should I train today?",
                "samples": [{"type": "hrv", "value": CANARY_HRV, "unit": "ms"}],
                "recent_metrics": {"readiness": CANARY_READINESS, "sleepHours": CANARY_SLEEP_H},
                "context": {
                    "readiness": {"recovery_score": CANARY_READINESS, "hrv_7day_trend": -14},
                    "sleep": {"duration_minutes": 4 * 60},
                },
            },
            uid,
        )
        self.assertEqual(status, 200)
        persona = contextual_learner.load(uid)
        plan = persona.last_plan if isinstance(persona.last_plan, dict) else {}
        blob = json.dumps(persona.as_dict())
        self.assertNotIn(str(CANARY_HRV), blob)
        self.assertNotIn("11.7", blob)
        factors = plan.get("signals") or plan.get("factors") or []
        factor_blob = json.dumps(factors).lower()
        self.assertNotIn("hrv", factor_blob)
        self.assertNotIn("recovery is thin", factor_blob)
        self.assertNotIn("last night ran short", factor_blob)
        echoed = _payload.get("supervision_plan")
        if isinstance(echoed, dict):
            self.assertFalse(health_privacy.plan_has_health_conclusions(echoed))
        readiness = ((_payload.get("aria_context") or {}).get("readiness") or {})
        sleep = ((_payload.get("aria_context") or {}).get("sleep") or {})
        self.assertNotEqual(readiness.get("recovery_score"), CANARY_READINESS)
        self.assertNotEqual(sleep.get("hrv"), CANARY_HRV)

    def test_chat_readiness_does_not_persist_health_plan(self):
        uid = "quin-chat"
        status, _payload = _post(
            "/ai/chat",
            {
                "user_id": uid,
                "message": "What should I train today?",
                "recent_metrics": {"readiness": CANARY_READINESS, "sleepHours": CANARY_SLEEP_H},
                "context": {
                    "readiness": {"recovery_score": CANARY_READINESS, "hrv_7day_trend": -14},
                    "sleep": {"duration_minutes": 4 * 60},
                },
                "samples": [{"type": "hrv", "value": CANARY_HRV, "unit": "ms"}],
            },
            uid,
        )
        self.assertEqual(status, 200)
        self.assertIsNone(dynamodb.get_item(**keys.aria_body_snapshot_key(uid)))
        self.assertEqual(dynamodb.query_prefix(keys.user_pk(uid), "METRIC#"), [])
        persona = contextual_learner.load(uid)
        blob = json.dumps(persona.as_dict())
        self.assertNotIn(str(CANARY_HRV), blob)
        self.assertNotIn("11.7", blob)
        plan = persona.last_plan if isinstance(persona.last_plan, dict) else {}
        factor_blob = json.dumps(plan.get("factors") or plan.get("signals") or []).lower()
        self.assertNotIn("hrv", factor_blob)
        self.assertNotIn("recovery is thin", factor_blob)
        self.assertNotIn("last night ran short", factor_blob)
        living = dynamodb.get_item(**keys.aria_context_key(uid)) or {}
        living_blob = json.dumps(living)
        self.assertNotIn(str(CANARY_HRV), living_blob)
        self.assertNotIn("11.7", living_blob)
        self.assertNotIn("low_readiness_streak", living_blob)
        self.assertNotIn("strong_sleep_recovery", living_blob)
        self.assertIsNone(persona.last_stance)
        insights = json.dumps(living.get("last_insights") or []).lower()
        self.assertNotIn("hrv", insights)
        self.assertNotIn("readiness", insights)
        self.assertNotIn("short on sleep", insights)

    def test_chat_camelcase_readiness_does_not_write_living_patterns(self):
        uid = "quin-chat-camel"
        status, _payload = _post(
            "/ai/chat",
            {
                "user_id": uid,
                "message": "What should I train today?",
                "recent_metrics": {"readiness": CANARY_READINESS, "sleepHours": CANARY_SLEEP_H},
                "context": {
                    "readiness": {"recoveryScore": CANARY_READINESS, "hrv7DayTrend": -14},
                    "sleep": {"durationMinutes": 4 * 60},
                },
            },
            uid,
        )
        self.assertEqual(status, 200)
        living = dynamodb.get_item(**keys.aria_context_key(uid)) or {}
        living_blob = json.dumps(
            {
                "recent_patterns": living.get("recent_patterns")
                or (living.get("payload") or {}).get("recent_patterns"),
                "last_insights": living.get("last_insights")
                or (living.get("payload") or {}).get("last_insights"),
                "supervision_plan": living.get("supervision_plan")
                or (living.get("payload") or {}).get("supervision_plan"),
            }
        )
        self.assertNotIn("low_readiness_streak", living_blob)
        self.assertNotIn(str(CANARY_READINESS), living_blob)
        persona = contextual_learner.load(uid)
        self.assertIsNone(persona.last_stance)

    def test_without_health_for_persona_clears_body_keeps_lifestyle(self):
        ctx = ARIAContext(
            sleep=SleepContext(duration_minutes=240, hrv=CANARY_HRV),
            readiness=ReadinessContext(recovery_score=CANARY_READINESS, hrv_7day_trend=-12),
        )
        ctx.lifestyle.tags = ["calendar:evening:busy"]
        stripped = health_privacy.without_health_for_persona(ctx)
        self.assertIsNone(stripped.sleep.duration_minutes)
        self.assertIsNone(stripped.readiness.recovery_score)
        self.assertIsNone(stripped.readiness.hrv_7day_trend)
        self.assertIn("calendar:evening:busy", stripped.lifestyle.tags)
        self.assertIsNone(health_privacy.without_health_for_persona(None))
