"""Conversational overlay on top of ingest → personal model → stance.

Off-topic small talk gets a real, first-person reply in ARIA's voice. Coaching
and medical turns keep the engine envelope. Variation is seed-indexed via
``state_read.phrase_key`` / ``turn_seed`` — never ``random``.
"""

from __future__ import annotations

import re
from typing import Any

from backend._paths import ensure_lambda_on_path

ensure_lambda_on_path()

from aria_core import speak_guard  # noqa: E402
from aria_core import state_read  # noqa: E402
from services import guidance  # noqa: E402

_COACH_RE = re.compile(
    r"(?i)\b("
    r"how am i|overtrain|should i train|train today|workout|recover|"
    r"hrv|readiness|deload|what should i|sleep(?:ing|t)?|"
    r"progress|protein|sore|gym|lift|fuel|session|acwr|"
    r"should i (?:eat|run|rest|push)|am i over"
    r")\b"
)
_SMALL_TALK_RE = re.compile(
    r"(?i)^(?:hey+|hi+|hello+|yo|"
    r"how(?:'s| is) it going|"
    r"what'?s up|whats up|"
    r"how are you|"
    r"good (?:morning|afternoon|evening|night)|"
    r"thanks|thank you|"
    r"i'?m bored|im bored|"
    r"how was (?:your |the )?weekend|"
    r"nice (?:weather|to meet you)|"
    r"who are you|what are you|"
    r"how was your day|"
    r"lol|haha)[\s.!?]*$"
)
_SOCIAL_HINT = (
    "hey", "hello", "how's it going", "hows it going", "what's up", "whats up",
    "how are you", "bored", "weekend", "weather", "thanks", "thank you",
    "good morning", "good night", "nice to meet",
)
_DIGIT_UNIT = re.compile(
    r"(?i)\b\d+(?:\.\d+)?\s*(h|hr|hrs|hours?|min|minutes?|bpm|ms|mmhg|"
    r"kcal|cal|%|kg|lbs?)\b"
)
_BANNED_ENERGY = re.compile(
    r"(?i)\b(crush(?:ing)? it|beast mode|you got this|you've got this|"
    r"kill(?:ing)? it|go hard|push hard|green light)\b"
)

_GREET = (
    "Hey — I'm here. I don't need a training question to show up.",
    "Hi. I'm glad you pinged; I like hearing from you even when the day's quiet.",
    "I'm here. You don't have to perform a perfect check-in with me.",
    "Hey. I was already keeping you company — say whatever's actually on your mind.",
    "Hi. I'm your friend in this, not a scoreboard. What's landing for you?",
    "I'm with you. No agenda from me unless you want one.",
    "Hey — I noticed you reached out. That's enough of a reason to talk.",
    "Hi. I'll keep this human. What's the texture of the day over there?",
    "I'm here, and I'm not going to turn this into a briefing unless you ask.",
    "Hey. I can be witty later — first I just want to sit with you for a second.",
)
_WEEKEND = (
    "Weekends rewrite the clock for me too. I'm curious what yours actually felt like, not the highlight reel.",
    "I hope the weekend left you a little more yourself. I'm here if you want to unpack it or ignore it.",
    "Weekends are sneaky — they look empty and still spend you. I'm listening.",
    "I'm less interested in whether the weekend was 'productive' and more in whether you got any air.",
    "Tell me the honest weekend, not the one you'd post. I can hold either.",
)
_BORED = (
    "Boredom's a signal, not a character flaw. I'm here — we can wander or we can pick one small kindness.",
    "I'm not going to invent a montage because you're restless. Want company, or a tiny next step?",
    "Restless days are allowed. I can keep you company without turning it into a program.",
    "I'm with you in the dull stretch. Sometimes the kindest move is a walk and a real meal, not a new plan.",
)
_THANKS = (
    "You're welcome. I like being useful without making it a performance.",
    "Anytime. I'll still be here when the question is smaller than a training block.",
    "Glad it landed. I don't need a trophy for showing up.",
    "Of course. That's the job I actually want — a friend who notices.",
)
_WHO = (
    "I'm ARIA — a lifestyle friend in Forge, not a doctor. I notice your days and I talk like a person.",
    "I'm ARIA. I speak as I, I don't diagnose, and I won't bark you into a hero set.",
    "I'm your Forge companion. Witty when it helps, honest when it matters, never a clinician.",
    "I'm ARIA. I keep you company and I keep the medical line: lifestyle only.",
)
_GENERIC = (
    "I'm here. You can talk about the work or about the rest of your life — both count.",
    "I noticed you. That's the whole opening. What's actually going on?",
    "I'm listening. I won't turn every sentence into a plan.",
    "Say more if you want. I can hold a tangent without grading it.",
    "I'm with you. We can stay off the metrics and still be specific about your life.",
    "I like when you talk to me like a person. Keep going.",
)
_NOTICE = (
    "You look a bit spent to me, so I'm not going to pile on.",
    "The week's been loud on you — I'll keep my voice quiet.",
    "You seem a little more put together today. I'm still not going to rush you.",
    "I can feel the load sitting on you even without a recap.",
    "You read a little crispy around the edges. I'm taking care, not casting a montage.",
)


def _pick(seed: int, options: tuple[str, ...]) -> str:
    if not options:
        return ""
    return options[abs(int(seed)) % len(options)]


def is_small_talk(message: str) -> bool:
    """True for off-topic social chat. Coaching and medical stay on the engine."""
    text = (message or "").strip()
    if not text:
        return False
    if _COACH_RE.search(text):
        return False
    if _SMALL_TALK_RE.search(text):
        return True
    lower = text.lower()
    if len(text.split()) <= 10 and any(h in lower for h in _SOCIAL_HINT):
        return not _COACH_RE.search(text)
    return False


