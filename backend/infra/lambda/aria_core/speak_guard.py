"""Shared user-visible speak guard for Dummy/lambda and live Bedrock paths.

Strips model-instruction / guide text, internal evidence labels, memory-block
headers and verbatim stored notes, rewrites same-day ``0 h since`` phrasing,
and dedupes repeated sentences/clauses. When a strip would leave the reply
without a step, inserts one sized second-person friend step (preferring
``card.action`` / ``card.why`` when those are themselves clean).

Vitals scrub lives elsewhere (``_speak_without_vitals`` / ``_VITALS_SPEAK``).
This module does not treat sleep minutes/hours or ``zone 2`` as banned.
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
    r"(?:only\s+)?0\s*h\s+since(?:\s+(?P<label>[A-Za-z][\w\s-]{0,40}?))?"
    r"(?=\s*[—–.,;:]|$)",
    re.I,
)

_MULTI_SPACE = re.compile(r"\s{2,}")
_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
_CLAUSE_SPLIT = re.compile(r"(\s*[—–;]\s*)")


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


def guard_speak(
    text: str,
    *,
    card: dict[str, Any] | None = None,
    memory_notes: Iterable[str] | None = None,
    memory_block: str | None = None,
) -> str:
    """Return user-visible speak with guide/label/memory leaks removed."""
    raw = str(text or "")
    if not raw.strip():
        return raw
    notes = [str(n).strip() for n in (memory_notes or []) if str(n).strip()]
    if memory_block:
        notes.extend(_notes_from_memory_block(memory_block))
    cleaned = _rewrite_zero_hours(raw)
    cleaned = _strip_denied(cleaned, _deny_phrases())
    cleaned = _strip_memory(cleaned, notes)
    cleaned = _dedupe_fragments(cleaned)
    cleaned = _tidy(cleaned)
    if _lost_its_step(raw, cleaned):
        step = _sized_step(card)
        if step and step.lower() not in cleaned.lower():
            cleaned = f"{cleaned} {step}".strip() if cleaned else step
            cleaned = _tidy(cleaned)
    return cleaned


def guard_envelope(
    envelope: dict[str, Any],
    *,
    memory_notes: Iterable[str] | None = None,
    memory_block: str | None = None,
) -> dict[str, Any]:
    """Apply ``guard_speak`` to every user-visible field on a response envelope."""
    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else None
    notes = list(memory_notes or [])
    for key in ("prose_summary", "message", "recommendation"):
        if envelope.get(key):
            envelope[key] = guard_speak(
                str(envelope[key]),
                card=card,
                memory_notes=notes,
                memory_block=memory_block,
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


def _strip_memory(text: str, notes: list[str]) -> str:
    out = text
    for header in _MEMORY_HEADERS:
        out = re.sub(re.escape(header), "", out, flags=re.I)
    out = re.sub(
        r"(?m)^\s*[-*]?\s*(?:knows|goals|constraints|patterns|recently told them|"
        r"supervision plan|ask next):\s*",
        "",
        out,
        flags=re.I,
    )
    out = re.sub(r"\b(?:knows|goals|constraints|patterns|recently told them|supervision plan|ask next):\s*", "", out, flags=re.I)
    for note in notes:
        if len(note) < 8:
            continue
        if note.lower() in out.lower():
            out = re.sub(re.escape(note), "", out, flags=re.I)
    return out


def _notes_from_memory_block(block: str) -> list[str]:
    notes: list[str] = []
    for raw in str(block or "").splitlines():
        line = raw.strip().lstrip("-* ").strip()
        if not line or line.startswith("["):
            continue
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


def _sized_step(card: dict[str, Any] | None) -> str:
    denied = _deny_phrases()
    if isinstance(card, dict):
        for key in ("action", "why", "recommendation", "timing"):
            raw = str(card.get(key) or "").strip()
            if not raw:
                continue
            if any(p.lower() in raw.lower() for p in denied):
                continue
            if any(lab.lower() in raw.lower() for lab in ("usable picture", "still thin")):
                continue
            if any(cue in raw.lower() for cue in _STEP_CUES) or len(raw.split()) <= 16:
                return raw.rstrip(".")
    return _SIZED_FRIEND_STEP


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
