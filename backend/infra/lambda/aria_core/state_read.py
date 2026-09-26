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
    "lighter night than your usual",
    "a shorter night than your usual",
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
# Single near-usual night — never "consistent" (that needs a multi-day streak).
AROUND_USUAL = (
    "right around your usual",
    "about your usual",
    "close to your usual",
)
CONSISTENT = (
    "you've been really consistent",
    "steadier than last week",
    "holding steady versus last week",
)

PHRASE_BANK: tuple[str, ...] = (
    SHORT_NIGHT
    + BETTER_NIGHT
    + BIGGER_LOAD
    + LIGHTER_LOAD
    + READY_DOWN
    + READY_UP
    + AROUND_USUAL
    + CONSISTENT
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

_USER_SLEEP_BAD = re.compile(
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
_USER_SLEEP_GOOD = re.compile(
    r"\b("
    r"i\s+slept\s+(?:great|well|amazing|awesome|solid|better|good)"
    r"|slept\s+(?:great|well|amazing|awesome|solid)"
    r"|great\s+night"
    r"|amazing\s+night"
    r"|solid\s+night"
    r"|good\s+night"
    r"|best\s+sleep"
    r"|slept\s+like\s+a\s+rock"
    r")\b",
    re.I,
)
_USER_TRAIN_BIG = re.compile(
    r"\b("
    r"(?:big|bigger|heavy|heavier|huge)\s+(?:training\s+)?week"
    r"|trained\s+a\s+lot"
    r")\b",
    re.I,
)
_USER_TRAIN_LIGHT = re.compile(
    r"\b("
    r"(?:light|lighter|easy|easier)\s+(?:training\s+)?week"
    r"|haven'?t\s+trained"
    r"|didn'?t\s+train"
    r")\b",
    re.I,
)
_EASY_STEP = re.compile(
    r"\b(easy|lighter|shorter|call it|protect|gentle|wind-down|wind down|recover)\b",
    re.I,
)
_PUSH_STEP = re.compile(
    r"\b(train hard|quality session|green light|push|hard session|go train|"
    r"high[- ]intensity)\b",
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
    kind, clause, direction = selected
    if _contradicts_user(message, kind, direction):
        return envelope
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
    # Keep a host notice that has no step of its own (e.g. "You're primed")
    # so the read+step cannot replace the line the person should hear.
    host = ""
    for candidate in (prose, chat):
        if (
            candidate
            and not _has_step(candidate)
            and candidate.lower() not in target.lower()
        ):
            host = candidate
            break
    if host:
        if host[-1] not in ".!?":
            host = f"{host}."
        target = f"{host} {target}"
    ack = _should_ack(message, kind, direction)
    clean_clause = speak_guard.rescrub_speak(clause)
    if not clean_clause or clean_clause != clause:
        return envelope
    updated = _join_read(target, clause, ack=ack, direction=direction)
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
    """Strip state-read clauses that came from ARIA's own reply.

    ``last_insights`` is ARIA-told (``routes/aria.py`` ``add_insight`` of the
    first ``prose_summary`` sentence). ``recentPatterns`` is user/client
    authored — no path writes ARIA's reply there, so leave it untouched.
    """
    if ctx is None:
        return ctx
    insights = getattr(ctx, "last_insights", None)
    if insights:
        filtered = reject_memory_items(list(insights), from_reply=True)
        if filtered != list(insights):
            try:
                ctx.last_insights = filtered
            except Exception:
                pass
    return ctx


def reject_memory_items(
    items: Iterable[str], *, from_reply: bool = False
) -> list[str]:
    """Keep user notes; strip a state-read clause out of ARIA-reply items."""
    kept: list[str] = []
    for raw in items:
        text = str(raw or "").strip()
        if not text:
            continue
        if not is_state_read_memory(text, from_reply=from_reply):
            kept.append(text)
            continue
        cleaned = strip_state_read_clause(text)
        if cleaned:
            kept.append(cleaned)
    return kept


def is_state_read_memory(text: str, *, from_reply: bool = False) -> bool:
    """True only for items that originated as ARIA's spoken reply.

    A user vault note that exactly matches a phrase (``lighter week than
    usual``) is not ARIA memory. ``from_reply=True`` is last_insights —
    the add_insight takeaway path. Without that flag, only a joined or
    yeah-ack sentence (substring, not exact-phrase-only) counts.
    """
    raw = (text or "").strip()
    if not raw:
        return False
    if from_reply:
        return _clause_in_text(raw) is not None
    return _looks_like_reply_read(raw)


def strip_state_read_clause(text: str) -> str:
    """Remove a phrase-bank clause from an ARIA-reply sentence; keep the rest."""
    raw = (text or "").strip()
    if not raw:
        return ""
    parts = [s.strip() for s in _SENTENCE_SPLIT.split(raw) if s.strip()]
    kept = [_strip_clause_from_sentence(part) for part in parts]
    return " ".join(part for part in kept if part)


def _clause_in_text(text: str) -> str | None:
    low = (text or "").strip().lower()
    if not low:
        return None
    for phrase in _PHRASES_LONGEST:
        if phrase in low:
            return phrase
    return None


def _looks_like_reply_read(text: str) -> bool:
    """Joined ``{read}, so {step}`` / ``Yeah, {read}`` — not a bare phrase."""
    low = (text or "").strip().lower()
    if not low:
        return False
    if low.startswith("yeah,") or low.startswith("yeah "):
        return _clause_in_text(low) is not None
    if _clause_in_text(low) is None:
        return False
    leftover = _strip_clause_from_sentence(text)
    return bool(leftover)


def _strip_clause_from_sentence(sent: str) -> str:
    phrase = _clause_in_text(sent)
    if not phrase:
        return (sent or "").strip()
    leftover = re.sub(
        rf"(?:yeah,\s+|yeah\s+)?{re.escape(phrase)}",
        "",
        sent,
        count=1,
        flags=re.I,
    )
    leftover = re.sub(r"^\s*,\s*so\s+", "", leftover, flags=re.I)
    leftover = re.sub(r"^\s*so\s+", "", leftover, flags=re.I)
    leftover = re.sub(r"^\s*still,\s+", "", leftover, flags=re.I)
    leftover = leftover.strip(" \t,;—!.")
    if not leftover:
        return ""
    return _sentence_case(leftover)


def _select(ctx: Any, seed: int) -> tuple[str, str, str] | None:
    if ctx is None:
        return None
    sleep = _sleep_signal(ctx)
    train = _train_signal(ctx)
    ready = _ready_signal(ctx)
    if sleep == "short":
        return "sleep", _pick(seed, SHORT_NIGHT), "short"
    if sleep == "better":
        return "sleep", _pick(seed, BETTER_NIGHT), "better"
    if train == "bigger":
        return "training", _pick(seed, BIGGER_LOAD), "bigger"
    if train == "lighter":
        return "training", _pick(seed, LIGHTER_LOAD), "lighter"
    if ready == "down":
        return "readiness", _pick(seed, READY_DOWN), "down"
    if ready == "up":
        return "readiness", _pick(seed, READY_UP), "up"
    if train == "steady":
        return "steady", _pick(seed, CONSISTENT), "steady"
    # A single near-usual night is not a streak.
    if sleep == "usual":
        if _has_multiday_streak(ctx, train=train):
            return "steady", _pick(seed, CONSISTENT), "steady"
        return "sleep", _pick(seed, AROUND_USUAL), "usual"
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
    if any(cue in low for cue in speak_guard._STEP_CUES):
        return True
    # Neutral sizing asks (no easy/push cue) are still a next step.
    return "sync healthkit" in low or "size today" in low


_READ_ALIASES = (
    "personal short night",
    "short for you",
    "around your usual",
    "below your usual",
    "a short night",
)


def _already_has_read(text: str) -> bool:
    low = (text or "").lower()
    if any(phrase in low for phrase in _PHRASE_SET):
        return True
    return any(alias in low for alias in _READ_ALIASES)


def _user_sleep_dir(message: str) -> str | None:
    text = message or ""
    if _USER_SLEEP_BAD.search(text):
        return "bad"
    if _USER_SLEEP_GOOD.search(text):
        return "good"
    return None


def _user_train_dir(message: str) -> str | None:
    text = message or ""
    if _USER_TRAIN_BIG.search(text):
        return "bigger"
    if _USER_TRAIN_LIGHT.search(text):
        return "lighter"
    return None


def _contradicts_user(message: str, kind: str, direction: str) -> bool:
    """Skip when the user's words point the opposite way from the data."""
    if kind == "sleep":
        claimed = _user_sleep_dir(message)
        if claimed == "bad" and direction == "better":
            return True
        if claimed == "good" and direction == "short":
            return True
        return False
    if kind == "training":
        claimed = _user_train_dir(message)
        if claimed == "bigger" and direction == "lighter":
            return True
        if claimed == "lighter" and direction == "bigger":
            return True
        return False
    return False


def _should_ack(message: str, kind: str, direction: str = "") -> bool:
    if kind == "sleep":
        claimed = _user_sleep_dir(message)
        if claimed == "bad" and direction == "short":
            return True
        if claimed == "good" and direction == "better":
            return True
        return False
    if kind == "training":
        claimed = _user_train_dir(message)
        return bool(claimed) and claimed == direction
    return False


def _read_polarity(direction: str) -> str:
    if direction in {"short", "down", "lighter"}:
        return "easy"
    if direction in {"better", "up", "bigger"}:
        return "push"
    return "neutral"


def _step_polarity(text: str) -> str:
    if _EASY_STEP.search(text or ""):
        return "easy"
    if _PUSH_STEP.search(text or ""):
        return "push"
    return "neutral"


def _aligned(direction: str, step_text: str) -> bool:
    read_way = _read_polarity(direction)
    step_way = _step_polarity(step_text)
    return read_way != "neutral" and read_way == step_way


def _opposite(direction: str, step_text: str) -> bool:
    read_way = _read_polarity(direction)
    step_way = _step_polarity(step_text)
    return (
        read_way != "neutral"
        and step_way != "neutral"
        and read_way != step_way
    )


def _has_multiday_streak(ctx: Any, *, train: str | None = None) -> bool:
    """True only with a real multi-day pattern, not one near-usual night."""
    if train == "steady":
        return True
    progress = getattr(ctx, "progress", None)
    workouts = _int(getattr(progress, "workouts_completed_30d", None)) if progress else None
    return workouts is not None and workouts >= 7


def _sentence_case(text: str) -> str:
    if not text:
        return text
    if text[0].islower():
        return text[0].upper() + text[1:]
    return text


def _join_read(speech: str, clause: str, *, ack: bool, direction: str = "") -> str:
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
        if _aligned(direction, sentence):
            rest = _de_sentence_case(sentence)
            parts[i] = f"{lead}, so {rest}"
        elif _opposite(direction, sentence):
            # Only 'Still,' when read and step point opposite ways.
            parts[i] = f"{lead}. Still, {_de_sentence_case(sentence)}"
        else:
            parts[i] = f"{lead}. {_sentence_case(sentence)}"
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
_PHRASES_LONGEST = tuple(sorted(_PHRASE_SET, key=len, reverse=True))
_assert_bank_clean()
