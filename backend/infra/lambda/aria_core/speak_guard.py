"""Shared user-visible speak guard for Dummy/lambda and live Bedrock paths.

Strips model-instruction / guide text, internal evidence labels, memory-block
headers and verbatim stored notes, rewrites same-day ``0 h since`` phrasing,
and dedupes repeated sentences/clauses. When a strip would leave the reply
without a step, inserts one sized second-person friend step (preferring
``card.action`` / ``card.why`` when those are themselves clean).

Vitals scrub lives in ``rescrub_speak`` (the engine ``_speak_without_vitals``
helper). An added step is memory-stripped and re-scrubbed so it cannot
reintroduce bpm / sleep-stage % or stored notes. Sleep minutes/hours and
``zone 2`` stay allowed.
"""

from __future__ import annotations

import ast
import re
from functools import lru_cache
from pathlib import Path
from typing import Any, Iterable

_SIZED_FRIEND_STEP = "20 easy minutes, then call it"

_MEMORY_HEADERS = (
    "Recent patterns:",
    "[MEMORY — long term]",
    "[MEMORY — short term / coming up]",
    "[MEMORY — long-term]",
    "[MEMORY — short-term / coming up]",
)

_MEMORY_LINE_LABELS = (
    "knows:",
    "goals:",
    "constraints:",
    "patterns:",
    "recently told them:",
    "supervision plan:",
    "ask next:",
)

_STEP_CUES = (
    "minute",
    "minutes",
    "session",
    "hold",
    "progress",
    "easy",
    "walk",
    "call it",
    "protect",
    "keep",
    "train",
    "lighter",
    "shorter",
    "block",
    "zone 2",
    "zone-2",
)

_RECOVERY_OPEN_RE = re.compile(
    r"recovery window is still open"
    r"|earlier today"
    r"|only\s+\d+\s*h\s+since"
    r"|\b0\s*h\s+since"
    r"|still carrying (?:the )?(?:last )?session",
    re.I,
)

_TRAIN_HARD_RE = re.compile(
    r"\btrain hard\b"
    r"|\bgo hard\b"
    r"|\bgo train hard\b"
    r"|\bhigh[- ]intensity\b"
    r"|\bpush for a pr\b"
    r"|\bheavy strength\b"
    r"|\bmax effort\b"
    r"|\bpush hard\b"
    r"|\bclear to push\b"
    r"|\bgreen light\b"
    r"|\bcrush(?:ing)? it\b",
    re.I,
)

_ZERO_HOURS_RE = re.compile(
    r"(?:only\s+)?0\s*h\s+since(?:\s+(?P<label>[A-Za-z][\w-]*))?",
    re.I,
)

_MULTI_SPACE = re.compile(r"\s{2,}")
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
_CLAUSE_SPLIT = re.compile(r"(\s*[—–;]\s*)")
# Structured-message headers that become "Why." / "Timing." when the body
# is stripped. Never leave a bare label in spoken text.
_SECTION_LABELS = (
    "What I notice",
    "One next step",
    "Why",
    "Timing",
    "Rationale",
    "Expected effect",
)
_BARE_LABEL = re.compile(
    r"(?i)(?:^|(?<=[.!?]\s))(?:"
    + "|".join(re.escape(label) for label in _SECTION_LABELS)
    + r")\s*\.(?=\s|$)"
)
_TRAILING_LABEL = re.compile(
    r"(?i)(?:^|[\s.])(?:"
    + "|".join(re.escape(label) for label in _SECTION_LABELS)
    + r")\s*[.:]?\s*$"
)


def user_visible(row: dict[str, Any] | None) -> str:
    """Join the fields a person (or voice) actually hears."""
    row = row or {}
    card = row.get("card") if isinstance(row.get("card"), dict) else {}
    parts = [
        row.get("prose_summary") or "",
        row.get("message") or "",
        row.get("recommendation") or "",
        card.get("action") or "",
        card.get("why") or "",
        card.get("timing") or "",
        card.get("rationale") or "",
        card.get("recommendation") or "",
    ]
    return " ".join(str(p) for p in parts if p)


