"""Deterministic reasoner for the dummy ARIA orchestrator.

Typed signals in, a Decision out, then a multi-paragraph letter.
No Bedrock. No answer bank.
"""

from __future__ import annotations

from .reasoner_core import Decision, TypedSignals, decide, extract_signals
from .reasoner_letter import compose_reply

__all__ = ["Decision", "TypedSignals", "compose_reply", "decide", "extract_signals", "reason"]


def reason(context, message: str, seed: int = 42) -> tuple[Decision, str]:
    signals = extract_signals(context, message)
    decision = decide(signals)
    _ = seed
    return decision, compose_reply(decision, signals)
