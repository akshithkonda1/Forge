"""One plain-language read of the user's state, against their own baseline.

Inputs are health-baseline fields only: last night vs the user's 7-day usual
sleep, training-load trend, and readiness direction. Lifestyle patterns,
persona, memory blocks, vault notes, partner/cycle, and calendar titles are
never read. Remember-me / memory-off still works.

The clause is seed-indexed so back-to-back turns do not repeat wording, and
the same seed always yields the same wording (SimRunner replay).
"""

from __future__ import annotations

import re
import zlib
from typing import Any, Iterable

from . import speak_guard

# History depth before we will speak of *this person's* 7-day usual.
_MIN_USUAL_NIGHTS = 7
_MIN_HRV_DAYS = 7
_SLEEP_DELTA_MIN = 30.0  # minutes vs usual before we call it short/better
_HRV_DOWN = -8.0
_HRV_UP = 5.0

# Phrase bank. No digits, units, or clinical tokens. Positive reads included.
SHORT_NIGHT = (
    "short night",
    "a bit under your usual",
    "lighter night than your usual",
)
BETTER_NIGHT = (
    "better night than your usual",
    "more rest than your usual",
    "a fuller night than your usual",
)
BIGGER_LOAD = (
    "bigger training week than usual",
    "more training than last week",
    "heavier week than your usual",
)
LIGHTER_LOAD = (
    "lighter week than usual",
    "easier training week than usual",
    "a lighter week than your usual",
)
READY_DOWN = (
    "a bit under your usual",
    "not quite at your usual",
    "softer than last week",
)
READY_UP = (
    "steadier than last week",
    "you've been really consistent",
    "holding up better than last week",
)
CONSISTENT = (
    "you've been really consistent",
    "steadier than last week",
    "holding steady versus last week",
)

PHRASE_BANK: tuple[str, ...] = (
    SHORT_NIGHT + BETTER_NIGHT + BIGGER_LOAD + LIGHTER_LOAD + READY_DOWN + READY_UP + CONSISTENT
)

_BANNED_WORDS = (
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
    "hrv",
    "readiness",
    "acwr",
    "busier",
)

_USER_SLEEP_STATED = re.compile(
    r"\b("
    r"i\s+slept\s+(?:terribly|terrible|awful|badly|poorly|rough|little)"
    r"|slept\s+(?:terribly|terrible|awful|badly|poorly)"
    r"|rough\s+night"
    r"|didn'?t\s+sleep"
    r"|did\s+not\s+sleep"
    r"|couldn'?t\s+sleep"
    r"|could\s+not\s+sleep"
    r"|no\s+sleep"
    r"|terrible\s+night"
    r"|awful\s+night"
    r")\b",
    re.I,
)

_USER_TRAIN_STATED = re.compile(
    r"\b("
    r"(?:big|bigger|heavy|heavier|huge)\s+(?:training\s+)?week"
    r"|(?:light|lighter|easy|easier)\s+(?:training\s+)?week"
    r"|trained\s+a\s+lot"
    r"|haven'?t\s+trained"
    r"|didn'?t\s+train"
    r")\b",
    re.I,
)

_SENTENCE_SPLIT = re.compile(r"(?<=[.!?])\s+")
_DIGIT = re.compile(r"\d")


def phrase_bank() -> tuple[str, ...]:
    """All speakable clauses. Tests assert cleanliness against this set."""
    return PHRASE_BANK


def turn_seed(ctx: Any, message: str, seed: int | None = None) -> int:
    """Deterministic turn/user/day seed. Explicit seed wins for tests/replay."""
    if seed is not None:
        return int(seed) & 0xFFFFFFFF
    raw = f"{getattr(ctx, 'timestamp', '') or ''}|{message or ''}"
    return zlib.adler32(raw.encode("utf-8", "replace")) & 0xFFFFFFFF


def _state_read(ctx: Any, seed: int) -> str:
    """Return one short clause, or empty when there is no personal baseline."""
    selected = _select(ctx, seed)
    return selected[1] if selected else ""