def recommendation_from_card(card: Any, *, response_type: str | None = None) -> str | None:
    """Progress/summary cards store the step on ``recommendation``; others on ``action``."""
    if not isinstance(card, dict):
        return None
    raw = card.get("action") or card.get("recommendation")
    if raw is None:
        return None
    text = str(raw).strip()
    return text or None


def cap_contradiction_confidence(
    text: str,
    confidence: Any,
    *,
    hours_since: float | None = None,
) -> float:
    """Cap reported confidence below 0.9 when the reply contradicts itself.

    The concrete case: recovery window is still open (same-day / <24h session,
    or the reply says so) but the spoken advice tells the user to train hard.
    """
    try:
        value = float(confidence) if confidence is not None else 0.5
    except (TypeError, ValueError):
        value = 0.5
    value = max(0.0, min(1.0, value))
    if _contradicts_recovery_window(text, hours_since=hours_since) and value >= 0.9:
        return 0.89
    return value


def rescrub_speak(*candidates: str) -> str:
    """Re-run the engine vitals scrub. Shared by lambda/friend_speak and live.

    ``_speak_without_vitals`` is all-or-nothing: a candidate with bpm / sleep-stage
    % is skipped in favor of the next clean candidate. Empty input stays empty
    so a sleep/food reply that lost its step is not replaced with training copy.
    """
    nonempty = [c for c in candidates if str(c or "").strip()]
    if not nonempty:
        return candidates[0] if candidates else ""
    from .aria_engine import _speak_without_vitals

    return _speak_without_vitals(*nonempty)


def guard_speak(
    text: str,
    *,
    card: dict[str, Any] | None = None,
    memory_notes: Iterable[str] | None = None,
    memory_block: str | None = None,
    stance: str = "",
    topic: str = "",
) -> str:
    """Return user-visible speak with guide/label/memory leaks removed."""
    raw = str(text or "")
    if not raw.strip():
        return raw
    notes = [str(n).strip() for n in (memory_notes or []) if str(n).strip()]
    if memory_block:
        notes.extend(_notes_from_memory_block(memory_block))
    topic = _infer_topic(topic, card, stance, raw)
    cleaned = _rewrite_zero_hours(raw)
    cleaned = _strip_denied(cleaned, _deny_phrases())
    cleaned = _strip_memory(cleaned, notes, original=raw)
    cleaned = _strip_bare_labels(cleaned)
    cleaned = _dedupe_fragments(cleaned)
    cleaned = _strip_bare_labels(cleaned)
    cleaned = _tidy(cleaned)
    if _lost_its_step(raw, cleaned):
        step = _sized_step(card, stance=stance, topic=topic)
        if step and step.lower() not in cleaned.lower():
            cleaned = _append_guarded_step(cleaned, step, notes=notes, topic=topic)
    return cleaned


def guard_envelope(
    envelope: dict[str, Any],
    *,
    memory_notes: Iterable[str] | None = None,
    memory_block: str | None = None,
    topic: str = "",
) -> dict[str, Any]:
    """Apply ``guard_speak`` to every user-visible field on a response envelope."""
    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else None
    notes = list(memory_notes or [])
    fusion = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    stance = str(fusion.get("stance") or "")
    topic = topic or _infer_topic("", card, stance, user_visible(envelope))
    for key in ("prose_summary", "message", "recommendation"):
        if envelope.get(key):
            envelope[key] = guard_speak(
                str(envelope[key]),
                card=card,
                memory_notes=notes,
                memory_block=memory_block,
                stance=stance,
                topic=topic,
            )
    if isinstance(card, dict):
        guarded = dict(card)
        for key in ("action", "why", "rationale", "timing", "recommendation", "interpretation"):
            if guarded.get(key):
                guarded[key] = guard_speak(
                    str(guarded[key]),
                    card=card,
                    memory_notes=notes,
                    memory_block=memory_block,
                    stance=stance,
                    topic=topic,
                )
        envelope["card"] = guarded
    rec = envelope.get("recommendation") or recommendation_from_card(
        envelope.get("card"), response_type=str(envelope.get("response_type") or "")
    )
    if rec:
        envelope["recommendation"] = rec
    blob = user_visible(envelope)
    envelope["confidence"] = cap_contradiction_confidence(
        blob,
        envelope.get("confidence"),
        hours_since=_hours_hint(envelope),
    )
    return envelope


