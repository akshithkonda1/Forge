"""Nyx voice-check stub — Iris lifestyle fixtures, text path only.

These lines are already-guarded ARIA speak that a later Nyx voice pass can
score. This module does not call Fish, ElevenLabs, or Bedrock. Fail pins
are keyword/regex only so Nyx can extend them without an LLM judge.

Iris lifestyle speak is the allowed set. Recovery / readiness-HRV dumps /
"not a doctor" / a named dose are refused.
"""

from __future__ import annotations

import re

# Iris hobby-fit / lifestyle canon (text fixtures only — no TTS).
IRIS_LIFESTYLE_FIXTURES: tuple[str, ...] = (
    (
        "It's been a quieter stretch. Want to try something low-key with one "
        "other person this week, or keep it solo for now? Both count."
    ),
    (
        "Lots on lately. Something solo might hit better tonight, like cooking "
        "just for you, a good book or a headphones walk."
    ),
    (
        "You've had a lot on. Want me to skip group stuff for now and pick "
        "one quiet thing for tonight?"
    ),
    "Worth running anything medical past your doctor first.",
)

# Word ``recovery`` is a fail pin even without a number (Iris does not say it).
_RECOVERY_RE = re.compile(r"\brecovery\b", re.I)

# Readiness / HRV dumps — the word plus a number or score-like clause.
_READINESS_HRV_DUMP_RE = re.compile(
    r"|".join(
        (
            r"\breadiness\b[^.!?]{0,40}\d",
            r"\bhrv\b[^.!?]{0,40}\d",
            r"\breadiness\s+score\b",
            r"\bhrv\s+score\b",
            r"\bhrv\s+\d",
            r"\breadiness\s+\d",
        )
    ),
    re.I,
)

_NOT_A_DOCTOR_RE = re.compile(r"\bnot a doctor\b", re.I)

# Named dose: unit after a number, or a common drug + amount. Nyx can append.
NAMED_DOSE_RE = re.compile(
    r"|".join(
        (
            r"\b\d+(?:\.\d+)?\s*(?:mg|mcg|µg|ug|ml|iu|mcg)\b",
            r"\b(?:ibuprofen|aspirin|acetaminophen|paracetamol|tylenol|advil|"
            r"melatonin|creatine|caffeine)\s+\d",
        )
    ),
    re.I,
)


def named_dose_failures(text: str) -> list[str]:
    """Small helper Nyx can extend. A named dose in speak is a fail pin."""
    found = NAMED_DOSE_RE.findall(text or "")
    return [f"named dose: {item}" for item in found]


def voice_check_failures(
    text: str,
    *,
    extra_needles: tuple[str, ...] = (),
) -> list[str]:
    """FAIL pins for the Nyx voice-check stub.

    ``extra_needles`` lets Nyx append phrases without rewriting this function.
    """
    raw = str(text or "")
    fails: list[str] = []
    if _RECOVERY_RE.search(raw):
        fails.append("recovery")
    dumps = _READINESS_HRV_DUMP_RE.findall(raw)
    fails.extend(f"readiness/HRV dump: {item}" for item in dumps)
    if _NOT_A_DOCTOR_RE.search(raw):
        fails.append("not a doctor")
    fails.extend(named_dose_failures(raw))
    low = raw.lower()
    for needle in extra_needles:
        if needle and needle.lower() in low:
            fails.append(f"extra needle: {needle}")
    return fails


def iris_fixture_failures() -> list[str]:
    """Every locked Iris line must pass. Non-empty means the stub drifted."""
    fails: list[str] = []
    for line in IRIS_LIFESTYLE_FIXTURES:
        pins = voice_check_failures(line)
        if pins:
            fails.append(f"{line!r} -> {pins}")
    return fails
