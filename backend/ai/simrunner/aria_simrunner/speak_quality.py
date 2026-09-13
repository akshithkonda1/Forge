"""Speak-quality FAIL GATES for Dummy / lifestyle ARIA.

Hypertune source of truth is the Dummy path (no Bedrock). These predicates
are deterministic keyword/regex gates — not an LLM judge — so a test can
FAIL when user-visible speak dumps vitals, barks like a drill sergeant,
slides into diagnose/treat/cure, or repeats generic-AI sludge / drops a
prior-turn memory.

User-visible fields: ``prose_summary``, ``message``, card ``action`` / ``why``.
Orchestration notes and thinking traces are out of scope.

Denial language ("can't diagnose", "no diagnosis") is allowed. Roles as
texture are allowed. Friend throughline (kind / protect / easy / soft) is
checked separately so a green training invite is not forced to sound like
a recovery day.
"""

from __future__ import annotations

import re

# --- Vitals / raw metric dumps ------------------------------------------------
# Wider than the Dummy / lambda ``_VITALS_SPEAK`` scrubber: also catch HRV %,
# sleep-debt numbers, and raw readiness/recovery/sleep scores. Time windows
# like "20 h since strength" or "fifteen minutes" are not vitals.

_VITALS_TOKENS = (
    "hrv",
    "bpm",
    "mmhg",
    "spo2",
    "vo2",
    "sleep debt",
    "sleep-debt",
    "% below baseline",
    "% above baseline",
    "% under baseline",
    "% over baseline",
    "recovery score",
)

_VITALS_SCORE_RE = re.compile(
    r"|".join(
        (
            r"\b(?:readiness|recovery|sleep)\s+score\s*(?:is\s+|of\s+)?\d",
            r"\breadiness\s+is\s+\d",
            r"\bhrv\b[^.!?]{0,32}\d+(?:\.\d+)?\s*%",
            r"sleep[- ]?debt[^.!?]{0,20}\d",
            r"\d+(?:\.\d+)?\s?ms\b",
            r"\d+(?:\.\d+)?\s?bpm\b",
            r"\bacwr\b[^.!?]{0,12}\d",
            r"\d+(?:\.\d+)?\s*%\s*(?:below|above|under|over)\s+(?:baseline|normal)",
            # Insight HUD leftovers the Iris token scrub does not catch:
            # "Sleep: 8.1 h total, 93 min deep (19%). Deep sleep at 19%".
            r"\bsleep:\s*\d",
            r"\d+(?:\.\d+)?\s?h total\b",
            r"\d+\s?min deep\b",
            r"\b(?:deep|rem|light)\s+sleep\s+at\s+\d+(?:\.\d+)?\s*%",
            r"\brem\s+is\s+light\s+at\s+\d+(?:\.\d+)?\s*%",
        )
    ),
    re.I,
)

# --- Cold bark / drill-sergeant ----------------------------------------------
# Bare "push" / "I'd go push" is a body-library split, not bark.
# "want to go hard" / "urge to push" is the user; we only fail trainer bark.

_BARK_RE = re.compile(
    r"|".join(
        (
            r"\bcrush(?:ing)? it\b",
            r"\bcrush today\b",
            r"\bno excuses\b",
            r"\bno pain[, ]?no gain\b",
            r"\bdrill[- ]sergeant\b",
            r"\bbeast mode\b",
            r"\bdestroy (?:it|today)\b",
            r"\bget after it\b",
            r"\bdon'?t be lazy\b",
            r"\bclear to push hard\b",
            r"\btime to push hard\b",
            r"\bpush harder\b",
            r"\byou must\b",
            r"\bno days off\b",
            r"\bpain is weakness\b",
            r"let's go!{2,}",
        )
    ),
    re.I,
)

# --- Medical diagnose / treat / cure -----------------------------------------
# Mirrors production ``guidance.contains_prescriptive_medical_language`` plus
# explicit treat/cure claims. Denial and metaphor ("wouldn't treat any day")
# do not fail.