def _hours_hint(envelope: dict[str, Any]) -> float | None:
    load = envelope.get("load")
    if isinstance(load, dict):
        raw = load.get("hours_since_last_workout") or load.get("hoursSinceLastWorkout")
        try:
            return float(raw) if raw is not None else None
        except (TypeError, ValueError):
            return None
    return None


def _contradicts_recovery_window(text: str, *, hours_since: float | None = None) -> bool:
    blob = text or ""
    window_open = bool(_RECOVERY_OPEN_RE.search(blob))
    if hours_since is not None:
        try:
            window_open = window_open or float(hours_since) < 24.0
        except (TypeError, ValueError):
            pass
    return window_open and bool(_TRAIN_HARD_RE.search(blob))


def _rewrite_zero_hours(text: str) -> str:
    def _repl(match: re.Match[str]) -> str:
        label = (match.group("label") or "").strip()
        return f"{label} earlier today" if label else "earlier today"

    return _ZERO_HOURS_RE.sub(_repl, text)


def _strip_denied(text: str, phrases: tuple[str, ...]) -> str:
    out = text
    lower = out.lower()
    for phrase in phrases:
        needle = phrase.lower()
        if needle not in lower:
            continue
        pattern = re.compile(re.escape(phrase), re.I)
        out = pattern.sub("", out)
        lower = out.lower()
    return out


def _word_count(text: str) -> int:
    return len([w for w in re.split(r"\s+", (text or "").strip()) if w])


def _appears_after_memory_label(text: str, note: str) -> bool:
    if not text or not note:
        return False
    labels = [re.escape(h) for h in _MEMORY_HEADERS]
    labels += [re.escape(lab) for lab in _MEMORY_LINE_LABELS]
    return bool(
        re.search(rf"(?:{'|'.join(labels)})\s*{re.escape(note)}", text, flags=re.I)
    )


def _note_is_readback(note: str, text: str) -> bool:
    """A stored note is a readback if it is ≥5 words or sits after a memory label."""
    if not note or not text or note.lower() not in text.lower():
        return False
    if _word_count(note) >= 5:
        return True
    return _appears_after_memory_label(text, note)


def _drop_sentences_containing(text: str, needle: str) -> str:
    parts = [s.strip() for s in _SENTENCE_SPLIT.split((text or "").strip()) if s.strip()]
    if not parts:
        return "" if needle.lower() in (text or "").lower() else text
    kept = [s for s in parts if needle.lower() not in s.lower()]
    return " ".join(kept)


def _strip_memory(text: str, notes: list[str], *, original: str | None = None) -> str:
    out = text
    source = original if original is not None else text
    for header in _MEMORY_HEADERS:
        out = re.sub(re.escape(header), "", out, flags=re.I)
    out = re.sub(
        r"(?m)^\s*[-*]?\s*(?:knows|goals|constraints|patterns|recently told them|"
        r"supervision plan|ask next):\s*",
        "",
        out,
        flags=re.I,
    )
    for note in notes:
        if not _note_is_readback(note, source) and not _note_is_readback(note, out):
            continue
        if note.lower() not in out.lower():
            continue
        out = _drop_sentences_containing(out, note)
    return out


