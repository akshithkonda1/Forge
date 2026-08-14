"""Cycle Partner mindset — partner and parent, from redacted fields only.

The client already holds a redacted digest (phase, energy, thoughtfulness).
This module turns that into how it *feels* to be them, and how you show up.
It never stores reproductive data. It never congratulates you for having kids.
"""

from __future__ import annotations

from typing import Any

from services.source_map import COACH_NAME

PHASES = {"bleeding", "rebuilding", "winding", "unknown"}
ROLES = {"partner", "child", "family", "friend"}


def mindset(body: dict[str, Any]) -> dict[str, Any]:
    role = str(body.get("role") or "partner").lower()
    if role not in ROLES:
        role = "partner"
    phase = str(body.get("phase") or "unknown").lower()
    if phase not in PHASES:
        phase = "unknown"
    energy = str(body.get("energy") or "steady").lower()
    name = str(body.get("name") or ("her" if role == "child" else "them")).strip()[:40]
    early = bool(body.get("earlyCycles"))
    thoughtfulness = bool(body.get("extraThoughtfulnessHelps"))

    if role == "child":
        return _child(name, phase, energy, early, thoughtfulness)
    if role == "partner":
        return _partner(name, phase, energy, thoughtfulness)
    return _other(name, role, phase, energy)


def _partner(name: str, phase: str, energy: str, thoughtfulness: bool) -> dict[str, Any]:
    if phase == "bleeding":
        feel = (
            f"{name} is bleeding. Pain, fog, and a shorter fuse can all be true at once. "
            "That is a body under load, not a personality change aimed at you."
        )
        do_this = [
            "Take one concrete thing off their plate without announcing it.",
            "Heat, water, easy food, and a quieter room. Ask once, then follow the answer.",
            "If they want closeness without sex, that is still closeness.",
        ]
        not_this = [
            "Don't explain their mood to them with this app.",
            "Don't read a no as rejection of you.",
            "Don't schedule anything that can't be cancelled.",
        ]
        headline = f"{name} is on their period. Comfort and a lighter load help most."
    elif phase == "winding":
        feel = (
            f"{name} is winding down. The week can feel heavier, sleep worse, patience thinner. "
            "They are not becoming difficult. Capacity is lower."
        )
        do_this = [
            "Lower the stakes — fewer commitments, earlier nights.",
            "Ask what would help rather than guessing.",
        ]
        not_this = [
            "Don't save a hard conversation for this week.",
            "Don't take irritability as the whole story about the relationship.",
        ]
        headline = f"{name} is winding down. Keep the week gentle."
    elif phase == "rebuilding":
        feel = (
            f"{name}'s energy is often coming back. Plans that were too much last week "
            "may fit again — still their call."
        )
        do_this = [
            "Follow their lead on how much to take on.",
            "Good stretch for the plan you postponed, if they want it.",
        ]
        not_this = ["Don't declare them 'back to normal' for them."]
        headline = f"{name} is in a steadier stretch. Follow their lead."
    else:
        feel = f"No recent update from {name}. The only reliable signal is asking."
        do_this = ["Check in once, without using the cycle as the subject."]
        not_this = ["Don't fill the silence with a theory about their hormones."]
        headline = f"No recent updates from {name}."

    if thoughtfulness:
        do_this.append("Small and specific beats big and vague.")
    if energy == "low":
        do_this.append("Match their pace instead of pulling them along.")

    return _pack(headline, feel, do_this, not_this, intimacy=_partner_intimacy(phase))


def _partner_intimacy(phase: str) -> list[str]:
    if phase == "bleeding":
        return [
            "Desire varies a lot here, in both directions. Ask, don't assume.",
            "If they're in pain, pressure is the opposite of helpful.",
        ]
    if phase == "winding":
        return ["Tenderness without an agenda is worth more than novelty."]
    if phase == "rebuilding":
        return ["Often easier to feel connected. Still ask. Nothing here tells you whether they want to."]
    return ["The only reliable signal is asking."]


