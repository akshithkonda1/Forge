"""ARIA – Adaptive Reasoning Intelligence Architecture.

Supports two inference backends selectable via ARIA_BACKEND env var:
  - "bedrock"   (default) – uses Lambda IAM role via boto3, no API key needed
  - "anthropic"           – uses Anthropic SDK, requires ANTHROPIC_API_KEY

Features:
  - Claude Sonnet 4.6 for real-time agentic chat with tool use
  - Claude Opus 4.8 for deep analysis with extended thinking
  - Prompt caching on system prompt and conversation history
  - Tool-augmented responses grounded in the user's real health data
  - Automatic fallback to ARIA_BACKUP_MODEL if the primary call fails
"""
from __future__ import annotations

import json
import logging
import os
from typing import Any, Callable

logger = logging.getLogger(__name__)

ARIA_BACKEND = os.getenv("ARIA_BACKEND", "bedrock")

_BD_CHAT = "anthropic.claude-sonnet-4-6"
_BD_ANALYSIS = "anthropic.claude-opus-4-8"
_AN_CHAT = "claude-sonnet-4-6"
_AN_ANALYSIS = "claude-opus-4-8"

if ARIA_BACKEND == "anthropic":
    ARIA_CHAT_MODEL = os.getenv("ARIA_CHAT_MODEL", _AN_CHAT)
    ARIA_ANALYSIS_MODEL = os.getenv("ARIA_ANALYSIS_MODEL", _AN_ANALYSIS)
    ARIA_BACKUP_MODEL = os.getenv("ARIA_BACKUP_MODEL", _AN_ANALYSIS)
else:
    ARIA_CHAT_MODEL = os.getenv("ARIA_CHAT_MODEL", _BD_CHAT)
    ARIA_ANALYSIS_MODEL = os.getenv("ARIA_ANALYSIS_MODEL", _BD_ANALYSIS)
    ARIA_BACKUP_MODEL = os.getenv("ARIA_BACKUP_MODEL", _BD_ANALYSIS)

ARIA_MAX_TOOL_ITERATIONS = int(os.getenv("ARIA_MAX_TOOL_ITERATIONS", "5"))
ARIA_CHAT_MAX_TOKENS = int(os.getenv("ARIA_CHAT_MAX_TOKENS", "2048"))
ARIA_ANALYSIS_MAX_TOKENS = int(os.getenv("ARIA_ANALYSIS_MAX_TOKENS", "8192"))
ARIA_THINKING_BUDGET = int(os.getenv("ARIA_THINKING_BUDGET", "10000"))
_AWS_REGION = os.getenv("AWS_REGION", "us-east-1")


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


# ---------------------------------------------------------------------------
# Format conversion helpers (module-level, stateless)
# ---------------------------------------------------------------------------

def _norm_to_bedrock_blocks(block: dict[str, Any]) -> list[dict[str, Any]]:
    """Translate one normalized content block into Bedrock converse block(s).

    Thinking blocks are input-only from Bedrock (they come back in responses)
    and cannot be round-tripped in the conversation history, so they are dropped.
    """
    btype = block.get("type")
    if btype == "text":
        return [{"text": block["text"]}]
    if btype == "tool_use":
        return [{"toolUse": {
            "toolUseId": block["id"],
            "name": block["name"],
            "input": block.get("input", {}),
        }}]
    if btype == "tool_result":
        content_val = block.get("content", "")
        status = "error" if block.get("is_error") else "success"
        return [{"toolResult": {
            "toolUseId": block["tool_use_id"],
            "content": [{"text": str(content_val)}],
            "status": status,
        }}]
    # "thinking" and unknown types: skip
    return []


def _bedrock_block_to_norm(block: dict[str, Any]) -> dict[str, Any] | None:
    """Translate one Bedrock response content block to normalized format."""
    if "text" in block:
        return {"type": "text", "text": block["text"]}
    if "toolUse" in block:
        tu = block["toolUse"]
        return {"type": "tool_use", "id": tu["toolUseId"], "name": tu["name"], "input": tu.get("input", {})}
    if "reasoningContent" in block:
        text = block["reasoningContent"].get("reasoningText", {}).get("text", "")
        return {"type": "thinking", "thinking": text}
    return None


