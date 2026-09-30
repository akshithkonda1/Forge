"""Turn a user's message into a topic query that is safe to send off-device.

The phone runs the same rules (``AriaQueryPrivacy`` in ForgeCore) before a
question ever reaches Scout; Scout runs them again on arrival as defense in
depth. What survives is a bag of topic keywords — no names, no numbers, no
contact details, no first-person narrative.

Why keywords and not the sentence: "I'm 34, slept 5 hours, my wife Priya
says my resting HR of 71 is high — should I skip leg day?" must reach a
search engine as ``skip leg day resting heart rate high`` and nothing else.
"""

from __future__ import annotations

import re

MAX_KEYWORDS = 10

# Health / training terms that legitimately carry digits. Everything else
# with a digit (ages, hours, vitals, dates, doses) is dropped.
_DIGIT_TERMS = frozenset(
    {
        "vo2", "vo2max", "omega-3", "omega3", "b12", "b6", "d3", "k2",
        "5k", "10k", "pm2.5", "covid-19", "zone-2", "zone2", "5x5", "a1c",
    }
)

_STOPWORDS = frozenset(
    """
    a an and are as at be been being but by can could did do does doing done
    for from had has have having he her hers him his how i i'd i'll i'm i've
    if in into is it it's its just me mine my myself of on or our ours she
    should so than that that's the their them then there these they this
    those to too up us was we we're were what what's when where which while
    who whom why will with would you you're your yours yourself am im ive
    id ill dont don't doesnt doesn't cant can't wont won't isnt isn't
    really very much many some any also still ok okay please thanks thank
    hey hi hello aria yeah yes no not today tonight tomorrow yesterday
    morning evening night week weekend
    wife husband partner girlfriend boyfriend son daughter mom dad mother
    father brother sister friend boss coworker kid kids baby
    named called says said told tell name
    """.split()
)

_EMAIL = re.compile(r"\b[\w.+-]+@[\w-]+\.[\w.-]+\b")
_URL = re.compile(r"\bhttps?://\S+|\bwww\.\S+", re.I)
_PHONE = re.compile(r"\+?\d[\d\s().-]{6,}\d")
_HANDLE = re.compile(r"(?<!\w)@\w+")
_NAMED = re.compile(r"\b(?:named|called|name\s+is|name's|this\s+is)\s+\S+", re.I)
_TOKEN = re.compile(r"[a-z][a-z0-9.+'-]*|\d[a-z0-9.+'-]*", re.I)


def scrub_query(text: str, private_terms: tuple[str, ...] | list[str] = ()) -> str:
    """Return a space-joined keyword query, or ``""`` when nothing safe remains."""
    raw = str(text or "")
    if not raw.strip():
        return ""
    raw = _EMAIL.sub(" ", raw)
    raw = _URL.sub(" ", raw)
    raw = _PHONE.sub(" ", raw)
    raw = _HANDLE.sub(" ", raw)
    raw = _NAMED.sub(" ", raw)
    private = {
        part.lower()
        for term in private_terms
        for part in re.split(r"\s+", str(term or "").strip())
        if len(part) >= 2
    }
    keywords: list[str] = []
    for match in _TOKEN.finditer(raw.lower()):
        token = match.group(0).strip(".'+-")
        if not token or token in _STOPWORDS or token in private:
            continue
        if any(ch.isdigit() for ch in token) and token not in _DIGIT_TERMS:
            continue
        if len(token) < 2:
            continue
        if token not in keywords:
            keywords.append(token)
        if len(keywords) >= MAX_KEYWORDS:
            break
    return " ".join(keywords)
