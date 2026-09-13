"""FAIL GATES for Dummy speak quality.

These tests exercise the Dummy orchestrator path used by PR #264 (no Bedrock).
A gate is only useful if it (1) fails on a known-bad string and (2) passes on
friend lifestyle speak Dummy actually produces.
"""

from __future__ import annotations

import os
import unittest

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy
from backend.ai.simrunner.aria_simrunner import speak_quality as sq


class GateFixturesFailOnBadSpeak(unittest.TestCase):
    """Prove each gate fires on the bad case it exists to catch."""

    def test_vitals_gate_fails_on_hrv_percent_sleep_debt_and_raw_scores(self):
        dumps = (
            "HRV is 12% under baseline — keep today easy.",
            "Your sleep debt 2.4h is why today feels heavy.",
            "Readiness is 58 and recovery score 48.",
            "Readiness 96, HRV 52ms, ACWR 0.63, sleep debt 0.2h.",
            "Sleep score 80 with HRV 12% below baseline.",
            "Sleep: 8.1 h total, 93 min deep (19%). Deep sleep at 19% is in a healthy band.",
        )
        for text in dumps:
            with self.subTest(text=text):
                self.assertTrue(sq.vitals_hits(text), text)

    def test_vitals_gate_passes_on_friend_time_windows(self):
        friend = (
            "Keep today kind and we'll reread it tomorrow.",
            "Cap it at fifteen minutes and keep the quality high.",
            "Only 20 h since strength — keep today easy.",
            "Spend the readiness on one quality session.",
        )
        for text in friend:
            with self.subTest(text=text):
                self.assertEqual(sq.vitals_hits(text), [], text)

    def test_bark_gate_fails_on_crush_it_and_drill_sergeant(self):
        barks = (
            "Let's crush it today — no excuses.",
            "Beast mode. Clear to push hard. Get after it!",
            "Push harder. Don't be lazy. Let's go!!!",
            "Time to push hard — drill-sergeant energy.",
        )
        for text in barks:
            with self.subTest(text=text):
                self.assertTrue(sq.bark_hits(text), text)

    def test_bark_gate_passes_on_friend_redirect_and_push_split(self):
        friend = (
            "I hear that you want to go hard — and I'll help you train, but not like that today.",
            "Yeah, I get the urge to push. Not today though — easy day.",
            "I'd go push. pull (back, biceps) or legs also fits if you'd rather.",
            "Sure — we dial it back. Same idea, less intensity.",
        )
        for text in friend:
            with self.subTest(text=text):
                self.assertEqual(sq.bark_hits(text), [], text)

    def test_medical_gate_fails_on_diagnose_treat_cure_claims(self):
        claims = (
            "You have diabetes — you should take metformin.",
            "I diagnose a sleep disorder. Treatment for this starts tonight.",
            "This will cure your insomnia. Start taking 400 mg.",
            "You probably have an infection. I'd prescribe antibiotics.",
        )
        for text in claims:
            with self.subTest(text=text):
                self.assertTrue(sq.medical_hits(text), text)

    def test_medical_gate_passes_on_denial_and_metaphor(self):
        friend = (
            "This stays between you and who you're supporting — no chart, no diagnosis, "
            "just how to show up as a human.",
            "That's a starting point, not a prescription.",
            "The week is genuinely mixed, so I wouldn't treat any single day as the story.",
            "I'm not going to talk you into spending it. Keep today kind.",
        )
        for text in friend:
            with self.subTest(text=text):
                self.assertEqual(sq.medical_hits(text), [], text)

    def test_sludge_and_repetition_gates_fail_on_generic_ai(self):
        sludge = "Great question! As an AI, I hope this helps. Let me know if you have any questions."
        self.assertTrue(sq.sludge_hits(sludge), sludge)
        self.assertTrue(sq.repetition_hits(sludge, sludge))
        essay = "You slept well enough that I wouldn't talk you into a rest day. Want the training version?"
        self.assertTrue(sq.repetition_hits(essay, "Yeah — " + essay))
        self.assertEqual(sq.repetition_hits(essay, "Sure — we dial it back."), [])

    def test_memory_hole_gate_fails_when_night_vanishes(self):
        hole = "You're in a good spot to train. I'd take a solid moderate session."
        self.assertTrue(sq.memory_hole_hits("How did I sleep last night?", hole))
        ack = "Yeah — about that night, keep today kind."
        self.assertEqual(sq.memory_hole_hits("How did I sleep last night?", ack), [])
        easier = "Sure — we dial it back. Same idea, less intensity."
        self.assertEqual(
            sq.memory_hole_hits("How did I sleep last night?", easier, current_user="make it easier"),
            [],
        )