def _messages_to_bedrock(
    messages: list[dict[str, Any]],
    *,
    cache_prefix_end: bool = False,
) -> list[dict[str, Any]]:
    """Convert normalized message list to Bedrock converse format.

    If cache_prefix_end is True a cachePoint block is appended to the last
    message's content, instructing Bedrock to cache everything up to that point.
    """
    result: list[dict[str, Any]] = []
    for i, msg in enumerate(messages):
        raw = msg.get("content", [])
        if isinstance(raw, str):
            raw = [{"type": "text", "text": raw}]
        blocks: list[dict[str, Any]] = []
        for b in raw:
            blocks.extend(_norm_to_bedrock_blocks(b))
        if cache_prefix_end and i == len(messages) - 1 and blocks:
            blocks.append({"cachePoint": {"type": "default"}})
        result.append({"role": msg["role"], "content": blocks})
    return result


def _messages_to_anthropic(
    messages: list[dict[str, Any]],
    *,
    cache_prefix_end: bool = False,
) -> list[dict[str, Any]]:
    """Convert normalized message list to Anthropic SDK format.

    If cache_prefix_end is True the last block of the last message gets a
    cache_control ephemeral marker.
    """
    result: list[dict[str, Any]] = []
    for i, msg in enumerate(messages):
        raw = msg.get("content", [])
        if isinstance(raw, str):
            raw = [{"type": "text", "text": raw}]
        content = [dict(b) for b in raw]
        if cache_prefix_end and i == len(messages) - 1 and content:
            last = dict(content[-1])
            last["cache_control"] = {"type": "ephemeral"}
            content[-1] = last
        result.append({"role": msg["role"], "content": content})
    return result