def _notes_from_memory_block(block: str) -> list[str]:
    notes: list[str] = []
    for raw in str(block or "").splitlines():
        line = raw.strip().lstrip("-* ").strip()
        if not line or line.startswith("["):
            continue
        for header in _MEMORY_HEADERS:
            if line.lower().startswith(header.lower()):
                line = line[len(header):].strip()
                break
        for label in _MEMORY_LINE_LABELS:
            if line.lower().startswith(label):
                line = line[len(label):].strip()
                break
        if line:
            notes.append(line)
    return notes


def _lost_its_step(original: str, cleaned: str) -> bool:
    if not cleaned.strip():
        return True
    if any(cue in cleaned.lower() for cue in _STEP_CUES):
        return False
    # Guide/label suppression emptied the actionable half.
    denied = _deny_phrases()
    original_had_denied = any(p.lower() in original.lower() for p in denied)
    return original_had_denied


_GENERIC_STEPS = (
    "reassess after you recover",
    "fit the session around the day you already have",
    "fit training around the day you already have",
)


def _is_usable_step(raw: str, denied: tuple[str, ...]) -> bool:
    text = str(raw or "").strip()
    if not text:
        return False
    if text.lower().rstrip(".") in _GENERIC_STEPS:
        return False
    if any(p.lower() in text.lower() for p in denied):
        return False
    if any(lab in text.lower() for lab in ("usable picture", "still thin")):
        return False
    return True


_HARD_STEP_CUES = (
    "hard session",
    "green light",
    "high-intensity",
    "high intensity",
    "push for",
    "train hard",
    "go hard",
)

_STANCE_FRIEND_STEPS = {
    "protect": "Keep it shorter and lighter — 20 easy minutes, then call it",
    "proceed": "One quality session, then call it",
    "fuel": "Protein and water with the next meal, then keep the session easy",
    "clarify": "Tell me how you slept and I'll size today",
}

_PATTERN_FRIEND_STEPS = {
    "sleep_debt": "Protect sleep tonight — 20 easy minutes, then call it",
    "under_recovery": "Protect sleep tonight — 20 easy minutes, then call it",
    "low_readiness": "Keep today easy — 20 easy minutes, then call it",
    "overreaching": "Back the load off — 20 easy minutes, then call it",
}


def _action_fits_stance(raw: str, stance: str) -> bool:
    if (stance or "").lower() == "protect" and any(cue in raw.lower() for cue in _HARD_STEP_CUES):
        return False
    return True


_SLEEP_TOPIC_RE = re.compile(r"\b(sleep|slept|rem|bedtime|wind-down|bed)\b", re.I)
_FOOD_TOPIC_RE = re.compile(
    r"\b(food|eat|meal|protein|calorie|diet|hydrat|nutrition|macro)\b", re.I
)
_TRAIN_TOPIC_RE = re.compile(r"\b(train|workout|session|lift|run|load)\b", re.I)


def _infer_topic(topic: str, card: dict[str, Any] | None, stance: str, text: str) -> str:
    explicit = (topic or "").strip().lower()
    if explicit in {"training", "sleep", "food", "other"}:
        return explicit
    key = ""
    if isinstance(card, dict):
        ev = card.get("evidence") if isinstance(card.get("evidence"), dict) else {}
        key = str(ev.get("key") or "")
        card_topic = str(card.get("topic") or "").strip().lower()
        if card_topic in {"training", "sleep", "food", "other"}:
            return card_topic
    if key == "sleep_debt" or "sleep" in key:
        return "sleep"
    if key == "fuel_gap" or (stance or "").lower() == "fuel":
        return "food"
    blob = f"{key} {stance} {text}"
    if _FOOD_TOPIC_RE.search(blob):
        return "food"
    if _SLEEP_TOPIC_RE.search(blob) and not _TRAIN_TOPIC_RE.search(blob):
        return "sleep"
    if _TRAIN_TOPIC_RE.search(blob) or key in {
        "under_recovery",
        "low_readiness",
        "overreaching",
        "green_light",
    }:
        return "training"
    return explicit or "other"


