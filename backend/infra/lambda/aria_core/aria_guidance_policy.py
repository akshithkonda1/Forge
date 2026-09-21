"""Three-band Dummy / on-device guidance — coach, coach-with-care, refer-out.

Python port of ForgeCore's ``AriaGuidancePolicy.swift``. The four-band
``guidance.assess`` path (first-aid / emergency / refer_out) still runs on
``generate_response``. This module is what Dummy and native chat use so a
Kotlin client does not reimplement the needles.

Stdlib only. Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

from dataclasses import dataclass

COACH = "coach"
COACH_WITH_CARE = "coachWithCare"
REFER_OUT = "referOut"

_REFER_OUT: tuple[tuple[str, str], ...] = (
    ("chest pain", "Stop what you're doing and get medical help now — chest pain isn't something I can coach around."),
    ("chest tightness", "Please treat chest tightness as urgent and speak to a doctor or emergency service now."),
    ("pressure in my chest", "That needs emergency care now, not a training decision."),
    ("can't breathe", "If you're struggling to breathe, call emergency services now."),
    ("cant breathe", "If you're struggling to breathe, call emergency services now."),
    ("passed out", "Fainting needs a doctor before any training question — please get it looked at."),
    ("fainted", "Fainting needs a doctor before any training question — please get it looked at."),
    ("blacked out", "Blacking out needs medical review before we talk about load."),
    ("slurred speech", "Sudden speech changes are an emergency — call emergency services now."),
    ("face is drooping", "That's an emergency. Call emergency services now."),
    ("numb on one side", "Sudden one-sided numbness is an emergency — call emergency services now."),
    ("kill myself", "I'm not the right help for this, and I don't want to hand you a workout instead. Please talk to someone now — a crisis line, a doctor, or someone you trust."),
    ("want to die", "I'm not the right help for this. Please reach out to a crisis line or someone you trust today."),
    ("hurt myself", "I'm not the right help for this. Please talk to a crisis line, a doctor, or someone you trust."),
    ("should i stop taking", "Never change a prescription on my say-so — that's between you and whoever prescribed it."),
    ("increase my dose", "Dosing is your prescriber's call, not mine."),
    ("do i have", "I can't diagnose, and guessing at one would be worse than useless. That's a question for a clinician."),
    ("is this cancer", "I can't answer that, and I won't guess. Please see a doctor."),
    ("make myself throw up", "I won't help with that. Please talk to a doctor or an eating-disorder helpline — that's the help that's actually useful here."),
    ("how little can i eat", "I'm not going to help you undereat. If food feels like this right now, a doctor or a dietitian is the right person."),
    ("stop eating for", "I won't build that. If you want to talk about fuelling properly, I'm here for that."),
)

_CARE: tuple[tuple[str, str], ...] = (
    ("for weeks", "Pain that's stuck around for weeks is worth getting looked at properly — I can work around it, but I can't tell you what it is."),
    ("for months", "Months is long enough to get it assessed. I'll keep the work clear of it in the meantime."),
    ("getting worse", "If it's trending worse rather than settling, get it seen. I'll keep today away from it."),
    ("sharp pain", "Sharp is the kind I take seriously — worth a professional look. Nothing today should reproduce it."),
    ("dizzy", "Dizziness I'd want a doctor's read on. Let's keep today low and off your feet where we can."),
    ("lightheaded", "Worth mentioning to a doctor if it repeats. Today we go easy."),
    ("can't put weight", "If you can't load it at all, that's an assessment, not a training tweak."),
    ("swollen", "Swelling that hasn't settled deserves a look. I'll route around it."),
    ("numb", "Numbness is worth a professional opinion. I'll keep load off it."),
    ("pregnant", "Training through pregnancy is real and doable, but the parameters are your doctor's to set — bring me what they say and I'll build inside it."),
)

_BODY_MARKERS = ("pain", "hurt", "sore", "injury", "ache", "strain", "symptom", "flare")


@dataclass(frozen=True)
class GuidanceDecision:
    band: str
    matched: str | None = None
    line: str | None = None

    def to_dict(self) -> dict:
        return {"band": self.band, "matched": self.matched, "line": self.line}


def _body_related(lower: str) -> bool:
    return any(marker in lower for marker in _BODY_MARKERS)


def decide(text: str, guidance_only_mode: bool = False) -> GuidanceDecision:
    lower = (text or "").lower()
    for needle, line in _REFER_OUT:
        if needle in lower:
            return GuidanceDecision(band=REFER_OUT, matched=needle, line=line)
    for needle, line in _CARE:
        if needle in lower:
            return GuidanceDecision(band=COACH_WITH_CARE, matched=needle, line=line)
    if guidance_only_mode and _body_related(lower):
        return GuidanceDecision(
            band=COACH_WITH_CARE,
            matched="guidance_only",
            line="Structure and pacing from me; anything diagnostic stays with your clinician.",
        )
    return GuidanceDecision(band=COACH)


def should_remind_on_ordinary_turn(turn_index: int) -> bool:
    return turn_index > 0 and turn_index % 12 == 0
