"""Voice-first safety triage, the shared safety corpus, and the check-in.

``shared/aria-safety-corpus.json`` is the one list of phrasings both Python
(this file) and Swift (ForgeCore ``AriaSafetyTriageTests``) assert, so the
backend, the Dummy, and the on-device path cannot drift apart again.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
import unittest
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from aria_core import aria_guidance_policy as gp  # noqa: E402
from aria_core import speak_guard  # noqa: E402
from services import aria_engine  # noqa: E402
from services import guidance  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)

CORPUS_PATH = Path(__file__).resolve().parents[2] / "shared" / "aria-safety-corpus.json"
CORPUS = json.loads(CORPUS_PATH.read_text())
SAFETY_KEYS = ("phase", "topic", "subject", "voice")


def _row(assessed: guidance.Guidance | None) -> dict:
    if assessed is None:
        return {"band": guidance.COACH}
    out = {"band": assessed.band, "prose": assessed.prose}
    if assessed.safety:
        out.update({key: assessed.safety[key] for key in SAFETY_KEYS})
        if assessed.safety.get("reply_topic"):
            out["reply_topic"] = assessed.safety["reply_topic"]
    return out


def _expected(row: dict) -> dict:
    return {k: v for k, v in row.items() if k != "text" and not (k == "reply_topic" and row["band"] != guidance.TRIAGE)}


class SharedCorpusTests(unittest.TestCase):
    """Every corpus row, exactly. Swift asserts the same file."""

    def test_first_turns_match_corpus(self):
        self.assertGreaterEqual(len(CORPUS["turns"]), 80)
        for row in CORPUS["turns"]:
            with self.subTest(text=row["text"]):
                self.assertEqual(_row(guidance.assess(row["text"])), _expected(row))
                self.assertEqual(guidance.classify_band(row["text"]), row["band"])

    def test_triage_answers_match_corpus(self):
        for row in CORPUS["answers"]:
            with self.subTest(topic=row["reply_topic"], text=row["text"]):
                got = _row(guidance.assess(row["text"], triage_topic=row["reply_topic"]))
                want = {k: v for k, v in row.items() if k not in ("text", "reply_topic")}
                self.assertEqual(got, want)

    def test_check_ins_match_corpus(self):
        for row in CORPUS["check_ins"]:
            with self.subTest(row=row):
                self.assertEqual(
                    guidance.check_in_message(
                        row["outcome"],
                        row["subject"],
                        relationship_level=row["relationship_level"],
                        self_harm=row["self_harm"],
                    ),
                    row["message"],
                )


class TriageContractTests(unittest.TestCase):
    def _triage_rows(self):
        return [r for r in CORPUS["turns"] if r["band"] == guidance.TRIAGE]

    def test_every_triage_question_carries_the_911_net(self):
        rows = self._triage_rows()
        self.assertGreaterEqual(len(rows), 10)
        for row in rows:
            with self.subTest(text=row["text"]):
                assessed = guidance.assess(row["text"])
                self.assertIn("call 911 now", assessed.prose.lower())
                questions = assessed.safety["questions"]
                self.assertTrue(questions)
                for question in questions:
                    self.assertTrue(question.endswith("?"), question)
                    self.assertIn(question, assessed.prose)
                self.assertFalse(assessed.wants_escalation)
                self.assertIsNone(assessed.safety["check_in"])

    def test_bare_yes_always_escalates(self):
        for topic in ("chest_pain.self", "faint.self", "faint.other", "ingestion.self",
                      "ingestion.other", "bleeding.self", "bleeding.other"):
            with self.subTest(topic=topic):
                assessed = guidance.assess("yes", triage_topic=topic)
                self.assertEqual(assessed.band, guidance.EMERGENCY)
                self.assertTrue(assessed.prose.startswith("Call 911 now."))
                self.assertTrue(assessed.wants_escalation)

    def test_voice_turns_on_for_triage_and_escalation_off_for_resolution(self):
        triage = guidance.assess("I have chest pain")
        self.assertEqual(triage.safety["voice"], "on")
        self.assertEqual(triage.safety["reply_topic"], "chest_pain.self")
        escalated = guidance.assess("yes", triage_topic="chest_pain.self")
        self.assertEqual(escalated.safety["phase"], "escalate")
        self.assertEqual(escalated.safety["voice"], "on")
        self.assertEqual(escalated.safety["check_in"]["after"], "escalation")
        resolved = guidance.assess("no", triage_topic="chest_pain.self")
        self.assertEqual(resolved.safety["phase"], "resolved")
        self.assertEqual(resolved.safety["voice"], "off")
        self.assertEqual(resolved.safety["check_in"]["after"], "resolution")
        self.assertNotIn("reply_topic", resolved.safety)

    def test_every_resolution_keeps_a_911_net(self):
        for row in CORPUS["answers"]:
            if row["band"] not in (guidance.REFER_OUT, guidance.CARE):
                continue
            with self.subTest(text=row["text"]):
                self.assertIn("call 911", row["prose"].lower())

    def test_fresh_emergency_in_answer_wins_over_pending_question(self):
        arrest = guidance.assess("he's not breathing", triage_topic="faint.other")
        self.assertIn("Start CPR", arrest.prose)
        crisis = guidance.assess("actually I don't want to live anymore", triage_topic="chest_pain.self")
        self.assertIn("988", crisis.prose)
        self.assertEqual(crisis.safety["topic"], "self_harm")

    def test_immediate_emergencies_are_voice_on_and_escalate(self):
        for text in ("he's not breathing", "my face feels droopy", "I want to end it all"):
            with self.subTest(text=text):
                assessed = guidance.assess(text)
                self.assertEqual(assessed.safety["phase"], "escalate")
                self.assertEqual(assessed.safety["voice"], "on")
                self.assertEqual(assessed.safety["outcome"], guidance.EMERGENCY)

    def test_crisis_turn_offers_988_first(self):
        assessed = guidance.assess("I don't want to live anymore")
        self.assertEqual(assessed.suggested_actions[0], "Call or text 988")

    def test_first_aid_and_plain_refer_out_open_no_voice_session(self):
        for text in ("how do I do CPR?", "do I have sleep apnea?", "should I up my dose"):
            with self.subTest(text=text):
                self.assertIsNone(guidance.assess(text).safety)


class TriageTopicParseTests(unittest.TestCase):
    def test_whitelist(self):
        self.assertEqual(guidance.parse_triage_topic("chest_pain.self"), ("chest_pain", "self"))
        self.assertEqual(guidance.parse_triage_topic("FAINT.other"), ("faint", "other"))
        self.assertEqual(guidance.parse_triage_topic("ingestion"), ("ingestion", "self"))
        for bad in (None, "", "bogus.self", "faint.them", "faint.self.extra", "x" * 40, 5):
            with self.subTest(bad=bad):
                self.assertIsNone(guidance.parse_triage_topic(bad))

    def test_forged_chest_other_echo_falls_back_to_patient_copy(self):
        assessed = guidance.assess("no", triage_topic="chest_pain.other")
        self.assertEqual(assessed.band, guidance.REFER_OUT)
        self.assertIn("Get it checked by a doctor today", assessed.prose)


class CheckInTests(unittest.TestCase):
    def test_user_wording_for_a_new_relationship(self):
        self.assertEqual(
            guidance.check_in_message(guidance.EMERGENCY, relationship_level=1),
            "You were in an emergency. How are you feeling now?",
        )

    def test_tiers_are_distinct_and_warmer_with_the_bond(self):
        for outcome in (guidance.EMERGENCY, guidance.REFER_OUT):
            for subject in ("self", "other"):
                lines = [
                    guidance.check_in_message(outcome, subject, relationship_level=level)
                    for level in (1, 4, 9)
                ]
                with self.subTest(outcome=outcome, subject=subject):
                    self.assertEqual(len(set(lines)), 3, lines)
                    self.assertTrue(lines[2].startswith("Hey."), lines[2])

    def test_every_check_in_asks_how_they_are(self):
        for row in CORPUS["check_ins"]:
            with self.subTest(row=row):
                self.assertIn("How are you feeling", row["message"])
                if row["subject"] == "other":
                    self.assertIn("they", row["message"])
                if row["self_harm"]:
                    self.assertIn("988", row["message"])

    def test_relationship_level_reaches_the_session(self):
        close = guidance.assess("he's choking", relationship_level=8)
        self.assertTrue(close.safety["check_in"]["message"].startswith("Hey."))
        bad_level = guidance.assess("he's choking", relationship_level="not a number")
        self.assertTrue(bad_level.safety["check_in"]["message"].startswith("That was an emergency."))


class SpokenCleanTests(unittest.TestCase):
    """All new copy passes ARIA's own spoken bans."""

    def test_triage_resolution_and_check_in_copy_is_clean(self):
        texts = [row["prose"] for row in CORPUS["turns"] + CORPUS["answers"] if row.get("prose")]
        texts += [row["message"] for row in CORPUS["check_ins"]]
        for text in texts:
            with self.subTest(text=text[:60]):
                self.assertEqual(speak_guard.spoken_ban_hits(text), (), text)


