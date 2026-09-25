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
            "REM is light at 12%. Light sleep at 61%.",
            "Deep sleep is 13% of the night, under your usual.",
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

    def test_clinical_words_fail_whole_word_not_bad_and_badminton_pass(self):
        terms = (
            "poor", "bad", "debt", "deficit", "exhausted", "fatigued",
            "stressed", "under-recovered", "overtrained", "abnormal", "elevated",
        )
        for term in terms:
            with self.subTest(term=term):
                line = f"Today looks {term}."
                self.assertTrue(sq.clinical_hits(line), line)
                self.assertTrue(sq.speak_failures({"prose_summary": line}), line)
        body = "Your body is asking for a lighter day."
        self.assertTrue(sq.clinical_hits(body), body)
        self.assertTrue(sq.speak_failures({"prose_summary": body}), body)
        self.assertEqual(sq.clinical_hits("That's not bad."), [])
        self.assertEqual(sq.speak_failures({"prose_summary": "That's not bad."}), [])
        self.assertEqual(sq.clinical_hits("Want to play badminton tonight?"), [])
        self.assertEqual(sq.speak_failures({"prose_summary": "Want to play badminton tonight?"}), [])

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


class LeakAndMemoryGates(unittest.TestCase):
    """Independent of speak_guard.py — catch runtime guard regressions."""

    def test_guide_text_leakage_fails(self):
        leaked = "They have repair in the bank. Spend it on one quality session."
        self.assertTrue(sq.guide_leak_hits(leaked), leaked)
        self.assertTrue(sq.speak_failures({"prose_summary": leaked}))
        why = "Usable picture is still thin — keep today easy."
        self.assertTrue(sq.guide_leak_hits(why), why)
        self.assertTrue(sq.speak_failures({"prose_summary": why}))
        friend = "Keep today kind. 20 easy minutes, then call it."
        self.assertEqual(sq.guide_leak_hits(friend), [])
        self.assertEqual(sq.speak_failures({"prose_summary": friend}), [])

    def test_zero_hours_since_phrasing_fails(self):
        bad = "Only 0 h since strength — keep today easy."
        self.assertTrue(sq.zero_hours_hits(bad), bad)
        self.assertTrue(sq.speak_failures({"prose_summary": bad}))
        ok = "Only 20 h since strength — keep today easy."
        self.assertEqual(sq.zero_hours_hits(ok), [])

    def test_repeated_fragments_fail(self):
        dup = (
            "Keep today easy. Keep today easy. "
            "20 easy minutes, then call it. 20 easy minutes, then call it."
        )
        hits = sq.repeated_fragment_hits(dup)
        self.assertTrue(hits, dup)
        self.assertTrue(sq.speak_failures({"prose_summary": dup}))
        once = "Keep today easy. 20 easy minutes, then call it."
        self.assertEqual(sq.repeated_fragment_hits(once), [])

    def test_memory_block_label_read_back_fails(self):
        labeled = "Recent patterns: you skip Friday nights. Hold the structure."
        self.assertTrue(sq.memory_label_hits(labeled), labeled)
        self.assertTrue(sq.speak_failures({"prose_summary": labeled}))
        clean = "Hold the structure and keep Friday light."
        self.assertEqual(sq.memory_label_hits(clean), [])

    def test_stored_memory_note_of_five_plus_words_fails_short_callback_passes(self):
        note = "You always skip Friday night sessions when work runs late"
        dumped = f"Yeah — {note}. Keep today easy."
        self.assertTrue(sq.memory_note_hits(dumped, [note]), dumped)
        self.assertTrue(
            sq.speak_failures({"prose_summary": dumped}, memory_notes=[note])
        )
        callback = "Sure — since you like morning runs, keep it easy."
        short = "since you like morning runs"
        self.assertEqual(sq.memory_note_hits(callback, [short]), [])
        self.assertEqual(
            sq.speak_failures({"prose_summary": callback}, memory_notes=[short]),
            [],
        )

    def test_hr_bpm_sleep_stage_and_quoted_vitals_fail_including_via_card(self):
        dumps = (
            "HR 72 bpm — keep today easy.",
            "Deep sleep at 19% is in a healthy band.",
            "Readiness is 96, HRV 52ms.",
        )
        for text in dumps:
            with self.subTest(text=text):
                self.assertTrue(sq.vitals_hits(text), text)
                self.assertTrue(sq.speak_failures({"prose_summary": text}))
        via_card = {
            "prose_summary": "Keep today kind.",
            "card": {
                "action": "HR 72 bpm then call it",
                "why": "Deep sleep at 19%",
            },
        }
        blob = sq.user_visible_blob(via_card)
        self.assertTrue(sq.vitals_hits(blob), blob)
        self.assertTrue(sq.speak_failures(via_card))
        via_why_only = {
            "prose_summary": "Keep today kind.",
            "card": {"action": "20 easy minutes, then call it", "why": "HRV 12% below baseline"},
        }
        self.assertTrue(sq.speak_failures(via_why_only))


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
            fails = sq.friend_speak_floor(
                sq.speak_failures(
                    row,
                    prior_user=history[-1] if history else None,
                    prior_reply=prev or None,
                    current_user=prompt,
                )
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
        fails = sq.friend_speak_floor(sq.speak_failures(row))
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
        self.assertEqual(sq.friend_speak_floor(sq.speak_failures(row)), [])

    def test_multi_turn_does_not_repeat_or_drop_the_night(self):
        history = ["How did I sleep last night?"]
        first = self._row(history[0], seed=11)
        second = self._row("ok what should I train then", seed=11, prior=history)
        fails = sq.friend_speak_floor(
            sq.speak_failures(
                second,
                prior_user=history[0],
                prior_reply=first["prose_summary"],
                current_user="ok what should I train then",
            )
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
            fails = sq.friend_speak_floor(
                sq.speak_failures(
                    row,
                    prior_user=history[-1] if history else None,
                    prior_reply=prev or None,
                    current_user=prompt,
                )
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

    def test_multi_turn_recovery_and_forget_theme_stays_friend_not_clinic(self):
        """Dummy parity for upcoming memory-off / recovery themes — no vitals/bark/clinic/sludge."""
        prompts = (
            "How's my recovery looking?",
            "forget what I just told you",
            "ok what should I train then",
        )
        history: list[str] = []
        prev = ""
        for prompt in prompts:
            row = self._row(prompt, seed=11, prior=history or None)
            fails = sq.friend_speak_floor(
                sq.speak_failures(
                    row,
                    prior_user=history[-1] if history else None,
                    prior_reply=prev or None,
                    current_user=prompt,
                )
            )
            self.assertEqual(fails, [], f"{prompt!r} → {row['prose_summary']!r} fails {fails}")
            blob = sq.user_visible_blob(row)
            self.assertEqual(sq.vitals_hits(blob), [], blob)
            self.assertEqual(sq.medical_hits(blob), [], blob)
            self.assertEqual(sq.bark_hits(blob), [], blob)
            self.assertEqual(sq.sludge_hits(blob), [], blob)
            history.append(prompt)
            prev = row["prose_summary"]
        self.assertNotEqual(prev, "")
        first = self._row(prompts[0], seed=11)["prose_summary"]
        later = self._row(prompts[2], seed=11, prior=list(prompts[:2]))["prose_summary"]
        self.assertNotEqual(first, later)

    def test_stub_and_lambda_offline_fallback_both_pass_friend_gates(self):
        """Dummy/offline fallback parity — Bedrock stays off; both engines stay friend-speak."""
        prompt = "How's my recovery looking?"
        for engine in ("stub", "lambda"):
            with self.subTest(engine=engine):
                row = dummy.respond(prompt, seed=5, engine=engine)
                self.assertEqual(
                    sq.friend_speak_floor(sq.speak_failures(row, current_user=prompt)),
                    [],
                    row.get("prose_summary"),
                )
                self.assertNotEqual((row.get("reasoning_source") or "").lower(), "bedrock")


class EvidenceCoverageTests(unittest.TestCase):
    """card.evidence: clinical / medical / sludge-guide, not vitals (yet)."""

    def _row(self, evidence: dict) -> dict:
        return {
            "prose_summary": "Keep today kind.",
            "message": "Keep today kind.",
            "card": {
                "action": "20 easy minutes, then call it.",
                "evidence": evidence,
            },
        }

    def test_evidence_vitals_and_acwr_numbers_pass_while_switch_is_off(self):
        self.assertFalse(sq.CHECK_VITALS_ON_EVIDENCE)
        row = self._row({"notice": "Deep sleep at 17%", "why": "ACWR 1.32"})
        self.assertEqual(sq.speak_failures(row), [])
        self.assertTrue(sq.vitals_hits("Deep sleep at 17%"))
        self.assertTrue(sq.vitals_hits("ACWR 1.32"))

    def test_evidence_banned_clinical_word_fails(self):
        row = self._row({"notice": "your body is under-recovered"})
        fails = sq.speak_failures(row)
        self.assertTrue(any("evidence-clinical" in f for f in fails), fails)
        self.assertTrue(any("under-recovered" in f or "your body is" in f.lower() for f in fails), fails)

    def test_evidence_medical_treat_claim_fails(self):
        row = self._row({"why": "this will treat your insomnia"})
        fails = sq.speak_failures(row)
        self.assertTrue(any("evidence-medical" in f for f in fails), fails)

    def test_evidence_guide_writer_note_fails_sludge_or_guide_check(self):
        sludge = self._row({"notice": "It's important to note that we should keep today easy."})
        sludge_fails = sq.speak_failures(sludge)
        self.assertTrue(any("evidence-sludge" in f for f in sludge_fails), sludge_fails)
        guide = self._row({"why": "They have repair in the bank. Spend it on one quality session."})
        guide_fails = sq.speak_failures(guide)
        self.assertTrue(any("evidence-guide-leak" in f or "evidence-sludge" in f for f in guide_fails), guide_fails)

    def test_nested_and_raw_card_evidence_strings_are_walked(self):
        nested = self._row({"extra": {"note": "your body is under-recovered"}})
        nested_fails = sq.speak_failures(nested)
        self.assertTrue(any("evidence-clinical" in f for f in nested_fails), nested_fails)
        raw_only = {
            "prose_summary": "Keep today kind.",
            "raw": {"card": {"evidence": {"why": "this will treat your insomnia"}}},
        }
        raw_fails = sq.speak_failures(raw_only)
        self.assertTrue(any("evidence-medical" in f for f in raw_fails), raw_fails)


class SpeechLabelAndDashCapitalTests(unittest.TestCase):
    """Internal labels, stray Why., and dash-capitals on user-visible speech."""

    def test_scout_hug_first_line_fails_label_and_dash_capital(self):
        line = (
            "Yesterday's work is still in the legs — Hug first: restock day — "
            "easy body, water with the next meal, protect sleep like a friend would."
        )
        self.assertTrue(sq.label_hits(line), line)
        self.assertTrue(sq.dash_capital_hits(line), line)
        fails = sq.speak_failures({"prose_summary": line})
        self.assertTrue(any("speech-label" in f for f in fails), fails)
        self.assertTrue(any("dash-capital" in f for f in fails), fails)
        self.assertTrue(any("Hug first:" in f for f in fails), fails)
        self.assertTrue(any("Hug" in f for f in fails if "dash-capital" in f), fails)

    def test_why_bare_label_after_short_night_fails(self):
        line = "7.3 h is below your usual 7.3 h — a personal short night. Why. Sync HealthKit."
        self.assertTrue(sq.bare_label_hits(line), line)
        fails = sq.speak_failures({"prose_summary": line})
        self.assertTrue(any("bare-label" in f and "Why." in f for f in fails), fails)

    def test_friend_mode_label_mid_sentence_fails(self):
        line = "Keep today easy. Friend mode: restock and protect sleep."
        self.assertTrue(sq.label_hits(line), line)
        fails = sq.speak_failures({"prose_summary": line})
        self.assertTrue(any("speech-label" in f and "Friend mode:" in f for f in fails), fails)

    def test_time_ratio_and_friend_speech_pass(self):
        passing = (
            "protect your 22:30 wind-down tonight",
            "Yesterday's work is still in the legs, so keep today easy.",
            "Easy day — I'm with you.",
            "Split the work 3:1 if you want a lighter second block.",
            "I'm in, sweetly — keep it easy: sharp work, then stop.",
            "From MedlinePlus: drink water and rest.",
            "From Some Source: real info.",
            "See https://example.com/sleep tonight.",
        )
        for line in passing:
            with self.subTest(line=line):
                self.assertEqual(sq.label_hits(line), [], line)
                self.assertEqual(sq.bare_label_hits(line), [], line)
                self.assertEqual(sq.dash_capital_hits(line), [], line)
                self.assertEqual(sq.speak_failures({"prose_summary": line}), [], line)

    def test_en_dash_and_spaced_hyphen_capital_fail_i_contraction_passes(self):
        self.assertTrue(sq.dash_capital_hits("easy day – Hug the restock."))
        self.assertTrue(sq.dash_capital_hits("easy day - Restock tonight."))
        self.assertEqual(sq.dash_capital_hits("Easy day — I'll stay with you."), [])
        self.assertEqual(sq.dash_capital_hits("Easy day – I've got you."), [])

    def test_sol_protect_day_lines_pass(self):
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import aria_engine

        self.assertEqual(len(aria_engine._PROTECT_DAY_STEPS), 3)
        for line in aria_engine._PROTECT_DAY_STEPS:
            with self.subTest(line=line):
                self.assertEqual(sq.speak_failures({"prose_summary": line, "card": {"action": line}}), [])


if __name__ == "__main__":
    unittest.main()

