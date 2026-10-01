"""Decide whether a turn should wake Scout, and write the mission brief.

Scout's process can stay up. It must not search on every chat turn. ARIA
(or the Dummy) runs ``evaluate`` on the prompt first. A yes is a handoff:
scrubbed keywords plus a mission, never the raw message, never names,
numbers, or samples. A no means ARIA keeps talking and Scout stays idle.

``from_handoff`` is for a caller that already decided. It still scrubs and
still refuses crisis language. It does not require a lookup cue.
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

_SAFETY_OFF = (
    "kill myself", "want to die", "end my life", "don't want to live",
    "dont want to live", "suicidal", "heart attack", "chest pain",
    "can't breathe", "cant breathe", "overdosed", "overdose",
    "not breathing", "call 911",
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

    def as_dict(self) -> dict:
        return {
            "activate": self.activate,
            "reason": self.reason,
            "mission": None if self.mission is None else self.mission.as_dict(),
        }


def _has(lower: str, needles: tuple[str, ...]) -> bool:
    return any(needle in lower for needle in needles)


def _prefer(terms: list[str]) -> list[str]:
    health = {
        "protein", "caffeine", "heat", "hydration", "supplement", "sleep",
        "hrv", "vo2", "injury", "tendon", "creatine", "electrolyte",
        "altitude", "illness", "fever",
    }
    if any(term in health or term.startswith("zone") for term in terms):
        return ["pubmed", "medlineplus"]
    return ["web"]


def _mission(text: str, private_terms) -> MissionBrief | None:
    scrubbed = scrub_query(text, private_terms)
    terms = [part for part in scrubbed.split() if part]
    if len(terms) < 2:
        return None
    return MissionBrief(question=scrubbed, terms=terms, prefer=_prefer(terms), retain=False)


def evaluate(prompt: str, private_terms: tuple[str, ...] | list[str] = ()) -> GateDecision:
    text = str(prompt or "").strip()
    if not text:
        return GateDecision(False, "empty")
    text = _RELATION.sub(" ", text)
    lower = text.lower()
    if _has(lower, _SAFETY_OFF):
        return GateDecision(False, "safety")
    explicit = _has(lower, _LOOKUP_CUES)
    session = _has(lower, _SESSION_CUES) and not explicit
    if session or not explicit:
        return GateDecision(False, "session")
    mission = _mission(text, private_terms)
    if mission is None:
        return GateDecision(False, "no_terms")
    return GateDecision(True, "lookup", mission)


def from_handoff(query: str, private_terms: tuple[str, ...] | list[str] = ()) -> GateDecision:
    """Caller already decided this is a lookup. Still scrub. Still refuse a crisis."""
    text = _RELATION.sub(" ", str(query or "").strip())
    if not text:
        return GateDecision(False, "empty")
    if _has(text.lower(), _SAFETY_OFF):
        return GateDecision(False, "safety")
    mission = _mission(text, private_terms)
    if mission is None:
        return GateDecision(False, "no_terms")
    return GateDecision(True, "handoff", mission)
