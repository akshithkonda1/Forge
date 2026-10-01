"""Scout query gate — decides per turn whether Scout should be active.

Scout is always-on as infrastructure (the box runs, the cache warms) but
*active* only when this gate says so. The gate runs on every prompt,
costs almost nothing, and only pays for Scout when the answer genuinely
needs the open web.

Design rules (from the Scout architecture discussion):

- The gate is a classifier, not a keyword bag that grows forever. v1 is
  phrase + domain matching ported from the existing
  ``AriaWebResearch.isResearchWorthy`` / ``AriaReferenceCatalog`` logic so
  Swift and Python trigger on the *same* turns. A future small model can
  replace the matching without changing the contract.
- The gate returns a **mission brief**, not a paragraph. Scout does not
  re-interpret the user's intent — it executes the brief.
- Fail-closed: any error returns an inactive decision. A missed lookup is
  fine; a gate that throws and stalls the turn is not.
- No network. No Bedrock. No AWS SDK. Stdlib only, same constraint as
  the rest of this package.
"""

from __future__ import annotations

import hashlib
import re
from dataclasses import dataclass, field

# Ported from AriaWebResearch.researchPhrases (Swift) — kept identical on
# purpose so the two platforms trigger on the same turns. One list, ported
# not reinvented.
_RESEARCH_PHRASES = (
    "how do i",
    "how to",
    "best way to",
    "is it true",
    "what does the science say",
    "what does research say",
    "research shows",
    "studies show",
    "recomp",
    "lose fat and gain muscle",
    "gain muscle and lose fat",
    "how much protein should",
    "is it possible to",
    "how long does it take to",
    "evidence for",
    "evidence on",
    "should i",
    "do i need",
    "what should i eat",
    "what should i do",
    "is it safe to",
    "can i",
    "will it help",
    "does it work",
    "benefits of",
    "side effects",
    "how much sleep",
    "how often should",
)

# From AriaReferenceCatalog.questionSuggestsFever — whole-phrase, not
# single-word, so "I run hot when I train" doesn't false-positive.
_FEVER_PHRASES = (
    "fever",
    "temperature",
    "too hot",
    "running hot",
    "chills",
    "thermometer",
    "100.",
    "99.5",
)

# From AriaReferenceCatalog.questionSuggestsEventPrep.
_EVENT_PREP_PHRASES = (
    "tuxedo",
    "tux ",
    "black tie",
    "what to wear",
    "what should i wear",
    "wedding attire",
    "suit for",
    "dress for a wedding",
    "outfit for",
)

# From AriaReferenceCatalog.questionSuggestsAging.
_AGING_PHRASES = (
    "training age",
    "biological age",
    "fitness age",
    "calendar age",
    "vascular age",
    "inner age",
    "metabolic age",
    "phenotypic age",
    "vo2 max",
    "vo2max",
    "cardiorespiratory",
    "cardio fitness",
    "how old am i",
    "age comparison",
)

# Domains where research is allowed at all. Mirrors the Swift leadingDomain
# allow-list. Everything else (companion, calendar, crisis) never fires.
_ALLOWED_DOMAINS = frozenset(
    {
        "training",
        "nutrition",
        "progress",
        "sleep",
        "readiness",
        "lifestyle",
        "activity",
        "body",
        "cycle",
        "aging",
        "fever",
    }
)


@dataclass(frozen=True)
class ScoutMissionBrief:
    """What Scout executes. Scrubbed keywords only — no raw prompt text,
    no vitals, no names, no titles."""

    keywords: tuple[str, ...]
    question: str
    domain: str
    cache_key: str


@dataclass(frozen=True)
class ScoutGateDecision:
    """The gate's answer for one turn."""

    active: bool
    brief: ScoutMissionBrief | None = None
    reason: str = ""


def _contains(text: str, phrase: str) -> bool:
    if " " in phrase:
        return phrase in text
    return re.search(rf"\b{re.escape(phrase)}\b", text) is not None


def _scrub_keywords(message: str, domain: str) -> tuple[str, ...]:
    """Pull the topic words Scout should search. Lowercased, de-punctuated,
    deduped, capped. This is what leaves the phone toward the box — nothing
    else does."""
    lower = message.lower()
    tokens = re.findall(r"[a-z0-9]{3,}", lower)
    stop = {
        "the", "and", "for", "you", "your", "are", "was", "were", "have", "has",
        "had", "this", "that", "with", "from", "what", "when", "where", "which",
        "who", "how", "why", "can", "will", "should", "would", "could", "about",
        "into", "over", "under", "after", "before", "between", "through",
        "during", "without", "within", "against", "among", "along", "across",
        "does", "did", "done", "being", "been", "also", "just", "only", "even",
        "much", "many", "some", "such", "than", "then", "them", "they", "their",
        "ours", "mine", "yours", "here", "there", "very", "really", "still",
        "already", "today", "now", "please", "help", "need", "want", "like",
        "know", "think", "feel", "make", "take", "give", "come", "went", "said",
        "told", "asked", "trying", "getting", "going", "doing", "saying",
        "looking", "finding", "using", "having", "being", " Aria ".strip().lower(),
    }
    # Domain word is the anchor keyword — Scout always searches it.
    keywords = [domain]
    for tok in tokens:
        if tok in stop or tok == domain:
            continue
        if tok not in keywords:
            keywords.append(tok)
        if len(keywords) >= 8:
            break
    return tuple(keywords)


def _cache_key(keywords: tuple[str, ...]) -> str:
    """Hash of the scrubbed keyword tuple. This is the only thing that
    survives a Scout run — not the content, not the question."""
    payload = "|".join(keywords).encode("utf-8")
    return hashlib.sha256(payload).hexdigest()[:16]


def classify_query_for_scout(
    message: str,
    kind: str = "lifestyle",
) -> ScoutGateDecision:
    """Evaluate one prompt. Returns an inactive decision on any error."""
    try:
        text = (message or "").strip()
        if not text:
            return ScoutGateDecision(active=False, reason="empty")

        domain = (kind or "lifestyle").strip().lower() or "lifestyle"
        if domain not in _ALLOWED_DOMAINS:
            return ScoutGateDecision(
                active=False, reason=f"domain_not_allowed:{domain}"
            )

        lower = text.lower()

        # Always-fire domains.
        if domain == "aging" or any(_contains(lower, p) for p in _AGING_PHRASES):
            reason = "aging"
        elif any(_contains(lower, p) for p in _FEVER_PHRASES):
            reason = "fever"
            domain = "fever"
        elif (
            any(_contains(lower, p) for p in _EVENT_PREP_PHRASES)
            or ("wedding" in lower and any(w in lower for w in ("wear", "suit", "dress")))
        ):
            reason = "event_prep"
        elif any(_contains(lower, p) for p in _RESEARCH_PHRASES):
            reason = "research_phrase"
        else:
            return ScoutGateDecision(active=False, reason="no_trigger")

        keywords = _scrub_keywords(text, domain)
        brief = ScoutMissionBrief(
            keywords=keywords,
            question=text[:500],
            domain=domain,
            cache_key=_cache_key(keywords),
        )
        return ScoutGateDecision(active=True, brief=brief, reason=reason)
    except Exception as exc:  # fail-closed: never let the gate break a turn
        return ScoutGateDecision(active=False, reason=f"error:{type(exc).__name__}")