def _tools_to_bedrock(tools: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Convert Anthropic-format tool defs to Bedrock toolConfig tools list."""
    return [
        {"toolSpec": {
            "name": t["name"],
            "description": t["description"],
            "inputSchema": {"json": t["input_schema"]},
        }}
        for t in tools
    ]


def _serialize_sdk_content(content: Any) -> list[dict[str, Any]]:
    """Convert Anthropic SDK content objects (with .type etc.) to plain dicts."""
    if isinstance(content, str):
        return [{"type": "text", "text": content}]
    if not isinstance(content, list):
        return []
    result: list[dict[str, Any]] = []
    for block in content:
        if isinstance(block, dict):
            result.append(block)
        elif hasattr(block, "type"):
            bt = block.type
            if bt == "text":
                result.append({"type": "text", "text": block.text})
            elif bt == "tool_use":
                result.append({"type": "tool_use", "id": block.id, "name": block.name, "input": block.input})
            elif bt == "thinking":
                result.append({"type": "thinking", "thinking": block.thinking})
            elif bt == "tool_result":
                result.append({"type": "tool_result", "tool_use_id": block.tool_use_id, "content": block.content})
    return result


# ---------------------------------------------------------------------------
# ARIAAgent
# ---------------------------------------------------------------------------

class ARIAAgent:
    """Core ARIA agent. Drives all AI-powered coaching interactions."""

    def __init__(self, tool_handler: ToolHandler | None = None) -> None:
        self._bedrock_client: Any = None
        self._anthropic_client: Any = None
        self.tool_handler = tool_handler

    # ── Client accessors ──────────────────────────────────────────────────────

    def _get_bedrock_client(self) -> Any:
        if self._bedrock_client is not None:
            return self._bedrock_client
        try:
            import boto3
        except ImportError as exc:
            raise ARIAError(503, "boto3 is required for the Bedrock backend. Add boto3 to requirements.txt.") from exc
        self._bedrock_client = boto3.client("bedrock-runtime", region_name=_AWS_REGION)
        return self._bedrock_client

    def _get_anthropic_client(self) -> Any:
        if self._anthropic_client is not None:
            return self._anthropic_client
        api_key = os.getenv("ANTHROPIC_API_KEY")
        if not api_key:
            raise ARIAError(
                503,
                "ARIA is not configured: ANTHROPIC_API_KEY environment variable is missing.",
            )
        try:
            import anthropic
        except ImportError as exc:
            raise ARIAError(503, "anthropic SDK is required for ARIA_BACKEND=anthropic.") from exc
        self._anthropic_client = anthropic.Anthropic(api_key=api_key)
        return self._anthropic_client

    def _get_client(self) -> Any:
        """Compatibility shim — returns the active backend client."""
        if ARIA_BACKEND == "anthropic":
            return self._get_anthropic_client()
        return self._get_bedrock_client()

    # ── System prompt blocks ──────────────────────────────────────────────────

    @staticmethod
    def _bedrock_system() -> list[dict[str, Any]]:
        return [{"text": ARIA_SYSTEM_PROMPT}, {"cachePoint": {"type": "default"}}]

    @staticmethod
    def _anthropic_system() -> list[dict[str, Any]]:
        return [{"type": "text", "text": ARIA_SYSTEM_PROMPT, "cache_control": {"type": "ephemeral"}}]

    # ── Low-level single-turn calls ───────────────────────────────────────────

    def _one_turn_bedrock(
        self,
        model: str,
        working: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None,
        max_tokens: int,
        extra_fields: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Single Bedrock converse() call. Returns normalized result."""
        client = self._get_bedrock_client()

        # Split history (all but last) from the new user turn (last)
        history = working[:-1]
        current = [working[-1]]
        bedrock_msgs = (
            _messages_to_bedrock(history, cache_prefix_end=bool(history))
            + _messages_to_bedrock(current)
        )

        kwargs: dict[str, Any] = {
            "modelId": model,
            "system": self._bedrock_system(),
            "messages": bedrock_msgs,
            "inferenceConfig": {"maxTokens": max_tokens},
        }
        if tools:
            kwargs["toolConfig"] = {"tools": _tools_to_bedrock(tools)}
        if extra_fields:
            kwargs["additionalModelRequestFields"] = extra_fields

        response = client.converse(**kwargs)

        stop_reason = response.get("stopReason", "end_turn")
        raw = response.get("output", {}).get("message", {}).get("content", [])
        norm_content = [b for b in (_bedrock_block_to_norm(b) for b in raw) if b is not None]
        u = response.get("usage", {})
        usage = {
            "inputTokens": u.get("inputTokens", 0),
            "outputTokens": u.get("outputTokens", 0),
            "cacheReadTokens": u.get("cacheReadInputTokens", 0),
            "cacheCreationTokens": u.get("cacheWriteInputTokens", 0),
        }
        return {"stop_reason": stop_reason, "content": norm_content, "usage": usage}

    def _one_turn_anthropic(
        self,
        model: str,
        working: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None,
        max_tokens: int,
        thinking: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Single Anthropic messages.create() call. Returns normalized result."""
        client = self._get_anthropic_client()

        history = working[:-1]
        current = [working[-1]]
        sdk_msgs = (
            _messages_to_anthropic(history, cache_prefix_end=bool(history))
            + _messages_to_anthropic(current)
        )

        kwargs: dict[str, Any] = {
            "model": model,
            "max_tokens": max_tokens,
            "system": self._anthropic_system(),
            "messages": sdk_msgs,
        }
        if tools:
            kwargs["tools"] = tools
            kwargs["tool_choice"] = {"type": "auto"}
        if thinking:
            kwargs["thinking"] = thinking

        response = client.messages.create(**kwargs)

        norm_content = _serialize_sdk_content(response.content)
        u = response.usage
        usage = {
            "inputTokens": getattr(u, "input_tokens", 0),
            "outputTokens": getattr(u, "output_tokens", 0),
            "cacheReadTokens": getattr(u, "cache_read_input_tokens", 0),
            "cacheCreationTokens": getattr(u, "cache_creation_input_tokens", 0),
        }
        return {"stop_reason": response.stop_reason, "content": norm_content, "usage": usage}

    def _one_turn(
        self,
        model: str,
        working: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None,
        max_tokens: int,
        *,
        bedrock_extra: dict[str, Any] | None = None,
        anthropic_thinking: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Single-turn call with automatic backup-model fallback.

        Tries `model` first. On any non-ARIAError exception, retries with
        ARIA_BACKUP_MODEL (if different) before raising ARIAError(503).
        """
        def call(m: str) -> dict[str, Any]:
            if ARIA_BACKEND == "anthropic":
                return self._one_turn_anthropic(m, working, tools, max_tokens, anthropic_thinking)
            return self._one_turn_bedrock(m, working, tools, max_tokens, bedrock_extra)

        try:
            return call(model)
        except ARIAError:
            raise
        except Exception as primary_exc:
            if ARIA_BACKUP_MODEL and ARIA_BACKUP_MODEL != model:
                logger.warning(
                    "ARIA primary model %s failed (%s); retrying with backup %s",
                    model, primary_exc, ARIA_BACKUP_MODEL,
                )
                try:
                    result = call(ARIA_BACKUP_MODEL)
                    result["usedBackup"] = True
                    result["backupModel"] = ARIA_BACKUP_MODEL
                    return result
                except Exception as backup_exc:
                    raise ARIAError(
                        503,
                        f"ARIA primary ({model}) and backup ({ARIA_BACKUP_MODEL}) both failed: {backup_exc}",
                    ) from backup_exc
            raise ARIAError(503, f"ARIA model call failed: {primary_exc}") from primary_exc

    # ── Helpers ───────────────────────────────────────────────────────────────

    @staticmethod
    def _extract_text(content: list[dict[str, Any]]) -> str:
        return "\n".join(
            b.get("text", "") for b in content if isinstance(b, dict) and b.get("type") == "text"
        ).strip()

    # ── Public API ────────────────────────────────────────────────────────────

    def chat(
        self,
        *,
        user_id: str,
        user_message: str,
        conversation: list[dict[str, Any]],
        tools: list[dict[str, Any]] | None = None,
        inject_context: str | None = None,
    ) -> dict[str, Any]:
        """Run one real-time chat turn with optional tool use.

        Returns:
          answer              – final assistant text
          toolCallsMade       – list of tool calls executed
          model               – model ID used
          usage               – cumulative token counts
          updatedConversation – full conversation after this turn (serializable)
          usedBackup          – True if backup model was used (optional)
          backupModel         – backup model ID if used (optional)
        """
        new_user_content: list[dict[str, Any]] = []
        if inject_context and not conversation:
            new_user_content.append({"type": "text", "text": f"[MY HEALTH & TRAINING CONTEXT]\n{inject_context}"})
        new_user_content.append({"type": "text", "text": user_message})

        working: list[dict[str, Any]] = list(conversation) + [
            {"role": "user", "content": new_user_content}
        ]
        tool_calls_made: list[dict[str, Any]] = []
        total_usage = {"inputTokens": 0, "outputTokens": 0, "cacheReadTokens": 0, "cacheCreationTokens": 0}
        used_backup = False
        backup_model_used: str | None = None

        for _ in range(ARIA_MAX_TOOL_ITERATIONS):
            result = self._one_turn(ARIA_CHAT_MODEL, working, tools, ARIA_CHAT_MAX_TOKENS)

            if result.get("usedBackup"):
                used_backup = True
                backup_model_used = result.get("backupModel")

            for k in total_usage:
                total_usage[k] += result["usage"].get(k, 0)

            if result["stop_reason"] == "tool_use":
                working.append({"role": "assistant", "content": result["content"]})

                tool_result_blocks: list[dict[str, Any]] = []
                for block in result["content"]:
                    if block.get("type") != "tool_use":
                        continue
                    tool_name = block["name"]
                    tool_input = block["input"]
                    tool_use_id = block["id"]

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

                    tool_calls_made.append({"tool": tool_name, "input": tool_input, "success": not is_error})
                    tool_result_blocks.append({
                        "type": "tool_result",
                        "tool_use_id": tool_use_id,
                        "content": result_str,
                        "is_error": is_error,
                    })

                working.append({"role": "user", "content": tool_result_blocks})
                continue

            # end_turn or max_tokens — finalize
            answer = self._extract_text(result["content"])
            working.append({"role": "assistant", "content": result["content"]})

            model_used = backup_model_used if used_backup else ARIA_CHAT_MODEL
            resp: dict[str, Any] = {
                "answer": answer,
                "toolCallsMade": tool_calls_made,
                "model": model_used,
                "usage": total_usage,
                "updatedConversation": working,
            }
            if used_backup:
                resp["usedBackup"] = True
                resp["backupModel"] = backup_model_used
            return resp

        raise ARIAError(500, "ARIA exceeded the maximum tool iteration limit without a final answer.")

    def analyze(
        self,
        *,
        question: str,
        context: str,
        thinking_budget: int = ARIA_THINKING_BUDGET,
    ) -> dict[str, Any]:
        """Deep analysis using Claude Opus with extended thinking.

        Best for periodization decisions, injury risk assessment, sleep
        pattern root-cause analysis, and other multi-step reasoning tasks.
        """
        prompt = (
            f"[USER HEALTH & TRAINING CONTEXT]\n{context}\n\n"
            f"[ANALYSIS QUESTION]\n{question}"
        )
        messages = [{"role": "user", "content": [{"type": "text", "text": prompt}]}]

        if ARIA_BACKEND == "anthropic":
            result = self._one_turn(
                ARIA_ANALYSIS_MODEL, messages, None, ARIA_ANALYSIS_MAX_TOKENS,
                anthropic_thinking={"type": "enabled", "budget_tokens": thinking_budget},
            )
        else:
            result = self._one_turn(
                ARIA_ANALYSIS_MODEL, messages, None, ARIA_ANALYSIS_MAX_TOKENS,
                bedrock_extra={"thinking": {"type": "enabled", "budget_tokens": thinking_budget}},
            )

        thinking_text = ""
        answer_text = ""
        for block in result["content"]:
            bt = block.get("type")
            if bt == "thinking":
                thinking_text = block.get("thinking", "")
            elif bt == "text":
                answer_text += block.get("text", "")

        model_used = result.get("backupModel", ARIA_ANALYSIS_MODEL) if result.get("usedBackup") else ARIA_ANALYSIS_MODEL
        resp: dict[str, Any] = {
            "answer": answer_text.strip(),
            "thinking": thinking_text,
            "model": model_used,
            "thinkingBudget": thinking_budget,
            "usage": result["usage"],
        }
        if result.get("usedBackup"):
            resp["usedBackup"] = True
            resp["backupModel"] = result.get("backupModel")
        return resp

    def generate_insights(self, *, context: str) -> dict[str, Any]:
        """Generate 3-5 proactive coaching insights from the user's data patterns."""
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
        messages = [{"role": "user", "content": [{"type": "text", "text": prompt}]}]
        result = self._one_turn(ARIA_CHAT_MODEL, messages, None, 2048)
        raw = self._extract_text(result["content"])
        insights = _parse_json_array(raw)
        model_used = result.get("backupModel", ARIA_CHAT_MODEL) if result.get("usedBackup") else ARIA_CHAT_MODEL
        resp: dict[str, Any] = {
            "insights": insights,
            "model": model_used,
            "usage": {"inputTokens": result["usage"]["inputTokens"], "outputTokens": result["usage"]["outputTokens"]},
        }
        if result.get("usedBackup"):
            resp["usedBackup"] = True
            resp["backupModel"] = result.get("backupModel")
        return resp

    def process_voice(self, *, transcript: str, context: str) -> dict[str, Any]:
        """Turn a raw voice transcript into a coaching response."""
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
        messages = [{"role": "user", "content": [{"type": "text", "text": prompt}]}]
        result = self._one_turn(ARIA_CHAT_MODEL, messages, None, 512)
        answer = self._extract_text(result["content"])
        model_used = result.get("backupModel", ARIA_CHAT_MODEL) if result.get("usedBackup") else ARIA_CHAT_MODEL
        resp: dict[str, Any] = {
            "answer": answer,
            "processedTranscript": transcript.strip(),
            "model": model_used,
            "usage": {"inputTokens": result["usage"]["inputTokens"], "outputTokens": result["usage"]["outputTokens"]},
        }
        if result.get("usedBackup"):
            resp["usedBackup"] = True
            resp["backupModel"] = result.get("backupModel")
        return resp


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
