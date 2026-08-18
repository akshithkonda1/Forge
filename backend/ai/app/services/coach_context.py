from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from backend.app.ai.models.context import UserContext
from backend.app.ai.storage import dynamodb, s3


class CoachContextEngine:
    """Layer 2 — persistent contextual model for ARIA."""

    CONTEXT_SK = "ARIA#CONTEXT"

    async def get_or_create_context(self, user_id: str) -> UserContext:
        key = dynamodb.context_key(user_id)
        item = dynamodb.get_item(key["pk"], key["sk"])
        if item and item.get("payload"):
            return UserContext.from_dict(item["payload"])
        return UserContext(user_id=user_id)

    async def update_context(self, user_id: str, updates: dict[str, Any]) -> UserContext:
        context = await self.get_or_create_context(user_id)
        for field_name, value in updates.items():
            if hasattr(context, field_name):
                setattr(context, field_name, value)
        context.last_updated = datetime.now(timezone.utc)
        await self._save(user_id, context)
        return context

    async def build_rich_context(self, user_id: str, recent_metrics: dict[str, float]) -> dict[str, Any]:
        context = await self.get_or_create_context(user_id)
        patterns = list(context.recent_patterns)
        readiness = recent_metrics.get("readiness", 0)
        if readiness and readiness < 55 and "low_readiness_streak" not in patterns:
            patterns.append("low_readiness_streak")
        sleep_score = recent_metrics.get("sleep_score", 0)
        if sleep_score >= 85 and "strong_sleep_recovery" not in patterns:
            patterns.append("strong_sleep_recovery")

        return {
            "user_id": user_id,
            "lifestyle_tags": context.lifestyle_tags,
            "goals": context.current_goals,
            "constraints": context.constraints,
            "recent_patterns": patterns,
            "recent_metrics": recent_metrics,
            "relationship_level": context.relationship_level,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    async def add_insight(self, user_id: str, insight: str) -> UserContext:
        context = await self.get_or_create_context(user_id)
        context.last_insights.insert(0, insight)
        if len(context.last_insights) > 15:
            context.last_insights.pop()
        context.last_updated = datetime.now(timezone.utc)
        await self._save(user_id, context)
        return context

    async def should_be_proactive(self, user_id: str) -> bool:
        context = await self.get_or_create_context(user_id)
        return context.relationship_level >= 3 and bool(context.recent_patterns)

    async def memory_reference(self, user_id: str, message: str) -> str | None:
        context = await self.get_or_create_context(user_id)
        if context.relationship_level < 2 or not context.last_insights:
            return None
        lower = message.lower()
        if any(token in lower for token in ("tired", "recovery", "sleep", "exhausted")):
            return f"Last time you felt like this, we focused on recovery — {context.last_insights[0]}"
        return None

    async def archive_snapshot(self, user_id: str, snapshot: dict[str, Any]) -> str | None:
        key = f"aria/context/{user_id}/{snapshot.get('timestamp', 'latest')}.json"
        return s3.put_json(key, snapshot)

    async def _save(self, user_id: str, context: UserContext) -> None:
        key = dynamodb.context_key(user_id)
        dynamodb.put_item(
            {
                "pk": key["pk"],
                "sk": key["sk"],
                "payload": context.to_dict(),
            }
        )