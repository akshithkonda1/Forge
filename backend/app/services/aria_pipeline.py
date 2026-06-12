"""Four-turn Bedrock coaching pipeline grounded in deidentified conclusions."""
from __future__ import annotations

import json
from typing import Any

from ai.aria_agent import ARIA_CHAT_MODEL, ARIAError, get_agent
from services.phi_deidentify import deidentify_conclusions


class PipelineIncompleteError(ARIAError):
    """Raised when any of the four required turns fails."""

    def __init__(self, turn: int, message: str) -> None:
        super().__init__(404, f"ARIA pipeline incomplete at turn {turn}: {message}")
        self.turn = turn


_REQUIRED_TURNS = 4


def _one_text_turn(prompt: str, *, max_tokens: int = 1024) -> tuple[str, dict[str, Any]]:
    agent = get_agent()
    messages = [{"role": "user", "content": [{"type": "text", "text": prompt}]}]
    result = agent._one_turn(ARIA_CHAT_MODEL, messages, None, max_tokens)
    text = agent._extract_text(result["content"])
    if not text.strip():
        raise ValueError("empty model response")
    return text.strip(), result.get("usage", {})


def run_four_turn_pipeline(
    *,
    user_message: str,
    conclusions: dict[str, Any],
    profile_context: str | None = None,
    mode: str = "chat",
) -> dict[str, Any]:
    """
    Execute exactly four Bedrock turns:
      1. Context synthesis
      2. Data-grounded analysis
      3. Recommendation formation
      4. Final coaching response
    """
    brief = deidentify_conclusions(conclusions)
    brief_json = json.dumps(brief, separators=(",", ":"))
    profile_block = profile_context or "{}"
    usages: list[dict[str, Any]] = []
    artifacts: dict[str, str] = {}

    try:
        turn1, usage1 = _one_text_turn(
            "Turn 1/4 — Context synthesis. Summarize the athlete state from the conclusions "
            f"JSON only. Output 3-5 bullet facts.\n\nCONCLUSIONS:\n{brief_json}\n\nPROFILE:\n{profile_block}",
            max_tokens=512,
        )
        artifacts["turn1"] = turn1
        usages.append(usage1)

        turn2, usage2 = _one_text_turn(
            "Turn 2/4 — Data-grounded analysis. Using the synthesis below, explain what matters "
            f"most for today's coaching decision.\n\nSYNTHESIS:\n{turn1}\n\nUSER MESSAGE:\n{user_message}",
            max_tokens=768,
        )
        artifacts["turn2"] = turn2
        usages.append(usage2)

        turn3, usage3 = _one_text_turn(
            "Turn 3/4 — Recommendation formation. Propose one primary action and one backup "
            f"action. Be specific to metrics.\n\nANALYSIS:\n{turn2}",
            max_tokens=768,
        )
        artifacts["turn3"] = turn3
        usages.append(usage3)

        turn4, usage4 = _one_text_turn(
            "Turn 4/4 — Final coaching response. Write the athlete-facing answer in 2-5 sentences. "
            f"Mode={mode}. No markdown.\n\nRECOMMENDATIONS:\n{turn3}\n\nUSER MESSAGE:\n{user_message}",
            max_tokens=1024,
        )
        artifacts["turn4"] = turn4
        usages.append(usage4)
    except (ARIAError, ValueError, KeyError) as exc:
        failed_turn = len(artifacts) + 1
        raise PipelineIncompleteError(failed_turn, str(exc)) from exc

    if len(artifacts) != _REQUIRED_TURNS:
        raise PipelineIncompleteError(len(artifacts) + 1, "missing turn output")

    total_usage = {
        "inputTokens": sum(u.get("inputTokens", 0) for u in usages),
        "outputTokens": sum(u.get("outputTokens", 0) for u in usages),
        "turnsCompleted": _REQUIRED_TURNS,
    }

    return {
        "answer": artifacts["turn4"],
        "pipelineArtifacts": artifacts,
        "coachingBrief": brief.get("coachingBrief"),
        "model": ARIA_CHAT_MODEL,
        "usage": total_usage,
        "turnsCompleted": _REQUIRED_TURNS,
    }