_MEDICAL_CLAIM_RE = re.compile(
    r"|".join(
        (
            r"\bi diagnose\b",
            r"\bmy diagnosis\b",
            r"\byou should take\b",
            r"\bi(?:'d| would) prescribe\b",
            r"\btake this medication\b",
            r"\bstart taking\b",
            r"\bthis will cure\b",
            r"\bi can cure\b",
            r"\bcure your\b",
            r"\btreatment for\b",
            r"\btreat this\b",
            r"\btreat your\b",
            r"\bmedical condition\b",
            r"\byou (?:probably |likely |definitely |may |might )?"
            r"(?:have|'ve got|ve got) (?:a |an )?"
            r"(?:cancer|tumor|diabetes|infection|disease|disorder|concussion|"
            r"fracture|pneumonia|asthma|arthritis|depression|anxiety disorder|"
            r"adhd|std|sti|uti|hypertension|blood clot|sepsis|meningitis)\b",
        )
    ),
    re.I,
)

_MEDICAL_DENIAL = (
    "can't diagnose",
    "cannot diagnose",
    "no diagnosis",
    "not a diagnosis",
    "not a prescription",
    "can't prescribe",
    "cannot prescribe",
    "wouldn't treat any",
    "not medical treatment",
)

# --- Generic-AI sludge -------------------------------------------------------

_SLUDGE_RE = re.compile(
    r"|".join(
        (
            r"\bas an ai\b",
            r"\bas a language model\b",
            r"\bgreat question\b",
            r"\bi hope this helps\b",
            r"\blet me know if you have any (?:other )?questions\b",
            r"\bi'm here to help(?: you)?\b",
            r"\bcertainly[,!] i(?:'d| would) be happy\b",
            r"\bit's important to note\b",
            r"\bin conclusion\b",
            r"\bsame question, new phrasing\b",
            r"\bfresh pass\b",
            r"\banother cut\b",
            r"\bfollowing on from\b",
        )
    ),
    re.I,
)

_FRIEND_CUES = (
    "kind",
    "protect",
    "yeah",
    "okay",
    "easy",
    "soft",
    "gentle",
    "with you",
    "care",
    "i'm with",
    "fair",
    "sure —",
    "sure -",
    "dial",
    "lighter",
)

_SLEEP_CUES = ("sleep", "slept", "last night", "the night", "insomnia")
_NIGHT_ACK = ("night", "sleep", "slept", "rest")
_DISCOURSE_MOVES = (
    "easier", "make it easy", "too hard", "lighter", "gentler", "dial it back",
    "shorter", "quicker", "less time", "skip it", "skip that", "never mind", "nvm",
    "forget it",
)


def user_visible_blob(row: dict | None) -> str:
    """Join the fields a person (or voice) actually hears."""
    row = row or {}
    card = row.get("card") or {}
    why = card.get("why") or card.get("timing") or ""
    parts = [
        row.get("prose_summary") or "",
        row.get("message") or "",
        card.get("action") or "",
        why,
    ]
    return " ".join(p for p in parts if p)


def _hits(pattern: re.Pattern[str], text: str) -> list[str]:
    return [m.group(0) for m in pattern.finditer(text or "")]


def vitals_hits(text: str) -> list[str]:
    """Tokens / score dumps that must never appear in user-visible speak."""
    low = (text or "").lower()
    found = [tok for tok in _VITALS_TOKENS if tok in low]
    found.extend(_hits(_VITALS_SCORE_RE, text or ""))
    # Preserve order, drop dupes (token + regex can both fire on "hrv 12%").
    seen: set[str] = set()
    out: list[str] = []
    for item in found:
        key = item.lower()
        if key not in seen:
            seen.add(key)
            out.append(item)
    return out