def _is_training_topic(topic: str) -> bool:
    return (topic or "").lower() in {"training", "workout", "session", "progress", "activity"}


def _join_with_step(cleaned: str, step: str) -> str:
    """Join speak + step with a sentence boundary; the step always ends with '.'."""
    step = (step or "").strip()
    if step and step[-1] not in ".!?":
        step += "."
    cleaned = _TRAILING_LABEL.sub("", (cleaned or "")).rstrip(" \t,;:—–-.")
    cleaned = _strip_bare_labels(cleaned).rstrip()
    if not cleaned:
        return step
    if cleaned[-1] not in ".!?":
        return f"{cleaned}. {step}"
    return f"{cleaned} {step}"


def _strip_bare_labels(text: str) -> str:
    """Drop leftover section headers ('Why.', 'Timing.') after a body strip."""
    out = _BARE_LABEL.sub(" ", str(text or ""))
    out = _TRAILING_LABEL.sub("", out)
    return _MULTI_SPACE.sub(" ", out).strip()


def dedupe_envelope_speech(envelope: dict[str, Any]) -> dict[str, Any]:
    """A read sentence must not appear twice across prose + message."""
    prose = _dedupe_fragments(str(envelope.get("prose_summary") or ""))
    chat = str(envelope.get("message") or "")
    prose_keys = {
        _norm(part) for part in _SENTENCE_SPLIT.split(prose) if part.strip()
    }
    kept: list[str] = []
    for part in _SENTENCE_SPLIT.split(chat):
        sentence = part.strip()
        if not sentence:
            continue
        key = _norm(sentence)
        if key and key in prose_keys:
            continue
        kept.append(sentence)
    chat = _dedupe_fragments(" ".join(kept)) if kept else ""
    if prose:
        envelope["prose_summary"] = prose
    if "message" in envelope:
        envelope["message"] = chat or prose
    return envelope


def _has_banned_vitals(text: str) -> bool:
    from .aria_engine import _VITALS_SPEAK, _strip_sleep_stage_pct

    scrubbed = _strip_sleep_stage_pct(str(text or "").strip())
    return bool(scrubbed) and bool(_VITALS_SPEAK.search(scrubbed))


def _append_guarded_step(
    cleaned: str,
    step: str,
    *,
    notes: list[str],
    topic: str = "",
) -> str:
    """Memory-strip the added step, join it, then re-scrub vitals.

    Shared helper for the lambda/friend_speak path and the live path — both
    reach it through ``guard_speak`` after a sized step is spliced in.
    """
    step = _tidy(_strip_memory(str(step or ""), notes, original=step))
    if not step or _has_banned_vitals(step):
        step = _SIZED_FRIEND_STEP if _is_training_topic(topic) else ""
        if not step:
            return cleaned
    joined = _tidy(_join_with_step(cleaned, step))
    return rescrub_speak(joined, cleaned)


def _sized_step(card: dict[str, Any] | None, *, stance: str = "", topic: str = "") -> str:
    denied = _deny_phrases()
    evidence: dict[str, Any] = {}
    pattern = ""
    if isinstance(card, dict):
        evidence = card.get("evidence") if isinstance(card.get("evidence"), dict) else {}
        stance = stance or str(evidence.get("stance") or card.get("stance") or "")
        pattern = str(evidence.get("key") or "")
        topic = topic or _infer_topic(str(card.get("topic") or ""), card, stance, "")
        for key in ("action", "recommendation"):
            raw = str(card.get(key) or "").strip()
            if _is_usable_step(raw, denied) and _action_fits_stance(raw, stance):
                return raw.rstrip(".")
        for key in ("why", "timing"):
            raw = str(card.get(key) or "").strip()
            if (
                _is_usable_step(raw, denied)
                and any(cue in raw.lower() for cue in _STEP_CUES)
                and _action_fits_stance(raw, stance)
            ):
                return raw.rstrip(".")
        for action in evidence.get("actions") or ():
            raw = str(action or "").strip()
            if _is_usable_step(raw, denied) and _action_fits_stance(raw, stance):
                return raw.rstrip(".")
        next_step = str(evidence.get("next_step") or "").strip()
        if _is_usable_step(next_step, denied) and _action_fits_stance(next_step, stance):
            return next_step.rstrip(".")
    if pattern in _PATTERN_FRIEND_STEPS:
        return _PATTERN_FRIEND_STEPS[pattern]
    if stance in _STANCE_FRIEND_STEPS:
        return _STANCE_FRIEND_STEPS[stance]
    if _is_training_topic(topic):
        return _SIZED_FRIEND_STEP
    return ""