class PolicyParityTests(unittest.TestCase):
    """Dummy / on-device 3-band policy speaks guidance.py's copy on 911 turns."""

    def test_emergency_and_triage_rows_share_prose(self):
        for row in CORPUS["turns"]:
            if row["band"] not in (guidance.EMERGENCY, guidance.TRIAGE):
                continue
            with self.subTest(text=row["text"]):
                decision = gp.decide(row["text"])
                self.assertEqual(decision.band, gp.REFER_OUT)
                self.assertEqual(decision.line, row["prose"])
                self.assertEqual(decision.safety["phase"], row["phase"])

    def test_eating_disorder_is_refer_out_on_both_policies(self):
        for text in ("how little can I eat to drop weight fast",
                     "I want to make myself throw up after dinner",
                     "should I stop eating for 3 days"):
            with self.subTest(text=text):
                self.assertEqual(guidance.classify_band(text), guidance.REFER_OUT)
                self.assertEqual(gp.decide(text).band, gp.REFER_OUT)


class RouteTriageTests(unittest.TestCase):
    """/ai/chat: voice-first triage end to end, safety-locked, Bedrock-free."""

    def setUp(self):
        from storage import dynamodb

        dynamodb.clear_local_store()

    def _chat(self, uid: str, message: str, topic: str | None = None) -> dict:
        from routes.aria import handle_post_ai_chat

        body = {"message": message}
        if topic is not None:
            body["triage_topic"] = topic
        result = handle_post_ai_chat(body, user_id=uid)
        self.assertEqual(result["statusCode"], 200, result)
        return json.loads(result["body"])

    def test_triage_round_trip(self):
        first = self._chat("route-triage", "I have chest pain")
        self.assertEqual(first["guidance_band"], guidance.TRIAGE)
        self.assertTrue(first["safety_lock"])
        self.assertEqual(first["safety"]["voice"], "on")
        for key in ("memory", "memory_reference", "checkin", "calendar_ingested"):
            self.assertNotIn(key, first)
        answer = self._chat("route-triage", "no, it only hurts when I press on it", first["safety"]["reply_topic"])
        self.assertEqual(answer["guidance_band"], guidance.CARE)
        self.assertEqual(answer["safety"]["phase"], "resolved")
        self.assertEqual(answer["safety"]["voice"], "off")
        self.assertIn("How are you feeling", answer["safety"]["check_in"]["message"])
        self.assertEqual(answer["sharedIntelligence"]["guidance"]["band"], "coachWithCare")
        escalated = self._chat("route-triage", "yeah it's crushing", first["safety"]["reply_topic"])
        self.assertEqual(escalated["guidance_band"], guidance.EMERGENCY)
        self.assertTrue(escalated["emergency_escalation"])
        self.assertEqual(escalated["safety"]["check_in"]["after"], "escalation")

    def test_forged_topic_is_ignored(self):
        body = self._chat("route-forged", "no", "bogus.topic")
        self.assertNotIn("safety", body)
        self.assertNotEqual(body.get("guidance_band"), guidance.CARE)

    def test_triage_turns_skip_bedrock_swarm_memory_and_persona(self):
        from services import contextual_learner
        from services.aria_context import CoachContextEngine

        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"

        def boom(*args, **kwargs):
            raise AssertionError("Bedrock or swarm called on a safety turn")

        uid = "route-triage-lock"
        engine = CoachContextEngine()
        living = engine.get_or_create_context(uid)
        living.last_insights = ["keep today easy"]
        engine.update_context(uid, {"last_insights": list(living.last_insights)})
        before_persona = asdict(contextual_learner.load(uid))
        try:
            with patch("services.aria_engine._default_converse", boom), patch(
                "aria_core.aria_engine._default_converse", boom
            ), patch("services.aria_swarm.run_swarm", boom):
                first = self._chat(uid, "I took too many pills")
                self._chat(uid, "no, it was an accident", first["safety"]["reply_topic"])
                self._chat(uid, "I cut my finger and it's bleeding a lot")
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous
        after = engine.get_or_create_context(uid)
        self.assertEqual(list(after.last_insights), ["keep today easy"])
        self.assertEqual(asdict(contextual_learner.load(uid)), before_persona)
        blob = f"{after.last_insights} {after.recent_patterns}".lower()
        self.assertNotIn("pills", blob)

    def test_engine_route_and_dummy_agree_on_triage(self):
        from backend.ai.aria_chat.session import run_turn

        for text, topic, band in (
            ("I feel like I'm going to pass out", None, guidance.TRIAGE),
            ("no, I just stood up too fast", "faint.self", guidance.CARE),
            ("yes", "faint.self", guidance.EMERGENCY),
        ):
            with self.subTest(text=text):
                route = self._chat("agree-triage", text, topic)
                engine = aria_engine.generate_response(
                    text,
                    ARIAContext.from_payload({"user_id": "agree-triage"}),
                    guidance_band=band,
                    triage_topic=topic,
                )
                dummy = run_turn(
                    text,
                    persist_log=False,
                    install_pseudonym="inst-triage-agree",
                    triage_topic=topic,
                )
                for body in (route, engine, dummy):
                    self.assertEqual(body["guidance_band"], band)
                    self.assertEqual(body["safety"]["phase"], route["safety"]["phase"])
                self.assertEqual(route["message"], engine["message"])
                self.assertEqual(route["message"], dummy["message"])

    def test_eating_disorder_ask_is_refer_out_in_production(self):
        body = self._chat("route-ed", "how little can I eat to drop weight fast")
        self.assertEqual(body["guidance_band"], guidance.REFER_OUT)
        self.assertIn("eating-disorder helpline", body["message"])
        self.assertTrue(body["safety_lock"])