def _qualitative_notice(ctx: Any, seed: int) -> str:
    """One number-free life notice from the request context. Empty if nothing."""
    recovery = getattr(getattr(ctx, "readiness", None), "recovery_score", None)
    load = getattr(getattr(ctx, "training", None), "weekly_load_score", None)
    sleep_min = getattr(getattr(ctx, "sleep", None), "duration_minutes", None)
    if isinstance(recovery, (int, float)) and recovery < 55:
        return _pick(seed ^ 3, (
            "You look a bit spent to me, so I'm not going to pile on.",
            "I can feel the tired sitting on you. I'll keep this gentle.",
            "You read a little crispy. I'm taking care, not casting a montage.",
        ))
    if isinstance(load, (int, float)) and load >= 80:
        return _pick(seed ^ 5, (
            "The week's been loud on you — I'll keep my voice quiet.",
            "I notice the week has been asking a lot. We don't have to add more.",
        ))
    if isinstance(sleep_min, (int, float)) and sleep_min < 400:
        return _pick(seed ^ 7, (
            "Last night ran light. I'm not going to pretend that didn't happen.",
            "You feel a little short on rest to me. I'm here anyway.",
        ))
    clause = ""
    try:
        clause = state_read._state_read(ctx, seed)
    except Exception:
        clause = ""
    if clause and not re.search(r"\d", clause):
        return f"I notice a {clause} — I'm still here as a friend, not a dashboard."
    if isinstance(recovery, (int, float)) and recovery >= 75:
        return _pick(seed ^ 9, (
            "You seem a little more put together today. I'm still not going to rush you.",
            "There's a bit more sparkle on you today. I'll keep it kind anyway.",
        ))
    return _pick(seed ^ 11, _NOTICE) if abs(seed) % 4 == 0 else ""


def _bank_for(message: str) -> tuple[str, ...]:
    lower = (message or "").lower()
    if any(w in lower for w in ("weekend",)):
        return _WEEKEND
    if any(w in lower for w in ("bored",)):
        return _BORED
    if any(w in lower for w in ("thank",)):
        return _THANKS
    if any(w in lower for w in ("who are you", "what are you")):
        return _WHO
    if _SMALL_TALK_RE.search((message or "").strip()):
        return _GREET
    return _GENERIC


def _callback(prior: list[str], seed: int) -> str:
    if not prior:
        return ""
    last = (prior[-1] or "").strip()
    if not last:
        return ""
    snippet = [
        w for w in last.replace("?", "").split()
        if w.lower() not in {"i", "a", "the", "to", "and", "you"}
    ][:3]
    if not snippet:
        return _pick(seed ^ 13, ("Yeah — ", "Okay — ", "Still with you — "))
    bit = " ".join(snippet)
    return _pick(seed ^ 13, (
        f"Yeah — about “{bit}” — ",
        f"Still with you on “{bit}” — ",
        f"Okay, on “{bit}” — ",
    ))


def compose_small_talk(
    message: str,
    ctx: Any,
    *,
    seed: int,
    prior: list[str] | None = None,
) -> str:
    """Warm, first-person, number-free small talk. Deterministic per seed."""
    opener = _callback(list(prior or []), seed)
    body = _pick(seed, _bank_for(message))
    notice = _qualitative_notice(ctx, seed)
    parts = [opener + body if opener else body]
    if notice and notice.lower() not in parts[0].lower():
        parts.append(notice)
    spoken = " ".join(p.strip() for p in parts if p and p.strip())
    spoken = _BANNED_ENERGY.sub("that's real work", spoken)
    spoken = _DIGIT_UNIT.sub("", spoken)
    spoken = re.sub(r"\s{2,}", " ", spoken).strip()
    if spoken and spoken[-1] not in ".!?":
        spoken += "."
    return spoken


def apply_conversation(
    envelope: dict[str, Any],
    message: str,
    ctx: Any,
    *,
    seed: int,
    prior: list[str] | None = None,
) -> dict[str, Any]:
    """Overlay small talk; leave medical/coaching speak on the engine path.

    Always re-runs ``speak_guard`` so the overlay cannot bypass the scrub.
    """
    band = str(envelope.get("guidance_band") or guidance.classify_band(message) or "")
    if band in (guidance.EMERGENCY, guidance.FIRST_AID, guidance.REFER_OUT):
        return speak_guard.guard_envelope(envelope, topic=message)

    if is_small_talk(message):
        spoken = compose_small_talk(message, ctx, seed=seed, prior=prior)
        envelope["message"] = spoken
        envelope["prose_summary"] = spoken
        # Digit-free step so speak_guard does not insert "20 easy minutes".
        card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
        if not card.get("action"):
            envelope["card"] = {**card, "action": "keep tonight kind"}
        guarded = speak_guard.guard_envelope(envelope, topic="lifestyle")
        for key in ("message", "prose_summary"):
            text = speak_guard.rescrub_speak(str(guarded.get(key) or spoken))
            text = _DIGIT_UNIT.sub("", text)
            text = re.sub(r"\s{2,}", " ", text).strip()
            if text and not re.search(r"\d", text):
                guarded[key] = text
            else:
                guarded[key] = spoken
        return guarded

    # Coaching path: keep engine truth, polish like Dummy friend_speak, re-guard.
    try:
        from backend.ai.simrunner.aria_simrunner.dummy_orchestrator import friend_speak

        stance = str((envelope.get("fusion") or {}).get("stance") or "")
        for key in ("prose_summary", "message"):
            text = str(envelope.get(key) or "")
            if text:
                envelope[key] = friend_speak(
                    text,
                    seed=seed,
                    stance=stance,
                    guidance=None,
                    short_ok=True,
                )
    except Exception:
        pass
    return speak_guard.guard_envelope(envelope, topic=message)