def apply_to_envelope(
    envelope: dict[str, Any],
    ctx: Any,
    *,
    seed: int,
    message: str,
) -> dict[str, Any]:
    """Attach at most one state read, and only when the reply already has a step.

    Combined speech is re-scrubbed for vitals. Never writes ctx / memory.
    """
    selected = _select(ctx, seed)
    if not selected:
        return envelope
    kind, clause = selected
    prose = str(envelope.get("prose_summary") or "")
    chat = str(envelope.get("message") or "")
    if _already_has_read(prose) or _already_has_read(chat):
        return envelope
    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
    action = str(card.get("action") or card.get("recommendation") or "").strip()
    if _has_step(prose):
        target_key, target = "prose_summary", prose
    elif _has_step(chat):
        target_key, target = "message", chat
    elif action and _has_step(action):
        target_key, target = "prose_summary", action
    else:
        return envelope
    ack = _should_ack(message, kind)
    clean_clause = speak_guard.rescrub_speak(clause)
    if not clean_clause or clean_clause != clause:
        return envelope
    updated = _join_read(target, clause, ack=ack)
    if not updated or updated == target:
        return envelope
    # Host speech may already carry live-path numbers; never all-or-nothing
    # discard it. Only refuse the read if *we* introduced new vitals.
    if speak_guard._has_banned_vitals(updated) and not speak_guard._has_banned_vitals(target):
        return envelope
    updated = speak_guard._tidy(updated)
    envelope[target_key] = updated
    if target_key == "prose_summary" and chat == prose:
        envelope["message"] = updated
    return envelope


def drop_from_memory(ctx: Any) -> Any:
    """Strip phrase-bank clauses out of recentPatterns / insights if they landed."""
    if ctx is None:
        return ctx
    lifestyle = getattr(ctx, "lifestyle", None)
    if lifestyle is not None:
        patterns = list(getattr(lifestyle, "recent_patterns", None) or [])
        filtered = reject_memory_items(patterns)
        if filtered != patterns:
            try:
                lifestyle.recent_patterns = filtered
            except Exception:
                pass
    insights = getattr(ctx, "last_insights", None)
    if insights:
        filtered = reject_memory_items(list(insights))
        if filtered != list(insights):
            try:
                ctx.last_insights = filtered
            except Exception:
                pass
    return ctx


def reject_memory_items(items: Iterable[str]) -> list[str]:
    """Keep stored notes that are not a state-read clause (or a yeah-ack of one)."""
    kept: list[str] = []
    for raw in items:
        text = str(raw or "").strip()
        if text and not is_state_read_memory(text):
            kept.append(text)
    return kept


def is_state_read_memory(text: str) -> bool:
    low = (text or "").strip().lower().rstrip(".!")
    if not low:
        return False
    if low.startswith("yeah, "):
        low = low[6:].strip()
    elif low.startswith("yeah "):
        low = low[5:].strip()
    return low in _PHRASE_SET


def _select(ctx: Any, seed: int) -> tuple[str, str] | None:
    if ctx is None:
        return None
    sleep = _sleep_signal(ctx)
    train = _train_signal(ctx)
    ready = _ready_signal(ctx)
    if sleep == "short":
        return "sleep", _pick(seed, SHORT_NIGHT)
    if sleep == "better":
        return "sleep", _pick(seed, BETTER_NIGHT)
    if train == "bigger":
        return "training", _pick(seed, BIGGER_LOAD)
    if train == "lighter":
        return "training", _pick(seed, LIGHTER_LOAD)
    if ready == "down":
        return "readiness", _pick(seed, READY_DOWN)
    if ready == "up":
        return "readiness", _pick(seed, READY_UP)
    # Positive "around usual" only when last night was judged against a
    # 7-day sleep baseline. A lone "stable" trend is not enough data.
    if sleep == "usual":
        return "steady", _pick(seed, CONSISTENT)
    return None