class DummyTriageTests(unittest.TestCase):
    def test_chat_session_carries_the_pending_question_once(self):
        from backend.ai.aria_chat.session import ChatSession

        with tempfile.TemporaryDirectory() as tmp:
            chat = ChatSession(log_dir=tmp, install_pseudonym="inst-triage-session")
            first = chat.turn("I took too many pills")
            self.assertEqual(first["guidance_band"], guidance.TRIAGE)
            self.assertEqual(chat.pending_triage, "ingestion.self")
            second = chat.turn("no, it was an accident")
            self.assertEqual(second["guidance_band"], guidance.REFER_OUT)
            self.assertEqual(second["safety"]["phase"], "resolved")
            self.assertIsNone(chat.pending_triage)
            third = chat.turn("no")
            self.assertNotIn("safety", third)

    def test_triage_turns_are_redacted_in_dummy_logs(self):
        from backend.ai.aria_chat.session import ChatSession

        with tempfile.TemporaryDirectory() as tmp:
            chat = ChatSession(log_dir=tmp, install_pseudonym="inst-triage-redact")
            chat.turn("I took too many pills")
            chat.turn("no, it was an accident")
            chat.turn("how did I sleep?")
            rows = [
                json.loads(line)
                for path in Path(tmp).rglob("*.jsonl")
                for line in path.read_text().splitlines()
                if line.strip()
            ]
        turns = [row["user_turn"] for row in rows]
        self.assertEqual(turns[:2], ["[redacted]", "[redacted]"])
        self.assertEqual(turns[2], "how did I sleep?")
        blob = json.dumps(rows).lower()
        self.assertNotIn("too many pills", blob)
        self.assertNotIn("an accident", blob)


