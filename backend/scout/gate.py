"""Decide whether a turn should wake Scout, and write the mission brief.

Scout's process can stay up. It must not search on every chat turn. ARIA
(or the Dummy) runs ``evaluate`` on the prompt first. A yes is a handoff:
scrubbed keywords plus a mission, never the raw message, never names,
numbers, or samples. A no means ARIA keeps talking and Scout stays idle.

Anything health related wakes Scout, with or without a lookup cue, and a
single health keyword is enough ("fever"). Other topics still need a lookup
cue and two keywords. Questions about the user's own data ("how did I
sleep", "my HRV") stay off unless they also ask for outside facts.

Crisis language is researched too, but the decision carries a safety line
that the server appends to the end of the brief, so ARIA always closes with
"call 911" (and 988 for self-harm).

``from_handoff`` is for a caller that already decided. It still scrubs and
still attaches the safety line. It does not require a lookup cue.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field

from .privacy import scrub_query

_RELATION = re.compile(
    r"\b(?:wife|husband|partner|girlfriend|boyfriend|mom|dad|mother|father|son|daughter|brother|sister)\s+[A-Z][a-z]+\b"
)

_LOOKUP_CUES = (
    "look up", "look this up", "search for", "what is", "what are", "what does",
    "what's the latest", "whats the latest", "latest on", "how does", "how do",
    "how much", "how many", "how long", "how often", "is it true", "is it safe",
    "evidence", "studies", "study on", "research on", "side effects", "versus",
    " vs ", "definition of", "what happened", "news about", "weather",
    "air quality", "aqi",
)

_SESSION_CUES = (
    "should i train", "should i workout", "should i work out", "how did i sleep",
    "my readiness", "my recovery", "my hrv", "last night", "leg day",
    "today's session", "todays session", "how are you", "good morning",
)

_SELF_HARM = (
    "kill myself", "want to die", "end my life", "don't want to live",
    "dont want to live", "suicidal",
)

_EMERGENCY = (
    "heart attack", "chest pain", "can't breathe", "cant breathe",
    "overdosed", "overdose", "not breathing", "call 911",
)

EMERGENCY_LINE = "If this is an emergency, call 911 now."
SELF_HARM_LINE = (
    "If you might act on these thoughts, call or text 988 now. "
    "If you are in danger, call 911."
)

# Clients clip evidence to this many characters from the front (Swift
# AriaWebParsers.clip, Python web_research._clip). The safety line must
# survive that clip, so the answer is trimmed before the line is appended.
CLIENT_EVIDENCE_CHARS = 420

# A fixed source for a crisis answer that has no brief (limit or error):
# both clients drop an answer without an https source.
EMERGENCY_SOURCE = {"title": "MedlinePlus: Recognizing medical emergencies", "url": "https://medlineplus.gov/ency/article/001927.htm"}
SELF_HARM_SOURCE = {"title": "988 Suicide & Crisis Lifeline", "url": "https://988lifeline.org/"}

# Self-harm wording is never searched as typed. Scout looks for support instead.
_SELF_HARM_MISSION = "suicidal thoughts crisis support"
_EMERGENCY_MISSION = "medical emergency warning signs"

# One health word is enough to wake Scout. Whole words only.
_HEALTH_WORDS = frozenset(
    """
    health healthy symptom symptoms sick ill illness disease condition diagnosis
    doctor hospital clinic therapy physio physiotherapy treatment recovery
    fever cough cold flu covid headache migraine nausea nauseous vomiting
    diarrhea constipation dizzy dizziness faint fatigue exhausted pain painful
    ache aches aching hurt hurts sore soreness cramp cramps swelling swollen
    stiff stiffness numb numbness tingling rash itch itchy bleeding bruise
    infection inflammation allergy allergies asthma wheezing breathe breathing
    breath throat sinus fracture sprain strain tendon tendinitis tendonitis
    injury injured concussion arthritis anemia thyroid diabetes hypertension
    cholesterol cancer stroke pregnant pregnancy menstrual period menopause
    knee back shoulder hip ankle wrist neck elbow heart lung lungs chest
    stomach gut muscle muscles joint joints bone bones skin liver kidney
    medication medications medicine drug drugs dose dosage pill pills tablet
    ibuprofen acetaminophen paracetamol tylenol advil aspirin naproxen
    antibiotic antibiotics supplement supplements vitamin vitamins mineral
    creatine caffeine melatonin magnesium iron zinc electrolyte electrolytes
    protein carbs carbohydrate carbohydrates fiber calories diet nutrition
    hydration hydrate dehydrated dehydration fasting sugar sodium alcohol
    sleep insomnia nap circadian apnea snoring
    hrv vo2 vo2max overtraining cardio endurance mobility stretching
    anxiety anxious depression depressed stress stressed burnout panic mood
    heat heatstroke hot humid humidity sunburn uv altitude
    """.split()
)

_HEALTH_PHRASES = (
    "blood pressure", "heart rate", "resting heart", "blood sugar",
    "mental health", "air quality", "body temperature",
)


@dataclass
class MissionBrief:
    question: str
    terms: list[str]
    prefer: list[str] = field(default_factory=list)
    retain: bool = False

    def as_dict(self) -> dict:
        return asdict(self)


@dataclass
class GateDecision:
    activate: bool
    reason: str
    mission: MissionBrief | None = None
    # Set for crisis language. The server appends it to the end of the brief.
    safety: str | None = None

    def as_dict(self) -> dict:
        out = {
            "activate": self.activate,
            "reason": self.reason,
            "mission": None if self.mission is None else self.mission.as_dict(),
        }
        if self.safety:
            out["safety"] = self.safety
        return out


def _has(lower: str, needles: tuple[str, ...]) -> bool:
    return any(needle in lower for needle in needles)


_WORD = re.compile(r"[a-z0-9]+(?:'[a-z]+)?")


def is_health(text: str) -> bool:
    """True when the text names a health topic (symptom, body, drug, sleep, ...)."""
    lower = str(text or "").lower()
    if _has(lower, _HEALTH_PHRASES):
        return True
    return any(word in _HEALTH_WORDS or word.startswith("zone") for word in _WORD.findall(lower))


def _prefer(terms: list[str]) -> list[str]:
    if is_health(" ".join(terms)):
        return ["pubmed", "medlineplus"]
    return ["web"]


def _mission(text: str, private_terms, *, min_terms: int = 2) -> MissionBrief | None:
    scrubbed = scrub_query(text, private_terms)
    terms = [part for part in scrubbed.split() if part]
    if len(terms) < min_terms:
        return None
    return MissionBrief(question=scrubbed, terms=terms, prefer=_prefer(terms), retain=False)


def _crisis(lower: str, text: str, private_terms) -> GateDecision | None:
    """Crisis language: research it, and always close with the safety line."""
    if _has(lower, _SELF_HARM):
        mission = MissionBrief(
            question=_SELF_HARM_MISSION, terms=_SELF_HARM_MISSION.split(),
            prefer=["medlineplus"], retain=False,
        )
        return GateDecision(True, "safety", mission, SELF_HARM_LINE)
    if _has(lower, _EMERGENCY):
        mission = _mission(text, private_terms, min_terms=1) or MissionBrief(
            question=_EMERGENCY_MISSION, terms=_EMERGENCY_MISSION.split(), retain=False,
        )
        mission.prefer = ["medlineplus", "pubmed"]
        return GateDecision(True, "safety", mission, EMERGENCY_LINE)
    return None


def safety_source(line: str) -> dict:
    return dict(SELF_HARM_SOURCE if line == SELF_HARM_LINE else EMERGENCY_SOURCE)


def with_safety(answer: str, line: str, limit: int = CLIENT_EVIDENCE_CHARS) -> str:
    """Answer with the safety line last, short enough that a client clip keeps it."""
    body = " ".join(str(answer or "").split())
    room = limit - len(line) - 2
    if len(body) > room:
        cut = body[: max(room, 0)]
        stop = cut.rfind(".")
        body = cut[: stop + 1] if stop > 0 else ""
    return f"{body}\n\n{line}" if body else line


def evaluate(prompt: str, private_terms: tuple[str, ...] | list[str] = ()) -> GateDecision:
    text = str(prompt or "").strip()
    if not text:
        return GateDecision(False, "empty")
    text = _RELATION.sub(" ", text)
    lower = text.lower()
    crisis = _crisis(lower, text, private_terms)
    if crisis is not None:
        return crisis
    explicit = _has(lower, _LOOKUP_CUES)
    if _has(lower, _SESSION_CUES) and not explicit:
        return GateDecision(False, "session")
    health = is_health(lower)
    if not explicit and not health:
        return GateDecision(False, "session")
    mission = _mission(text, private_terms, min_terms=1 if health else 2)
    if mission is None:
        return GateDecision(False, "no_terms")
    return GateDecision(True, "lookup" if explicit else "health", mission)


def from_handoff(query: str, private_terms: tuple[str, ...] | list[str] = ()) -> GateDecision:
    """Caller already decided this is a lookup. Still scrub. Still add the safety line."""
    text = _RELATION.sub(" ", str(query or "").strip())
    if not text:
        return GateDecision(False, "empty")
    crisis = _crisis(text.lower(), text, private_terms)
    if crisis is not None:
        return crisis
    mission = _mission(text, private_terms, min_terms=1 if is_health(text) else 2)
    if mission is None:
        return GateDecision(False, "no_terms")
    return GateDecision(True, "handoff", mission)
