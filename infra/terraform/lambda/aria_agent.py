"""ARIA – Adaptive Reasoning Intelligence Architecture.

The elite AI performance coach for Forge, powered by Claude directly via the
Anthropic API. Features:
  - Claude Sonnet 4.6 for real-time agentic chat with tool use
  - Claude Opus 4.8 for deep analysis with extended thinking
  - Prompt caching on the system prompt and conversation history
  - Tool-augmented responses grounded in the user's real health data
  - Graceful fallback when the API is unreachable
"""
from __future__ import annotations

import json
import os
from typing import Any, Callable

ARIA_CHAT_MODEL = os.getenv("ARIA_CHAT_MODEL", "claude-sonnet-4-6")
ARIA_ANALYSIS_MODEL = os.getenv("ARIA_ANALYSIS_MODEL", "claude-opus-4-8")
ARIA_MAX_TOOL_ITERATIONS = int(os.getenv("ARIA_MAX_TOOL_ITERATIONS", "5"))
ARIA_CHAT_MAX_TOKENS = int(os.getenv("ARIA_CHAT_MAX_TOKENS", "2048"))
ARIA_ANALYSIS_MAX_TOKENS = int(os.getenv("ARIA_ANALYSIS_MAX_TOKENS", "8192"))
ARIA_THINKING_BUDGET = int(os.getenv("ARIA_THINKING_BUDGET", "10000"))


ARIA_SYSTEM_PROMPT = """\
You are ARIA (Adaptive Reasoning Intelligence Architecture), the elite AI \
performance coach built into the Forge fitness app. You are the user's dedicated \
personal coach with full access to their biometric profile, training history, \
and health data.

Your expertise spans:
- NSCA Certified Strength and Conditioning (CSCS) — programming, periodization, \
exercise science, injury prevention
- Sleep science and recovery — HRV interpretation, sleep staging, autonomic \
nervous system recovery, readiness modelling
- Sports nutrition — macronutrient strategy, meal timing, periodized nutrition, \
supplementation evidence
- Sports psychology — mindset coaching, habit formation, intrinsic motivation, \
performance under pressure

Core coaching principles:
1. Data-first: Every recommendation is grounded in the user's actual metrics — \
never give generic advice when real data exists
2. Individualized: Adapt every response to their specific goals, experience level, \
coaching style preference, and today's readiness
3. Progressive: Build sustainable momentum, not one-off interventions
4. Holistic: Sleep, stress, nutrition, and training are one interconnected system — \
coach the whole athlete
5. Honest: When data is incomplete or a question is outside your scope, say so \
directly rather than guessing

Communication style:
- Direct and specific — give the exact number, exercise, or recommendation
- Evidence-based — cite the user's actual metrics when making recommendations
- Adapt tone to their coaching style (push-hard, balanced, patient, data-driven)
- Concise but complete — say everything that matters, skip what does not

CRITICAL RULE: Before making any specific training, recovery, or nutrition \
recommendation, call the appropriate tools to check the user's current data. \
A recommendation without their actual readiness score, sleep, or workout history \
is a guess — not coaching.\
"""


class ARIAError(Exception):
    """Raised when ARIA cannot complete a request."""

    def __init__(self, status_code: int, message: str) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message


ToolHandler = Callable[[str, str, dict[str, Any]], Any]


