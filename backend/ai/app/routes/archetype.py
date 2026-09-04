"""ARIA archetype forge — invent relational archetypes for person-specific coaching.

Prefers live Bedrock/Claude when available; always returns a usable local draft.
"""
from __future__ import annotations

import json
import re
import uuid
from datetime import datetime, timezone
from typing import Any


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def _slug(name: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "_", name.lower()).strip("_")
    return s or f"custom_{uuid.uuid4().hex[:8]}"


def _local_synthesize(description: str, preferred_name: str | None) -> dict[str, Any]:
    d = (description or "").lower()
    name = preferred_name or "Living Pattern"
    tagline = description[:160] if description else "A pattern ARIA is still learning."
    speech = "Listen for their tempo. Reflect their words. Ask before advising."
    avoid = ["generic advice", "one-size-fits-all scripts"]
    stance = "See them as a full person; adapt to what you know."
    formality, humor, expressiveness, length = "neutral", "none", "balanced", "medium"
    example = "I'm here. What would help right now?"
    related = None

    if any(k in d for k in ("logic", "analyst", "data", "facts")):
        name = preferred_name or "Clear Signal"
        related = "analyst"
        speech = "Use clean structure: situation → need → ask. Skip vague emotional fog."
        humor, expressiveness = "dry", "reserved"
        example = "Here's what I'm seeing. Does that match your read?"
    elif any(k in d for k in ("teen", "daughter", "sensitive")):
        name = preferred_name or "Private Flame"
        related = "sensitiveTeen"
        speech = "Very short. Validate first. No audience. No moral speeches."
        formality, length, humor = "casual", "terse", "playful"
        avoid = ["lectures", "public call-outs", "calm down"]
        example = "I'm not mad. Want space or a snack?"
    elif any(k in d for k in ("independent", "autonomy", "control", "rebel")):
        name = preferred_name or "Open Gate"
        related = "sovereign"
        speech = "Ask permission. Offer choices. Never corner."
        avoid = ["orders", "you should", "ultimatums"]
        example = "No pressure — options are A or B. What do you want?"
    elif any(k in d for k in ("joke", "humor", "funny", "laugh")):
        name = preferred_name or "Bright Edge"
        related = "jester"
        speech = "Allow humor; land the real point gently after the laugh."
        humor, length = "playful", "terse"
    elif any(k in d for k in ("nurtur", "care", "warm")):
        name = preferred_name or "Warm Anchor"
        related = "nurturer"
        speech = "Lead with gratitude. Offer care back."
        expressiveness = "open"

    return {
        "id": str(uuid.uuid4()),
        "name": name,
        "slug": _slug(name),
        "tagline": tagline if related is None else f"{tagline}",
        "speechGuidance": speech,
        "avoid": avoid,
        "supportStance": stance,
        "formality": formality,
        "humor": humor,
        "expressiveness": expressiveness,
        "lengthBias": length,
        "exampleScript": example,
        "source": "backend",
        "inspiredByDescription": description,
        "relatedBuiltin": related,
        "createdAt": _now(),
        "updatedAt": _now(),
    }


async def create_archetype(payload: dict[str, Any]) -> dict[str, Any]:
    """POST /ai/archetype — invent a relational coaching archetype.

    Body: { user_id, description, preferred_name? }
    Tries Bedrock Claude when AWS is configured; always falls back to local synthesis.
    """
    description = str(payload.get("description") or "").strip()
    preferred = payload.get("preferred_name")
    preferred_name = str(preferred).strip() if preferred else None
    if not description:
        return {"error": "description is required", "status": 400}

    # Optional live path — best effort, never hard-fail the request.
    live: dict[str, Any] | None = None
    try:
        live = await _try_bedrock(description, preferred_name)
    except Exception:  # noqa: BLE001 — offline-friendly
        live = None

    archetype = live or _local_synthesize(description, preferred_name)
    return {
        "archetype": archetype,
        "model": archetype.get("source", "backend"),
        "status": 200,
    }


async def _try_bedrock(description: str, preferred_name: str | None) -> dict[str, Any] | None:
    """Invoke Claude on Bedrock, opt-in via ``ARIA_BEDROCK_ENABLED`` (same flag and
    truthy-value set ``services/aria_engine.py``'s ``bedrock_enabled()`` uses) so the
    default/offline path and CI stay hermetic."""
    import os

    if os.getenv("ARIA_BEDROCK_ENABLED", "").strip().lower() not in {"1", "true", "yes", "on"}:
        return None
    try:
        from backend.ai.simrunner.aria_simrunner.bedrock_client import converse
    except Exception:
        return None

    system = (
        "You invent relational personality archetypes for coaching. "
        "Return STRICT JSON with keys: name, tagline, speechGuidance, avoid (array), "
        "supportStance, formality, humor, expressiveness, lengthBias, exampleScript, relatedBuiltin."
    )
    user = f"Description: {description}\nPreferred name: {preferred_name or ''}"
    model_id = os.getenv("AI_ROUTER_MODEL_1_ID", "anthropic.claude-sonnet-4-6")
    try:
        raw = converse(model_id, system, user)
    except Exception:
        return None

    if not raw or not isinstance(raw, str):
        return None
    start, end = raw.find("{"), raw.rfind("}")
    if start < 0 or end <= start:
        return None
    try:
        obj = json.loads(raw[start : end + 1])
    except json.JSONDecodeError:
        return None

    name = str(obj.get("name") or preferred_name or "Living Pattern")
    return {
        "id": str(uuid.uuid4()),
        "name": name,
        "slug": _slug(name),
        "tagline": str(obj.get("tagline") or description[:160]),
        "speechGuidance": str(obj.get("speechGuidance") or ""),
        "avoid": list(obj.get("avoid") or []),
        "supportStance": str(obj.get("supportStance") or ""),
        "formality": str(obj.get("formality") or "neutral"),
        "humor": str(obj.get("humor") or "none"),
        "expressiveness": str(obj.get("expressiveness") or "balanced"),
        "lengthBias": str(obj.get("lengthBias") or "medium"),
        "exampleScript": str(obj.get("exampleScript") or "I'm here. What would help?"),
        "source": "claude",
        "inspiredByDescription": description,
        "relatedBuiltin": obj.get("relatedBuiltin"),
        "createdAt": _now(),
        "updatedAt": _now(),
    }