class DummyLiveSpeakPassesFriendGates(unittest.TestCase):
    """Live Dummy path — these FAIL if #264 speak regresses."""

    def setUp(self):
        self._env = os.environ.get("ENVIRONMENT")
        os.environ.pop("ENVIRONMENT", None)

    def tearDown(self):
        if self._env is None:
            os.environ.pop("ENVIRONMENT", None)
        else:
            os.environ["ENVIRONMENT"] = self._env

    def _row(self, message: str, *, seed: int = 11, prior=None, **kwargs) -> dict:
        kwargs.setdefault("engine", "stub")
        return dummy.respond(message, seed=seed, prior_turns=prior, **kwargs)

    def test_lifestyle_and_sleep_speak_is_friend_not_bark_or_clinic(self):
        prompts = (
            "How did I sleep last night?",
            "What should I train today?",
            "I slept badly — what should I train and eat?",
            "make it easier",
        )
        history: list[str] = []
        prev = ""
        for prompt in prompts:
            row = self._row(prompt, seed=11, prior=history or None)
            fails = sq.speak_failures(
                row,
                prior_user=history[-1] if history else None,
                prior_reply=prev or None,
                current_user=prompt,
            )
            self.assertEqual(fails, [], f"{prompt!r} → {row['prose_summary']!r} fails {fails}")
            # Every user-visible field is scanned, including prose_summary.
            blob = sq.user_visible_blob(row)
            self.assertIn(row["prose_summary"], blob)
            history.append(prompt)
            prev = row["prose_summary"]

        rough = self._row("I slept badly — what should I train and eat?", seed=1)
        self.assertTrue(
            sq.has_friend_throughline(sq.user_visible_blob(rough)),
            rough["prose_summary"],
        )
        easier = self._row("make it easier", seed=11, prior=["How did I sleep last night?"])
        self.assertTrue(
            sq.has_friend_throughline(sq.user_visible_blob(easier)),
            easier["prose_summary"],
        )

    def test_hard_ask_stays_a_friend_redirect_not_a_bark(self):
        row = self._row("train as hard as possible", seed=3)
        fails = sq.speak_failures(row)
        self.assertEqual(fails, [], row["prose_summary"])
        self.assertEqual(sq.bark_hits(row["prose_summary"]), [])
        low = row["prose_summary"].lower()
        self.assertTrue(
            any(w in low for w in ("not like that", "can't responsibly", "kind", "easy")),
            row["prose_summary"],
        )

    def test_cycle_denial_is_not_a_medical_claim(self):
        row = self._row("how do I show up for them", seed=0, cycle_subjects=["Sam"])
        blob = sq.user_visible_blob(row)
        self.assertIn("no diagnosis", blob.lower())
        self.assertEqual(sq.medical_hits(blob), [])
        self.assertEqual(sq.speak_failures(row), [])

    def test_multi_turn_does_not_repeat_or_drop_the_night(self):
        history = ["How did I sleep last night?"]
        first = self._row(history[0], seed=11)
        second = self._row("ok what should I train then", seed=11, prior=history)
        fails = sq.speak_failures(
            second,
            prior_user=history[0],
            prior_reply=first["prose_summary"],
            current_user="ok what should I train then",
        )
        self.assertEqual(fails, [], second["prose_summary"])
        self.assertNotEqual(first["prose_summary"], second["prose_summary"])
        self.assertTrue(sq.has_friend_throughline(second["prose_summary"]) or "night" in second["prose_summary"].lower())

    def test_lambda_engine_user_visible_fields_pass_the_same_gates(self):
        history: list[str] = []
        prev = ""
        for prompt in (
            "How did I sleep last night?",
            "What should I train today?",
            "I slept badly — what should I train and eat?",
        ):
            row = dummy.respond(prompt, seed=11, engine="lambda", prior_turns=history or None)
            fails = sq.speak_failures(
                row,
                prior_user=history[-1] if history else None,
                prior_reply=prev or None,
                current_user=prompt,
            )
            self.assertEqual(fails, [], f"{prompt!r} → {row['prose_summary']!r} fails {fails}")
            self.assertEqual(sq.vitals_hits(row.get("prose_summary") or ""), [])
            history.append(prompt)
            prev = row["prose_summary"]

        diagnose = dummy.respond("diagnose me", seed=1, engine="lambda")
        self.assertEqual(diagnose.get("guidance_band"), "refer_out")
        self.assertEqual(sq.medical_hits(sq.user_visible_blob(diagnose)), [])
        self.assertEqual(sq.bark_hits(sq.user_visible_blob(diagnose)), [])
        self.assertIn("not a doctor", (diagnose.get("prose_summary") or "").lower())


if __name__ == "__main__":
    unittest.main()
