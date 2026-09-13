"""Inbound chat must not persist partner/cycle PII, calendar titles, or invented QoL."""

from __future__ import annotations

import json
import unittest
from datetime import datetime, timedelta, timezone

import _bootstrap  # noqa: F401

from routes.aria import handle_post_ai_chat, sanitize_inbound_chat_payload  # noqa: E402
from services import aria_engine, contextual_learner  # noqa: E402
from services.aria_context import CoachContextEngine  # noqa: E402
from storage import dynamodb  # noqa: E402

BANNED = ("partner_name", "partner_phase", "partner_cycle")


def _chat(uid: str, body: dict) -> dict:
    result = handle_post_ai_chat(body, user_id=uid)
    assert result["statusCode"] == 200
    return json.loads(result["body"])


class InboundSanitizerTests(unittest.TestCase):
    def test_strips_partner_cycle_tags_and_patterns(self):
        payload = sanitize_inbound_chat_payload(
            {
                "message": "What should I train today?",
                "context": {
                    "lifestyle": {
                        "tags": [
                            "partner_name:sam",
                            "partner_phase:luteal",
                            "partner_cycle:day14",
                            "support_cycle:yes",
                            "cycle:fertile_window",
                            "cycle:tww",
                            "cycle:goal:trying",
                            "cycle:bleeding",
                            "cycle:condition",
                            "calendar:evening:busy",
                        ],
                        "recentPatterns": ["partner_name:sam", "late_caffeine"],
                    }
                },
            }
        )
        lifestyle = payload["context"]["lifestyle"]
        blob = " ".join(lifestyle["tags"] + lifestyle["recentPatterns"]).lower()
        for token in BANNED:
            self.assertNotIn(token, blob, token)
        self.assertNotIn("support_cycle", blob)
        self.assertNotIn("cycle:fertile", blob)
        self.assertIn("calendar:evening:busy", lifestyle["tags"])
        self.assertIn("late_caffeine", lifestyle["recentPatterns"])
        self.assertNotIn("qualityOfLifeScore", lifestyle)
        self.assertNotIn("qol:", blob)

    def test_redacts_calendar_titles(self):
        soon = (datetime.now(timezone.utc) + timedelta(days=8)).isoformat()
        payload = sanitize_inbound_chat_payload(
            {"calendar_events": [{"title": "Sister's wedding", "start": soon, "name": "PII"}]}
        )
        event = payload["calendar_events"][0]
        self.assertEqual(event["title"], "Busy window")
        self.assertNotIn("name", event)
        self.assertNotIn("summary", event)
        self.assertNotIn("Sister", json.dumps(event))


class ChatPrivacyPersistTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_partner_fields_absent_from_model_persona_and_patterns(self):
        uid = "privacy-partner"
        body = {
            "user_id": uid,
            "message": "What should I train today?",
            "recent_metrics": {"readiness": 72},
            "context": {
                "lifestyle": {
                    "tags": [
                        "partner_name:sam",
                        "partner_phase:luteal",
                        "partner_cycle:day14",
                        "calendar:evening:busy",
                    ],
                    "recentPatterns": ["partner_name:sam", "partner_phase:luteal"],
                }
            },
        }
        out = _chat(uid, body)
        clean = sanitize_inbound_chat_payload(body)
        ctx = aria_engine.ARIAContext.from_payload(clean)
        block = ctx.user_model_block()
        persona = contextual_learner.load(uid)
        living = CoachContextEngine().get_or_create_context(uid)
        surfaces = " ".join(
            [
                block,
                json.dumps(persona.as_dict()),
                " ".join(living.recent_patterns),
                " ".join(living.lifestyle_tags),
                json.dumps(out.get("contextualization") or {}),
                out.get("prose_summary") or "",
                out.get("message") or "",
            ]
        ).lower()
        for token in BANNED:
            self.assertNotIn(token, surfaces, token)
        self.assertNotIn("partner_name:sam", " ".join(ctx.lifestyle.tags).lower())
        self.assertNotIn("partner_name:sam", " ".join(ctx.lifestyle.recent_patterns).lower())

    def test_calendar_title_stays_out_of_short_term_memory(self):
        uid = "privacy-cal"
        soon = (datetime.now(timezone.utc) + timedelta(days=10)).isoformat()
        out = _chat(
            uid,
            {
                "user_id": uid,
                "message": "hey",
                "recent_metrics": {"readiness": 80},
                "calendar_events": [{"title": "Sister's wedding", "start": soon}],
            },
        )
        engine = CoachContextEngine()
        block = engine.memory_prompt_block(uid)
        stm = " ".join(m.text for m in engine.short_term_memories(uid))
        blob = f"{block} {stm} {out.get('memory') or ''}".lower()
        self.assertNotIn("sister", blob)
        self.assertNotIn("wedding", blob)
        self.assertIn("busy window", blob)

    def test_no_life_rhythm_without_explicit_qol(self):
        uid = "privacy-qol"
        body = {
            "user_id": uid,
            "message": "What should I train today?",
            "recent_metrics": {"readiness": 70},
            "context": {"lifestyle": {"tags": ["calendar:evening:busy"]}},
        }
        out = _chat(uid, body)
        ctx = aria_engine.ARIAContext.from_payload(sanitize_inbound_chat_payload(body))
        self.assertIsNone(ctx.lifestyle.quality_of_life_score)
        self.assertNotIn("life_rhythm", ctx.user_model_block())
        speak = f"{out.get('prose_summary') or ''} {out.get('message') or ''}".lower()
        self.assertNotIn("life_rhythm", speak)
        self.assertNotIn("qol:", speak)


if __name__ == "__main__":
    unittest.main()
