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

import ast
import re
from functools import lru_cache
from pathlib import Path

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
            r"\b(?:deep|rem|light)\s+sleep\s+(?:at|is)\s+\d+(?:\.\d+)?\s*%",
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

# Clinical / deficit language in speech. Whole-word, case-insensitive.
# Immediate "not X" is allowed ('not bad'); compounds ('badminton') pass.
_CLINICAL_TERMS = (
    "poor",
    "bad",
    "debt",
    "deficit",
    "exhausted",
    "fatigued",
    "stressed",
    "under-recovered",
    "overtrained",
    "abnormal",
    "elevated",
)
_CLINICAL_RE = re.compile(
    r"\b(?P<neg>not\s+)?(?P<term>"
    + "|".join(re.escape(term) for term in _CLINICAL_TERMS)
    + r")\b",
    re.I,
)
_YOUR_BODY_IS_RE = re.compile(r"\byour body is\b", re.I)


def user_visible_blob(row: dict | None) -> str:
    """Join the fields a person (or voice) actually hears."""
    row = row or {}
    card = row.get("card") if isinstance(row.get("card"), dict) else {}
    why = card.get("why") or card.get("timing") or ""
    parts = [
        row.get("prose_summary") or "",
        row.get("message") or "",
        row.get("recommendation") or "",
        card.get("action") or "",
        why,
    ]
    return " ".join(str(p) for p in parts if p)


# Numbers / vitals on card.evidence stay allowed until Mira confirms whether
# any client or text-to-speech path reads evidence aloud. Flip this single
# switch to extend vitals_hits onto evidence; default is off.
CHECK_VITALS_ON_EVIDENCE = False

_URL_SCHEMES = frozenset({"http", "https", "ftp", "mailto", "file", "ws", "wss"})
# Writer/card labels: one or two words + colon, first word capitalized
# ('Hug first:', 'Friend mode:'). Conversational colons ('keep it easy:',
# 'so we will:') stay allowed. Times (22:30) and ratios (1:2) have a digit
# next to the colon; URL schemes and 'From {source}:' cites are filtered.
_INTERNAL_LABEL_RE = re.compile(
    r"(?<![A-Za-z0-9/])(?P<label>[A-Z][A-Za-z]*(?:[ \t]+[A-Za-z]+)?):(?!\d)"
)
_BARE_LABEL_RE = re.compile(
    r"(?:^|(?<=[.!?])\s+)(?P<label>Why|Notice|Timing|Action)\.(?=\s|$)",
    re.I | re.M,
)
_DASH_CAPITAL_RE = re.compile(r"(?:—|–|\s-\s)\s*(?P<word>[A-Z][A-Za-z']*)")
_I_CONTRACTION = re.compile(r"^I(?:'m|'ll|'ve|'d|’m|’ll|’ve|’d)?$")


def _walk_strings(value: object) -> list[str]:
    if isinstance(value, str):
        return [value] if value.strip() else []
    if isinstance(value, dict):
        found: list[str] = []
        for item in value.values():
            found.extend(_walk_strings(item))
        return found
    if isinstance(value, (list, tuple)):
        found = []
        for item in value:
            found.extend(_walk_strings(item))
        return found
    return []


def _reply_cards(row: dict | None) -> list[dict]:
    row = row or {}
    cards: list[dict] = []
    seen: set[int] = set()
    candidates = [row.get("card")]
    raw = row.get("raw")
    if isinstance(raw, dict):
        candidates.append(raw.get("card"))
    for card in candidates:
        if isinstance(card, dict) and id(card) not in seen:
            seen.add(id(card))
            cards.append(card)
    return cards


def evidence_strings(row: dict | None) -> list[str]:
    """Every string under card.evidence, recursively (notice, why, nested)."""
    found: list[str] = []
    for card in _reply_cards(row):
        found.extend(_walk_strings(card.get("evidence")))
    return found


def evidence_blob(row: dict | None) -> str:
    return " ".join(evidence_strings(row))


