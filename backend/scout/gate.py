"""Decide whether a turn should wake Scout, and write the mission brief.

Scout's process can stay up. It must not search on every chat turn. ARIA
(or the Dummy) runs ``evaluate`` on the prompt first. A yes is a handoff:
scrubbed keywords plus a mission, never the raw message, never names,
numbers, or samples. A no means ARIA keeps talking and Scout stays idle.

Anything health related wakes Scout, with or without a lookup cue, and a
single unambiguous health keyword is enough ("fever"). Ambiguous everyday
words (back, period, cold, hot, heart, …) count only with another health
word or a lookup cue. Other topics still need a lookup cue and two
keywords. Questions about the user's own data ("how did I sleep", "my
HRV") stay off unless they also ask for outside facts.

Crisis wording and the safety line come from ``guidance.py`` — gate does
not keep its own crisis lists. The safety line leads the answer so a
client clip cannot drop it. Self-harm tiers never search.

``from_handoff`` is for a caller that already decided. It still scrubs
and still attaches the safety line. It does not require a lookup cue.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass, field

from backend._paths import ensure_lambda_on_path

from .privacy import scrub_query

ensure_lambda_on_path()
from aria_core import guidance as _guidance  # noqa: E402

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

# Re-export guidance templates so tests name the same strings Scout speaks.
TIER_EMERGENCY = _guidance.TIER_EMERGENCY
TIER_SELF_HARM_INTENT = _guidance.TIER_SELF_HARM_INTENT
TIER_SELF_HARM_THOUGHTS = _guidance.TIER_SELF_HARM_THOUGHTS
TIER_URGENT = _guidance.TIER_URGENT
TIER_STRESS = _guidance.TIER_STRESS
TIER_NONE = _guidance.TIER_NONE
ACTION_911 = _guidance.ACTION_911
ACTION_988 = _guidance.ACTION_988
SCOUT_SELF_HARM_INTENT_LINE = _guidance.SCOUT_SELF_HARM_INTENT_LINE
SCOUT_SELF_HARM_THOUGHTS_LINE = _guidance.SCOUT_SELF_HARM_THOUGHTS_LINE
SCOUT_STRESS_LINE = _guidance.SCOUT_STRESS_LINE
emergency_phrases = _guidance.emergency_phrases
scout_safety = _guidance.scout_safety

# Clients clip evidence from the front to this many characters
# (ForgeCore AriaWebEvidence.swift — AriaWebParsers.maxEvidenceChars,
#  Python web_research._clip). The safety line leads so a clip keeps it.
CLIENT_EVIDENCE_CHARS = 420

# A fixed source for a crisis answer that has no brief (limit or error):
# both clients drop an answer without an https source.
EMERGENCY_SOURCE = {"title": "MedlinePlus: Recognizing medical emergencies", "url": "https://medlineplus.gov/ency/article/001927.htm"}
SELF_HARM_SOURCE = {"title": "988 Suicide & Crisis Lifeline", "url": "https://988lifeline.org/"}

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

# Everyday words that are also health tokens. Alone they do not wake Scout.
_AMBIGUOUS_HEALTH = frozenset(
    """
    back period cold hot condition drug drugs iron sugar mood heart
    chest heat tablet pill pills joint neck skin bone diet lung lungs
    """.split()
)

_ACTIVITY_WORDS = frozenset(
    """
    run running runner workout train training exercise jog jogging walk
    walking hike hiking lift lifting bike biking swim swimming
    """.split()
)

_HEALTH_PHRASES = (
    "blood pressure", "heart rate", "resting heart", "blood sugar",
    "mental health", "air quality", "body temperature",
    "too hot", "too cold",
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
    # Set for a Scout safety tier. The server puts this line first.
    safety: str | None = None
    tier: str = TIER_NONE
    search: bool = True
    actions: list[str] = field(default_factory=list)

    def as_dict(self) -> dict:
        out = {
            "activate": self.activate,
            "reason": self.reason,
            "mission": None if self.mission is None else self.mission.as_dict(),
            "tier": self.tier,
            "search": self.search,
        }
        if self.safety:
            out["safety"] = self.safety
        if self.actions:
            out["actions"] = list(self.actions)
        return out


def _has(lower: str, needles: tuple[str, ...]) -> bool:
    return any(needle in lower for needle in needles)


_WORD = re.compile(r"[a-z0-9]+(?:'[a-z]+)?")


def is_health(text: str) -> bool:
    """True when the text names a health topic (symptom, body, drug, sleep, ...).

    Ambiguous everyday words only count with another health word, a lookup
    cue, or an activity word ("too hot to run", "iron supplement").
    """
    lower = str(text or "").lower()
    if _has(lower, _HEALTH_PHRASES):
        return True
    words = _WORD.findall(lower)
    clear: list[str] = []
    ambiguous: list[str] = []
    for word in words:
        if word.startswith("zone"):
            clear.append(word)
        elif word in _HEALTH_WORDS:
            (ambiguous if word in _AMBIGUOUS_HEALTH else clear).append(word)
    if clear:
        return True
    if not ambiguous:
        return False
    if len(ambiguous) >= 2:
        return True
    if _has(lower, _LOOKUP_CUES):
        return True
    return any(word in _ACTIVITY_WORDS for word in words)


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


def _crisis(text: str, private_terms) -> GateDecision | None:
    """Ask guidance for the Scout tier. Self-harm never searches."""
    found = _guidance.scout_safety(text)
    if found is None:
        return None
    if not found.search:
        return GateDecision(
            True, "safety", None, found.line,
            tier=found.tier, search=False, actions=list(found.actions),
        )
    mission = _mission(text, private_terms, min_terms=1)
    if mission is None:
        mission = MissionBrief(
            question="medical emergency warning signs",
            terms=["medical", "emergency", "warning", "signs"],
            prefer=["medlineplus", "pubmed"],
            retain=False,
        )
    else:
        mission.prefer = ["medlineplus", "pubmed"]
    return GateDecision(
        True, "safety", mission, found.line,
        tier=found.tier, search=True, actions=list(found.actions),
    )


def safety_source(line: str = "", *, tier: str | None = None) -> dict:
    if tier in (TIER_SELF_HARM_INTENT, TIER_SELF_HARM_THOUGHTS, TIER_STRESS):
        return dict(SELF_HARM_SOURCE)
    if line and "988" in line and tier != TIER_EMERGENCY:
        return dict(SELF_HARM_SOURCE)
    return dict(EMERGENCY_SOURCE)


def with_safety(answer: str, line: str, limit: int = CLIENT_EVIDENCE_CHARS) -> str:
    """Safety line first so a front-clip cannot drop it."""
    line = str(line or "").strip()
    body = " ".join(str(answer or "").split())
    if not line:
        return body[:limit] if len(body) > limit else body
    if not body:
        return line
    room = limit - len(line) - 2
    if room <= 0:
        return line[:limit]
    if len(body) > room:
        cut = body[:room]
        stop = cut.rfind(".")
        body = cut[: stop + 1].strip() if stop > 0 else ""
    text = f"{line}\n\n{body}" if body else line
    return text if len(text) <= limit else text[:limit]


def evaluate(prompt: str, private_terms: tuple[str, ...] | list[str] = ()) -> GateDecision:
    text = str(prompt or "").strip()
    if not text:
        return GateDecision(False, "empty")
    text = _RELATION.sub(" ", text)
    crisis = _crisis(text, private_terms)
    if crisis is not None:
        return crisis
    lower = text.lower()
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
    crisis = _crisis(text, private_terms)
    if crisis is not None:
        return crisis
    mission = _mission(text, private_terms, min_terms=1 if is_health(text) else 2)
    if mission is None:
        return GateDecision(False, "no_terms")
    return GateDecision(True, "handoff", mission)
