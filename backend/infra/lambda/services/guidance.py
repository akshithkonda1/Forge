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

The line: general first-aid *information* and "call 911" are in-bounds; naming a
diagnosis or prescribing/adjusting medication for a condition is not. This is a
safety layer, not medical advice.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field

COACH = "coach"
FIRST_AID = "first_aid"
EMERGENCY = "emergency"
REFER_OUT = "refer_out"


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


def _has(text: str, needles: tuple[str, ...]) -> bool:
    return any(n in text for n in needles)


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
    "suicidal", "kill myself", "want to die", "end my life", "hurt myself",
    "take my own life", "don't want to be here", "dont want to be here",
)

# --- First-aid how-to (helping someone; information is in-bounds) ------------
_HOWTO_CUES = (
    "how do i", "how to", "how can i", "what do i do", "what should i do",
    "steps to", "how would i", "teach me", "walk me through", "show me how",
)
_FIRST_AID_TOPICS = (
    "cpr", "rescue breath", "heimlich", "choking", "aed", "defibrillat",
    "recovery position", "stop the bleeding", "stop bleeding", "bleeding",
    "tourniquet", "first aid", "first-aid", "someone is choking",
    "someone collapsed", "someone passed out", "burn", "drowning", "seizure",
    "nosebleed",
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
)
_DIRECT_MED = (
    "prescribe", "prescription for", "what medication", "which medication",
    "what medicine", "what drug", "my medication", "my meds", "my dose",
    "my dosage", "increase my dose", "decrease my dose", "up my dose",
    "lower my dose", "adjust my dose", "double my dose", "change my dose",
    "stop taking", "should i stop my", "off my meds", "how much insulin",
    "what dosage", "what dose", "how many mg", "mg of",
)
_TAKE_CUES = ("what should i take", "what can i take", "should i take")
_SYMPTOM_TERMS = (
    "pain", "headache", "migraine", "fever", "cough", "cold", "flu", "nausea",
    "vomiting", "diarrhea", "rash", "cramps", "ache", "sore throat", "infection",
    "dizzy", "dizziness", "chest",
)

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
    return _has(lower, _TAKE_CUES) and _has(lower, _SYMPTOM_TERMS)


def _detect_first_aid_topics(lower: str) -> list[str]:
    topics: list[str] = []
    if _has(lower, ("cpr", "rescue breath", "chest compression", "not breathing",
                    "isn't breathing", "isnt breathing", "no pulse", "no heartbeat",
                    "cardiac arrest", "aed", "defibrillat")):
        topics.append("cpr")
    if _has(lower, ("choking", "heimlich", "can't breathe", "cant breathe",
                    "something stuck", "throat is closing")):
        topics.append("choking")
    if _has(lower, ("bleeding", "blood", "tourniquet", "cut", "wound", "nosebleed")):
        topics.append("bleeding")
    if _has(lower, ("collapsed", "passed out", "unconscious", "unresponsive",
                    "won't wake", "wont wake", "fainted")):
        topics.append("unconscious")
    if _has(lower, ("seizure", "convulsing")):
        topics.append("seizure")
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


def _first_aid_body(lower: str) -> str:
    return "\n".join(_FIRST_AID_STEPS[t] for t in _detect_first_aid_topics(lower))


def classify_band(message: str) -> str:
    lower = (message or "").lower()
    if _has(lower, _SELF_HARM):
        return EMERGENCY
    if _has(lower, _ESCALATION_REQUEST) or _has(lower, _EMERGENCY_STATE):
        return EMERGENCY
    if _has(lower, _HOWTO_CUES) and _has(lower, _FIRST_AID_TOPICS):
        return FIRST_AID
    if _is_prescription_request(lower) or _is_diagnosis_request(lower):
        return REFER_OUT
    return COACH


def assess(message: str) -> Guidance | None:
    """Return a Guidance for a boundary/emergency message, or None for COACH."""
    lower = (message or "").lower()
    band = classify_band(message)
    if band == COACH:
        return None

    if band == EMERGENCY:
        parts = [
            "If this is an emergency, call 911 (or your local emergency number) "
            "right now — or use your phone's Emergency SOS. That comes first."
        ]
        if _has(lower, _SELF_HARM):
            parts.append(_CRISIS_LINE)
        parts.append(_first_aid_body(lower))
        parts.append(
            "I'm a lifestyle coach, not a doctor, so I can't diagnose what's "
            "happening — but getting emergency help matters most right now."
        )
        prose = " ".join(p.strip() for p in parts if p.strip())
        return Guidance(
            band=EMERGENCY,
            prose=prose,
            message=prose,
            confidence_reason="Safety policy: possible emergency — escalate to 911.",
            suggested_actions=["Call 911", "Start first aid", "Stay on the line"],
            wants_escalation=True,
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

    # REFER_OUT
    prose = (
        "I'm your lifestyle coach here in Forge — not a doctor — so I can't "
        "diagnose conditions or make medication decisions. That kind of call "
        "deserves a licensed clinician who can actually examine you, so please "
        "loop in your doctor or pharmacist on this one. What I can help with is "
        "the lifestyle side around it — sleep, training load, recovery, stress, "
        "nutrition — whenever you want to go there."
    )
    return Guidance(
        band=REFER_OUT,
        prose=prose,
        message=prose,
        confidence_reason="Safety policy: ARIA suggests lifestyle, never diagnoses or prescribes.",
        suggested_actions=["Talk to a clinician", "Work on the lifestyle side", "Ask me something else"],
        wants_escalation=False,
    )


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