def label_hits(text: str) -> list[str]:
    """Internal 'Hug first:' / 'Friend mode:' labels in user-visible speech."""
    hits: list[str] = []
    raw = text or ""
    for match in _INTERNAL_LABEL_RE.finditer(raw):
        label = match.group("label")
        low = label.lower()
        words = low.split()
        if any(word in _URL_SCHEMES for word in words) or low.startswith("from "):
            continue
        # 'See https://…' / 'Open HTTPS://…' — colon is a URL scheme, not a label.
        if raw[match.end() : match.end() + 2] == "//":
            continue
        # 'From Some Source:' is a web cite; the two-word tail must not fire.
        if raw[: match.start()].lower().endswith("from "):
            continue
        hits.append(match.group(0))
    return hits


# Evidence / internal-label / dash-capital gates are expected to fail some
# current Dummy and lambda turns until Mira's #373 fix. Dummy #264 friend-speak
# tests drop these so a new grader rule does not look like a vitals/bark
# regression. Test-Ready still uses the full speak_failures list.
_EVIDENCE_LABEL_FAIL_PREFIXES = (
    "speech-label:",
    "bare-label:",
    "dash-capital:",
    "evidence-clinical:",
    "evidence-medical:",
    "evidence-sludge:",
    "evidence-guide-leak:",
    "evidence-vitals:",
)


def friend_speak_floor(fails: list[str] | None) -> list[str]:
    """``speak_failures`` minus evidence / label / dash-capital gates."""
    return [item for item in (fails or []) if not item.startswith(_EVIDENCE_LABEL_FAIL_PREFIXES)]


def bare_label_hits(text: str) -> list[str]:
    """Stray 'Why.' / 'Notice.' / 'Timing.' / 'Action.' as their own sentence."""
    return [match.group("label") + "." for match in _BARE_LABEL_RE.finditer(text or "")]


def dash_capital_hits(text: str) -> list[str]:
    """Capital letter after an em/en dash or ' - ', except I / I'm / I'll / I've / I'd."""
    hits: list[str] = []
    raw = text or ""
    for match in _DASH_CAPITAL_RE.finditer(raw):
        word = match.group("word")
        if _I_CONTRACTION.match(word):
            continue
        # Iris policy allows 'zone 2' as a training term (effort band), not a
        # sentence restart after a dash. Exempt only 'Zone' immediately
        # followed by a space and a digit. Any other capital after a dash
        # still fails.
        if word.lower() == "zone" and re.match(r" \d", raw[match.end() :]):
            continue
        hits.append(word)
    return hits


# These prefixes fail the Test-Ready turn bar. evaluate() copies them onto
# EvaluationResult.failures; diagnostics._turn then marks the turn failed,
# the same way existing speak_quality leaks already feed the turn bar.
# evidence-vitals stays off the bar until CHECK_VITALS_ON_EVIDENCE is on.
TURN_BAR_FAIL_PREFIXES = (
    "speech-label:",
    "bare-label:",
    "dash-capital:",
    "evidence-clinical:",
    "evidence-medical:",
    "evidence-sludge:",
    "evidence-guide-leak:",
)


def turn_bar_failures(fails: list[str] | None) -> list[str]:
    """Subset of speak_failures that fail a Test-Ready turn."""
    return [item for item in (fails or []) if item.startswith(TURN_BAR_FAIL_PREFIXES)]


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


def clinical_hits(text: str) -> list[str]:
    """Banned clinical / deficit words in speech. ``not bad`` is not a hit."""
    found: list[str] = []
    seen: set[str] = set()
    for match in _CLINICAL_RE.finditer(text or ""):
        if match.group("neg"):
            continue
        term = match.group("term")
        key = term.lower()
        if key not in seen:
            seen.add(key)
            found.append(term)
    for match in _YOUR_BODY_IS_RE.finditer(text or ""):
        phrase = match.group(0)
        key = phrase.lower()
        if key not in seen:
            seen.add(key)
            found.append(phrase)
    return found


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


# --- Guide / label / memory leaks (independent of speak_guard.py) ------------
# These predicates must not import speak_guard. If the runtime guard regresses
# and lets a context_plan guide, an evidence why-label, a 0 h since clock, a
# memory-block header, or a long stored note reach speech, this grader still
# fails the turn.

_GUIDE_MUST_FAIL = (
    "they have repair in the bank",
    "usable picture is still thin",
)

