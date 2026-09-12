import unittest

import _bootstrap  # noqa: F401

from services import contextual_parsing as cp  # noqa: E402


class WordBoundaryTests(unittest.TestCase):
    """The bug this module exists to fix: a short keyword firing inside an
    unrelated longer word."""

    def test_rest_does_not_fire_inside_restaurant(self):
        self.assertFalse(cp.contains_word("let's pick a restaurant for dinner", "rest"))

    def test_nap_does_not_fire_inside_napkin(self):
        self.assertFalse(cp.contains_word("grab a napkin please", "nap"))

    def test_sex_does_not_fire_inside_exercise(self):
        self.assertFalse(cp.contains_word("what exercise should I do", "sex"))

    def test_whole_word_still_matches(self):
        self.assertTrue(cp.contains_word("I need to rest today", "rest"))
        self.assertTrue(cp.contains_word("time for a nap", "nap"))


class InflectionTests(unittest.TestCase):
    """Ordinary, correctly-spelled inflections must keep matching — the
    fix for false positives must not regress plain plurals/gerunds."""

    def test_common_suffixes_still_match(self):
        self.assertTrue(cp.contains_word("my knee hurts today", "hurt"))
        self.assertTrue(cp.contains_word("still eating breakfast", "eat"))
        self.assertFalse(cp.contains_word("I ate already", "eat"))  # "ate" isn't "eat" + a suffix
        self.assertTrue(cp.contains_word("the pain runs deep", "pain"))

    def test_deliberate_stem_keywords_still_catch_every_inflection(self):
        # "hydrat"/"ovulat" are truncated on purpose in the real keyword
        # lists, specifically so they catch every inflected form.
        for word in ("hydrate", "hydrating", "hydration"):
            self.assertTrue(cp.contains_word(f"remember to {word}", "hydrat"), word)
        for word in ("ovulate", "ovulating", "ovulation"):
            self.assertTrue(cp.contains_word(f"tracking {word}", "ovulat"), word)

    def test_stem_leftover_must_look_like_a_real_inflection(self):
        # "ovulat" + "ing"/"ion" are real inflections (allowed); a leftover
        # that isn't a plausible ending is exactly the "nap"/"napkin" shape
        # of false positive, so it stays blocked even past the stem.
        self.assertTrue(cp.contains_word("hydrated meals only", "hydrat"))
        self.assertFalse(cp.contains_word("ovulatory cycle tracking", "ovulat"))


class TypoToleranceTests(unittest.TestCase):
    def test_one_letter_typo_still_matches(self):
        self.assertTrue(cp.contains_word("I feel so tird today", "tired"))
        self.assertTrue(cp.contains_word("how did I sleeep", "sleep"))

    def test_short_words_require_an_exact_match(self):
        # Below the fuzzy floor: any "typo" at this length is usually just a
        # different real word, so no fuzzy tolerance is applied.
        self.assertFalse(cp.contains_word("let's go run a test", "rest"))

    def test_typo_too_far_away_does_not_match(self):
        self.assertFalse(cp.contains_word("completely unrelated word", "tired"))


class PhraseMatchingTests(unittest.TestCase):
    def test_multi_word_phrase_matches_with_boundaries(self):
        self.assertTrue(cp.contains_phrase("what should i eat for lunch", "what should"))
        self.assertFalse(cp.contains_phrase("somewhat shouldering the load", "what should"))

    def test_short_acronym_needs_no_manual_padding(self):
        # The real keyword list used to pad this as " pr " to fake a word
        # boundary; that padding missed "pr" at the very start or end of a
        # message (no space beyond the punctuation). Plain "pr" now works
        # correctly in every position.
        self.assertTrue(cp.contains_phrase("what's my pr?", "pr"))
        self.assertTrue(cp.contains_phrase("pr day today", "pr"))
        self.assertFalse(cp.contains_phrase("this is private", "pr"))

    def test_matches_dispatches_by_needle_shape(self):
        self.assertTrue(cp.matches("time to rest", "rest"))
        self.assertTrue(cp.matches("what should i train today", "what should"))
        self.assertFalse(cp.matches("restaurant night", "rest"))


class MatchesAnyTests(unittest.TestCase):
    def test_matches_any_short_circuits_on_first_hit(self):
        needles = ("recover", "recovery", "tired", "exhausted")
        self.assertTrue(cp.matches_any("so tired after that session", needles))
        self.assertFalse(cp.matches_any("great restaurant last night", needles))


if __name__ == "__main__":
    unittest.main()
