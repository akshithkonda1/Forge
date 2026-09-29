"""Iris speak overlay on top of ingest → personal model → stance.

Friend first: a warm, witty take plus one useful point, usually 1-3
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

# PR 380 `cursor/spoken-safety-tip-fix-f013` speech bank, copied word for word.
# `SPOKEN_SHORT_SLEEP` / `SPOKEN_PROTECT_STEP`: backend/infra/lambda/aria_core/aria_engine.py:2202–2203
# Dummy closer `_SAFETY_CLOSER`: backend/ai/simrunner/aria_simrunner/dummy_orchestrator.py:873
SPOKEN_SHORT_SLEEP = "You've been running short on sleep this week, so sleep comes first."
SPOKEN_PROTECT_STEP = "Keep today easy and call it a win."
SAFETY_CLOSER = "Future you says thanks."
APPROVED_SHORT_SLEEP = f"{SPOKEN_SHORT_SLEEP} {SPOKEN_PROTECT_STEP} {SAFETY_CLOSER}"

RECOVERY_IN_SPEECH = re.compile(r"(?i)\brecovery\b")
# Spoken-reply gate only. Narrow list — do not match bare "I won't" / "I don't".
SELF_DESCRIBE = re.compile(
    r"(?i)("
    r"\bpretend\b|"
    r"claim to be human|"
    r"not a doctor|"
    r"keep you safe|"
    r"turn it into a plan|"
    r"kept a note|"
    r"the useful bit|"
    r"the useful thought|"
    r"we'll take this kindly|"
    r"i(?:'| a)?m on your side|"
    r"perfectly browned take"
    r")"
)
_QUOTED_ECHO = re.compile(r"[“”\"]")
_THREAD_CALLBACK_LEAD = re.compile(
    r"(?is)^\s*(?:"
    r"(?:okay|ok|yeah|right|still with you)(?:,|\s+on|\s+about)?\s+[“\"].*?[”\"]\s*[—–-]\s+"
    r"|(?:yeah|okay|ok|right|still with you)\s*[—–-]\s+"
    r"|(?:still on|picking up|you were asking|from the training|on the workout|after what you said)"
    r"[^.!?]*?[—–:]\s+"
    r")"
)
_CARD_POINTER = re.compile(
    r"(?i)\b(figures live on the card|check the card|the card has|the card holds)\b"
)

_GREET = (
    "Hey — you pinged like someone who already did the hard part. What's actually landing?",
    "Hi. I was sitting here like a plant that texts back. What's the texture of the day?",
    "I'm here, and I brought snacks for the tangent. What's going on over there?",
    "Hey. Glad you showed up. What's on your mind?",
    "Hi. I'm your friend in this. What's landing for you?",
    "I'm listening. What's the day doing from where you sit?",
    "Hey — you reached out, so something's stirring. What is it?",
    "Okay — I'm listening. Paint the room for me.",
)
_MOVIE = (
    "That ending followed you home like a stray plot twist. Sit with it a minute, then tell me the beat that stuck.",
    "Movie hangover is a real condition and I'm not curing it. What vibe did it leave in the room?",
    "I'm staying on the film. Was it the kind that follows you out of the room?",
    "Yeah — sitting with the movie. What did it do to you?",
)
_DOG = (
    "Your dog just unionized the furniture. A walk after dinner might win the cushion back.",
    "I'm a little on the dog's side — they negotiated the couch fair and square. Toss a toy before they annex the bed.",
    "Couch theft is a hostile takeover with extra slobber. Bribe them with a stroll and you might get a seat again.",
    "Ha — a four-legged landlord with no lease. Reclaim one corner, then take the long way down the street.",
)
_DOG_FOLLOW = (
    "The dog clearly has a long-term couch strategy — that stare is a whole campaign. A stroll before supper might stall the next plot.",
    "Plotting? Yeah, he's already claimed the high ground and the remote. A snack and a loop down the lane could pause the coup.",
)
_BAD_DAY = (
    "A rough day gets a real sit-down. Want to vent, or want one tiny kindness?",
    "Rough days count. I'm with you in the mess — we can just sit here a minute.",
    "Yeah — a crummy day is allowed to be the whole topic. I'm here.",
)
_JOKE = (
    "If I'm a toaster, my only setting is 'opinions' and it jams. Sit with whatever's warming — you don't have to perform.",
    "A talking toaster would at least own the bagel slot. Kick your shoes off and stay a minute.",
    "Ha — then I pop crumbs, not lectures. A slow breath and a real sit-down beats rushing the next thing.",
    "Toaster? Heat stays low. Tell me what's actually on the counter.",
)
_WEEKEND = (
    "Weekends rewrite the clock for me too. What did yours actually feel like?",
    "Weekends are sneaky — they look empty and still spend you. Unpack it or ignore it, I'm here.",
    "Tell me the honest weekend, not the one you'd post.",
)
_BORED = (
    "Boredom's a signal, not a character flaw. We can wander or pick one small kindness.",
    "Restless days are allowed. Sometimes a walk and a real meal beat a new plan.",
    "I'm with you in the dull stretch. Want company, or a tiny next step?",
)
_THANKS = (
    "You're welcome. What do you want to chew on next?",
    "Anytime. The smaller question counts too.",
    "Glad it landed. What else is sitting with you?",
)
_WHO = (
    "I'm ARIA — a lifestyle friend with a sense of humor. What's on your mind?",
    "I'm ARIA. Witty when it helps, honest when it matters. What do you need?",
)
_GENERIC = (
    "I'm here, and I brought snacks for the tangent. What's actually going on?",
    "Say the unpolished version. I can sit with what's going on.",
    "Say more if you want. I can stay on the specific thing.",
    "Tell me the specific thing, not the polished version. I can sit with it.",
)
_THIN = (
    "I don't have enough to go on yet. Tell me about the day?",
)
_COACH_SPENT = (
    "You're running on leftover toast energy — charming, until the crumbs stage a coup.",
    "You look like a phone that opened one more app on fumes. Soften the day and lights out earlier.",
    "That stubborn streak is doing unpaid overtime. Walk, eat, and call it before you prove anything.",
)
_COACH_STEADY = (
    "You look like a bookshelf that finally sat still. Keep tonight quiet and don't stack another errand.",
    "Steady — like tea that hasn't gone cold. Leave a little room and skip the late spiral.",
)
_COACH_SPARK = (
    "There's extra sparkle on you, like a bike that found a downhill. Spend it kindly and hop off while it's still fun.",
    "You look like someone who found the good mug. Keep it gentle and stop before you prove anything.",
)
_SAFETY = (APPROVED_SHORT_SLEEP,)
_NUMBER_ASK = (
    "From here you look {direction}.",
)
_HABIT = (
    "A slightly earlier lights-out would help more than another grind.",
    "One real meal and a quieter evening beats another late push.",
)
_MEMORY_OFF = (
    "That story isn't with me — I'd love to hear about it.",
    "That one's not with me. Tell me the story?",
)
_REFER_OUT_SPEAK = (
    "I can't tell from here — a doctor can check it properly. Meanwhile I'm glad to help with sleep habits.",
    "I can't tell from here — a doctor can check it properly. Meanwhile I'm glad to help with the day-to-day stuff around it.",
    "That one's a call for your doctor or pharmacist — they know what you're on. I'm glad to help with the day-to-day stuff around it.",
)
_WARMER_AFTER_DOWN = (
    "I'm still here. Want to pick up the thread, or start a smaller one?",
    "Glad you stayed. What's the next thing that actually wants air?",
)
SPEECH_BANKS = (
    _GREET,
    _MOVIE,
    _DOG,
    _DOG_FOLLOW,
    _BAD_DAY,
    _JOKE,
    _WEEKEND,
    _BORED,
    _THANKS,
    _WHO,
    _GENERIC,
    _THIN,
    _COACH_SPENT,
    _COACH_STEADY,
    _COACH_SPARK,
    _SAFETY,
    _NUMBER_ASK,
    _HABIT,
    _MEMORY_OFF,
    _REFER_OUT_SPEAK,
    _WARMER_AFTER_DOWN,
)
_HERO_OR_BARK = re.compile(
    r"(?i)\b(hero set|trainer bark|crush(?:ing)? it|beast mode|you got this)\b"
)
_RATING_TALK = re.compile(r"(?i)\b(rating|feedback|noted|thumbs[- ]down|thumbs[- ]up)\b")


def _pick(seed: int, options: tuple[str, ...]) -> str:
    if not options:
        return ""
    return options[abs(int(seed)) % len(options)]


def word_ngrams(text: str, n: int) -> set[str]:
    words = re.findall(r"[a-z0-9']+", (text or "").lower())
    if len(words) < n:
        return set()
    return {" ".join(words[i : i + n]) for i in range(len(words) - n + 1)}


def _emergency_allow_ngrams() -> set[str]:
    """Exact approved emergency strings only — never a whole band."""
    replies = (
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_CARDIAC}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_CARDIAC_HELPER}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_STROKE}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_STROKE_HELPER}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_FAINT}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_FAINT_HELPER}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_CPR}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_CPR_IF_NEEDED}",
        f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_PATIENT_FALLBACK}",
        guidance._CRISIS_LINE,
    )
    grams: set[str] = set()
    for text in replies:
        grams |= word_ngrams(text, 3)
    return grams


_SAFE_REPEAT_NGRAMS = (
    word_ngrams(SPOKEN_SHORT_SLEEP, 3)
    | word_ngrams(SPOKEN_PROTECT_STEP, 3)
    | word_ngrams(SAFETY_CLOSER, 3)
    | _emergency_allow_ngrams()
    | word_ngrams(_REFER_OUT_SPEAK[0], 3)
    | word_ngrams(_REFER_OUT_SPEAK[1], 3)
    | word_ngrams(_REFER_OUT_SPEAK[2], 3)
)


def prior_spoken_from_history(history: list | None) -> list[str]:
    out: list[str] = []
    if not isinstance(history, list):
        return out
    for item in history:
        if not isinstance(item, dict):
            continue
        role = str(item.get("role") or item.get("speaker") or "").strip().lower()
        if role not in {"assistant", "aria", "bot"}:
            continue
        text = str(item.get("content") or item.get("message") or item.get("text") or "")
        if text.strip():
            out.append(text)
    return out


def _repeat_ngrams(text: str) -> set[str]:
    return word_ngrams(text, 3) - _SAFE_REPEAT_NGRAMS


def _overlaps_prior(text: str, prior_spoken: list[str] | None) -> bool:
    grams = _repeat_ngrams(text)
    if not grams:
        return False
    for prev in prior_spoken or []:
        if grams & _repeat_ngrams(prev):
            return True
    return False


def _copies_user_run(text: str, prior_user: list[str] | None, n: int = 4) -> bool:
    grams = word_ngrams(text, n)
    if not grams:
        return False
    for prev in prior_user or []:
        if grams & word_ngrams(prev, n):
            return True
    return False


def _pick_fresh(
    seed: int,
    options: tuple[str, ...],
    prior_spoken: list[str] | None = None,
) -> str:
    if not options:
        return ""
    start = abs(int(seed)) % len(options)
    ordered = options[start:] + options[:start]
    for cand in ordered:
        if not _overlaps_prior(cand, prior_spoken):
            return cand
    return ordered[0]


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


def _bank_for(message: str, prior: list[str] | None = None) -> tuple[str, ...]:
    lower = (message or "").lower()
    last = str((prior or [""])[-1] or "")
    follow = bool(prior) and (
        _FOLLOW_RE.search(message or "") or topic_of(message) in {"small_talk", "coach"}
    )
    if follow and topic_of(last) == "dog" and is_small_talk(message, prior):
        return _DOG_FOLLOW
    if follow and topic_of(last) == "movie" and is_small_talk(message, prior):
        return _MOVIE
    if follow and topic_of(last) == "joke" and is_small_talk(message, prior):
        return _JOKE
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


def _strip_thread_callback(text: str) -> str:
    """Drop a Dummy/Iris thread opener, especially one that quotes prior user text."""
    cleaned = _THREAD_CALLBACK_LEAD.sub("", text or "", count=1).strip()
    if cleaned and cleaned[0].islower():
        cleaned = cleaned[0].upper() + cleaned[1:]
    return cleaned


def _callback(prior: list[str], seed: int, message: str) -> str:
    if not prior:
        return ""
    last = (prior[-1] or "").strip()
    if not last:
        return ""
    if guidance.classify_band(message) in (
        guidance.EMERGENCY,
        guidance.FIRST_AID,
        guidance.REFER_OUT,
    ):
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
        opener = _pick(seed ^ 13, (
            "Still on the dog thing — ",
            "Yeah, about that couch thief — ",
        ))
    elif topic == "movie":
        opener = _pick(seed ^ 13, (
            "Still with you on the movie — ",
            "Yeah, about that film — ",
        ))
    else:
        opener = _pick(seed ^ 13, ("Yeah — ", "Okay — ", "Still with you — "))
    # Topic in ARIA's words only — never quote or copy a 4-word user run.
    if _QUOTED_ECHO.search(opener) or _copies_user_run(opener, [last, *prior[:-1]]):
        return ""
    return opener


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
    text = text.replace("[redacted]", "")
    text = _QUOTED_ECHO.sub("", text)
    text = _BANNED_ENERGY.sub("that's real work", text)
    text = _ROBOT_TELL.sub("", text)
    text = _BUTTON_READ.sub("", text)
    text = _HUMAN_CLAIM.sub("I'm ARIA", text)
    text = _MEDICAL_SPEECH.sub("that load", text)
    text = _DIGIT_UNIT.sub("", text)
    text = text.replace("911", "\ue000")
    text = _ANY_NUMBER.sub("", text)
    text = text.replace("\ue000", "911")
    text = RECOVERY_IN_SPEECH.sub("rest", text)
    text = _CARD_POINTER.sub("", text)
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
    last_rating: str = "",
    prior_spoken: list[str] | None = None,
) -> str:
    """Warm, first-person, number-free small talk. Deterministic per seed."""
    topic = topic_of(message)
    last = str((prior or [""])[-1] or "")
    if prior and is_small_talk(message, prior) and topic_of(last) in {"dog", "movie", "joke"}:
        topic = topic_of(last)
    bank = _bank_for(message, prior)
    # Follow-up banks already name the thread — skip a prefix that turns into filler.
    # After a thumbs-down, skip the callback so we never quote the user's text.
    opener = ""
    if (
        bank not in {_DOG_FOLLOW, _DOG, _MOVIE, _JOKE}
        and str(last_rating or "").strip().lower() != "down"
    ):
        opener = _callback(list(prior or []), seed, message)
    used = list(prior_spoken or [])
    body = _pick_fresh(seed, bank, used)
    habit = _habit_line(seed, topic)
    if habit and _overlaps_prior(f"{body} {habit}", used):
        habit = ""
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
    prior_spoken: list[str] | None = None,
) -> str:
    """Direction in words, never a number or a diagnosis."""
    used = list(prior_spoken or [])
    if data_is_thin(ctx):
        spoken = _pick_fresh(seed, _THIN, used)
        return polish_iris(
            spoken,
            memory_enabled=memory_enabled,
            last_spoken=last_spoken,
            seed=seed,
            alternatives=_THIN,
        )
    elif _NUMBER_ASK_RE.search(message or ""):
        spoken = _pick(seed, _NUMBER_ASK).format(direction=_direction(ctx))
    elif _safety_turn(message, ctx):
        return polish_iris(
            APPROVED_SHORT_SLEEP,
            memory_enabled=memory_enabled,
            last_spoken=last_spoken,
            seed=seed,
            alternatives=_SAFETY,
        )
    else:
        recovery, load, sleep_min = _ctx_scores(ctx)
        if stance == "protect" or (
            isinstance(recovery, (int, float)) and recovery < 55
        ) or (
            isinstance(sleep_min, (int, float)) and sleep_min < 400
        ) or (
            isinstance(load, (int, float)) and load >= 80
        ):
            spoken = _pick_fresh(seed, _COACH_SPENT, used)
        elif isinstance(recovery, (int, float)) and recovery >= 75:
            spoken = _pick_fresh(seed, _COACH_SPARK, used)
        else:
            spoken = _pick_fresh(seed, _COACH_STEADY, used)
    topic = topic_of(message)
    habit = _habit_line(seed, topic)
    if habit and habit.lower() not in spoken.lower() and not _overlaps_prior(
        f"{spoken} {habit}", used
    ):
        spoken = f"{spoken} {habit}"
    return polish_iris(
        spoken,
        memory_enabled=memory_enabled,
        last_spoken=last_spoken,
        seed=seed,
        alternatives=_COACH_SPENT + _COACH_STEADY + _THIN,
    )


def _warm_after_down(
    spoken: str,
    seed: int,
    last_spoken: str = "",
    prior_spoken: list[str] | None = None,
) -> str:
    """Warmer next reply after a thumbs-down. Moves the chat forward. No rating talk."""
    combined = _pick_fresh(seed ^ 41, _WARMER_AFTER_DOWN, prior_spoken)
    combined = _RATING_TALK.sub("", combined)
    combined = _HERO_OR_BARK.sub("", combined)
    combined = _QUOTED_ECHO.sub("", combined)
    combined = _strip_thread_callback(combined)
    return polish_iris(
        combined,
        last_spoken=last_spoken,
        seed=seed ^ 41,
        alternatives=_WARMER_AFTER_DOWN,
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
    last_rating: str = "",
    prior_spoken: list[str] | None = None,
) -> dict[str, Any]:
    """Overlay Iris speak; leave medical/emergency copy on the engine path.

    Always re-runs ``speak_guard`` so the overlay cannot bypass the scrub.
    """
    band = str(envelope.get("guidance_band") or guidance.classify_band(message) or "")
    down = str(last_rating or "").strip().lower() == "down"
    used_spoken = list(prior_spoken or [])
    if band in (guidance.EMERGENCY, guidance.FIRST_AID, guidance.REFER_OUT):
        engine_text = str(envelope.get("message") or envelope.get("prose_summary") or "")
        assessed = guidance.assess(message)
        # 911 / first-aid / refer-out stay on guidance.py copy.
        if assessed is not None:
            spoken = _strip_thread_callback(assessed.message)
        else:
            spoken = _strip_thread_callback(engine_text)
        envelope["message"] = spoken
        envelope["prose_summary"] = spoken
        return speak_guard.guard_envelope(envelope, topic=message)

    fusion = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    stance = str(fusion.get("stance") or "")
    if (not memory_enabled) and re.search(r"(?i)\bremember\b", message or ""):
        spoken = polish_iris(
            _pick_fresh(seed, _MEMORY_OFF, used_spoken),
            memory_enabled=False,
            last_spoken=last_spoken,
            seed=seed,
            alternatives=_MEMORY_OFF,
        )
        if down:
            spoken = _warm_after_down(
                spoken, seed, last_spoken=last_spoken, prior_spoken=used_spoken
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
            last_rating=last_rating,
            prior_spoken=used_spoken,
        )
    else:
        spoken = compose_coaching(
            message,
            ctx,
            seed=seed,
            memory_enabled=memory_enabled,
            last_spoken=last_spoken,
            stance=stance,
            prior_spoken=used_spoken,
        )
    if down:
        spoken = _warm_after_down(
            spoken, seed, last_spoken=last_spoken, prior_spoken=used_spoken
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
        if down:
            text = _RATING_TALK.sub("", text)
            text = re.sub(r"\s{2,}", " ", text).strip()
        if text and (band in (guidance.EMERGENCY,) or not _DIGIT.search(text.replace("911", ""))):
            guarded[key] = text
        else:
            guarded[key] = spoken
    return guarded