class ARIAAgent:
    """
    Core ARIA agent. Drives all AI-powered coaching interactions.

    tool_handler: callable(user_id, tool_name, tool_input) -> Any
    """

    def __init__(self, tool_handler: ToolHandler | None = None) -> None:
        self._client: Any = None
        self.tool_handler = tool_handler

    # ------------------------------------------------------------------
    # Client
    # ------------------------------------------------------------------

    def _get_client(self) -> Any:
        if self._client is not None:
            return self._client

        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise ARIAError(
                503,
                "ARIA is not configured: ANTHROPIC_API_KEY environment variable is missing.",
            )

        try:
            import anthropic
        except ImportError as exc:
            raise ARIAError(
                503,
                "ARIA requires the anthropic SDK. Add 'anthropic' to requirements.txt.",
            ) from exc

        self._client = anthropic.Anthropic(api_key=api_key)
        return self._client

    # ------------------------------------------------------------------
    # Helpers
    # ------------------------------------------------------------------

    def _system_blocks(self) -> list[dict[str, Any]]:
        """System prompt blocks with cache_control on the large static block."""
        return [
            {
                "type": "text",
                "text": ARIA_SYSTEM_PROMPT,
                "cache_control": {"type": "ephemeral"},
            }
        ]

    @staticmethod
    def _serialize_content(content: Any) -> list[dict[str, Any]]:
        """Convert SDK content blocks to JSON-serializable dicts."""
        if isinstance(content, str):
            return [{"type": "text", "text": content}]
        if isinstance(content, list):
            result = []
            for block in content:
                if isinstance(block, dict):
                    result.append(block)
                elif hasattr(block, "type"):
                    block_type = block.type
                    if block_type == "text":
                        result.append({"type": "text", "text": block.text})
                    elif block_type == "tool_use":
                        result.append(
                            {
                                "type": "tool_use",
                                "id": block.id,
                                "name": block.name,
                                "input": block.input,
                            }
                        )
                    elif block_type == "thinking":
                        result.append({"type": "thinking", "thinking": block.thinking})
                    elif block_type == "tool_result":
                        result.append(
                            {
                                "type": "tool_result",
                                "tool_use_id": block.tool_use_id,
                                "content": block.content,
                            }
                        )
            return result
        return []

    @staticmethod
    def _extract_text(content: Any) -> str:
        """Pull all text parts from content blocks."""
        parts: list[str] = []
        if isinstance(content, str):
            return content
        if isinstance(content, list):
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    parts.append(str(block.get("text", "")))
                elif hasattr(block, "type") and block.type == "text":
                    parts.append(block.text)
        return "\n".join(parts).strip()

    def _build_messages(
        self,
        conversation: list[dict[str, Any]],
        new_user_content: str,
        inject_context: str | None = None,
    ) -> list[dict[str, Any]]:
        """
        Build the messages list for the API.

        Applies cache_control to the last historical message to persist the
        conversation prefix in the cache between turns.
        """
        messages: list[dict[str, Any]] = []

        # Stamp the last historical message with a cache breakpoint so turns
        # after the first benefit from cached prompt tokens.
        for i, msg in enumerate(conversation):
            if i == len(conversation) - 1 and msg.get("role") == "assistant":
                msg_copy = dict(msg)
                content = list(msg_copy.get("content", []))
                if content:
                    last = dict(content[-1]) if isinstance(content[-1], dict) else {"type": "text", "text": str(content[-1])}
                    last["cache_control"] = {"type": "ephemeral"}
                    content[-1] = last
                msg_copy["content"] = content
                messages.append(msg_copy)
            else:
                messages.append(msg)

        # Build the new user turn.
        if inject_context and not conversation:
            # On the first message inject a cached context block so subsequent
            # turns reuse those tokens without re-sending the context.
            user_content: list[dict[str, Any]] = [
                {
                    "type": "text",
                    "text": f"[MY HEALTH & TRAINING CONTEXT]\n{inject_context}",
                    "cache_control": {"type": "ephemeral"},
                },
                {"type": "text", "text": new_user_content},
            ]
        else:
            user_content = [{"type": "text", "text": new_user_content}]

        messages.append({"role": "user", "content": user_content})
        return messages

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def chat(
        self,
        *,
        user_id: str,
        user_message: str,
        conversation: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        inject_context: str | None = None,
    ) -> dict[str, Any]:
        """
        Run one real-time chat turn with optional tool use.

        Returns a dict containing:
          answer          – the final assistant text
          toolCallsMade   – list of tool calls executed
          model           – model ID used
          usage           – token counts including cache stats
          updatedConversation – the full conversation after this turn (serializable)
        """
        client = self._get_client()
        messages = self._build_messages(conversation, user_message, inject_context)
        tool_calls_made: list[dict[str, Any]] = []
        total_in = total_out = cache_read = cache_create = 0

        for _ in range(ARIA_MAX_TOOL_ITERATIONS):
            kwargs: dict[str, Any] = {
                "model": ARIA_CHAT_MODEL,
                "max_tokens": ARIA_CHAT_MAX_TOKENS,
                "system": self._system_blocks(),
                "messages": messages,
            }
            if tools:
                kwargs["tools"] = tools
                kwargs["tool_choice"] = {"type": "auto"}

            response = client.messages.create(**kwargs)

            usage = response.usage
            total_in += getattr(usage, "input_tokens", 0)
            total_out += getattr(usage, "output_tokens", 0)
            cache_read += getattr(usage, "cache_read_input_tokens", 0)
            cache_create += getattr(usage, "cache_creation_input_tokens", 0)

            serialized_content = self._serialize_content(response.content)

            if response.stop_reason == "tool_use":
                messages.append({"role": "assistant", "content": response.content})

                tool_result_blocks: list[dict[str, Any]] = []
                for block in response.content:
                    if not (hasattr(block, "type") and block.type == "tool_use"):
                        continue
                    tool_name = block.name
                    tool_input = block.input
                    tool_use_id = block.id

                    if self.tool_handler is not None:
                        try:
                            raw = self.tool_handler(user_id, tool_name, tool_input)
                            result_str = json.dumps(raw, default=str)
                            is_error = False
                        except Exception as exc:
                            result_str = f"Tool error: {exc}"
                            is_error = True
                    else:
                        result_str = json.dumps({"note": "no tool handler"})
                        is_error = False

                    tool_calls_made.append(
                        {
                            "tool": tool_name,
                            "input": tool_input,
                            "success": not is_error,
                        }
                    )
                    tool_result_blocks.append(
                        {
                            "type": "tool_result",
                            "tool_use_id": tool_use_id,
                            "content": result_str,
                            "is_error": is_error,
                        }
                    )

                messages.append({"role": "user", "content": tool_result_blocks})
                continue

            # end_turn or max_tokens — extract the final answer
            answer = self._extract_text(response.content)

            # Build the serializable conversation snapshot
            updated: list[dict[str, Any]] = []
            for m in messages:
                mc = dict(m)
                if isinstance(mc.get("content"), list):
                    mc["content"] = self._serialize_content(mc["content"])
                updated.append(mc)
            updated.append({"role": "assistant", "content": serialized_content})

            return {
                "answer": answer,
                "toolCallsMade": tool_calls_made,
                "model": ARIA_CHAT_MODEL,
                "usage": {
                    "inputTokens": total_in,
                    "outputTokens": total_out,
                    "cacheReadTokens": cache_read,
                    "cacheCreationTokens": cache_create,
                },
                "updatedConversation": updated,
            }

        raise ARIAError(500, "ARIA exceeded the maximum tool iteration limit without a final answer.")

    def analyze(
        self,
        *,
        question: str,
        context: str,
        thinking_budget: int = ARIA_THINKING_BUDGET,
    ) -> dict[str, Any]:
        """
        Deep analysis using Claude Opus with extended thinking.

        Best for complex, multi-faceted questions that benefit from careful
        multi-step reasoning: periodization decisions, injury risk assessment,
        sleep pattern root-cause analysis.

        Returns answer, thinking trace, model used, and token counts.
        """
        client = self._get_client()

        prompt = (
            f"[USER HEALTH & TRAINING CONTEXT]\n{context}\n\n"
            f"[ANALYSIS QUESTION]\n{question}"
        )

        response = client.messages.create(
            model=ARIA_ANALYSIS_MODEL,
            max_tokens=ARIA_ANALYSIS_MAX_TOKENS,
            thinking={
                "type": "enabled",
                "budget_tokens": thinking_budget,
            },
            system=self._system_blocks(),
            messages=[{"role": "user", "content": prompt}],
        )

        thinking_text = ""
        answer_text = ""
        for block in response.content:
            if hasattr(block, "type"):
                if block.type == "thinking":
                    thinking_text = block.thinking
                elif block.type == "text":
                    answer_text += block.text

        usage = response.usage
        return {
            "answer": answer_text.strip(),
            "thinking": thinking_text,
            "model": ARIA_ANALYSIS_MODEL,
            "thinkingBudget": thinking_budget,
            "usage": {
                "inputTokens": getattr(usage, "input_tokens", 0),
                "outputTokens": getattr(usage, "output_tokens", 0),
                "cacheReadTokens": getattr(usage, "cache_read_input_tokens", 0),
                "cacheCreationTokens": getattr(usage, "cache_creation_input_tokens", 0),
            },
        }

    def generate_insights(
        self,
        *,
        context: str,
    ) -> dict[str, Any]:
        """
        Generate 3-5 proactive coaching insights from the user's data patterns.

        Returns a structured list of insight objects.
        """
        client = self._get_client()

        prompt = f"""\
Analyze the following user health and training data and identify 3-5 proactive \
coaching insights.

{context}

For each insight examine a concrete data pattern, explain why it matters for \
the user's stated goals, and give one specific, actionable recommendation.

Return ONLY a JSON array — no other text — in this exact structure:
[
  {{
    "type": "sleep|training|recovery|nutrition|mindset",
    "priority": "high|medium|low",
    "title": "Short insight title (max 8 words)",
    "observation": "What the data shows (1-2 sentences)",
    "recommendation": "One specific actionable step",
    "metric": "The key metric that triggered this insight"
  }}
]\
"""

        response = client.messages.create(
            model=ARIA_CHAT_MODEL,
            max_tokens=2048,
            system=self._system_blocks(),
            messages=[{"role": "user", "content": prompt}],
        )

        raw = self._extract_text(response.content)
        insights = _parse_json_array(raw)

        usage = response.usage
        return {
            "insights": insights,
            "model": ARIA_CHAT_MODEL,
            "usage": {
                "inputTokens": getattr(usage, "input_tokens", 0),
                "outputTokens": getattr(usage, "output_tokens", 0),
            },
        }

    def process_voice(
        self,
        *,
        transcript: str,
        context: str,
    ) -> dict[str, Any]:
        """
        Turn a raw voice transcript into a coaching response.

        Handles natural speech patterns, filler words, and incomplete sentences.
        Returns a concise, conversational answer suitable for text-to-speech.
        """
        client = self._get_client()

        prompt = f"""\
The following is a voice transcript from the user. Interpret it as a natural \
spoken coaching query, correct any voice-to-text artifacts, and respond as \
their coach.

USER CONTEXT:
{context}

VOICE TRANSCRIPT:
"{transcript}"

Respond in 2-4 conversational sentences. Use their actual data where relevant. \
Keep your answer suitable for reading aloud.\
"""

        response = client.messages.create(
            model=ARIA_CHAT_MODEL,
            max_tokens=512,
            system=self._system_blocks(),
            messages=[{"role": "user", "content": prompt}],
        )

        answer = self._extract_text(response.content)
        usage = response.usage
        return {
            "answer": answer,
            "processedTranscript": transcript.strip(),
            "model": ARIA_CHAT_MODEL,
            "usage": {
                "inputTokens": getattr(usage, "input_tokens", 0),
                "outputTokens": getattr(usage, "output_tokens", 0),
            },
        }


# ---------------------------------------------------------------------------
# Module-level agent instance and test seam
# ---------------------------------------------------------------------------

_agent: ARIAAgent | None = None


def get_agent() -> ARIAAgent:
    global _agent
    if _agent is None:
        from aria_tools import handle_tool_call
        _agent = ARIAAgent(tool_handler=handle_tool_call)
    return _agent


def set_agent(agent: ARIAAgent | None) -> None:
    """Test seam: replace the module-level agent."""
    global _agent
    _agent = agent


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_json_array(text: str) -> list[Any]:
    """Extract and parse the first JSON array from a text response."""
    try:
        return json.loads(text)
    except (json.JSONDecodeError, ValueError):
        pass
    start = text.find("[")
    end = text.rfind("]") + 1
    if start >= 0 and end > start:
        try:
            return json.loads(text[start:end])
        except (json.JSONDecodeError, ValueError):
            pass
    return []