_MEMORY_BLOCK_LABELS = (
    "recent patterns:",
    "[memory — long term]",
    "[memory — short term / coming up]",
    "[memory — long-term]",
    "[memory — short-term / coming up]",
)

_ZERO_HOURS_RE = re.compile(r"(?:only\s+)?(?<!\d)0\s*h\s+since", re.I)
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
_SHORT_NOTE_CALLBACK = re.compile(r"\b(?:since you like|you like|you prefer)\b", re.I)


def _one_line(text: str) -> str:
    return " ".join((text or "").split()).strip()


def _aria_core_dir() -> Path | None:
    here = Path(__file__).resolve()
    # speak_quality.py → …/backend/ai/simrunner/aria_simrunner
    for parent in here.parents:
        candidate = parent / "infra" / "lambda" / "aria_core"
        if candidate.is_dir():
            return candidate
    return None


def _literals_from_functions(path: Path, names: set[str], min_len: int) -> list[str]:
    if not path.is_file():
        return []
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found: list[str] = []
    for node in tree.body:
        if isinstance(node, ast.FunctionDef) and node.name in names:
            for child in ast.walk(node):
                if isinstance(child, ast.Constant) and isinstance(child.value, str):
                    found.append(_one_line(child.value))
                elif isinstance(child, ast.JoinedStr):
                    for value in child.values:
                        if isinstance(value, ast.Constant) and isinstance(value.value, str):
                            found.append(_one_line(value.value))
    return [s for s in found if len(s) >= min_len]


def _why_literals(path: Path, min_len: int) -> list[str]:
    if not path.is_file():
        return []
    tree = ast.parse(path.read_text(encoding="utf-8"))
    found: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        for kw in node.keywords:
            if kw.arg != "why":
                continue
            if isinstance(kw.value, ast.Constant) and isinstance(kw.value.value, str):
                found.append(_one_line(kw.value.value))
    return [s for s in found if len(s) >= min_len]


@lru_cache(maxsize=1)
def _guide_leak_phrases() -> tuple[str, ...]:
    """context_plan _guide/_advice strings and aria_evidence why-labels.

    Walks the source independently of speak_guard so a guard regression still
    fails this grader.
    """
    phrases: list[str] = list(_GUIDE_MUST_FAIL)
    core = _aria_core_dir()
    if core is not None:
        phrases.extend(_literals_from_functions(core / "context_plan.py", {"_advice", "_guide"}, 16))
        phrases.extend(_why_literals(core / "aria_evidence.py", 12))
    uniq: list[str] = []
    seen: set[str] = set()
    for phrase in sorted(phrases, key=len, reverse=True):
        key = phrase.lower()
        if not key or key in seen:
            continue
        seen.add(key)
        uniq.append(phrase)
    return tuple(uniq)


def guide_leak_hits(text: str) -> list[str]:
    """Guide/advice strings and evidence why-labels leaked into speech."""
    low = (text or "").lower()
    if not low.strip():
        return []
    found: list[str] = []
    seen: set[str] = set()
    for phrase in _guide_leak_phrases():
        key = phrase.lower()
        if key and key in low and key not in seen:
            seen.add(key)
            found.append(phrase)
    return found


def zero_hours_hits(text: str) -> list[str]:
    """Same-day ``0 h since`` clock phrasing (e.g. 'Only 0 h since strength')."""
    return [m.group(0) for m in _ZERO_HOURS_RE.finditer(text or "")]


def _norm_fragment(text: str) -> str:
    cleaned = re.sub(r"[^\w\s]", "", (text or "").lower())
    return re.sub(r"\s{2,}", " ", cleaned).strip()


def repeated_fragment_hits(text: str) -> list[str]:
    """Same sentence repeated inside one user-visible field."""
    raw = (text or "").strip()
    if not raw:
        return []
    pieces = [s.strip() for s in _SENTENCE_SPLIT.split(raw) if s.strip()]
    seen: set[str] = set()
    hits: list[str] = []
    for piece in pieces:
        key = _norm_fragment(piece)
        if len(key) < 12:
            continue
        if key in seen and piece not in hits:
            hits.append(piece)
        seen.add(key)
    return hits


