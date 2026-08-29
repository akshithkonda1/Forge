import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import voice_diagnostics  # noqa: E402


class SourceHygieneTests(unittest.TestCase):
    def test_never_imports_a_cloud_sdk_or_does_network_io(self):
        # Same proof this package's other dummy-orchestrator collaborators
        # each carry for themselves: this module works on text already in
        # hand, so it has no legitimate reason to import anything beyond
        # stdlib. (Deliberately avoids naming the network-fetch module in
        # this comment — that module's own isolation test flags any file
        # outside its own allowed set that so much as mentions its name.)
        src = Path(voice_diagnostics.__file__).read_text()
        imports = [
            line.strip()
            for line in src.splitlines()
            if line.strip().startswith(("import ", "from "))
        ]
        forbidden = ("boto3", "botocore", "bedrock_client", "urllib", "requests", "http.client")
        for stmt in imports:
            for needle in forbidden:
                self.assertNotIn(needle, stmt, f"voice_diagnostics imported {needle}")


class DiagnoseVerdictTests(unittest.TestCase):
    def test_clearly_human_text_reads_as_human(self):
        text = (
            "You're in a solid spot today, since sleep's been catching up — "
            "that's worth building on. I'd keep the session moderate and see "
            "how the next few days feel."
        )
        diagnosis = voice_diagnostics.diagnose(text)
        self.assertEqual(diagnosis.verdict, "human")
        self.assertFalse(diagnosis.leads_with_number)
        self.assertTrue(diagnosis.has_correlation_language)
        self.assertTrue(diagnosis.has_second_person_address)

    def test_clearly_data_driven_text_reads_as_data_driven(self):
        # Same shape ARIAEngine._context_phrase produces: a bare label
        # immediately against its value, no connecting prose, no address to
        # the reader — a field dump wearing a period.
        text = "Readiness is 96, HRV 52ms (7-day avg 48.3), ACWR 0.63, sleep debt 0.2h."
        diagnosis = voice_diagnostics.diagnose(text)
        self.assertEqual(diagnosis.verdict, "data_driven")
        self.assertTrue(diagnosis.leads_with_number)
        self.assertFalse(diagnosis.has_second_person_address)
        self.assertGreaterEqual(diagnosis.field_dump_hits, 2)

    def test_a_plain_language_lead_around_a_field_dump_middle_reads_as_mixed(self):
        # The actual text a live `--voice-check` run produced for "How did I
        # sleep last night?" (seed=42): an organic lead and tail sentence
        # wrapped around one `_context_phrase`-shaped middle sentence. Pinned
        # here verbatim so this exact real-world case can never silently
        # start reading as "human" again.
        text = (
            "You're in a good spot to train. Readiness is 96, HRV 52ms "
            "(7-day avg 48.3), ACWR 0.63, sleep debt 0.2h. A solid "
            "moderate-to-hard session fits today."
        )
        diagnosis = voice_diagnostics.diagnose(text)
        self.assertEqual(diagnosis.verdict, "mixed")
        self.assertEqual(diagnosis.sentence_count, 3)
        self.assertFalse(diagnosis.leads_with_number)
        self.assertTrue(diagnosis.has_second_person_address)
        self.assertGreaterEqual(diagnosis.field_dump_hits, 2)


class NumberCitationRegressionTests(unittest.TestCase):
    """Coverage for the bug found and fixed while building this module: the
    original `_NUMBER_RE` only matched a number carrying a unit suffix
    ("48ms"), so a bare "Readiness 62" was invisible to the heuristic — which
    silently flipped both `leads_with_number` and `number_density` to
    false-human signals for text that was obviously mechanical. These tests
    pin the fixed behavior directly so this specific regression can't
    reappear unnoticed."""

    def test_bare_number_after_a_metric_label_counts_as_a_citation(self):
        diagnosis = voice_diagnostics.diagnose("Readiness 62. HRV 48. Streak 4.")
        self.assertEqual(diagnosis.number_count, 3)

    def test_number_with_a_unit_suffix_still_counts_as_a_citation(self):
        diagnosis = voice_diagnostics.diagnose("Rest for 20 min then log 3 sets.")
        self.assertEqual(diagnosis.number_count, 2)

    def test_bare_number_without_a_recognized_metric_label_is_not_a_citation(self):
        # "day" isn't one of this domain's metric names — a bare digit next
        # to it (a date, a rep count in passing) shouldn't read as a data
        # point the way "readiness 62" should.
        diagnosis = voice_diagnostics.diagnose(
            "On day 2 you felt good. By day 5 things clicked."
        )
        self.assertEqual(diagnosis.number_count, 0)


