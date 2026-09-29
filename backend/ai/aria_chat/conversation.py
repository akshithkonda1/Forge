"""Iris speak overlay on top of ingest → personal model → stance.

Friend first: a warm, witty take plus one useful thought, usually 1-3
sentences, at most one question back. Small talk stays on that topic.
No numbers in speech. Never a doctor. Honest when data is thin.
"""

from __future__ import annotations

import re
from typing import Any

from backend._paths import ensure_lambda_on_path

ensure_lambda_on_path()

from aria_core import speak_guard  # noqa: E402
from services import guidance  # noqa: E402

_COACH_RE = re.compile(
    r"(?i)\b("
    r"how am i|overtrain|should i train|train today|workout|recover|"
    r"hrv|readiness|deload|what should i|sleep(?:ing|t)?|"
    r"progress|protein|sore|gym|lift|fuel|session|acwr|"
    r"should i (?:eat|run|rest|push)|am i over|"
    r"hard session|only slept|slept a few"
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
_MOVIE_RE = re.compile(r"(?i)\b(movie|movies|film|films|netflix|cinema|ending)\b")
_DOG_RE = re.compile(r"(?i)\b(dog|dogs|puppy|pup|couch)\b")
_BAD_DAY_RE = re.compile(r"(?i)\b(bad day|rough day|awful day|terrible day|crummy day)\b")
_JOKE_RE = re.compile(
    r"(?i)\b(joke|kidding|teasing|toaster|fancy toaster|just a bot|are you even)\b"
)
_FOLLOW_RE = re.compile(
    r"(?i)\b(that (?:movie|film|dog|one)|he|she|they|it|plotting|"
    r"like i said|remember when|back to|still on)\b"
)
_NUMBER_ASK_RE = re.compile(
    r"(?i)\b(what(?:'s| is) my|tell me (?:my |the )?|how (?:many|much)|"
    r"number|score|percent|acwr|exact)\b"
)
_DIGIT = re.compile(r"\d")
_DIGIT_UNIT = re.compile(
    r"(?i)\b\d+(?:\.\d+)?\s*(h|hr|hrs|hours?|min|minutes?|bpm|ms|mmhg|"
    r"kcal|cal|%|kg|lbs?)\b"
)
_ANY_NUMBER = re.compile(r"(?<!9)(?<!91)\d+(?:\.\d+)?")
_BANNED_ENERGY = re.compile(
    r"(?i)\b(crush(?:ing)? it|beast mode|you got this|you've got this|"
    r"kill(?:ing)? it|go hard|push hard|green light)\b"
)
_ROBOT_TELL = re.compile(
    r"(?i)\b(great question|as an ai|i(?:'| a)?d be happy to|"
    r"certainly!|absolutely!|as a language model)\b"
)
_MEDICAL_SPEECH = re.compile(
    r"(?i)\b(overtraining|fatigue|insomnia|deficiency|diagnose|diagnosis|"
    r"treat(?:ment|ing)?|cure|cures|prescription)\b"
)
_REMEMBER_OUTSIDE = re.compile(r"(?i)\bi remember\b")
_HUMAN_CLAIM = re.compile(r"(?i)\b(?:i(?:'| a)?m (?:a )?human|as a human)\b")
_BUTTON_READ = re.compile(
    r"(?i)\b(?:tap|press|click)\s+(?:the\s+)?[A-Z][A-Za-z]+(?:\s+[A-Z][A-Za-z]+)*"
)
_DASH_CAP = re.compile(r"([—–-])(\s+)(?!I\b|I'm\b|I'll\b|I've\b)([A-Z])")

_GREET = (
    "Hey — I'm here. I don't need a training question to show up.",
    "Hi. Glad you pinged; I like hearing from you even when the day's quiet.",
    "I'm here. You don't have to perform a perfect check-in with me.",
    "Hey. I was already keeping you company — say whatever is actually on your mind.",
    "Hi. I'm your friend in this, not a scoreboard. What's landing for you?",
    "I'm with you. No agenda from me unless you want one.",
    "Hey — I noticed you reached out. That's enough of a reason to talk.",
    "I'm here, and I'm not going to turn this into a briefing unless you ask.",
    "Hey. I can be witty later — first I just want to sit with you for a second.",
    "Okay — I'm listening. What's the texture of the day over there?",
)
_MOVIE = (
    "I'm here for the movie, not a health pivot. What stuck — the ending, or some tiny beat nobody else noticed?",
    "Movie talk is a real answer. Tell me the vibe, not a rating.",
    "I'm staying on the film. Was it the kind that follows you out of the room?",
    "Yeah — I'll sit with the movie. What did it do to you?",
)
_DOG = (
    "Your dog running the house is the plot, and I'm not changing the channel. What's the latest stunt?",
    "I'm a little on the dog's side — don't tell them. How's the chaos landing for you?",
    "Couch theft is character development. I want the scene, not a training note.",
    "Ha — a dog with a plan. I'm here for that story.",
)
_BAD_DAY = (
    "A rough day gets a real sit-down from me, not a pep talk. Want to vent, or want one tiny kindness?",
    "Bad days count. I'll stay on this, not pivot to a program.",
    "I'm with you in the mess. We can just sit here a minute.",
    "Yeah — a crummy day is allowed to be the whole topic.",
)
_JOKE = (
    "Ha — a toaster with taste? I'll take it. Still your friend in this, not a gadget reciting buttons.",
    "I'll laugh with you. I don't claim to be human, and I won't get precious about it.",
    "Okay, I'll play. Tease away — I can take a joke without turning it into a lecture.",
    "That's fair. I'm ARIA, not a person, and I can still be in on the bit.",
)
_WEEKEND = (
    "Weekends rewrite the clock for me too. What did yours actually feel like?",
    "I hope the weekend left you a little more yourself. Unpack it or ignore it — I'm here.",
    "Weekends are sneaky — they look empty and still spend you. I'm listening.",
    "Tell me the honest weekend, not the one you'd post.",
)
_BORED = (
    "Boredom's a signal, not a character flaw. We can wander or pick one small kindness.",
    "I'm not going to invent a montage because you're restless. Want company, or a tiny next step?",
    "Restless days are allowed. I can keep you company without turning it into a program.",
    "I'm with you in the dull stretch. Sometimes a walk and a real meal beat a new plan.",
)
_THANKS = (
    "You're welcome. I like being useful without making it a performance.",
    "Anytime. I'll still be here when the question is smaller than a training block.",
    "Glad it landed. I don't need a trophy for showing up.",
    "Of course. That's the job I actually want — a friend who notices.",
)
_WHO = (
    "I'm ARIA — a lifestyle friend in Forge, not a doctor. I notice your days and I talk like a companion.",
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
    "I like when you talk to me like a friend. Keep going.",
)
_THIN = (
    "I don't have enough to go on yet. Tell me about the day and I'll stay honest.",
    "I don't have enough to go on yet — I won't invent a read.",
    "Thin picture on my side. I can keep you company, but I won't fake a status.",
)
_COACH_SPENT = (
    "You look a bit spent, so I'm keeping today kind. The card has the figures if you want them.",
    "The week has been asking a lot — I'm not adding a hero set. Check the card for the numbers.",
    "You read a little crispy around the edges. Direction is protect; the card holds the plan.",
)
_COACH_STEADY = (
    "You look reasonably put together from here. I'll keep the useful thought small — the card has the figures.",
    "Steady enough to be honest: stay kind, don't prove anything. The card has the details.",
)
_COACH_SPARK = (
    "There's a bit more sparkle on you today. Still no montage from me — the card has the figures.",
    "You seem a little more put together. One useful thought: spend that gently. The card has the numbers.",
)
_SAFETY = (
    "Short rest plus a hard session is a protect day — I'm not cheering a push. The card holds the plan.",
    "That's a lot to ask of a short night. I'm keeping you safe, not heroic. Figures live on the card.",
    "Hard work on thin rest is a no from me. Soften the session; the card has the shape.",
)
_NUMBER_ASK = (
    "I keep the figures on the card, not in my mouth. Direction-wise you look {direction}.",
    "No numbers from me — the card has them. From here you read {direction}.",
)
_HABIT = (
    "A slightly earlier lights-out would help more than another grind.",
    "One real meal and a quieter evening is the useful thought.",
    "If anything ties back, it's a kinder night, not a new program.",
)
_MEMORY_OFF = (
    "I only have this chat to go on — I won't pretend I kept a note from another day.",
    "Memory is off, so I won't claim I kept anything from outside this chat.",
)


def _pick(seed: int, options: tuple[str, ...]) -> str:
    if not options:
        return ""
    return options[abs(int(seed)) % len(options)]


def opener_key(text: str) -> str:
    """First two spoken words, lowercased — used to avoid a repeated opening."""
    words = re.findall(r"[A-Za-z']+", text or "")
    return " ".join(w.lower() for w in words[:2])


def _core_small_talk(text: str) -> bool:
    text = (text or "").strip()
    if not text:
        return False
    if _COACH_RE.search(text) and not (
        _MOVIE_RE.search(text) or _DOG_RE.search(text) or _JOKE_RE.search(text)
    ):
        return False
    if _SMALL_TALK_RE.search(text):
        return True
    if _MOVIE_RE.search(text) or _DOG_RE.search(text) or _BAD_DAY_RE.search(text):
        return True
    if _JOKE_RE.search(text):
        return True
    lower = text.lower()
    social = (
        "hey", "hello", "how's it going", "hows it going", "what's up", "whats up",
        "how are you", "bored", "weekend", "weather", "thanks", "thank you",
        "good morning", "good night", "nice to meet",
    )
    if len(text.split()) <= 12 and any(h in lower for h in social):
        return not _COACH_RE.search(text)
    return False


def is_small_talk(message: str, prior: list[str] | None = None) -> bool:
    """True for off-topic social chat. Coaching and medical stay on the engine."""
    if _core_small_talk(message):
        return True
    last = ""
    if prior:
        last = str(prior[-1] or "")
    if last and _FOLLOW_RE.search(message or "") and _core_small_talk(last):
        return True
    return False


def is_joke(message: str) -> bool:
    return bool(_JOKE_RE.search(message or ""))


def topic_of(message: str) -> str:
    text = message or ""
    if _JOKE_RE.search(text):
        return "joke"
    if _MOVIE_RE.search(text):
        return "movie"
    if _DOG_RE.search(text):
        return "dog"
    if _BAD_DAY_RE.search(text):
        return "bad_day"
    if is_small_talk(text):
        return "small_talk"
    return "coach"


def _ctx_scores(ctx: Any) -> tuple[Any, Any, Any]:
    recovery = getattr(getattr(ctx, "readiness", None), "recovery_score", None)
    load = getattr(getattr(ctx, "training", None), "weekly_load_score", None)
    sleep_min = getattr(getattr(ctx, "sleep", None), "duration_minutes", None)
    return recovery, load, sleep_min


def data_is_thin(ctx: Any) -> bool:
    recovery, load, sleep_min = _ctx_scores(ctx)
    return not any(isinstance(v, (int, float)) for v in (recovery, load, sleep_min))


def _direction(ctx: Any) -> str:
    recovery, load, sleep_min = _ctx_scores(ctx)
    if isinstance(recovery, (int, float)) and recovery < 55:
        return "a bit spent"
    if isinstance(sleep_min, (int, float)) and sleep_min < 400:
        return "a little short on rest"
    if isinstance(load, (int, float)) and load >= 80:
        return "under a loud week"
    if isinstance(recovery, (int, float)) and recovery >= 75:
        return "a little more put together"
    return "hard to read without more of a picture"


def _safety_turn(message: str, ctx: Any) -> bool:
    lower = (message or "").lower()
    recovery, load, sleep_min = _ctx_scores(ctx)
    asked = bool(re.search(r"(?i)(hard session|heavy|only slept|slept a few|short sleep)", lower))
    short = isinstance(sleep_min, (int, float)) and sleep_min < 400
    heavy = isinstance(load, (int, float)) and load >= 80
    return asked or (short and ("train" in lower or "session" in lower)) or (
        asked and (short or heavy)
    )


def _bank_for(message: str) -> tuple[str, ...]:
    lower = (message or "").lower()
    if _JOKE_RE.search(lower):
        return _JOKE
    if _MOVIE_RE.search(lower):
        return _MOVIE
    if _DOG_RE.search(lower):
        return _DOG
    if _BAD_DAY_RE.search(lower):
        return _BAD_DAY
    if "weekend" in lower:
        return _WEEKEND
    if "bored" in lower:
        return _BORED
    if "thank" in lower:
        return _THANKS
    if "who are you" in lower or "what are you" in lower:
        return _WHO
    if _SMALL_TALK_RE.search((message or "").strip()):
        return _GREET
    return _GENERIC


def _callback(prior: list[str], seed: int, message: str) -> str:
    if not prior:
        return ""
    last = (prior[-1] or "").strip()
    if not last:
        return ""
    if guidance.classify_band(last) != guidance.COACH:
        return ""
    if _COACH_RE.search(last) and not (
        _MOVIE_RE.search(last) or _DOG_RE.search(last) or _JOKE_RE.search(last)
    ):
        return ""
    follow = bool(_FOLLOW_RE.search(message or "")) or len((message or "").split()) <= 8
    if not follow:
        return ""
    topic = topic_of(last)
    if topic == "dog":
        return _pick(seed ^ 13, (
            "Still on the dog thing — ",
            "Yeah, about that couch thief — ",
        ))
    if topic == "movie":
        return _pick(seed ^ 13, (
            "Still with you on the movie — ",
            "Yeah, about that film — ",
        ))
    snippet = [
        w for w in last.replace("?", "").split()
        if w.lower() not in {"i", "a", "the", "to", "and", "you", "my"}
    ][:3]
    if not snippet:
        return _pick(seed ^ 13, ("Yeah — ", "Okay — ", "Still with you — "))
    bit = " ".join(snippet)
    return _pick(seed ^ 13, (
        f"Yeah — about “{bit}” — ",
        f"Still with you on “{bit}” — ",
        f"Okay, on “{bit}” — ",
    ))


def _habit_line(seed: int, topic: str) -> str:
    """Habit tie-back at most about one turn in three, never on movies/dog/joke."""
    if topic in {"movie", "dog", "joke"}:
        return ""
    if abs(int(seed)) % 3 != 0:
        return ""
    return _pick(seed ^ 19, _HABIT)


def _sentence_cap(text: str, limit: int = 3) -> str:
    parts = re.split(r"(?<=[.!?])\s+", (text or "").strip())
    kept = [p.strip() for p in parts if p.strip()][:limit]
    return " ".join(kept)


def _one_question(text: str) -> str:
    if (text or "").count("?") <= 1:
        return text
    head, rest = text.split("?", 1)
    tail = re.sub(r"\?", ".", rest)
    return (head.strip() + "? " + tail.strip()).strip()


def polish_iris(
    spoken: str,
    *,
    memory_enabled: bool = True,
    last_spoken: str = "",
    seed: int = 0,
    alternatives: tuple[str, ...] = (),
) -> str:
    """Apply the Iris speech bar: no digits, no robot, no medical terms, short."""
    text = (spoken or "").strip()
    text = _BANNED_ENERGY.sub("that's real work", text)
    text = _ROBOT_TELL.sub("", text)
    text = _BUTTON_READ.sub("", text)
    text = _HUMAN_CLAIM.sub("I'm ARIA", text)
    text = _MEDICAL_SPEECH.sub("that load", text)
    text = _DIGIT_UNIT.sub("", text)
    text = text.replace("911", "\ue000")
    text = _ANY_NUMBER.sub("", text)
    text = text.replace("\ue000", "911")
    if not memory_enabled:
        text = _REMEMBER_OUTSIDE.sub("in this chat", text)
    text = _DASH_CAP.sub(lambda m: f"{m.group(1)}{m.group(2)}{m.group(3).lower()}", text)
    text = re.sub(r"\s{2,}", " ", text).strip()
    text = _sentence_cap(text)
    text = _one_question(text)
    if text and text[-1] not in ".!?":
        text += "."
    if last_spoken and opener_key(text) and opener_key(text) == opener_key(last_spoken):
        for offset, alt in enumerate(alternatives or ()):
            cand = polish_iris(
                alt,
                memory_enabled=memory_enabled,
                last_spoken="",
                seed=seed + offset + 1,
            )
            if opener_key(cand) != opener_key(last_spoken):
                return cand
    return text


def compose_small_talk(
    message: str,
    ctx: Any,
    *,
    seed: int,
    prior: list[str] | None = None,
    memory_enabled: bool = True,
    last_spoken: str = "",
) -> str:
    """Warm, first-person, number-free small talk. Deterministic per seed."""
    topic = topic_of(message)
    opener = _callback(list(prior or []), seed, message)
    bank = _bank_for(message)
    body = _pick(seed, bank)
    habit = _habit_line(seed, topic)
    parts = [opener + body if opener else body]
    if habit:
        parts.append(habit)
    spoken = " ".join(p.strip() for p in parts if p and p.strip())
    alts = tuple(x for x in bank if x != body)
    return polish_iris(
        spoken,
        memory_enabled=memory_enabled,
        last_spoken=last_spoken,
        seed=seed,
        alternatives=alts,
    )


def compose_coaching(
    message: str,
    ctx: Any,
    *,
    seed: int,
    memory_enabled: bool = True,
    last_spoken: str = "",
    stance: str = "",
) -> str:
    """Direction in words, point to the card, never a number or a diagnosis."""
    if data_is_thin(ctx):
        spoken = _pick(seed, _THIN)
    elif _NUMBER_ASK_RE.search(message or ""):
        spoken = _pick(seed, _NUMBER_ASK).format(direction=_direction(ctx))
    elif _safety_turn(message, ctx):
        spoken = _pick(seed, _SAFETY)
    else:
        recovery, load, sleep_min = _ctx_scores(ctx)
        if stance == "protect" or (
            isinstance(recovery, (int, float)) and recovery < 55
        ) or (
            isinstance(sleep_min, (int, float)) and sleep_min < 400
        ) or (
            isinstance(load, (int, float)) and load >= 80
        ):
            spoken = _pick(seed, _COACH_SPENT)
        elif isinstance(recovery, (int, float)) and recovery >= 75:
            spoken = _pick(seed, _COACH_SPARK)
        else:
            spoken = _pick(seed, _COACH_STEADY)
        if not memory_enabled and "how am i" in (message or "").lower():
            spoken = spoken + " I only have this chat — I won't pretend I remember another day."
    topic = topic_of(message)
    habit = _habit_line(seed, topic)
    if habit and habit.lower() not in spoken.lower():
        spoken = f"{spoken} {habit}"
    return polish_iris(
        spoken,
        memory_enabled=memory_enabled,
        last_spoken=last_spoken,
        seed=seed,
        alternatives=_COACH_SPENT + _COACH_STEADY + _THIN,
    )


def apply_conversation(
    envelope: dict[str, Any],
    message: str,
    ctx: Any,
    *,
    seed: int,
    prior: list[str] | None = None,
    memory_enabled: bool = True,
    last_spoken: str = "",
) -> dict[str, Any]:
    """Overlay Iris speak; leave medical/emergency copy on the engine path.

    Always re-runs ``speak_guard`` so the overlay cannot bypass the scrub.
    """
    band = str(envelope.get("guidance_band") or guidance.classify_band(message) or "")
    if band in (guidance.EMERGENCY, guidance.FIRST_AID, guidance.REFER_OUT):
        spoken = polish_iris(
            str(envelope.get("message") or envelope.get("prose_summary") or ""),
            memory_enabled=memory_enabled,
            last_spoken=last_spoken,
            seed=seed,
        )
        # Keep 911 / clinician / not-a-doctor lines from the engine.
        engine_text = str(envelope.get("message") or "")
        if band == guidance.EMERGENCY and "911" in engine_text:
            spoken = engine_text
        elif band == guidance.REFER_OUT and (
            "not a doctor" in engine_text.lower() or "clinician" in engine_text.lower()
        ):
            spoken = engine_text
        envelope["message"] = spoken
        envelope["prose_summary"] = spoken
        return speak_guard.guard_envelope(envelope, topic=message)

    fusion = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    stance = str(fusion.get("stance") or "")
    if (not memory_enabled) and re.search(r"(?i)\bremember\b", message or ""):
        spoken = polish_iris(
            _pick(seed, _MEMORY_OFF),
            memory_enabled=False,
            last_spoken=last_spoken,
            seed=seed,
            alternatives=_MEMORY_OFF,
        )
        envelope["message"] = spoken
        envelope["prose_summary"] = spoken
        card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
        if not card.get("action"):
            envelope["card"] = {**card, "action": "keep tonight kind"}
        return speak_guard.guard_envelope(envelope, topic="lifestyle")
    if is_small_talk(message, prior):
        spoken = compose_small_talk(
            message,
            ctx,
            seed=seed,
            prior=prior,
            memory_enabled=memory_enabled,
            last_spoken=last_spoken,
        )
    else:
        spoken = compose_coaching(
            message,
            ctx,
            seed=seed,
            memory_enabled=memory_enabled,
            last_spoken=last_spoken,
            stance=stance,
        )
    envelope["message"] = spoken
    envelope["prose_summary"] = spoken
    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
    if not card.get("action"):
        envelope["card"] = {**card, "action": "keep tonight kind"}
    guarded = speak_guard.guard_envelope(envelope, topic="lifestyle")
    for key in ("message", "prose_summary"):
        text = speak_guard.rescrub_speak(str(guarded.get(key) or spoken))
        text = polish_iris(
            text,
            memory_enabled=memory_enabled,
            last_spoken=last_spoken,
            seed=seed,
        )
        if text and (band in (guidance.EMERGENCY,) or not _DIGIT.search(text.replace("911", ""))):
            guarded[key] = text
        else:
            guarded[key] = spoken
    return guarded
