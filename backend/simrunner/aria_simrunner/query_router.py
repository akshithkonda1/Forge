"""Query router — classify a query and mirror ARIA's real model-routing table."""

from __future__ import annotations

import re

QUERY_TYPES: dict[str, list[str]] = {
    "recovery_assessment": ["recover", "recovery", "recovering", "recovered", "tired", "sore", "rest", "hrv", "readiness"],
    "training_decision": ["train", "workout", "exercise", "lift", "run"],
    "sleep_analysis": ["sleep", "slept", "wake", "bed"],
    "progress_check": ["progress", "improving", "making gains", "pr", "plateau", "gains"],
    "override_request": ["don't care", "override", "ignore", "push through", "anyway", "stop telling me", "your data is wrong"],
    "ambiguous": [],  # fallback
}

# Most-specific / highest-stakes intents win when several match.
_PRECEDENCE = [
    "override_request",
    "recovery_assessment",
    "training_decision",
    "sleep_analysis",
    "progress_check",
    "ambiguous",
]

MODEL_ROUTING: dict[str, str] = {
    "recovery_assessment": "opus",
    "training_decision": "opus",
    "sleep_analysis": "sonnet",
    "progress_check": "sonnet",
    "override_request": "opus",
    "ambiguous": "sonnet",
}


def classify_query(query: str) -> str:
    text = query.lower()
    matched = {
        qtype
        for qtype, keywords in QUERY_TYPES.items()
        if any(_contains(text, kw) for kw in keywords)
    }
    for qtype in _PRECEDENCE:
        if qtype in matched:
            return qtype
    return "ambiguous"


def route_model(query_type: str) -> str:
    return MODEL_ROUTING.get(query_type, "sonnet")


def _contains(text: str, keyword: str) -> bool:
    if " " in keyword:
        return keyword in text
    return re.search(rf"\b{re.escape(keyword)}\b", text) is not None