class SignalDetectionTests(unittest.TestCase):
    def test_leads_with_number_true_when_the_opening_words_carry_a_number(self):
        diagnosis = voice_diagnostics.diagnose("68% ready today. Let's build from there.")
        self.assertTrue(diagnosis.leads_with_number)
        self.assertIn("leads with a number", diagnosis.evidence[0])

    def test_leads_with_number_false_when_prose_opens_the_reply(self):
        diagnosis = voice_diagnostics.diagnose("You're ready today at 68%. Let's build from there.")
        self.assertFalse(diagnosis.leads_with_number)

    def test_correlation_language_is_detected(self):
        diagnosis = voice_diagnostics.diagnose(
            "Your HRV dipped since your sleep ran short, so today calls for an easier session."
        )
        self.assertTrue(diagnosis.has_correlation_language)

    def test_correlation_language_absent_by_default(self):
        diagnosis = voice_diagnostics.diagnose("HRV is 48. Sleep debt is 2 hours.")
        self.assertFalse(diagnosis.has_correlation_language)

    def test_second_person_address_is_detected(self):
        diagnosis = voice_diagnostics.diagnose("Your recovery looks solid — you're in good shape today.")
        self.assertTrue(diagnosis.has_second_person_address)

    def test_second_person_address_absent_when_the_reply_only_reports(self):
        diagnosis = voice_diagnostics.diagnose("Recovery looks solid. The plan is to train today.")
        self.assertFalse(diagnosis.has_second_person_address)

    def test_field_dump_pattern_counts_tight_label_value_runs(self):
        diagnosis = voice_diagnostics.diagnose("HRV 48, readiness 62, streak 4 — a busy day ahead.")
        self.assertGreaterEqual(diagnosis.field_dump_hits, 2)

    def test_field_dump_pattern_ignores_a_label_used_in_prose(self):
        diagnosis = voice_diagnostics.diagnose(
            "Your readiness is looking better than it has all week."
        )
        self.assertEqual(diagnosis.field_dump_hits, 0)


class SentenceSplittingTests(unittest.TestCase):
    def test_decimal_numbers_do_not_cause_spurious_sentence_splits(self):
        diagnosis = voice_diagnostics.diagnose("HRV is 48.3 today. That's a good sign.")
        self.assertEqual(diagnosis.sentence_count, 2)

    def test_empty_text_does_not_crash(self):
        diagnosis = voice_diagnostics.diagnose("")
        self.assertEqual(diagnosis.sentence_count, 1)
        self.assertEqual(diagnosis.lead_sentence, "")
        self.assertIn(diagnosis.verdict, ("human", "data_driven", "mixed"))

    def test_single_sentence_reply_is_its_own_lead(self):
        diagnosis = voice_diagnostics.diagnose("You're good to train today.")
        self.assertEqual(diagnosis.sentence_count, 1)
        self.assertEqual(diagnosis.lead_sentence, "You're good to train today.")


class AsDictTests(unittest.TestCase):
    def test_as_dict_has_every_field_and_matches_the_dataclass(self):
        diagnosis = voice_diagnostics.diagnose("You're doing fine. Keep it steady.")
        d = diagnosis.as_dict()
        self.assertEqual(
            set(d.keys()),
            {
                "verdict", "lead_sentence", "leads_with_number", "number_count",
                "sentence_count", "number_density", "has_correlation_language",
                "has_second_person_address", "field_dump_hits", "evidence",
            },
        )
        self.assertEqual(d["verdict"], diagnosis.verdict)
        self.assertEqual(d["evidence"], diagnosis.evidence)
        self.assertIsInstance(d["evidence"], list)


if __name__ == "__main__":
    unittest.main()