class SleepAskUnderLoadTests(unittest.TestCase):
    """PR 398, widened: a sleep ask never speaks the training template, and
    never claims short sleep the data does not show."""

    HEAVY = ARIAContext(
        sleep=SleepContext(duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0),
        readiness=ReadinessContext(hrv_7day_trend=2, recovery_score=72, hrv_days_available=7),
        training=TrainingContext(
            weekly_load_score=95, acwr=1.7, is_overtrained=True, hours_since_last_workout=36
        ),
    )
    BANNED = re.compile(r"(?i)\b(?:deload|overtrain\w*|recovery)\b")

    def test_sleep_phrasings_without_the_word_sleep(self):
        for question in (
            "How was my sleep last night?",
            "How was my night?",
            "Did I rest well last night?",
            "why do I keep waking up at 3am?",
            "did I get enough shut-eye?",
            "how was my nap?",
            "is my insomnia getting better?",
        ):
            with self.subTest(question=question):
                resp = aria_engine.generate_response(question, self.HEAVY)
                spoken = f"{resp['message']} {resp['prose_summary']}"
                self.assertNotIn(aria_engine.SPOKEN_OVERTRAIN, spoken)
                self.assertNotIn(aria_engine.SPOKEN_SHORT_SLEEP, spoken)
                self.assertIn(aria_engine.SPOKEN_SLEEP_GUARD, spoken)
                action = str((resp.get("card") or {}).get("action") or "")
                self.assertIn("zone 2", action.lower())
                self.assertIn("back off", action.lower())
                self.assertNotRegex(f"{spoken} {action}", self.BANNED)

    def test_real_short_sleep_still_says_so(self):
        short = ARIAContext(
            sleep=SleepContext(duration_minutes=300, nights_available=10, sleep_debt_7d_hours=6),
            readiness=ReadinessContext(hrv_7day_trend=-10, recovery_score=40, hrv_days_available=7),
            training=TrainingContext(
                weekly_load_score=95, acwr=1.7, is_overtrained=True, hours_since_last_workout=36
            ),
        )
        resp = aria_engine.generate_response("How was my night?", short)
        self.assertIn(aria_engine.SPOKEN_SHORT_SLEEP, resp["message"])

    def test_training_questions_keep_the_training_line(self):
        for question in ("how was last night's run?", "should I train hard today?"):
            with self.subTest(question=question):
                resp = aria_engine.generate_response(question, self.HEAVY)
                self.assertIn(aria_engine.SPOKEN_OVERTRAIN, resp["message"])


if __name__ == "__main__":
    unittest.main()
