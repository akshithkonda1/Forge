"""Slice 2: on-device people tags → UserContext on the Dummy fuse path.

Remember-me on files sanitized names into recent_patterns / life_facts.
Remember-me off and SAFETY_LOCK_BANDS write nothing (off ≠ delete).
Vault view/add/edit/delete stays on CoachContextEngine. Bedrock stays off.
"""

from __future__ import annotations

import json
import unittest

import _bootstrap  # noqa: F401

from aria_core import guidance  # noqa: E402
from aria_core import hobby_fit as hf  # noqa: E402
from aria_core.aria_engine import ARIAContext, LifestyleContext, generate_response  # noqa: E402
from routes.aria import handle_post_ai_chat, sanitize_inbound_chat_payload  # noqa: E402
from services import coach_context  # noqa: E402
from services import editable_memory as mem  # noqa: E402
from services import provider_capabilities as caps  # noqa: E402
from services.aria_context import CoachContextEngine  # noqa: E402
from storage import dynamodb  # noqa: E402

USER = "people-slice2-0001"
TAGS = [
    "people:Sam:partner",
    "people:5551212:friend",
    "people:sam@x.com:friend",
    "people:count:3",
    "people:partner_name:x",
    "partner_cycle:day14",
]


def _payload(tags=None):
    return {
        "message": "who are my people",
        "context": {
            "lifestyle": {
                "tags": list(tags if tags is not None else TAGS),
                "recentPatterns": list(tags if tags is not None else TAGS),
            }
        },
    }


class PeopleAdmitTests(unittest.TestCase):
    def test_admit_drops_phones_emails_and_partner_cycle(self):
        self.assertEqual(
            coach_context.admit_people_tag("people:Sam:partner"),
            {"firstName": "Sam", "relation": "partner"},
        )
        self.assertIsNone(coach_context.admit_people_tag("people:5551212:friend"))
        self.assertIsNone(coach_context.admit_people_tag("people:sam@x.com:friend"))
        self.assertIsNone(coach_context.admit_people_tag("people:partner_name:x"))
        self.assertIsNone(coach_context.admit_people_tag("people:count:3"))
        self.assertTrue(coach_context.people_tag_is_dirty("people:5551212:friend"))
        self.assertFalse(coach_context.people_tag_is_dirty("people:Sam:partner"))

    def test_inbound_sanitizer_strips_dirty_people_tags(self):
        clean = sanitize_inbound_chat_payload(_payload())
        blob = " ".join(
            clean["context"]["lifestyle"]["tags"]
            + clean["context"]["lifestyle"]["recentPatterns"]
        )
        self.assertIn("people:Sam:partner", blob)
        self.assertNotIn("555", blob)
        self.assertNotIn("@", blob)
        self.assertNotIn("partner_name", blob)
        self.assertNotIn("partner_cycle", blob)


class PeopleFileRememberMeTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()
        self.engine = CoachContextEngine()

    def test_remember_me_on_files_sanitized_people(self):
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=True))
        filed = coach_context.file_people_tags(
            USER,
            _payload(),
            allow_ingest=True,
            safety_lock=False,
            engine=self.engine,
        )
        self.assertEqual(filed, [{"firstName": "Sam", "relation": "partner"}])
        ctx = self.engine.get_or_create_context(USER)
        self.assertIn("people:Sam:partner", ctx.recent_patterns)
        self.assertIn("Sam is a partner", ctx.life_facts)
        self.assertFalse(any("555" in row for row in ctx.recent_patterns + ctx.life_facts))
        self.assertFalse(any("@" in row for row in ctx.recent_patterns + ctx.life_facts))
        self.assertFalse(any("partner_cycle" in row for row in ctx.recent_patterns + ctx.life_facts))
        self.assertFalse(any("people:count" in row for row in ctx.recent_patterns))

    def test_remember_me_off_writes_nothing_and_deletes_nothing(self):
        self.engine.record_life_fact(USER, "Keep this note.")
        self.engine.update_context(USER, {"recent_patterns": ["late_caffeine"]})
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=False))
        filed = coach_context.file_people_tags(
            USER,
            _payload(),
            allow_ingest=mem.auto_ingest_allowed(mem.get_settings(USER)),
            safety_lock=False,
            engine=self.engine,
        )
        self.assertEqual(filed, [])
        ctx = self.engine.get_or_create_context(USER)
        self.assertEqual(ctx.life_facts, ["Keep this note."])
        self.assertEqual(ctx.recent_patterns, ["late_caffeine"])
        # Vault stays editable while auto-file is off.
        self.engine.record_life_fact(USER, "User added this.")
        self.engine.update_context(USER, {"life_facts": ["User edited this."]})
        after = self.engine.get_or_create_context(USER)
        self.assertEqual(after.life_facts, ["User edited this."])
        self.engine.update_context(USER, {"life_facts": []})
        self.assertEqual(self.engine.get_or_create_context(USER).life_facts, [])

    def test_safety_lock_writes_nothing(self):
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=True))
        filed = coach_context.file_people_tags(
            USER,
            _payload(),
            allow_ingest=True,
            safety_lock=True,
            engine=self.engine,
        )
        self.assertEqual(filed, [])
        ctx = self.engine.get_or_create_context(USER)
        self.assertEqual(ctx.life_facts, [])
        self.assertEqual(ctx.recent_patterns, [])

    def test_dummy_stub_gate_is_on_and_bedrock_stays_off(self):
        self.assertTrue(coach_context.people_auto_file_allowed())
        self.assertFalse(caps.invoke_now_allowed())
        self.assertNotEqual(caps.DEFAULT_PATH, "live_bedrock")
        self.assertTrue(caps.DO_NOT_INVOKE)


class PeopleChatRouteTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_fuse_path_files_when_remember_me_on(self):
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=True))
        result = handle_post_ai_chat(_payload(), user_id=USER)
        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        spoken = f"{body.get('message', '')} {body.get('prose_summary', '')}"
        self.assertNotIn("people:Sam", spoken)
        self.assertNotIn("Your people:", spoken)
        self.assertNotIn("555", spoken)
        ctx = CoachContextEngine().get_or_create_context(USER)
        self.assertIn("people:Sam:partner", ctx.recent_patterns)
        self.assertIn("Sam is a partner", ctx.life_facts)

    def test_fuse_path_skips_file_when_remember_me_off(self):
        engine = CoachContextEngine()
        engine.record_life_fact(USER, "Keep this note.")
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=False))
        result = handle_post_ai_chat(_payload(), user_id=USER)
        self.assertEqual(result["statusCode"], 200)
        ctx = engine.get_or_create_context(USER)
        self.assertEqual(ctx.life_facts, ["Keep this note."])
        self.assertNotIn("people:Sam:partner", ctx.recent_patterns)

    def test_safety_lock_band_does_not_file_people(self):
        mem.put_settings(USER, mem.CompanionMemorySettings(memory_enabled=True))
        result = handle_post_ai_chat(
            {
                "message": "chest pain and my left arm is numb",
                "context": {"lifestyle": {"tags": ["people:Sam:partner"]}},
            },
            user_id=USER,
        )
        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertIn(body.get("guidance_band"), guidance.SAFETY_LOCK_BANDS)
        ctx = CoachContextEngine().get_or_create_context(USER)
        self.assertNotIn("people:Sam:partner", ctx.recent_patterns)
        self.assertEqual(ctx.life_facts, [])


class PeopleSpokenTests(unittest.TestCase):
    def test_people_question_is_coach_words_not_a_list(self):
        line = hf.people_coach_line(
            "who are my people",
            ["people:Sam:partner", "people:Jo:friend", "people:5551212:friend"],
        )
        self.assertIsNotNone(line)
        self.assertIn("Sam", line)
        self.assertNotIn("Jo", line)
        self.assertNotIn("people:", line)
        self.assertNotIn("Your people:", line)
        self.assertNotIn("555", line)

    def test_generate_response_never_dumps_people_tags(self):
        ctx = ARIAContext(
            lifestyle=LifestyleContext(
                tags=["people:Sam:partner", "people:Jo:friend"],
                recent_patterns=["people:Sam:partner"],
            )
        )
        resp = generate_response("who are my people", ctx, seed=0)
        spoken = f"{resp.get('prose_summary', '')} {resp.get('message', '')}"
        self.assertNotIn("people:", spoken)
        self.assertNotIn("Your people:", spoken)
        self.assertNotIn("555", spoken)
        self.assertTrue("Sam" in spoken or "named" in spoken.lower())


class DummyChatPeopleTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_dummy_chat_files_when_remember_me_on(self):
        from backend.ai.aria_chat.session import run_turn

        result = run_turn(
            "who are my people",
            payload=_payload(),
            user_id=USER,
            memory_enabled=True,
            persist_log=False,
        )
        spoken = f"{result.get('message', '')} {result.get('prose_summary', '')}"
        self.assertNotIn("people:", spoken)
        self.assertNotIn("Your people:", spoken)
        ctx = CoachContextEngine().get_or_create_context(USER)
        self.assertIn("people:Sam:partner", ctx.recent_patterns)
        self.assertIn("Sam is a partner", ctx.life_facts)

    def test_dummy_chat_memory_off_does_not_file(self):
        from backend.ai.aria_chat.session import run_turn

        CoachContextEngine().record_life_fact(USER, "Keep this note.")
        run_turn(
            "who are my people",
            payload=_payload(),
            user_id=USER,
            memory_enabled=False,
            persist_log=False,
        )
        ctx = CoachContextEngine().get_or_create_context(USER)
        self.assertEqual(ctx.life_facts, ["Keep this note."])
        self.assertNotIn("people:Sam:partner", ctx.recent_patterns)


if __name__ == "__main__":
    unittest.main()
