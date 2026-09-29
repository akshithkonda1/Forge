"""Dummy-only open-ended ARIA chat for local founder tuning.

Every turn still runs ingest → personal model → stance through
``dummy_orchestrator.respond(engine="lambda")``. The conversational layer
sits on top and never bypasses speak_guard, the vitals/digit scrub, or
medical-boundary guidance. Bedrock stays off.
"""

from .session import ChatSession, run_turn, ENGINE, SCHEMA_VERSION

__all__ = ["ChatSession", "run_turn", "ENGINE", "SCHEMA_VERSION"]
