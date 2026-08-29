"""Human-vs-data-driven voice diagnostics for the dummy ARIA orchestrator.

Answers a specific, standing product question, in the user's own words:
when the dummy orchestrator uses the real synthetic data it already has,
does the resulting reply read as human — a considered read that happens to
cite numbers — or as data-driven — a field dump wearing sentence
punctuation? This measures the exact thing this session's Swift-side voice
rewrites (``AriaVoiceEngine.statusLine``, ``AriaCoachAgent.brief()``) were
built to fix, reusing their own stated definition rather than inventing a
new one: "a plain-language read leads, numbers are cited only sometimes,
signals get correlated into one statement instead of listed."

Same discipline as ``aria_evaluator.py``: deterministic, heuristic, no
LLM-as-judge — every signal here is a countable, inspectable property of
the actual generated text, not a guess.

Kept as its own module rather than a 7th ``DimensionScores`` dimension in
``aria_evaluator.py`` on purpose: that scorer's weights and dimension count
are shared by the model-comparison pipeline (``lifetime_suite.py``'s
``_eval_seed``, the committed ``baselines/*.json`` fixtures) — changing its
shape is a bigger, separate decision than "diagnose the dummy
orchestrator's own voice." This module works standalone against any reply
text regardless of where it came from.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

# A metric citation: either a number with a plausible health/fitness unit
# attached ("68%", "48ms", "6.8h", "3 sets"), or a bare number sitting right
# after one of this domain's own metric names ("readiness 62", "score 55",
# "streak 4"). Both count as "citing a number" — a unit isn't what makes
# "readiness 62" read as a data point instead of prose; the label does. Not
# every bare digit counts ("day 2" isn't a citation), which is why the bare
# form requires a recognized metric-name prefix rather than matching \d+ on
# its own.
_METRIC_LABELS = r"readiness|hrv|score|streak|debt|steps|acwr|rhr"
# The unit alternation splits "%" out from the alphabetic units on purpose:
# `\b` only fires at a word/non-word transition, and "%" is itself a
# non-word character, so `(?:%|ms|...)\b` never actually matched a percent
# sign followed by anything else non-word (a space, a comma, end of
# string) — "68% ready" was silently invisible the same way a bare
# "readiness 62" was before the label-number branch below was added. The
# alphabetic units still need their own trailing `\b` (so "hr" doesn't
# swallow part of "hrs"); "%" needs none, since it can't be mistaken for
# part of a following word.
_NUMBER_RE = re.compile(
    r"\b\d+(?:\.\d+)?\s?(?:%|(?:ms|bpm|h|hr|hrs|hours|min|mins|minutes|kg|lbs?|kcal|cal|reps?|sets?|x)\b)"
    rf"|\b(?:{_METRIC_LABELS})\b\s*(?:is\s*|score\s*|of\s*)?\d+(?:\.\d+)?",
    re.IGNORECASE,
)

# Words that tie two or more signals into one read rather than leaving them
# as parallel facts — "since", "because", "given", "which means", "so".
_CORRELATION_MARKERS = (
    "since", "because", "given that", "given ", "which means", " so ", " so,",
    "that means", "means you", "means today",
)

_SECOND_PERSON_RE = re.compile(r"\byou(?:'re|r|'ve|'ll)?\b", re.IGNORECASE)

# A bare "label ... value" run with no connecting prose in between — the
# shape a raw field dump takes even inside something that is grammatically
# a sentence, e.g. "HRV 48ms, readiness 62, sleep 6.8h." Same label set as
# `_NUMBER_RE`, plus "sleep" specifically for this pattern (it's rarely
# followed directly by a bare number elsewhere, but "sleep 6.8h" — label
# immediately against value — is exactly the shape this regex exists to
# catch).
_FIELD_DUMP_RE = re.compile(
    rf"\b(?:{_METRIC_LABELS}|sleep)\b[^.!?]{{0,3}}\d",
    re.IGNORECASE,
)


@dataclass
class VoiceDiagnosis:
    verdict: str  # "human" | "data_driven" | "mixed"
    lead_sentence: str
    leads_with_number: bool
    number_count: int
    sentence_count: int
    number_density: float
    has_correlation_language: bool
    has_second_person_address: bool
    field_dump_hits: int
    evidence: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        return {
            "verdict": self.verdict,
            "lead_sentence": self.lead_sentence,
            "leads_with_number": self.leads_with_number,
            "number_count": self.number_count,
            "sentence_count": self.sentence_count,
            "number_density": self.number_density,
            "has_correlation_language": self.has_correlation_language,
            "has_second_person_address": self.has_second_person_address,
            "field_dump_hits": self.field_dump_hits,
            "evidence": self.evidence,
        }


def _split_sentences(text: str) -> list[str]:
    """Good enough for short coaching replies: split on sentence-ending
    punctuation, drop empties. Not built to handle abbreviations or a
    decimal landing exactly at a sentence boundary — rare enough in this
    text style not to matter here."""
    parts = re.split(r"(?<=[.!?])\s+", text.strip())
    return [p for p in parts if p.strip()]


def diagnose(text: str) -> VoiceDiagnosis:
    """Classify one piece of ARIA reply text along the human<->data-driven
    axis. Works on any prose, not just the dummy orchestrator's own output
    — the criteria are about the text's shape, not its source.

    Five signals, each backed by a concrete count or match rather than a
    subjective read, weighed by a simple majority (not a black-box score):
    which sentence leads, how dense the numbers run, whether a field-dump
    pattern shows up, whether signals get tied together, and whether the
    reply talks to a person or just reports at one.
    """
    sentences = _split_sentences(text)
    sentence_count = max(1, len(sentences))
    lead = sentences[0] if sentences else text.strip()

    numbers = _NUMBER_RE.findall(text)
    number_count = len(numbers)
    density = round(number_count / sentence_count, 2)

    # "Leads with a number" if one appears in the lead sentence's first
    # three words — concrete version of "a plain-language read leads":
    # "68% ready, HRV 48ms" leads with the number; "You're solid today at
    # 68%" does not.
    lead_words = lead.split()[:3]
    leads_with_number = bool(_NUMBER_RE.search(" ".join(lead_words)))

    correlation = any(marker in text.lower() for marker in _CORRELATION_MARKERS)
    second_person = bool(_SECOND_PERSON_RE.search(text))
    field_dump_hits = len(_FIELD_DUMP_RE.findall(text))

    evidence: list[str] = []
    data_driven_signals = 0
    human_signals = 0

    if leads_with_number:
        data_driven_signals += 1
        evidence.append(f"leads with a number: {' '.join(lead_words)!r}")
    else:
        human_signals += 1
        evidence.append("leads with a plain-language read, not a number")

    if density > 1.2:
        data_driven_signals += 1
        evidence.append(
            f"{number_count} numbers across {sentence_count} sentence(s) "
            f"({density}/sentence) — reads as a field dump"
        )
    elif density <= 0.6:
        human_signals += 1
        evidence.append(f"numbers cited sparingly ({density}/sentence)")

    if field_dump_hits >= 2:
        data_driven_signals += 1
        evidence.append(
            f"{field_dump_hits} label-then-value runs (e.g. \"HRV 48\") with no connecting prose"
        )

    if correlation:
        human_signals += 1
        evidence.append("correlates signals into one statement (found a connective like \"since\"/\"which means\")")

    if second_person:
        human_signals += 1
        evidence.append("addresses the reader directly (\"you\"/\"your\")")
    else:
        data_driven_signals += 1
        evidence.append("no direct address — reads like a report, not a conversation")

    if data_driven_signals > human_signals:
        verdict = "data_driven"
    elif human_signals > data_driven_signals:
        verdict = "human"
    else:
        verdict = "mixed"

    return VoiceDiagnosis(
        verdict=verdict,
        lead_sentence=lead,
        leads_with_number=leads_with_number,
        number_count=number_count,
        sentence_count=sentence_count,
        number_density=density,
        has_correlation_language=correlation,
        has_second_person_address=second_person,
        field_dump_hits=field_dump_hits,
        evidence=evidence,
    )