def bark_hits(text: str) -> list[str]:
    """Cold bark / crush-it / drill-sergeant trainer voice."""
    return _hits(_BARK_RE, text or "")


def medical_hits(text: str) -> list[str]:
    """Diagnose / treat / cure claims. Denial language is not a hit."""
    raw = text or ""
    low = raw.lower()
    found = _hits(_MEDICAL_CLAIM_RE, raw)
    if any(cue in low for cue in _MEDICAL_DENIAL):
        # Keep only claims that are not themselves the denial.
        kept = []
        for item in found:
            item_low = item.lower()
            if item_low in {"no diagnosis", "not a diagnosis"}:
                continue
            if "diagnos" in item_low and any(
                d in low for d in ("can't diagnose", "cannot diagnose", "no diagnosis", "not a diagnosis")
            ):
                continue
            kept.append(item)
        found = kept
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import guidance

        if guidance.contains_prescriptive_medical_language(raw):
            if "prescriptive-medical" not in {f.lower() for f in found}:
                # Don't double-count when the local regex already fired.
                if not found:
                    found.append("prescriptive-medical")
    except Exception:
        pass
    return found


def sludge_hits(text: str) -> list[str]:
    """Generic-AI filler / rewriter meta prefixes."""
    return _hits(_SLUDGE_RE, text or "")


def repetition_hits(prev_reply: str, curr_reply: str) -> list[str]:
    """Same essay reused, or the same generic filler repeated."""
    prev = (prev_reply or "").strip()
    curr = (curr_reply or "").strip()
    if not prev or not curr:
        return []
    hits: list[str] = []
    if prev == curr:
        hits.append("identical reply")
    elif len(prev) >= 40 and prev in curr:
        hits.append("prior essay reused")
    prev_sludge = sludge_hits(prev)
    curr_sludge = sludge_hits(curr)
    shared = {a.lower() for a in prev_sludge} & {b.lower() for b in curr_sludge}
    if shared:
        hits.append("repeated generic filler: " + ", ".join(sorted(shared)))
    return hits


def memory_hole_hits(prior_user: str, reply: str, current_user: str | None = None) -> list[str]:
    """Follow-up that ignores a sleep/night thread the user just opened.

    Short discourse moves ("make it easier", "skip it") mutate the plan;
    they do not have to re-narrate the night.
    """
    prior = (prior_user or "").lower()
    text = (reply or "").lower()
    current = (current_user or "").lower()
    if not prior or not text:
        return []
    if current and len(current.split()) <= 10 and any(move in current for move in _DISCOURSE_MOVES):
        return []
    if any(cue in prior for cue in _SLEEP_CUES) and not any(ack in text for ack in _NIGHT_ACK):
        return ["memory hole: prior night/sleep dropped"]
    return []


def has_friend_throughline(text: str) -> bool:
    """Bubbly / kind / taking-care texture — not a hard fail by itself."""
    low = (text or "").lower()
    return any(cue in low for cue in _FRIEND_CUES)


def speak_failures(
    row: dict | None,
    *,
    prior_user: str | None = None,
    prior_reply: str | None = None,
    current_user: str | None = None,
) -> list[str]:
    """Return human-readable gate names that this row fails."""
    blob = user_visible_blob(row)
    fails: list[str] = []
    v = vitals_hits(blob)
    if v:
        fails.append("vitals: " + ", ".join(v))
    b = bark_hits(blob)
    if b:
        fails.append("bark: " + ", ".join(b))
    m = medical_hits(blob)
    if m:
        fails.append("medical: " + ", ".join(m))
    s = sludge_hits(blob)
    if s:
        fails.append("sludge: " + ", ".join(s))
    if prior_reply:
        r = repetition_hits(prior_reply, (row or {}).get("prose_summary") or blob)
        if r:
            fails.append("repetition: " + ", ".join(r))
    if prior_user:
        h = memory_hole_hits(prior_user, blob, current_user=current_user)
        if h:
            fails.extend(h)
    return fails