def _sleep_signal(ctx: Any) -> str | None:
    sleep = getattr(ctx, "sleep", None)
    if sleep is None:
        return None
    night = _num(getattr(sleep, "duration_minutes", None))
    usual = _num(getattr(sleep, "baseline_median_minutes", None))
    nights = _int(getattr(sleep, "nights_available", None))
    if night is None or usual is None or usual <= 0:
        return None
    if nights is None or nights < _MIN_USUAL_NIGHTS:
        return None
    delta = night - usual
    if delta <= -_SLEEP_DELTA_MIN:
        return "short"
    if delta >= _SLEEP_DELTA_MIN:
        return "better"
    return "usual"


def _train_signal(ctx: Any) -> str | None:
    progress = getattr(ctx, "progress", None)
    training = getattr(ctx, "training", None)
    if progress is None:
        return None
    # A trend label without a load score is not a personal training baseline
    # (Dummy maps readiness_trend onto this field).
    if _num(getattr(training, "weekly_load_score", None)) is None:
        return None
    trend = str(getattr(progress, "training_load_trend", None) or "").strip().lower()
    if trend in {"rising", "up"}:
        return "bigger"
    if trend in {"falling", "down"}:
        return "lighter"
    if trend in {"steady", "stable"}:
        return "steady"
    return None


def _ready_signal(ctx: Any) -> str | None:
    readiness = getattr(ctx, "readiness", None)
    if readiness is None:
        return None
    trend = _num(getattr(readiness, "hrv_7day_trend", None))
    days = _int(getattr(readiness, "hrv_days_available", None))
    if trend is None or days is None or days < _MIN_HRV_DAYS:
        return None
    if trend <= _HRV_DOWN:
        return "down"
    if trend >= _HRV_UP:
        return "up"
    return "steady"


def _pick(seed: int, options: tuple[str, ...]) -> str:
    if not options:
        return ""
    return options[abs(int(seed)) % len(options)]


def _has_step(text: str) -> bool:
    low = (text or "").lower()
    return any(cue in low for cue in speak_guard._STEP_CUES)


def _already_has_read(text: str) -> bool:
    low = (text or "").lower()
    return any(phrase in low for phrase in _PHRASE_SET)


def _should_ack(message: str, kind: str) -> bool:
    if kind == "sleep" and _USER_SLEEP_STATED.search(message or ""):
        return True
    if kind == "training" and _USER_TRAIN_STATED.search(message or ""):
        return True
    return False


def _join_read(speech: str, clause: str, *, ack: bool) -> str:
    if not clause or not (speech or "").strip():
        return speech
    lead = f"yeah, {clause}" if ack else clause
    lead = lead[0].upper() + lead[1:] if lead else lead
    body = (speech or "").strip()
    parts = [s.strip() for s in _SENTENCE_SPLIT.split(body) if s.strip()]
    if not parts:
        return speech
    for i, sentence in enumerate(parts):
        if not _has_step(sentence):
            continue
        rest = _de_sentence_case(sentence)
        parts[i] = f"{lead}, so {rest}"
        return " ".join(parts)
    return speech


def _de_sentence_case(text: str) -> str:
    if not text:
        return text
    if text.startswith(("I ", "I'll ", "I'm ", "I've ", "I'd ")):
        return text
    if text[0].isupper():
        return text[0].lower() + text[1:]
    return text


def _num(value: Any) -> float | None:
    if isinstance(value, bool) or value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _int(value: Any) -> int | None:
    number = _num(value)
    if number is None:
        return None
    return int(number)


def _assert_bank_clean() -> None:
    """Dev-time check so a sloppy phrase cannot land in the bank."""
    for phrase in PHRASE_BANK:
        low = phrase.lower()
        if _DIGIT.search(phrase):
            raise ValueError(f"state-read phrase has a digit: {phrase!r}")
        if "your body is" in low:
            raise ValueError(f"state-read phrase explains physiology: {phrase!r}")
        for word in _BANNED_WORDS:
            if re.search(rf"\b{re.escape(word)}\b", low):
                raise ValueError(f"state-read phrase has banned word {word!r}: {phrase!r}")


_PHRASE_SET = frozenset(p.lower() for p in PHRASE_BANK)
_assert_bank_clean()
