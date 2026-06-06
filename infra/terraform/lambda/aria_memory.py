"""ARIA memory management.

Handles persistence and retrieval of ARIA conversation history, long-term
insights, and user summaries. Conversation is stored in DynamoDB as a flat
list of message dicts that the agent can replay for multi-turn context.

When a conversation grows past MAX_MESSAGES it is automatically summarized by
ARIA to keep the messages array within API context limits.
"""
from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone
from typing import Any

from storage import dynamodb, keys


MAX_MESSAGES = 40
SUMMARY_KEEP_TAIL = 6  # messages preserved verbatim after a summary


def _strip_keys(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


# ---------------------------------------------------------------------------
# Conversation storage
# ---------------------------------------------------------------------------

def load_conversation(user_id: str, thread_id: str = "current") -> list[dict[str, Any]]:
    """
    Load the full ARIA conversation for this user thread from DynamoDB.

    Returns a list of message dicts: [{"role": "user"|"assistant", "content": ...}, ...]
    The first item may be a special "summary" marker if the conversation was
    compressed.
    """
    meta_item = dynamodb.get_item(**keys.aria_conversation_key(user_id, thread_id))
    if not meta_item:
        return []

    raw_messages = meta_item.get("messages") or []
    # DynamoDB may store as a JSON string if the list was too large for a
    # DynamoDB attribute; handle both.
    if isinstance(raw_messages, str):
        try:
            raw_messages = json.loads(raw_messages)
        except (json.JSONDecodeError, ValueError):
            raw_messages = []

    return raw_messages if isinstance(raw_messages, list) else []


def save_conversation(
    user_id: str,
    messages: list[dict[str, Any]],
    thread_id: str = "current",
) -> None:
    """
    Persist the ARIA conversation to DynamoDB.

    Messages are serialized to JSON and stored in a single item to keep
    the read path to one GetItem call.
    """
    now = datetime.now(timezone.utc).isoformat()
    item = {
        **keys.aria_conversation_key(user_id, thread_id),
        "messages": json.dumps(messages, default=str),
        "messageCount": len(messages),
        "updatedAt": now,
        "threadId": thread_id,
    }
    dynamodb.put_item(item)


def clear_conversation(user_id: str, thread_id: str = "current") -> None:
    """Delete the stored ARIA conversation for this thread."""
    dynamodb.delete_item(**keys.aria_conversation_key(user_id, thread_id))


def append_messages(
    user_id: str,
    new_messages: list[dict[str, Any]],
    thread_id: str = "current",
) -> list[dict[str, Any]]:
    """
    Append new messages and return the full updated conversation.

    If the conversation exceeds MAX_MESSAGES a summary marker is prepended
    and only the tail is kept verbatim.
    """
    existing = load_conversation(user_id, thread_id)
    combined = existing + new_messages

    if len(combined) > MAX_MESSAGES:
        summary_text = _build_summary_text(combined[: -SUMMARY_KEEP_TAIL])
        summary_marker: dict[str, Any] = {
            "role": "user",
            "content": (
                "[ARIA CONVERSATION SUMMARY — prior turns compressed]\n"
                + summary_text
            ),
        }
        combined = [summary_marker] + combined[-SUMMARY_KEEP_TAIL:]

    save_conversation(user_id, combined, thread_id)
    return combined


# ---------------------------------------------------------------------------
# Insights storage
# ---------------------------------------------------------------------------

def save_insight(user_id: str, insight: dict[str, Any]) -> str:
    """Persist a single coaching insight. Returns the insight ID."""
    from seed_data import today_iso  # avoid circular at module level

    insight_id = insight.get("insightId") or uuid.uuid4().hex[:12]
    date = today_iso()
    now = datetime.now(timezone.utc).isoformat()
    item = {
        **keys.aria_insight_key(user_id, date, insight_id),
        "insightId": insight_id,
        "date": date,
        "createdAt": now,
        **{k: v for k, v in insight.items() if k not in ("pk", "sk")},
    }
    dynamodb.put_item(item)
    return insight_id


def load_insights(user_id: str, days: int = 7) -> list[dict[str, Any]]:
    """Load ARIA insights created within the last N days."""
    items = dynamodb.query_prefix_desc(
        keys.user_pk(user_id),
        "ARIA#INSIGHT#",
        limit=days * 5,
    )
    return [_strip_keys(i) for i in items]


def save_bulk_insights(
    user_id: str, insights: list[dict[str, Any]]
) -> list[str]:
    """Persist multiple insights and return their IDs."""
    return [save_insight(user_id, insight) for insight in insights]


# ---------------------------------------------------------------------------
# User summary (long-term ARIA memory)
# ---------------------------------------------------------------------------

def load_user_summary(user_id: str) -> dict[str, Any] | None:
    """Load the long-term ARIA user summary if one exists."""
    item = dynamodb.get_item(**keys.aria_summary_key(user_id))
    return _strip_keys(item) if item else None


def save_user_summary(user_id: str, summary: str) -> None:
    """Save an updated long-term summary of the user's coaching context."""
    now = datetime.now(timezone.utc).isoformat()
    item = {
        **keys.aria_summary_key(user_id),
        "summary": summary,
        "updatedAt": now,
    }
    dynamodb.put_item(item)


# ---------------------------------------------------------------------------
# Internal helpers
# ---------------------------------------------------------------------------

def _build_summary_text(messages: list[dict[str, Any]]) -> str:
    """
    Build a compact text summary of conversation messages.

    This is used locally (no LLM call) to avoid recursive API calls during
    message compression. A proper async summarization task should be kicked
    off separately for high-quality compression.
    """
    lines: list[str] = []
    for msg in messages:
        role = msg.get("role", "unknown")
        content = msg.get("content", "")
        if isinstance(content, list):
            text_parts = []
            for block in content:
                if isinstance(block, dict) and block.get("type") == "text":
                    text_parts.append(block.get("text", ""))
            content = " ".join(text_parts)
        prefix = "User" if role == "user" else "ARIA"
        snippet = str(content)[:200].strip()
        if snippet:
            lines.append(f"{prefix}: {snippet}")

    return "\n".join(lines[:30])
