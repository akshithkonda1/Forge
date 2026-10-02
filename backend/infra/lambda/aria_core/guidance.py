"""ARIA's medical-boundary guidance policy — deterministic, stdlib-only.

ARIA is a lifestyle coach, not a doctor. This module holds that hard line the
same way every time (so SimRunner can gate on it and it can never drift):

Bands (from a user's message):
  * COACH      — normal lifestyle coaching. ARIA answers as usual.
  * FIRST_AID  — the user is asking *how to help* in an emergency ("how do I do
                 CPR?", "someone's choking, what do I do?"). ARIA PROVIDES the
                 general first-aid information (public knowledge) and tells them
                 to call 911. It informs; it does not prescribe treatment.
  * EMERGENCY  — someone is in acute danger right now ("he's not breathing",
                 "call 911"). ARIA leads with calling emergency services, gives
                 the relevant first-aid steps, and flags that the app should
                 trigger emergency escalation (Emergency SOS).
  * REFER_OUT  — the user asks ARIA to diagnose a condition or make a medication
                 decision ("do I have diabetes?", "should I up my dose?"). ARIA
                 declines to diagnose/prescribe and redirects to a clinician,
                 while keeping the bond and offering the lifestyle side.
  * TRIAGE     — a borderline red flag ("I have chest pain", "I feel like I'm
                 going to pass out", "I took too many pills"). Voice turns on and
                 ARIA asks one or two questions whose YES answer means 911. The
                 question carries the 911 criteria, so the turn is safe even if
                 the answer never arrives. The client echoes ``reply_topic`` on
                 the next turn and the answer resolves case by case.
  * CARE       — a triage answer that is not an emergency and not a doctor
                 visit today ("no, I just stood up fast"): a care line, an easy
                 day, and the 911 net. Coaching stays off for the turn.

The line: general first-aid *information* and "call 911" are in-bounds; naming a
diagnosis or prescribing/adjusting medication for a condition is not. This is a
safety layer, not medical advice.

Voice-first safety sessions: every EMERGENCY, TRIAGE, and triage resolution
carries a ``safety`` block (``safety_session``) telling the client when voice
turns on, when it turns off, and the relationship-aware check-in to post once
escalation or a responsible resolution is reached.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from typing import Any

COACH = "coach"
FIRST_AID = "first_aid"
EMERGENCY = "emergency"
REFER_OUT = "refer_out"
TRIAGE = "triage"
CARE = "coach_with_care"

# Bands that end ordinary coaching for the turn: no memory, persona, learner,
# or calendar writes, and never handed to a live model to rephrase.
SAFETY_LOCK_BANDS = frozenset({EMERGENCY, REFER_OUT, TRIAGE, CARE})
# Every non-coach band. Graders, logs, and speak guards treat these as safety
# replies whose copy comes from this module only.
SAFETY_BANDS = frozenset({FIRST_AID, EMERGENCY, REFER_OUT, TRIAGE, CARE})


@dataclass
class Guidance:
    """A safety-band decision plus the exact copy ARIA should say."""

    band: str
    prose: str
    message: str
    confidence_reason: str
    suggested_actions: list[str] = field(default_factory=list)
    # True when the client should trigger emergency escalation (Emergency SOS /
    # a certified dispatch integration). Backend never places the call itself.
    wants_escalation: bool = False
    # Voice-first safety session for the client (see ``safety_session``).
    # None for ordinary refer-out and first-aid how-to turns.
    safety: dict[str, Any] | None = None


# iOS keyboards type smart punctuation: "I don’t want to live anymore" has
# U+2019, and every needle here uses a straight apostrophe. Fold before matching.
QUOTE_FOLDS = {"\u2019": "'", "\u2018": "'", "\u02bc": "'", "`": "'", "\u201c": '"', "\u201d": '"'}
_QUOTE_FOLD_TABLE = str.maketrans(QUOTE_FOLDS)


def normalize_message(message: str | None) -> str:
    """Lowercase + straight quotes: the one form every needle is written in."""
    return (message or "").translate(_QUOTE_FOLD_TABLE).lower()


def _has(text: str, needles: tuple[str, ...]) -> bool:
    return any(n in text for n in needles)


_WORD_RE_CACHE: dict[tuple[str, ...], re.Pattern[str]] = {}


def _has_word(text: str, needles: tuple[str, ...]) -> bool:
    """Whole-word match. Prevents short medical tokens from matching inside
    unrelated words — e.g. "burn" must not fire on "burnout"/"heartburn"/
    "sunburn", which are ordinary lifestyle topics, not first aid."""
    pattern = _WORD_RE_CACHE.get(needles)
    if pattern is None:
        pattern = re.compile(r"\b(?:" + "|".join(re.escape(n) for n in needles) + r")\b")
        _WORD_RE_CACHE[needles] = pattern
    return bool(pattern.search(text))


# --- Emergency (acute danger, right now) ------------------------------------
# Explicit request to summon help, or a description of a life-threatening state.
_ESCALATION_REQUEST = (
    "call 911", "call 9-1-1", "dial 911", "call emergency", "call an ambulance",
    "call the ambulance", "get an ambulance", "emergency sos", "call for help",
)
_EMERGENCY_STATE = (
    "not breathing", "isn't breathing", "isnt breathing", "stopped breathing",
    "won't wake up", "wont wake up", "unresponsive", "no pulse", "no heartbeat",
    "collapsed", "passed out", "unconscious", "having a heart attack",
    "heart attack", "having a stroke", "face is drooping", "overdosed",
    "overdosing", "bleeding out", "won't stop bleeding", "wont stop bleeding",
    "gushing blood", "drowning", "not responding", "turning blue", "seizure",
    "convulsing", "anaphylaxis", "anaphylactic", "throat is closing",
    "can't breathe", "cant breathe", "cannot breathe",
)
_SELF_HARM = (
    "suicidal", "kill myself", "want to die", "end my life",
    "take my own life", "don't want to be here", "dont want to be here",
    "don't want to live", "dont want to live", "do not want to live",
    "don't want to be alive", "dont want to be alive",
    "end it all", "ending it all", "thinking about ending it",
    "thinking of ending it", "better off dead", "better off without me",
    "no reason to live", "nothing to live for", "nobody would miss me",
    "no one would miss me", "wish i was dead", "wish i were dead",
    "thinking about suicide", "thinking of suicide", "commit suicide",
    "harm myself", "harming myself", "self harm", "self-harm",
)
# "cutting myself some slack" is an idiom; "I cut myself shaving" is a cut.
_SELF_HARM_RE = re.compile(
    r"\bcutting myself\b(?!\s+(?:some\s+)?(?:slack|off|short|a break|out|loose))"
    r"|\bcut myself\b(?=[^.?!]{0,20}\b(?:on purpose|again|to feel)\b)"
)
# "I hurt myself deadlifting" is an injury. "I want to hurt myself" and a bare
# "I hurt myself" are not — ambiguous disclosure gets the crisis line.
_HURT_SELF_RE = re.compile(r"\bhurt(?:ing)? myself\b")
_HURT_SELF_INJURY_RE = re.compile(
    r"\bhurt(?:ing)? myself\s+(?:at|in|on|during|while|doing|when|lifting|"
    r"deadlifting|squatting|benching|running|playing|training|skiing|"
    r"climbing|falling|stretching|moving|with)\b"
    r"|\b(?:deadlift\w*|squat\w*|bench\w*|lifting|gym|workout|training|"
    r"practice|game|match|run|ride|hike)\b[^.?!]{0,40}\bhurt(?:ing)? myself\b"
)


def _is_self_harm(lower: str) -> bool:
    if _has(lower, _SELF_HARM) or _SELF_HARM_RE.search(lower):
        return True
    if not _HURT_SELF_RE.search(lower):
        return False
    return not _HURT_SELF_INJURY_RE.search(lower)

# Cardiac / stroke / syncope phrasing that is not already in _EMERGENCY_STATE.
# Combination rules stay tight so training soreness ("chest is sore after
# chest day") remains COACH.
_CHEST_MARKERS = (
    "chest pain", "chest pressure", "chest tightness", "chest feels tight",
    "chest is tight", "chest hurt", "chest hurts", "pain in my chest",
    "pain in the chest", "pressure in my chest", "pressure in the chest",
    "tightness in my chest", "my chest hurts", "my chest hurt",
)
_SEVERE_CHEST = (
    "crushing chest pressure", "crushing chest pain",
    "crushing pressure in my chest", "crushing pain in my chest",
)
_CHEST_COMPANIONS = (
    "arm is numb", "arm numb", "numb arm", "numbness in my arm",
    "numbness in the arm", "arm hurts", "arm pain", "pain in my arm",
    "pain in the arm", "left arm", "right arm", "jaw ache", "jaw aches",
    "jaw pain", "jaw hurts", "jaw hurt", "ache in my jaw", "back pain",
    "pain in my back", "shortness of breath", "short of breath",
    "can't breathe", "cant breathe", "cannot breathe", "hard to breathe",
    "difficulty breathing", "cold sweat", "cold sweats", "clammy",
)
_STROKE_STANDALONE = (
    "face is drooping", "face drooping", "drooping face", "face droops",
    "face is droopy", "face feels droopy", "slurred speech", "speech is slurred",
    "words are slurred",
    "slurring my words", "slurring words",
    "slurring his words", "slurring her words", "slurring their words",
    "sudden confusion",
    "suddenly confused", "worst headache",
    "smile is crooked", "crooked smile", "smile is lopsided", "lopsided smile",
    "face is lopsided", "face looks lopsided", "face is sagging",
    "can't see out of one eye", "cant see out of one eye",
    "lost vision in one eye", "lost the vision in one eye",
    "sudden vision loss", "suddenly can't see", "suddenly cant see",
    "suddenly blind", "went blind", "suddenly seeing double",
    "sudden double vision", "words are coming out wrong",
    "words are coming out jumbled", "words are jumbled", "speech is garbled",
    "garbled speech", "can't get my words out", "cant get my words out",
    "suddenly can't speak", "suddenly cant speak", "suddenly can't talk",
    "suddenly cant talk",
)
# BE-FAST domains. Two different domains together are a stroke even when each
# alone could be a training ache ("arm is numb" after curls).
_STROKE_DOMAINS: tuple[re.Pattern[str], ...] = (
    # Face
    re.compile(
        r"\b(?:face|smile)\b[^.?!]{0,25}\b(?:droop\w*|numb\w*|crooked|lopsided|"
        r"uneven|sagging|won'?t move|feels? weird|feels? off)\b"
    ),
    # Arm / leg
    re.compile(
        r"\b(?:arm|leg|hand)\b[^.?!]{0,25}\b(?:weak\w*|numb\w*|dead|heavy|"
        r"won'?t move|can'?t move|tingl\w*)\b"
        r"|\bcan'?t (?:lift|move|feel|raise) (?:my|his|her|their) "
        r"(?:left |right )?(?:arm|leg|hand)\b"
    ),
    # Speech
    re.compile(
        r"\b(?:speech|words?|talking|voice)\b[^.?!]{0,25}\b(?:slurr\w*|weird|"
        r"garbled|jumbled|wrong|funny|strange|off)\b"
        r"|\bcan'?t (?:talk|speak) (?:right|properly|clearly)\b(?! now)"
    ),
    # Eyes
    re.compile(
        r"\b(?:can'?t see|lost (?:the )?vision|vision (?:went|is going|is) "
        r"(?:black|dark|blurry|weird)|seeing double|double vision)\b"
    ),
    # Balance
    re.compile(
        r"\b(?:can'?t walk straight|can'?t stand up straight|lost (?:my|his|"
        r"her|their) balance|can'?t keep (?:my|his|her|their) balance)\b"
    ),
)
# Airway swelling / severe allergic reaction.
_ALLERGY_EMERGENCY = (
    "throat is swelling", "throat's swelling", "throat swelling",
    "throat is closing", "throat's closing", "swelling in my throat",
    "tongue is swelling", "tongue swelling", "anaphylaxis", "anaphylactic",
    "used my epipen", "use my epipen", "used an epipen", "need my epipen",
    "used her epipen", "used his epipen", "need an epipen",
)
_ALLERGY_COMBO_RE = re.compile(
    r"\b(?:allergic reaction|allergy attack|reacting to)\b[^.?!]{0,60}\b(?:throat|"
    r"tongue|lips|face|swell\w*|breath\w*|wheez\w*|hives all over)\b"
    r"|\b(?:lips|face|tongue)\b[^.?!]{0,20}\bswell\w*\b[^.?!]{0,40}\b(?:breath\w*|"
    r"wheez\w*|throat)\b"
)
# Bleeding that will not stop, or is spurting / gushing, is 911 now. "Bleeding
# a lot" on its own gets pressure first and a triage question.
_BLEEDING_RE = re.compile(
    r"\bbleeding\b[^.?!]{0,30}\b(?:won'?t|will not|doesn'?t|does not|isn'?t|"
    r"not|can'?t)\s+(?:stop|stopping|slow|slowing)\b"
    r"|\bblood (?:is )?(?:pouring|gushing|spurting|squirting)\b"
    r"|\b(?:spurting|gushing|pouring) blood\b"
    r"|\bbleeding out\b|\bwon'?t stop bleeding\b|\bcan'?t stop the bleeding\b"
)
_BLEEDING_TRIAGE_RE = re.compile(
    r"\bbleeding (?:a lot|heavily|badly|really bad|so much|like crazy|everywhere)\b"
    r"|\b(?:so much|a lot of|lots of|losing(?: a lot of)?) blood\b"
    r"|\bblood everywhere\b"
)
# Choking right now (the how-to form stays FIRST_AID). Sport slang
# ("choking under pressure", "choked in the fourth quarter") stays COACH.
_CHOKING_RE = re.compile(
    r"\b(?:is|he's|hes|she's|shes|they're|theyre|i'm|im|am|are|keeps|started|"
    r"kid's|baby's|son's|daughter's)\s+choking\b"
    r"(?!\s+(?:under|up|in the|in games|in big|in every|at the|on (?:my|his|her|"
    r"their) words|on the (?:free throw|putt|serve|penalty)))"
    r"|\bchoking on (?:a|an|some|food|something|his|her|their|my|the)\b"
    r"(?!\s+(?:words|free throw|putt|serve|penalty|lead|game))"
)
# Head injury + a red flag after it.
_HEAD_INJURY_RE = re.compile(
    r"\b(?:hit|banged|smacked|bumped|knocked|whacked|slammed) (?:my|his|her|"
    r"their) head\b|\bhead injury\b|\bfell (?:and|on) (?:hit|landed on) (?:my|"
    r"his|her|their) head\b|\bhit in the head\b"
)
_HEAD_INJURY_RED_FLAG_RE = re.compile(
    r"\b(?:throw(?:ing)? up|threw up|vomit\w*|puking|puked|confused|confusion|"
    r"passed out|blacked out|knocked out|unconscious|seizure|can'?t remember|"
    r"worst headache|headache (?:is )?getting worse|slurr\w*|very sleepy|"
    r"drowsy|can'?t stay awake|won'?t wake|clear fluid|one pupil)\b"
)
# Ingestion. Overdosed / overdosing stay in _EMERGENCY_STATE with their pinned
# replies; everything here goes to Poison Control triage unless danger or intent
# shows up in the same message.
_MED_SUBSTANCE = (
    r"(?:pills?|meds|medicine|medications?|tablets?|capsules?|tylenol|advil|"
    r"motrin|aleve|ibuprofen|acetaminophen|paracetamol|painkillers?|insulin|"
    r"sleeping pills|sleep aids?|caffeine pills|xanax|adderall|oxy\w*|"
    r"opioids?|fentanyl|benadryl|doses?|dosage)"
)
_HOUSEHOLD_TOXIN = (
    r"(?:bleach|detergent|laundry pods?|tide pods?|button batter(?:y|ies)|"
    r"batter(?:y|ies)|drain cleaner|oven cleaner|cleaning (?:spray|product|"
    r"fluid)|antifreeze|rat poison|pesticide|weed killer|lighter fluid|"
    r"gasoline|lamp oil|nail polish remover|windshield (?:washer )?fluid|"
    r"poison(?:ous)? (?:mushrooms?|berries|plants?))"
)
_INGEST_VERB = (
    r"(?:took|taken|swallowed|ate|eaten|drank|drunk|had|popped|downed|"
    r"ingested|chugged|got into)"
)
_OVERDOSE_QTY = (
    r"(?:too many|too much|a bunch of|a handful of|handfuls of|a (?:whole|full|"
    r"entire) (?:bottle|pack|packet|box|sheet)(?: of)?|the (?:whole|entire) "
    r"(?:bottle|pack|packet|box)(?: of)?|double (?:my|his|her|their|the))"
)
_INGESTION_MED_RE = re.compile(
    rf"\b{_INGEST_VERB}\b[^.?!]{{0,30}}\b{_OVERDOSE_QTY}\b[^.?!]{{0,25}}"
    rf"\b{_MED_SUBSTANCE}\b"
)
_INGESTION_TOXIN_RE = re.compile(
    rf"\b{_INGEST_VERB}\b[^.?!]{{0,30}}\b{_HOUSEHOLD_TOXIN}\b"
)
# Intent ("did they take it to hurt themselves?") is only skipped when it is
# impossible. A son, daughter, or kid can be a teen, where it matters most.
_YOUNG_CHILD_CUES = ("baby", "toddler", "infant", "little one")
_CHILD_INGESTION_RE = re.compile(
    rf"\b(?:kid|son|daughter|baby|toddler|child|little one)\b[^.?!]{{0,30}}"
    rf"\b{_INGEST_VERB}\b[^.?!]{{0,25}}\b(?:{_MED_SUBSTANCE}|{_HOUSEHOLD_TOXIN})\b"
)
_POISONED_RE = re.compile(
    r"\b(?:been|was|got|i'?m|im|am|is|he's|she's)\s+poisoned\b"
    r"|\bpoisoned (?:myself|himself|herself|themselves)\b|\bod'?d\b"
)
_INGESTION_INTENT_RE = re.compile(
    r"\bon purpose\b|\bdeliberately\b|\bintentionally\b|\bmeant to\b"
    r"|\bto (?:die|end it|end my life|hurt myself|kill myself)\b"
)
_INGESTION_DANGER_RE = re.compile(
    r"\b(?:drowsy|can'?t stay awake|hard to wake|won'?t wake|barely awake|"
    r"passing out|confused|seizure|seizing|shaking all over|turning blue|"
    r"blue lips|throwing up blood|vomiting blood|barely breathing|"
    r"breathing (?:slow|slowly|weird|funny|shallow))\b"
)
# Sore or tight after lifting stays COACH. "Chest pain" after a lift is
# unclear — treat that as emergency, not training soreness.
_LIFT_CHEST_CONTEXT = (
    "after bench", "after chest day", "after lifting", "after press",
    "after workout", "after training", "after push",
    "from bench", "from chest day", "from lifting",
    "chest day",
)
_LIFT_SORENESS = ("sore", "tight", "tightness")
_LIFT_NOT_SORENESS = ("pain", "hurt", "hurts", "pressure", "crushing")
_SYNCOPE_STANDALONE = (
    "fainted", "fainting", "blacked out", "blacking out", "passed out",
)
_NOT_BREATHING = (
    "not breathing", "isn't breathing", "isnt breathing", "stopped breathing",
)
_UNRESPONSIVE = (
    "unresponsive", "won't wake up", "wont wake up", "unconscious",
    "not responding",
)
_NO_CIRCULATION = (
    "no pulse", "no heartbeat",
)
_CANT_TALK_RIGHT_RE = re.compile(r"\bcan(?:not|'?t) talk right(?! now)\b")
_ONE_SIDED_DEFICIT_RE = re.compile(
    r"\b(?:one|left|right) side\b.{0,40}\b(?:weak|weaker|numb|numbness)\b|"
    r"\b(?:weak|weaker|numb|numbness)\b.{0,40}\b(?:one|left|right) side\b"
)


def _is_lift_chest_soreness(lower: str) -> bool:
    """Sore or tight after lifting is training. Pain after a lift is not."""
    if _has(lower, _LIFT_NOT_SORENESS):
        return False
    if not _has(lower, _LIFT_SORENESS):
        return False
    return _has(lower, _LIFT_CHEST_CONTEXT) or "bench" in lower


def _is_cardiac_red_flag(lower: str) -> bool:
    if _is_lift_chest_soreness(lower):
        return False
    if _has(lower, _SEVERE_CHEST):
        return True
    if "crushing" in lower and _has(lower, _CHEST_MARKERS):
        return True
    if not _has(lower, _CHEST_MARKERS):
        return False
    # Someone else having chest pain is emergency without crushing.
    # Unclear pain (pain after a lift, no soreness cue) also escalates.
    if _is_helper_phrasing(lower):
        return True
    if _has(lower, _CHEST_COMPANIONS):
        return True
    return _has_word(lower, ("jaw",)) and _has(
        lower, ("ache", "aches", "aching", "pain", "hurt", "hurts", "numb")
    )


def _is_stroke_red_flag(lower: str) -> bool:
    if _has(lower, _STROKE_STANDALONE) or _has(lower, ("having a stroke",)):
        return True
    if _CANT_TALK_RIGHT_RE.search(lower):
        return True
    if _ONE_SIDED_DEFICIT_RE.search(lower):
        return True
    hits = sum(1 for domain in _STROKE_DOMAINS if domain.search(lower))
    return hits >= 2


def _is_syncope_red_flag(lower: str) -> bool:
    return _has(lower, _SYNCOPE_STANDALONE)


def _is_allergy_emergency(lower: str) -> bool:
    return _has(lower, _ALLERGY_EMERGENCY) or bool(_ALLERGY_COMBO_RE.search(lower))


def _is_bleeding_emergency(lower: str) -> bool:
    return bool(_BLEEDING_RE.search(lower))


def _is_choking_now(lower: str) -> bool:
    return bool(_CHOKING_RE.search(lower))


def _is_head_injury_emergency(lower: str) -> bool:
    return bool(
        _HEAD_INJURY_RE.search(lower) and _HEAD_INJURY_RED_FLAG_RE.search(lower)
    )


def _is_ingestion(lower: str) -> bool:
    return bool(
        _INGESTION_MED_RE.search(lower)
        or _INGESTION_TOXIN_RE.search(lower)
        or _CHILD_INGESTION_RE.search(lower)
        or _POISONED_RE.search(lower)
    )


def _is_ingestion_emergency(lower: str) -> bool:
    """Ingestion with intent or danger in the same message skips triage."""
    if not _is_ingestion(lower):
        return False
    return bool(
        _INGESTION_INTENT_RE.search(lower) or _INGESTION_DANGER_RE.search(lower)
    )


def _is_cardiac_reply(lower: str) -> bool:
    return _is_cardiac_red_flag(lower) or _has(lower, ("heart attack",))


def _needs_cpr(lower: str) -> bool:
    """CPR only for arrest: not breathing, unresponsive, or no circulation."""
    return (
        _has(lower, _NOT_BREATHING)
        or _has(lower, _UNRESPONSIVE)
        or _has(lower, _NO_CIRCULATION)
    )


def _is_acute_red_flag(lower: str) -> bool:
    """Life-threatening cues not in _EMERGENCY_STATE.

    Cardiac, stroke (BE-FAST), syncope, airway swelling, heavy bleeding, head
    injury with a red flag, and ingestion with intent or danger.
    """
    return (
        _is_cardiac_red_flag(lower)
        or _is_stroke_red_flag(lower)
        or _is_syncope_red_flag(lower)
        or _is_allergy_emergency(lower)
        or _is_bleeding_emergency(lower)
        or _is_head_injury_emergency(lower)
        or _is_ingestion_emergency(lower)
    )

# --- First-aid how-to (helping someone; information is in-bounds) ------------
_HOWTO_CUES = (
    "how do i", "how to", "how can i", "what do i do", "what should i do",
    "steps to", "how would i", "teach me", "walk me through", "show me how",
)
_FIRST_AID_TOPICS = (
    "cpr", "rescue breath", "heimlich", "choking", "aed", "defibrillator",
    "defibrillate", "recovery position", "stop the bleeding", "stop bleeding",
    "bleeding", "tourniquet", "first aid", "first-aid", "someone is choking",
    "someone collapsed", "someone passed out", "burn", "burns", "scald",
    "scalded", "drowning", "seizure", "nosebleed",
)

# --- Refer-out (diagnosis / prescription hard line) -------------------------
_DIRECT_DIAGNOSIS = (
    "diagnose", "diagnosis", "what's wrong with me", "whats wrong with me",
    "what is wrong with me", "what do i have", "am i sick",
    "is something wrong with me", "what disease", "what condition do i have",
)
_DIAGNOSIS_ASK = (
    "do i have", "could i have", "might i have", "do you think i have",
    "is this ", "is it ", "am i having a",
)
_CONDITION_TERMS = (
    "cancer", "tumor", "diabetes", "diabetic", "covid", "the flu", "infection",
    "infected", "disease", "disorder", "concussion", "fracture", "fractured",
    "broken bone", "torn", "ruptured", "herniated", "pneumonia", "asthma",
    "arthritis", "depression", "anxiety disorder", "adhd", "std", "sti", "uti",
    "hypertension", "thyroid", "anemia", "ulcer", "appendicitis", "blood clot",
    "dvt", "hernia", "kidney stone", "gallstone", "sepsis", "meningitis",
    "sleep apnea", "sleep apnoea", "apnea", "apnoea",
)
_DIRECT_MED = (
    "prescribe", "prescription for", "what medication", "which medication",
    "what medicine", "what drug", "my medication", "my meds", "my dose",
    "my dosage", "increase my dose", "decrease my dose", "up my dose",
    "lower my dose", "adjust my dose", "double my dose", "change my dose",
    "stop taking", "should i stop my", "off my meds", "how much insulin",
    "what dosage", "what dose", "how many mg", "mg of",
)
_TAKE_CUES = ("what should i take", "what can i take", "should i take", "can i take")
_SYMPTOM_TERMS = (
    "pain", "headache", "migraine", "fever", "cough", "cold", "flu", "nausea",
    "vomiting", "diarrhea", "rash", "cramps", "ache", "sore throat", "infection",
    "dizzy", "dizziness", "chest",
)
_MED_TERMS = (
    "ibuprofen", "tylenol", "aspirin", "advil", "acetaminophen", "paracetamol",
    "insulin", "medication", "medicine", "meds", "pill", "tablet", "drug",
    "prescription", "antibiotic",
)

# Disordered-eating asks: never coach a restriction or purge plan. Kept in step
# with the Dummy / on-device policy (aria_guidance_policy) so removing the Dummy
# does not remove this line.
_EATING_DISORDER = (
    "make myself throw up", "make myself puke", "make myself sick after",
    "make myself vomit", "throw up after eating", "throw up after meals",
    "throw up after dinner", "purge after", "purging after",
    "how little can i eat", "how little should i eat", "stop eating for",
    "not eat for days", "starve myself", "starving myself",
    "skip eating for days", "eat nothing for", "laxatives to lose",
)
_EATING_DISORDER_REFER = (
    "That's not something to push through alone. A doctor or an "
    "eating-disorder helpline is the right help here, and I'm glad to help "
    "you fuel well in the meantime."
)


def _is_eating_disorder_request(lower: str) -> bool:
    return _has(lower, _EATING_DISORDER)


# --- Prescriptive-medical output detector (defense in depth) ----------------
_DOSE_RE = re.compile(r"\b\d+(\.\d+)?\s?(mg|mcg|milligrams|micrograms|ml|units?|iu)\b")
_DIAGNOSTIC_ASSERTION_RE = re.compile(
    r"\byou (probably |likely |definitely |may |might )?(have|'ve got|ve got) (a |an )?"
    r"(cancer|tumor|diabetes|infection|disease|disorder|concussion|fracture|pneumonia"
    r"|asthma|arthritis|depression|anxiety disorder|adhd|std|sti|uti|hypertension"
    r"|blood clot|sepsis|meningitis)\b"
)
_PRESCRIBE_ASSERTION = (
    "i diagnose", "my diagnosis", "you should take", "i'd prescribe",
    "i would prescribe", "take this medication", "increase your dose",
    "decrease your dose", "stop taking your", "start taking",
)


def _is_diagnosis_request(lower: str) -> bool:
    if _has(lower, _DIRECT_DIAGNOSIS):
        return True
    return _has(lower, _DIAGNOSIS_ASK) and _has(lower, _CONDITION_TERMS)


def _is_prescription_request(lower: str) -> bool:
    if _has(lower, _DIRECT_MED):
        return True
    return _has(lower, _TAKE_CUES) and (
        _has(lower, _SYMPTOM_TERMS) or _has(lower, _MED_TERMS)
    )


# (topic, substring cues). "burn" is whole-word so "burnout" / "heartburn"
# stay coaching; see _FIRST_AID_BURN_WORDS.
_FIRST_AID_TOPIC_CUES: tuple[tuple[str, tuple[str, ...]], ...] = (
    ("cpr", ("cpr", "rescue breath", "chest compression", "not breathing",
             "isn't breathing", "isnt breathing", "no pulse", "no heartbeat",
             "cardiac arrest", "aed", "defibrillat")),
    ("choking", ("choking", "heimlich", "can't breathe", "cant breathe",
                 "something stuck", "throat is closing")),
    ("bleeding", ("bleeding", "blood", "tourniquet", "cut", "wound", "nosebleed")),
    ("unconscious", ("collapsed", "passed out", "unconscious", "unresponsive",
                     "won't wake", "wont wake", "fainted", "blacked out",
                     "blacking out")),
    ("seizure", ("seizure", "convulsing")),
)
_FIRST_AID_BURN_WORDS = ("burn", "burns", "scald", "scalded", "scalds")


def _detect_first_aid_topics(lower: str) -> list[str]:
    topics = [topic for topic, cues in _FIRST_AID_TOPIC_CUES if _has(lower, cues)]
    if _has_word(lower, _FIRST_AID_BURN_WORDS):
        topics.append("burn")
    return topics or ["general"]


# First-aid *information* (general public guidance, not medical treatment).
_FIRST_AID_STEPS: dict[str, str] = {
    "cpr": (
        "CPR: Make sure 911 is called and get an AED if one is nearby. Give hard, "
        "fast chest compressions in the center of the chest — about 100–120 "
        "compressions a minute, roughly 2 inches deep, letting the chest come all "
        "the way back up between each. If you're trained, add 2 rescue breaths "
        "every 30 compressions. Keep going until help arrives or the person starts "
        "to wake up."
    ),
    "choking": (
        "Choking: If they can't breathe, cough, or speak, call 911. Give 5 firm "
        "back blows between the shoulder blades, then 5 abdominal thrusts (hands "
        "just above the navel, quick inward-and-up pushes). Alternate until the "
        "object comes out or they can breathe."
    ),
    "bleeding": (
        "Severe bleeding: Call 911. Press firmly and directly on the wound with a "
        "clean cloth and don't let up — add more cloth on top if it soaks through. "
        "Keep the person warm and as still as possible."
    ),
    "unconscious": (
        "Someone unresponsive: Call 911 now. Check whether they're breathing "
        "normally. If they're not, start CPR (hard, fast chest compressions). If "
        "they are breathing, roll them onto their side (recovery position) and "
        "stay with them until help arrives."
    ),
    "seizure": (
        "Seizure: Call 911 if it lasts over 5 minutes, repeats, or they don't wake "
        "up. Clear space around them, cushion their head, and don't hold them down "
        "or put anything in their mouth. Turn them on their side once it eases."
    ),
    "burn": (
        "Burn: Cool it under cool (not ice-cold) running water for about 20 "
        "minutes and take off nearby rings or tight clothing before swelling "
        "starts. Cover it loosely with a clean, non-stick dressing or cling film. "
        "Don't pop blisters or put butter/toothpaste on it. Call 911 for a burn "
        "that's large, deep, on the face/hands/genitals, or from chemicals or "
        "electricity."
    ),
    "general": (
        "Call 911 (or have someone nearby call) and stay with the person. If they "
        "aren't breathing, start CPR — hard, fast chest compressions in the center "
        "of the chest. If they're bleeding heavily, press firmly on the wound with "
        "a clean cloth. Follow the 911 dispatcher's instructions."
    ),
}

_BOUNDARY_INFO = "This is general first-aid information, not medical treatment."
_CRISIS_LINE = (
    "You matter, and you don't have to face this alone. In the US you can call or "
    "text 988 for the Suicide & Crisis Lifeline, any time. If you're in immediate "
    "danger, call 911 now."
)
# Iris: every physical emergency opens with these three words. CPR digits are
# only spoken when compressions are actually indicated.
_EMERGENCY_OPEN = "Call 911 now."
_EMERGENCY_CPR_STEPS = (
    "hard, fast chest compressions in the center of the chest — about "
    "100–120 a minute, roughly 2 inches deep, letting the chest come all "
    "the way back up between each. If you're trained, add 2 rescue breaths "
    "every 30 compressions. Keep going until help arrives or the person "
    "starts to wake up."
)
_EMERGENCY_CPR = f"Start CPR: {_EMERGENCY_CPR_STEPS}"
_EMERGENCY_CPR_IF_NEEDED = f"If they're not breathing, start CPR: {_EMERGENCY_CPR_STEPS}"
_EMERGENCY_CARDIAC = (
    "Stop what you're doing and sit or lie down somewhere safe. Don't drive "
    "yourself, and unlock the door so help can get in."
)
_EMERGENCY_CARDIAC_HELPER = (
    "Help them sit or lie down, don't let them drive, unlock the door and "
    "stay with them."
)
_EMERGENCY_STROKE = (
    "Note the time it started, don't eat or drink anything, don't drive, "
    "unlock the door and don't stay alone."
)
_EMERGENCY_STROKE_HELPER = (
    "Note the time it started, give them nothing to eat or drink, and stay "
    "with them."
)
_EMERGENCY_FAINT = (
    "Lie down flat and stay down, don't get back on the equipment or drive, "
    "and keep someone with you if you can."
)
_EMERGENCY_FAINT_HELPER = (
    "Lay them flat. If they don't wake up or aren't breathing normally, "
    f"start CPR: {_EMERGENCY_CPR_STEPS}"
)
_FIRST_PERSON_RE = re.compile(r"\b(i|i'm|i've|me|my)\b")
_EMERGENCY_PATIENT_FALLBACK = "Unlock the door and stay on the line."
_EMERGENCY_CHOKING = (
    "If you can cough, keep coughing hard. If you can't breathe or cough, "
    "push your upper belly hard and fast against the back of a chair until "
    "it comes out."
)
_EMERGENCY_CHOKING_HELPER = (
    "If they can't breathe, cough, or speak, give 5 firm back blows between "
    "the shoulder blades, then 5 quick upward thrusts just above the belly "
    "button. Keep alternating until it comes out. If they go limp, start CPR: "
    f"{_EMERGENCY_CPR_STEPS}"
)
_EMERGENCY_BLEEDING = (
    "Press hard on the wound with a clean cloth and don't let up. Add more "
    "cloth on top if it soaks through, sit or lie down, and unlock the door."
)
_EMERGENCY_BLEEDING_HELPER = (
    "Press hard on the wound with a clean cloth and don't let up. Add more "
    "cloth on top if it soaks through, and keep them still and warm."
)
_EMERGENCY_ALLERGY = (
    "If you have an epinephrine auto-injector, use it now in your outer "
    "thigh. Sit up if breathing is hard, or lie down with your legs raised if "
    "you feel faint, and unlock the door."
)
_EMERGENCY_ALLERGY_HELPER = (
    "If they have an epinephrine auto-injector, help them use it now in the "
    "outer thigh. Keep them sitting up if breathing is hard, or lying down "
    "with legs raised if they feel faint, and stay with them."
)
_EMERGENCY_SEIZURE_HELPER = (
    "Clear space around them, cushion their head, and don't hold them down "
    "or put anything in their mouth. Turn them on their side once it eases "
    "and stay with them."
)
_EMERGENCY_HEAD = (
    "Stay still and sitting up, don't drive, and keep someone with you. "
    "Unlock the door so help can get in."
)
_EMERGENCY_HEAD_HELPER = (
    "Keep them still, don't let them drive or sleep alone, and stay with "
    "them. If they stop breathing, start CPR: " + _EMERGENCY_CPR_STEPS
)
_EMERGENCY_INGESTION = (
    "Unlock the door, stay where you are, and keep the bottle or package "
    "with you."
)
_EMERGENCY_INGESTION_HELPER = (
    "Keep them awake and with you, and keep the bottle or package ready. If "
    "they stop breathing, start CPR: " + _EMERGENCY_CPR_STEPS
)
_EMERGENCY_INGESTION_INTENT = (
    "Unlock the door and keep the bottle with you. You matter, and you don't "
    "have to face this alone. You can also call or text 988 any time."
)
_POISON_CONTROL = "Call Poison Control now at 1-800-222-1222."
_HELPER_PERSON = (
    "my dad", "my mom", "my mum", "my father", "my mother",
    "my friend", "my wife", "my husband", "my partner",
    "my brother", "my sister", "my girlfriend", "my boyfriend",
    "my son", "my daughter", "someone",
    "my kid", "my child", "my baby", "my toddler", "my grandma",
    "my grandpa", "my grandmother", "my grandfather", "my roommate",
    "my coworker", "my teammate", "my buddy", "my aunt", "my uncle",
    "my cousin", "my neighbor", "my neighbour", "my fiance", "my fiancé",
    "my spouse", "my client",
)
_HELPER_PRONOUN_RE = re.compile(
    r"""
    \b(?:
        (?:her|his|their)\s+
        (?:face|arm|chest|jaw|head|speech|side|body|words?|pulse)
      |
        (?:he|she|they|he's|she's|they're|hes|shes|theyre)\s+
        (?:not\s+)?
        (?:
            breathing|collapsed|fainted|fainting|overdosed|blacked|passed
          | having|has|have|had|is|are|isn't|isnt|unresponsive|suddenly
          | took|swallowed|drank|ate|feels|seems|looks|keeps|choking
          | can't|cant|won't|wont|can\s+not
        )
    )\b
    """,
    re.VERBOSE,
)
_SLEEP_REFER = (
    "sleep apnea", "sleep apnoea", "apnea", "apnoea", "insomnia", "sleep",
)
_DIAGNOSIS_REFER_OPEN = (
    "I can't tell from here — a doctor can check it properly. "
    "Meanwhile I'm glad to help with "
)
_MEDICATION_REFER = (
    "That one's a call for your doctor or pharmacist — they know what you're on. "
    "I'm glad to help with the day-to-day stuff around it."
)


def _is_helper_phrasing(lower: str) -> bool:
    """True when the symptom's subject is someone else.

    Keys on a helper person (``my dad``) or a pronoun attached to the
    symptom (``her face``, ``he's having``). A bare ``they`` in
    ``they said my chest pain…`` is not helper phrasing.
    """
    if _has(lower, _HELPER_PERSON):
        return True
    return bool(_HELPER_PRONOUN_RE.search(lower))


def _self_harm_prose() -> str:
    """Crisis line already ends with call 911 now — do not lead with it twice."""
    crisis = _CRISIS_LINE.strip()
    if crisis.lower().rstrip(".").endswith("call 911 now"):
        return crisis
    return f"{_EMERGENCY_OPEN} {crisis}"


def _refer_out_prose(lower: str) -> str:
    if _is_eating_disorder_request(lower):
        return _EATING_DISORDER_REFER
    if _is_prescription_request(lower):
        return _MEDICATION_REFER
    habit = "sleep habits" if _has(lower, _SLEEP_REFER) else "the day-to-day stuff around it"
    return f"{_DIAGNOSIS_REFER_OPEN}{habit}."


def _emergency_kind(lower: str) -> str:
    """Which emergency this is. Order matters: arrest and crisis lead."""
    if _is_self_harm(lower):
        return "self_harm"
    if _needs_cpr(lower):
        return "arrest"
    if _is_ingestion(lower) and _INGESTION_INTENT_RE.search(lower):
        return "ingestion_intent"
    if _is_cardiac_reply(lower):
        return "cardiac"
    if _is_stroke_red_flag(lower):
        return "stroke"
    if _is_syncope_red_flag(lower):
        return "faint"
    if _is_allergy_emergency(lower):
        return "allergy"
    if _is_choking_now(lower):
        return "choking"
    if _is_bleeding_emergency(lower):
        return "bleeding"
    if _is_head_injury_emergency(lower):
        return "head_injury"
    if _has(lower, ("seizure", "convulsing")):
        return "seizure"
    if _is_ingestion(lower) or _has(lower, ("overdosed", "overdosing")):
        return "ingestion"
    return "general"


def _emergency_subject(lower: str, kind: str) -> str:
    """Whose emergency it is. Mirrors the branch ``_emergency_prose`` takes."""
    if kind == "self_harm":
        return _SUBJECT_SELF
    if _is_helper_phrasing(lower):
        return _SUBJECT_OTHER
    if kind in ("arrest", "general"):
        # No typed patient/helper steps: first person is the patient fallback,
        # anything else gets the bystander CPR-if-needed reply.
        if _FIRST_PERSON_RE.search(lower):
            return _SUBJECT_SELF
        return _SUBJECT_OTHER
    return _SUBJECT_SELF


def _emergency_prose(lower: str) -> str:
    """Pick steps by red-flag type. Not-breathing / unresponsive CPR wins."""
    helper = _is_helper_phrasing(lower)
    kind = _emergency_kind(lower)
    if kind == "self_harm":
        return _self_harm_prose()
    if kind == "arrest":
        return f"{_EMERGENCY_OPEN} {_EMERGENCY_CPR}"
    if kind == "ingestion_intent":
        body = _EMERGENCY_INGESTION_HELPER if helper else _EMERGENCY_INGESTION_INTENT
        return f"{_EMERGENCY_OPEN} {body}"
    steps = {
        "cardiac": (_EMERGENCY_CARDIAC, _EMERGENCY_CARDIAC_HELPER),
        "stroke": (_EMERGENCY_STROKE, _EMERGENCY_STROKE_HELPER),
        "faint": (_EMERGENCY_FAINT, _EMERGENCY_FAINT_HELPER),
        "allergy": (_EMERGENCY_ALLERGY, _EMERGENCY_ALLERGY_HELPER),
        "choking": (_EMERGENCY_CHOKING, _EMERGENCY_CHOKING_HELPER),
        "bleeding": (_EMERGENCY_BLEEDING, _EMERGENCY_BLEEDING_HELPER),
        "head_injury": (_EMERGENCY_HEAD, _EMERGENCY_HEAD_HELPER),
    }
    if kind in steps:
        patient, helper_body = steps[kind]
        return f"{_EMERGENCY_OPEN} {helper_body if helper else patient}"
    if kind == "seizure" and helper:
        return f"{_EMERGENCY_OPEN} {_EMERGENCY_SEIZURE_HELPER}"
    if kind == "ingestion" and not _has(lower, ("overdosed", "overdosing")):
        body = _EMERGENCY_INGESTION_HELPER if helper else _EMERGENCY_INGESTION
        return f"{_EMERGENCY_OPEN} {body}"
    if helper:
        return f"{_EMERGENCY_OPEN} {_EMERGENCY_CPR_IF_NEEDED}"
    if _FIRST_PERSON_RE.search(lower):
        return f"{_EMERGENCY_OPEN} {_EMERGENCY_PATIENT_FALLBACK}"
    return f"{_EMERGENCY_OPEN} {_EMERGENCY_CPR_IF_NEEDED}"


def _first_aid_body(lower: str) -> str:
    return "\n".join(_FIRST_AID_STEPS[t] for t in _detect_first_aid_topics(lower))


# --- Voice-first triage (borderline red flags) --------------------------------
# One or two questions, phrased so YES always means 911. The question carries
# the 911 criteria, so the turn is safe even if the answer never comes back.
TRIAGE_CHEST = "chest_pain"
TRIAGE_FAINT = "faint"
TRIAGE_INGESTION = "ingestion"
TRIAGE_BLEEDING = "bleeding"
TRIAGE_TOPICS = (TRIAGE_CHEST, TRIAGE_FAINT, TRIAGE_INGESTION, TRIAGE_BLEEDING)
_SUBJECT_SELF = "self"
_SUBJECT_OTHER = "other"

_FAINT_CUES = (
    "feel faint", "feels faint", "feeling faint", "felt faint", "going to pass out",
    "gonna pass out", "about to pass out", "might pass out", "going to faint",
    "gonna faint", "about to faint", "lightheaded", "light-headed",
    "light headed", "dizzy", "dizziness", "room is spinning",
    "room's spinning", "vision is going grey", "vision is going gray",
    "vision went grey", "vision went gray",
)
# A clinician already looked: never coach it, never re-triage it.
_CHEST_CLEARED = (
    "doctor said", "doctor cleared", "doc said", "doc cleared",
    "cardiologist said", "cardiologist cleared", "got it checked",
    "had it checked", "was checked out", "got checked out", "ruled out",
    "ecg was", "ekg was", "ecg came back", "ekg came back",
    "tests came back", "cleared me",
)
_CHEST_CLEARED_REFER = (
    "Good that it was checked. Stick with what your doctor said, and call "
    "them if it changes or comes back. Call 911 if it's crushing, spreading, "
    "or you're short of breath."
)

_TRIAGE_COPY: dict[tuple[str, str], tuple[str, tuple[str, ...], str]] = {
    # (topic, subject): (lead, questions, net)
    (TRIAGE_CHEST, _SUBJECT_SELF): (
        "Stop what you're doing and sit down.",
        (
            "Is the pain crushing or squeezing, or spreading to your arm, "
            "jaw, neck or back?",
            "Any trouble breathing, sweating, or feeling sick?",
        ),
        "If yes to any of that, call 911 now.",
    ),
    (TRIAGE_FAINT, _SUBJECT_SELF): (
        "Sit or lie down right now, wherever you are.",
        (
            "Any chest pain, trouble breathing, or a heartbeat that's "
            "pounding and won't settle?",
            "Did you black out at all?",
        ),
        "If yes to any of that, call 911 now.",
    ),
    (TRIAGE_FAINT, _SUBJECT_OTHER): (
        "Help them sit or lie down right now.",
        (
            "Do they have chest pain, trouble breathing, or a heartbeat "
            "that's pounding and won't settle?",
            "Did they black out at all?",
        ),
        "If yes to any of that, call 911 now.",
    ),
    (TRIAGE_INGESTION, _SUBJECT_SELF): (
        f"{_POISON_CONTROL} They'll tell you exactly what to do.",
        (
            "Are you getting drowsy or confused, or is it hard to breathe?",
            "Did you take it to hurt yourself?",
        ),
        "If yes to either, call 911 now.",
    ),
    (TRIAGE_INGESTION, _SUBJECT_OTHER): (
        f"{_POISON_CONTROL} They'll tell you exactly what to do, so keep the "
        "package with you.",
        (
            "Are they getting drowsy or confused, or is it hard for them to "
            "breathe?",
            "Did they take it to hurt themselves?",
        ),
        "If yes to either, call 911 now.",
    ),
    (TRIAGE_BLEEDING, _SUBJECT_SELF): (
        "Press hard on it with a clean cloth and keep pressing.",
        (
            "Is it spurting, soaking through the cloth, or still going after "
            "10 minutes of firm pressure?",
            "Do you feel faint or cold?",
        ),
        "If yes to any of that, call 911 now.",
    ),
    (TRIAGE_BLEEDING, _SUBJECT_OTHER): (
        "Press hard on it with a clean cloth and keep pressing.",
        (
            "Is it spurting, soaking through the cloth, or still going after "
            "10 minutes of firm pressure?",
            "Are they faint, pale, or cold?",
        ),
        "If yes to any of that, call 911 now.",
    ),
}

# Answer parsing. YES always means danger; a danger cue wins over a "no" lead
# unless the cue itself is negated ("no arm or jaw pain").
_YES_LEAD_RE = re.compile(
    r"^\s*(?:yes|yeah|yea|yep|yup|ya|y|sure|i think so|kind of|kinda|sort of|"
    r"a little|a bit|maybe|possibly|definitely|absolutely|it is|it does)\b"
)
_NO_LEAD_RE = re.compile(
    r"^\s*(?:no|nope|nah|n|not really|none|neither|nothing like that|"
    r"i'?m fine|im fine|i'?m okay|im okay|i'?m ok|im ok|all good|not at all|"
    r"they'?re fine|they'?re okay|he'?s fine|she'?s fine|he'?s okay|"
    r"she'?s okay)\b"
)
_NEGATORS = frozenset({
    "no", "not", "nor", "without", "never", "isn't", "isnt", "aren't",
    "arent", "don't", "dont", "doesn't", "doesnt", "didn't", "didnt",
    "nothing", "neither", "none",
})
_BREATH_TROUBLE = (
    r"(?:trouble|hard|difficult|difficulty|struggling)\s+(?:to\s+)?breath\w*"
    r"|can'?t breathe|cannot breathe|short(?:ness)? of breath|breathless"
    r"|out of breath"
)
_TRIAGE_DANGER: dict[str, re.Pattern[str]] = {
    TRIAGE_CHEST: re.compile(
        r"\b(?:crushing|squeez\w*|spread\w*|radiat\w*|arm|jaw|neck|back|"
        r"shoulder|sweat\w*|clammy|sick|nause\w*|throw(?:ing)? up|vomit\w*|"
        r"dizzy|faint|lightheaded|worse|pressure|heavy|tight\w*|"
        + _BREATH_TROUBLE
        + r")\b"
    ),
    TRIAGE_FAINT: re.compile(
        r"\b(?:chest|pound\w*|racing|flutter\w*|irregular|skipp\w*|"
        r"blacked out|passed out|fainted|lost consciousness|collapsed|"
        r"confused|numb|slurr\w*|can'?t see|"
        + _BREATH_TROUBLE
        + r")\b"
    ),
    TRIAGE_INGESTION: re.compile(
        r"\b(?:drowsy|sleepy|can'?t stay awake|hard to wake|won'?t wake|"
        r"confused|seizure|seizing|shaking|blue|unconscious|passed out|"
        r"on purpose|hurt (?:myself|themselves|himself|herself)|wanted to|"
        r"meant to|intentional\w*|deliberately|to die|end it|"
        + _BREATH_TROUBLE
        + r")\b"
    ),
    TRIAGE_BLEEDING: re.compile(
        r"\b(?:spurt\w*|squirt\w*|soak\w*|still (?:going|bleeding)|won'?t stop|"
        r"not stopping|keeps bleeding|gushing|pouring|faint|dizzy|lightheaded|"
        r"pale|cold|clammy|passing out|"
        + _BREATH_TROUBLE
        + r")\b"
    ),
}
_TRIAGE_CARDIAC_CUE_RE = re.compile(
    r"\b(?:chest|pound\w*|racing|" + _BREATH_TROUBLE + r")\b"
)
_TRIAGE_INTENT_CUE_RE = re.compile(
    r"\b(?:on purpose|hurt (?:myself|themselves|himself|herself)|wanted to|"
    r"meant to|intentional\w*|deliberately|to die|end it)\b"
)
_CHEST_MSK_CUES = (
    "when i press", "when i push on", "when i touch", "press on it",
    "push on it", "touch it", "sore", "tender", "when i move", "when i twist",
    "when i stretch", "after chest day", "after bench", "pulled", "strained",
    "muscle",
)
_WOUND_NEEDS_LOOK_CUES = (
    "deep", "gaping", "wide open", "stitches", "can see", "bone", "rusty",
    "dirty", "bite", "bit me", "bit him", "bit her", "glass", "face", "eye",
)
_RECURRING_CUES = (
    "again", "keeps happening", "keep happening", "every time", "a lot lately",
    "for days", "for weeks", "all week", "third time", "second time",
    "happens often", "happens a lot", "keeps coming back",
)

_TRIAGE_RESOLUTION: dict[tuple[str, str, str], str] = {
    (TRIAGE_CHEST, _SUBJECT_SELF, REFER_OUT): (
        "Okay. Get it checked by a doctor today. Chest pain deserves a proper "
        "look even when it's mild, so no training until then. If it gets "
        "worse, spreads, or you're short of breath, call 911."
    ),
    (TRIAGE_CHEST, _SUBJECT_SELF, CARE): (
        "Okay. Keep today easy with no chest work or hard cardio. If it's "
        "still there tomorrow, get it checked. If it changes, spreads, or "
        "you're short of breath, call 911."
    ),
    (TRIAGE_FAINT, _SUBJECT_SELF, CARE): (
        "Okay. Stay down until it passes, sip some water, and eat something "
        "if you haven't. Training is done for today. If it keeps happening, "
        "tell a doctor, and call 911 if chest pain or trouble breathing shows "
        "up."
    ),
    (TRIAGE_FAINT, _SUBJECT_SELF, REFER_OUT): (
        "Okay. Since it keeps happening, get checked by a doctor before you "
        "train again. For now, stay down until it passes and sip some water. "
        "Call 911 if chest pain or trouble breathing shows up."
    ),
    (TRIAGE_FAINT, _SUBJECT_OTHER, CARE): (
        "Okay. Keep them sitting or lying down until it passes, with some "
        "water and something to eat. No more training for them today. If it "
        "keeps happening, they should see a doctor, and call 911 if chest pain "
        "or trouble breathing shows up."
    ),
    (TRIAGE_FAINT, _SUBJECT_OTHER, REFER_OUT): (
        "Okay. Since it keeps happening, they should see a doctor before "
        "training again. For now, keep them sitting or lying down with some "
        "water. Call 911 if chest pain or trouble breathing shows up."
    ),
    (TRIAGE_INGESTION, _SUBJECT_SELF, REFER_OUT): (
        "Okay. Stay on with Poison Control and do exactly what they say, and "
        "keep the bottle with you. If you get drowsy, confused, or it's hard "
        "to breathe, call 911."
    ),
    (TRIAGE_INGESTION, _SUBJECT_OTHER, REFER_OUT): (
        "Okay. Stay on with Poison Control and do exactly what they say, and "
        "keep the package with you. If they get drowsy, confused, or it's hard "
        "for them to breathe, call 911."
    ),
    (TRIAGE_BLEEDING, _SUBJECT_SELF, CARE): (
        "Okay. Keep steady pressure until it stops, then clean it gently and "
        "cover it. If it starts again, looks deep, or came from something "
        "dirty or rusty, get it looked at today. If it won't stop, call 911."
    ),
    (TRIAGE_BLEEDING, _SUBJECT_SELF, REFER_OUT): (
        "Okay. Keep pressure on it and get it looked at today. That one needs "
        "a proper look. If it won't stop or you feel faint, call 911."
    ),
    (TRIAGE_BLEEDING, _SUBJECT_OTHER, CARE): (
        "Okay. Keep steady pressure on it until it stops, then clean it gently "
        "and cover it. If it starts again, looks deep, or came from something "
        "dirty or rusty, they should get it looked at today. If it won't stop, "
        "call 911."
    ),
    (TRIAGE_BLEEDING, _SUBJECT_OTHER, REFER_OUT): (
        "Okay. Keep pressure on it and get them seen today. That one needs a "
        "proper look. If it won't stop or they feel faint, call 911."
    ),
}


def triage_reply_topic(topic: str, subject: str) -> str:
    """Opaque token the client echoes back as ``triage_topic`` next turn."""
    return f"{topic}.{subject}"


def parse_triage_topic(raw: Any) -> tuple[str, str] | None:
    """Whitelist-parse a client echo. Unknown or malformed tokens are ignored."""
    text = str(raw or "").strip().lower()
    if not text or len(text) > 32:
        return None
    topic, _, subject = text.partition(".")
    subject = subject or _SUBJECT_SELF
    if topic in TRIAGE_TOPICS and subject in (_SUBJECT_SELF, _SUBJECT_OTHER):
        return topic, subject
    return None


def _is_chest_cleared(lower: str) -> bool:
    return _has(lower, _CHEST_MARKERS) and _has(lower, _CHEST_CLEARED)


def _triage_topic(lower: str) -> tuple[str, str] | None:
    """Borderline red flag that needs a question before 911 or a doctor."""
    helper = _is_helper_phrasing(lower)
    subject = _SUBJECT_OTHER if helper else _SUBJECT_SELF
    if _is_ingestion(lower):
        return TRIAGE_INGESTION, subject
    if _BLEEDING_TRIAGE_RE.search(lower):
        return TRIAGE_BLEEDING, subject
    if (
        not helper
        and _has(lower, _CHEST_MARKERS)
        and not _is_lift_chest_soreness(lower)
        and not _is_chest_cleared(lower)
    ):
        return TRIAGE_CHEST, _SUBJECT_SELF
    if _has(lower, _FAINT_CUES):
        return TRIAGE_FAINT, subject
    return None


_CLAUSE_BREAK_RE = re.compile(r"[,.;!?]|\b(?:but|though|although|except|however|yet)\b")


def _cue_is_negated(lower: str, start: int) -> bool:
    """"no arm or jaw pain" negates the cue; "no, but it's worse" does not."""
    clause = _CLAUSE_BREAK_RE.split(lower[:start])[-1]
    before = re.findall(r"[a-z']+", clause)[-3:]
    return any(word in _NEGATORS for word in before)


def _has_live_cue(pattern: re.Pattern[str], lower: str) -> bool:
    return any(
        not _cue_is_negated(lower, match.start()) for match in pattern.finditer(lower)
    )


def _resolve_triage(topic: str, subject: str, lower: str) -> str:
    """Case-by-case outcome for a triage answer: EMERGENCY, REFER_OUT, or CARE."""
    danger = _has_live_cue(_TRIAGE_DANGER[topic], lower)
    said_yes = bool(_YES_LEAD_RE.search(lower)) and not _NO_LEAD_RE.search(lower)
    if danger or said_yes:
        return EMERGENCY
    said_no = bool(_NO_LEAD_RE.search(lower))
    if topic == TRIAGE_CHEST:
        if said_no and _has(lower, _CHEST_MSK_CUES):
            return CARE
        # A "no" without a muscle cue, or an unclear answer, still sees a doctor.
        return REFER_OUT
    if topic == TRIAGE_FAINT:
        return REFER_OUT if _has(lower, _RECURRING_CUES) else CARE
    if topic == TRIAGE_BLEEDING:
        return REFER_OUT if _has(lower, _WOUND_NEEDS_LOOK_CUES) else CARE
    # Ingestion: Poison Control is the responsible resolution.
    return REFER_OUT


def _triage_emergency_prose(topic: str, subject: str, lower: str) -> tuple[str, str]:
    """911 copy for a triage answer that escalated, plus its emergency kind."""
    other = subject == _SUBJECT_OTHER
    if topic == TRIAGE_INGESTION:
        bare_yes = bool(_YES_LEAD_RE.search(lower)) and not _TRIAGE_DANGER[topic].search(lower)
        if other:
            return f"{_EMERGENCY_OPEN} {_EMERGENCY_INGESTION_HELPER}", "ingestion"
        if bare_yes or _has_live_cue(_TRIAGE_INTENT_CUE_RE, lower):
            return f"{_EMERGENCY_OPEN} {_EMERGENCY_INGESTION_INTENT}", "ingestion_intent"
        return f"{_EMERGENCY_OPEN} {_EMERGENCY_INGESTION}", "ingestion"
    if topic == TRIAGE_BLEEDING:
        body = _EMERGENCY_BLEEDING_HELPER if other else _EMERGENCY_BLEEDING
        return f"{_EMERGENCY_OPEN} {body}", "bleeding"
    if topic == TRIAGE_FAINT and not _has_live_cue(_TRIAGE_CARDIAC_CUE_RE, lower):
        body = _EMERGENCY_FAINT_HELPER if other else _EMERGENCY_FAINT
        return f"{_EMERGENCY_OPEN} {body}", "faint"
    body = _EMERGENCY_CARDIAC_HELPER if other else _EMERGENCY_CARDIAC
    return f"{_EMERGENCY_OPEN} {body}", "cardiac"


# --- Relationship-aware check-in ---------------------------------------------
# Posted once escalation or a responsible resolution is reached, after voice
# turns off. Tiers match the learner's own read of the relationship
# (contextual_learner): new 1-2, familiar 3-5, real bond 6-10.
_CHECK_IN: dict[tuple[str, str], tuple[str, str, str]] = {
    ("emergency", _SUBJECT_SELF): (
        "You were in an emergency. How are you feeling now?",
        "You were in an emergency. I'm glad you're back. How are you feeling now?",
        "Hey. You were in an emergency, and I've been hoping you're okay. "
        "How are you feeling now? Take your time.",
    ),
    ("emergency", _SUBJECT_OTHER): (
        "That was an emergency. How are you feeling now, and how are they?",
        "That was an emergency, and you stayed with them. How are you feeling "
        "now, and how are they?",
        "Hey. That was a lot to carry, and you stayed with them. How are you "
        "feeling now, and how are they doing?",
    ),
    ("self_harm", _SUBJECT_SELF): (
        "You were in a really hard moment. How are you feeling now? 988 is "
        "there any time, call or text.",
        "You were in a really hard moment, and I'm glad you're still here "
        "talking to me. How are you feeling now? 988 is there any time, call "
        "or text.",
        "Hey. I'm really glad you're here. You were in a really hard moment. "
        "How are you feeling now? 988 is there any time, call or text.",
    ),
    ("resolved", _SUBJECT_SELF): (
        "That could have been an emergency. How are you feeling now?",
        "That could have been an emergency. I'm glad you told me. How are you "
        "feeling now?",
        "Hey. That could have been an emergency, and I'm glad you told me. How "
        "are you feeling now? Take your time.",
    ),
    ("resolved", _SUBJECT_OTHER): (
        "That could have been an emergency. How are you feeling now, and how "
        "are they?",
        "That could have been an emergency, and you stayed with them. How are "
        "you feeling now, and how are they?",
        "Hey. That could have been a lot, and you stayed with them. How are "
        "you feeling now, and how are they doing?",
    ),
}


def _relationship_tier(relationship_level: Any) -> int:
    try:
        level = int(relationship_level)
    except (TypeError, ValueError):
        level = 1
    if level <= 2:
        return 0
    if level <= 5:
        return 1
    return 2


def check_in_message(
    outcome: str,
    subject: str = _SUBJECT_SELF,
    *,
    relationship_level: Any = 1,
    self_harm: bool = False,
) -> str:
    """Warm, relationship-aware check-in for after the safety session ends."""
    tier = _relationship_tier(relationship_level)
    if self_harm and subject == _SUBJECT_SELF:
        key = ("self_harm", _SUBJECT_SELF)
    elif outcome == EMERGENCY:
        key = ("emergency", subject)
    else:
        key = ("resolved", subject)
    return _CHECK_IN.get(key, _CHECK_IN[("resolved", _SUBJECT_SELF)])[tier]


def safety_session(
    *,
    phase: str,
    topic: str,
    subject: str = _SUBJECT_SELF,
    outcome: str | None = None,
    questions: tuple[str, ...] = (),
    relationship_level: Any = 1,
) -> dict[str, Any]:
    """Client contract for a voice-first safety session.

    ``phase``:
      * ``triage``   — voice ON. Speak ``prose``, then ask ``questions`` one at a
        time. Send the answer with ``triage_topic = reply_topic``.
      * ``escalate`` — voice ON until escalation is achieved (911 dialed / SOS
        placed). Then voice OFF and post ``check_in.message``.
      * ``resolved`` — a responsible resolution (doctor, Poison Control, care
        line). Speak ``prose``, then voice OFF and post ``check_in.message``.
    """
    block: dict[str, Any] = {
        "schema": 1,
        "phase": phase,
        "topic": topic,
        "subject": subject,
        "voice": "on" if phase in ("triage", "escalate") else "off",
        "outcome": outcome,
    }
    if phase == "triage":
        block["questions"] = list(questions)
        block["reply_topic"] = triage_reply_topic(topic, subject)
        block["check_in"] = None
        return block
    block["check_in"] = {
        "after": "escalation" if phase == "escalate" else "resolution",
        "message": check_in_message(
            outcome or REFER_OUT,
            subject,
            relationship_level=relationship_level,
            self_harm=topic == "self_harm",
        ),
    }
    return block


def _classify(lower: str, pending: tuple[str, str] | None) -> str:
    if _is_self_harm(lower):
        return EMERGENCY
    if _has(lower, _ESCALATION_REQUEST) or _has(lower, _EMERGENCY_STATE):
        return EMERGENCY
    if _is_acute_red_flag(lower):
        return EMERGENCY
    if _has(lower, _HOWTO_CUES) and _has_word(lower, _FIRST_AID_TOPICS):
        return FIRST_AID
    if _is_choking_now(lower):
        return EMERGENCY
    if pending is not None:
        return _resolve_triage(pending[0], pending[1], lower)
    if _is_chest_cleared(lower):
        return REFER_OUT
    if _triage_topic(lower) is not None:
        return TRIAGE
    if _is_eating_disorder_request(lower):
        return REFER_OUT
    if _is_prescription_request(lower) or _is_diagnosis_request(lower):
        return REFER_OUT
    return COACH


def classify_band(message: str, *, triage_topic: Any = None) -> str:
    """One band per turn. ``triage_topic`` is the echo of a pending triage."""
    return _classify(normalize_message(message), parse_triage_topic(triage_topic))


def assess(
    message: str,
    band: str | None = None,
    *,
    triage_topic: Any = None,
    relationship_level: Any = 1,
) -> Guidance | None:
    """Return a Guidance for a boundary/emergency message, or None for COACH.

    When ``band`` is passed (chat route), skip ``classify_band`` — the caller
    already classified once, with the same ``triage_topic``.

    ``triage_topic`` is the client's echo of the previous turn's
    ``safety.reply_topic``. ``relationship_level`` (1-10) shapes the check-in.
    """
    lower = normalize_message(message)
    pending = parse_triage_topic(triage_topic)
    if band is not None:
        resolved = band
    elif pending is None:
        resolved = classify_band(message)
    else:
        resolved = classify_band(message, triage_topic=triage_topic)
    if resolved == COACH or not resolved:
        return None
    band = resolved

    if band == EMERGENCY:
        # A fresh emergency in the answer itself ("he's not breathing") wins
        # over the pending triage question's own 911 copy.
        if pending is not None and _classify(lower, None) != EMERGENCY:
            prose, kind = _triage_emergency_prose(pending[0], pending[1], lower)
            subject = pending[1]
        else:
            prose = _emergency_prose(lower)
            kind = _emergency_kind(lower)
            subject = _emergency_subject(lower, kind)
        helper = subject == _SUBJECT_OTHER
        actions = ["Call 911", "Stay on the line"]
        if kind == "self_harm":
            actions = ["Call or text 988", "Call 911", "Stay on the line"]
        elif helper:
            actions = ["Call 911", "Start first aid", "Stay on the line"]
        return Guidance(
            band=EMERGENCY,
            prose=prose,
            message=prose,
            confidence_reason="Safety policy: possible emergency — escalate to 911.",
            suggested_actions=actions,
            wants_escalation=True,
            safety=safety_session(
                phase="escalate",
                topic=kind,
                subject=subject,
                outcome=EMERGENCY,
                relationship_level=relationship_level,
            ),
        )

    if band == FIRST_AID:
        prose = (
            "Here's how to help — and call 911 (or have someone nearby call) right "
            "away:\n" + _first_aid_body(lower) + "\n" + _BOUNDARY_INFO
        )
        return Guidance(
            band=FIRST_AID,
            prose=prose,
            message=prose,
            confidence_reason="Safety policy: first-aid information with a 911 prompt.",
            suggested_actions=["Call 911", "Follow the steps", "Stay with them"],
            wants_escalation=False,
        )

    if band == TRIAGE:
        found = _triage_topic(lower) or (TRIAGE_FAINT, _SUBJECT_SELF)
        topic, subject = found
        lead, questions, net = _TRIAGE_COPY.get(
            (topic, subject), _TRIAGE_COPY[(topic, _SUBJECT_SELF)]
        )
        if topic == TRIAGE_INGESTION and _has_word(lower, _YOUNG_CHILD_CUES):
            questions = questions[:1]
        prose = " ".join((lead, *questions, net))
        return Guidance(
            band=TRIAGE,
            prose=prose,
            message=prose,
            confidence_reason=(
                "Safety policy: borderline red flag — voice triage decides "
                "911, a doctor, or a care line."
            ),
            suggested_actions=["Yes", "No", "Call 911"],
            wants_escalation=False,
            safety=safety_session(
                phase="triage",
                topic=topic,
                subject=subject,
                questions=questions,
                relationship_level=relationship_level,
            ),
        )

    if pending is not None and band in (REFER_OUT, CARE):
        topic, subject = pending
        # Chest triage is only ever opened for the patient; a stale or forged
        # "chest_pain.other" echo falls back to the patient copy.
        prose = (
            _TRIAGE_RESOLUTION.get((topic, subject, band))
            or _TRIAGE_RESOLUTION.get((topic, subject, REFER_OUT))
            or _TRIAGE_RESOLUTION[(topic, _SUBJECT_SELF, REFER_OUT)]
        )
        if topic == TRIAGE_INGESTION:
            actions = ["Call Poison Control", "Call 911"]
        elif band == REFER_OUT:
            actions = ["Get it checked today", "Call 911"]
        elif topic == TRIAGE_BLEEDING:
            actions = ["Keep pressure on it", "Call 911"]
        else:
            actions = ["Keep today easy", "Call 911"]
        return Guidance(
            band=band,
            prose=prose,
            message=prose,
            confidence_reason=(
                "Safety policy: triage answer resolved without 911 — "
                "responsible next step plus the 911 net."
            ),
            suggested_actions=actions,
            wants_escalation=False,
            safety=safety_session(
                phase="resolved",
                topic=topic,
                subject=subject,
                outcome=band,
                relationship_level=relationship_level,
            ),
        )

    if band == REFER_OUT:
        prose = _CHEST_CLEARED_REFER if _is_chest_cleared(lower) else _refer_out_prose(lower)
        return Guidance(
            band=REFER_OUT,
            prose=prose,
            message=prose,
            confidence_reason="Safety policy: ARIA suggests lifestyle, never diagnoses or prescribes.",
            suggested_actions=["Talk to a clinician", "Work on the lifestyle side", "Ask me something else"],
            wants_escalation=False,
        )
    return None


def contains_prescriptive_medical_language(text: str) -> bool:
    """Detect diagnosis/prescription language in *outgoing* text (defense in depth
    for the live model path). Conservative — targets explicit medical claims, not
    ordinary lifestyle imperatives like "you should sleep more"."""
    lower = (text or "").lower()
    if _DOSE_RE.search(lower):
        return True
    if _DIAGNOSTIC_ASSERTION_RE.search(lower):
        return True
    return _has(lower, _PRESCRIBE_ASSERTION)


def append_clinician_disclaimer(text: str) -> str:
    disclaimer = (
        "(Reminder: I'm a lifestyle coach, not a doctor — please confirm anything "
        "medical with a licensed clinician.)"
    )
    text = (text or "").rstrip()
    if not text:
        return disclaimer
    return f"{text}\n\n{disclaimer}"