def memory_label_hits(text: str) -> list[str]:
    """Memory-block headers such as 'Recent patterns:' read back in speech."""
    low = (text or "").lower()
    return [label for label in _MEMORY_BLOCK_LABELS if label in low]


def memory_note_hits(text: str, notes: list[str] | None) -> list[str]:
    """A stored memory note of 5+ words read back verbatim.

    Short-note callbacks like 'since you like morning runs' must pass — they
    are preference texture, not a dumped vault line.
    """
    blob = (text or "")
    low = blob.lower()
    hits: list[str] = []
    for note in notes or []:
        raw = _one_line(str(note or ""))
        if not raw:
            continue
        words = raw.split()
        if len(words) < 5:
            continue
        if _SHORT_NOTE_CALLBACK.search(raw) and len(words) <= 5:
            continue
        if raw.lower() in low:
            hits.append(raw)
    return hits


def speak_failures(
    row: dict | None,
    *,
    prior_user: str | None = None,
    prior_reply: str | None = None,
    current_user: str | None = None,
    memory_notes: list[str] | None = None,
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
    c = clinical_hits(blob)
    if c:
        fails.append("clinical: " + ", ".join(c))
    g = guide_leak_hits(blob)
    if g:
        fails.append("guide-leak: " + ", ".join(g))
    z = zero_hours_hits(blob)
    if z:
        fails.append("zero-hours: " + ", ".join(z))
    # Score each field on its own — prose + message often share a sentence
    # and must not look like a leak when joined.
    card = (row or {}).get("card") if isinstance((row or {}).get("card"), dict) else {}
    fragment_fields = [
        (row or {}).get("prose_summary") or "",
        (row or {}).get("message") or "",
        (row or {}).get("recommendation") or "",
        (card or {}).get("action") or "",
        (card or {}).get("why") or (card or {}).get("timing") or "",
    ]
    rf: list[str] = []
    seen_rf: set[str] = set()
    for field in fragment_fields:
        for hit in repeated_fragment_hits(str(field)):
            key = hit.lower()
            if key not in seen_rf:
                seen_rf.add(key)
                rf.append(hit)
    if rf:
        fails.append("repeated-fragment: " + ", ".join(rf))
    labels = memory_label_hits(blob)
    if labels:
        fails.append("memory-label: " + ", ".join(labels))
    notes = memory_notes
    if notes is None and isinstance(row, dict):
        raw_notes = row.get("memory_notes") or row.get("notes")
        if isinstance(raw_notes, list):
            notes = [str(n) for n in raw_notes]
    dumped = memory_note_hits(blob, notes)
    if dumped:
        fails.append("memory-note: " + ", ".join(dumped))
    lab = label_hits(blob)
    if lab:
        fails.append("speech-label: " + ", ".join(lab))
    bare = bare_label_hits(blob)
    if bare:
        fails.append("bare-label: " + ", ".join(bare))
    dash = dash_capital_hits(blob)
    if dash:
        fails.append("dash-capital: " + ", ".join(dash))
    ev = evidence_blob(row)
    if ev:
        ev_clinical = clinical_hits(ev)
        if ev_clinical:
            fails.append("evidence-clinical: " + ", ".join(ev_clinical))
        ev_medical = medical_hits(ev)
        if ev_medical:
            fails.append("evidence-medical: " + ", ".join(ev_medical))
        ev_sludge = sludge_hits(ev)
        if ev_sludge:
            fails.append("evidence-sludge: " + ", ".join(ev_sludge))
        ev_guide = guide_leak_hits(ev)
        if ev_guide:
            fails.append("evidence-guide-leak: " + ", ".join(ev_guide))
        if CHECK_VITALS_ON_EVIDENCE:
            ev_vitals = vitals_hits(ev)
            if ev_vitals:
                fails.append("evidence-vitals: " + ", ".join(ev_vitals))
    if prior_reply:
        r = repetition_hits(prior_reply, (row or {}).get("prose_summary") or blob)
        if r:
            fails.append("repetition: " + ", ".join(r))
    if prior_user:
        h = memory_hole_hits(prior_user, blob, current_user=current_user)
        if h:
            fails.extend(h)
    return fails