def _child(name: str, phase: str, energy: str, early: bool, thoughtfulness: bool) -> dict[str, Any]:
    if early and phase == "bleeding":
        feel = (
            f"This may be new for {name}. First cycles are often irregular, crampy, and embarrassing "
            "in a way that has nothing to do with you. She needs the day to stay ordinary."
        )
        headline = f"{name} is bleeding. First-year cycles: supplies, privacy, zero spectacle."
        do_this = [
            "Keep pads, liners, period underwear, and a spare pair of underwear where she can take them without asking.",
            "A heat pack, water, and a favourite meal. No speech.",
            "Believe pain. 'Walk it off' is not care.",
            "If she wants school or practice cancelled, you are the adult who makes that easy with the coach or office.",
            "If she wants to talk, she will start. Leave the door open. Do not walk through it.",
        ]
        not_this = [
            "Don't say 'welcome to womanhood' or treat this as a milestone to celebrate in front of her.",
            "Don't joke, nickname, or mention it to siblings, relatives, or teammates.",
            "Don't interrogate flow, products, or 'are you sure?'",
            "Don't make her educate you. You read this so she doesn't have to teach.",
        ]
    elif phase == "bleeding":
        feel = (
            f"{name} is on her period. Cramps, fatigue, and wanting to be left alone can sit next to "
            "wanting someone quietly nearby. That is not mixed signals. It is a hard day."
        )
        headline = f"{name} is on her period. Comfort, supplies, zero embarrassment."
        do_this = [
            "Stock the bathroom and the car. No announcement.",
            "Offer heat, water, a ride, a lighter evening. Let her pick.",
            "Back her if she needs to modify sport or skip it.",
        ]
        not_this = [
            "No commentary on her body — not even kind commentary.",
            "Don't tease, and don't use this app to explain her to herself.",
        ]
    elif phase == "winding":
        feel = (
            f"{name} may be pre-period: shorter patience, worse sleep, less buffer for a long day. "
            "She is not being dramatic."
        )
        headline = f"{name} may be pre-period. Softer expectations help."
        do_this = ["Lighter evening, snacks she actually wants, fewer stacked commitments."]
        not_this = ["Don't call it attitude. Don't pile on corrections today."]
    elif phase == "rebuilding":
        feel = f"{name}'s energy is often coming back. Let her set the pace back into full days."
        headline = f"{name} is in a steadier stretch. Follow her lead."
        do_this = ["Normal life is fine. Still ask before a packed weekend."]
        not_this = ["Don't make the cycle ending a topic either."]
    else:
        feel = f"No recent update from {name}. Be available. Don't hunt for a cycle story."
        headline = f"No recent updates from {name}."
        do_this = ["Ordinary reliability — food, rides, privacy."]
        not_this = ["Don't fill the gap by asking if she's 'on her period.'"]

    if thoughtfulness:
        do_this.append("A ride home and a favourite meal beat a talk about feelings.")
    if energy == "low":
        do_this.append("Match her pace. Quiet is a form of help.")

    return _pack(headline, feel, do_this, not_this, intimacy=[], parent=True, early=early)


def _other(name: str, role: str, phase: str, energy: str) -> dict[str, Any]:
    feel = f"{name} shared a coarse update with you. Stay practical. Don't become the narrator of their body."
    headline = f"Show up for {name}. Keep it ordinary."
    do_this = ["Ask what would help. Follow the answer."]
    not_this = ["Don't explain their mood using this app."]
    return _pack(headline, feel, do_this, not_this, intimacy=[])


def _pack(
    headline: str,
    feel: str,
    do_this: list[str],
    not_this: list[str],
    *,
    intimacy: list[str],
    parent: bool = False,
    early: bool = False,
) -> dict[str, Any]:
    return {
        "coach": COACH_NAME,
        "headline": headline,
        "mindset": feel,
        "doThis": do_this,
        "notThis": not_this,
        "intimacy": intimacy,
        "parent": parent,
        "earlyCycles": early,
    }