def _dedupe_fragments(text: str) -> str:
    sentences = [s.strip() for s in _SENTENCE_SPLIT.split(text.strip()) if s.strip()]
    if not sentences:
        return text
    seen: set[str] = set()
    kept: list[str] = []
    for sentence in sentences:
        clause = _dedupe_clauses(sentence)
        key = _norm(clause)
        if not key or key in seen:
            continue
        seen.add(key)
        kept.append(clause)
    return " ".join(kept)


def _dedupe_clauses(sentence: str) -> str:
    bits = _CLAUSE_SPLIT.split(sentence)
    if len(bits) == 1:
        return sentence
    seen: set[str] = set()
    out: list[str] = []
    pending_sep = ""
    for bit in bits:
        if _CLAUSE_SPLIT.fullmatch(bit):
            pending_sep = bit
            continue
        key = _norm(bit)
        if not key or key in seen:
            pending_sep = ""
            continue
        seen.add(key)
        if out and pending_sep:
            out.append(pending_sep)
        out.append(bit.strip())
        pending_sep = ""
    return "".join(out).strip()


def _norm(text: str) -> str:
    cleaned = re.sub(r"[^\w\s]", "", (text or "").lower())
    return _MULTI_SPACE.sub(" ", cleaned).strip()


def _tidy(text: str) -> str:
    cleaned = str(text or "")
    cleaned = re.sub(r"\s+([,.;:!?])", r"\1", cleaned)
    cleaned = re.sub(r"\(\s*\)", "", cleaned)
    cleaned = re.sub(r"\s*[—–-]\s*[—–-]\s*", " — ", cleaned)
    cleaned = re.sub(r"\s*[—–-]\s*$", "", cleaned)
    cleaned = re.sub(r"^\s*[—–-]\s*", "", cleaned)
    cleaned = _MULTI_SPACE.sub(" ", cleaned)
    cleaned = cleaned.strip(" ,;:—–-")
    if cleaned and cleaned[0].islower():
        cleaned = cleaned[0].upper() + cleaned[1:]
    return cleaned


@lru_cache(maxsize=1)
def _deny_phrases() -> tuple[str, ...]:
    here = Path(__file__).resolve().parent
    phrases: list[str] = []
    phrases.extend(_literals_from_functions(here / "context_plan.py", {"_advice", "_guide"}))
    phrases.extend(_why_literals(here / "aria_evidence.py"))
    # Longest first so a long guide swallows its shorter prefix.
    uniq: list[str] = []
    seen: set[str] = set()
    for phrase in sorted(phrases, key=len, reverse=True):
        key = phrase.lower()
        if key in seen or len(phrase) < 12:
            continue
        seen.add(key)
        uniq.append(phrase)
    return tuple(uniq)


def _literals_from_functions(path: Path, names: set[str]) -> list[str]:
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
    return [s for s in found if len(s) >= 16]


def _why_literals(path: Path) -> list[str]:
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
    return [s for s in found if len(s) >= 12]


def _one_line(text: str) -> str:
    return " ".join((text or "").split()).strip()
