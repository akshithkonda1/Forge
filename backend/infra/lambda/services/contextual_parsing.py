"""Word-boundary-safe, typo-tolerant keyword matching for ARIA's request
classifier.

``classify_request``/``_focus_domain`` (in ``aria_engine.py``) test raw
substring containment against short keyword lists — ``"push" in text``. That
fails in two directions at once: a short keyword like ``"rest"`` fires inside
an unrelated longer word (``"restaurant"``), and a single typo drops a
message out of every keyword list with no signal at all (``"sleeep"``
matches nothing, so a real sleep question silently falls through to whatever
the classifier's default happens to be).

This mirrors the Swift ``ContextualParsingEngine`` used for the same reason
on the client (``AriaCoachAgentRouter``, ``AriaIntentResolver``) — same
approach, no shared code, since Swift and Python cannot share a library
here. Standard library only: ``re`` for word-boundary-safe phrase matching,
a plain word-length-scaled edit distance for typo tolerance.
"""

from __future__ import annotations

import re
from typing import Iterable

_WORD_RE = re.compile(r"[a-z']+")

# A few common inflectional endings a truncated stem keyword (e.g. "hydrat",
# "recover") is allowed to complete into. Kept short on purpose: it is what
# separates "hydrat" + "ing" (a real inflection) from "nap" + "kin" (an
# unrelated word that happens to start the same way) — a bare prefix check
# cannot tell those apart on its own.
_INFLECTIONAL_SUFFIXES = {"ing", "ion", "ions", "ers", "ors", "able", "ment"}


def tokenize(text: str) -> list[str]:
    """Lowercased letter-run tokens (apostrophes kept, so "don't" is one word)."""
    return _WORD_RE.findall(text.lower())


def _max_typo_distance(length: int) -> int:
    """How many single-character edits a word of this length tolerates
    before it counts as a different word rather than the same one, mistyped.
    Four letters or fewer get none: at that length almost any single edit
    lands on a real, different word ("rest"/"test"), so fuzzy matching there
    would trade one false-positive class for another."""
    if length <= 4:
        return 0
    if length <= 7:
        return 1
    return 2


def _edit_distance(a: str, b: str) -> int:
    """Levenshtein distance — the classic single-row DP. Keyword lists here
    run a few dozen words at most per message, so nothing fancier earns
    its keep."""
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    previous = list(range(len(b) + 1))
    for i, ca in enumerate(a, start=1):
        current = [i] + [0] * len(b)
        for j, cb in enumerate(b, start=1):
            cost = 0 if ca == cb else 1
            current[j] = min(
                previous[j] + 1,          # deletion
                current[j - 1] + 1,       # insertion
                previous[j - 1] + cost,   # substitution
            )
        previous = current
    return previous[-1]


def _token_matches(token: str, needle: str) -> bool:
    """Whether `token` counts as the same word as `needle`: exact, a bounded
    prefix ending in a plausible inflection, or a small typo."""
    if token == needle:
        return True
    if token.startswith(needle):
        leftover = token[len(needle):]
        if len(leftover) <= 2:
            return True
        if len(leftover) <= 4 and leftover in _INFLECTIONAL_SUFFIXES:
            return True
    tolerance = _max_typo_distance(len(needle))
    if tolerance and abs(len(token) - len(needle)) <= tolerance:
        if _edit_distance(token, needle) <= tolerance:
            return True
    return False


def contains_word(text: str, needle: str) -> bool:
    """A single-word needle, matched whole-word against `text` (exact,
    bounded prefix, or small typo — see `_token_matches`). Multi-word
    needles always return False here; use `contains_phrase`, or `matches`,
    which dispatches for you."""
    needle = needle.strip().lower()
    if not needle or " " in needle:
        return False
    return any(_token_matches(tok, needle) for tok in tokenize(text))


def contains_phrase(text: str, phrase: str) -> bool:
    """A multi-word needle, matched as a whole-word-boundary substring —
    anchored (so a short entry like "pr" only matches as its own word,
    no manual space-padding needed) but not fuzzy: a wrong phrase reads as a
    different intent far more easily than a wrong single word does,
    so this stays exact past the boundary fix. Falls back to `contains_word`
    when `phrase` turns out not to have a space in it."""
    phrase = phrase.strip().lower()
    if not phrase:
        return False
    if " " not in phrase:
        return contains_word(text, phrase)
    pattern = r"\b" + re.escape(phrase) + r"\b"
    return re.search(pattern, text.lower()) is not None


def matches(text: str, needle: str) -> bool:
    """Drop-in replacement for `needle in text.lower()`."""
    return contains_phrase(text, needle) if " " in needle else contains_word(text, needle)


def matches_any(text: str, needles: Iterable[str]) -> bool:
    return any(matches(text, needle) for needle in needles)
