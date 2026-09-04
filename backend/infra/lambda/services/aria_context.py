from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from storage import dynamodb, keys


def _utcnow() -> datetime:
    return datetime.now(timezone.utc)


@dataclass
class UserContext:
    user_id: str
    lifestyle_tags: list[str] = field(default_factory=list)
    current_goals: list[str] = field(default_factory=list)
    constraints: list[str] = field(default_factory=list)
    recent_patterns: list[str] = field(default_factory=list)
    last_insights: list[str] = field(default_factory=list)
    relationship_level: int = 1
    last_updated: datetime = field(default_factory=_utcnow)
    last_promoted_at: datetime | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "user_id": self.user_id,
            "lifestyle_tags": self.lifestyle_tags,
            "current_goals": self.current_goals,
            "constraints": self.constraints,
            "recent_patterns": self.recent_patterns,
            "last_insights": self.last_insights,
            "relationship_level": self.relationship_level,
            "last_updated": self.last_updated.isoformat(),
            "last_promoted_at": self.last_promoted_at.isoformat() if self.last_promoted_at else None,
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> UserContext:
        last_updated = data.get("last_updated")
        if isinstance(last_updated, str):
            parsed = datetime.fromisoformat(last_updated.replace("Z", "+00:00"))
        else:
            parsed = _utcnow()
        promoted = data.get("last_promoted_at")
        if isinstance(promoted, str):
            try:
                promoted_at = datetime.fromisoformat(promoted.replace("Z", "+00:00"))
            except ValueError:
                promoted_at = None
        else:
            promoted_at = None
        return cls(
            user_id=str(data.get("user_id", "")),
            lifestyle_tags=list(data.get("lifestyle_tags") or []),
            current_goals=list(data.get("current_goals") or []),
            constraints=list(data.get("constraints") or []),
            recent_patterns=list(data.get("recent_patterns") or []),
            last_insights=list(data.get("last_insights") or []),
            relationship_level=int(data.get("relationship_level") or 1),
            last_updated=parsed,
            last_promoted_at=promoted_at,
        )


class CoachContextEngine:
    """Layer 2 — persistent contextual model for ARIA."""

    def get_or_create_context(self, user_id: str) -> UserContext:
        key = keys.aria_context_key(user_id)
        item = dynamodb.get_item(key["pk"], key["sk"])
        if item and item.get("payload"):
            return UserContext.from_dict(item["payload"])
        return UserContext(user_id=user_id)

    def update_context(self, user_id: str, updates: dict[str, Any]) -> UserContext:
        context = self.get_or_create_context(user_id)
        for field_name, value in updates.items():
            if hasattr(context, field_name):
                setattr(context, field_name, value)
        context.last_updated = _utcnow()
        self._save(user_id, context)
        return context

    def build_rich_context(self, user_id: str, recent_metrics: dict[str, float]) -> dict[str, Any]:
        context = self.get_or_create_context(user_id)
        patterns = list(context.recent_patterns)
        readiness = recent_metrics.get("readiness", 0)
        if readiness and readiness < 55 and "low_readiness_streak" not in patterns:
            patterns.append("low_readiness_streak")
        sleep_score = recent_metrics.get("sleep_score", 0)
        if sleep_score >= 85 and "strong_sleep_recovery" not in patterns:
            patterns.append("strong_sleep_recovery")

        if patterns != context.recent_patterns:
            context.recent_patterns = patterns
            self._save(user_id, context)

        return {
            "user_id": user_id,
            "lifestyle_tags": context.lifestyle_tags,
            "goals": context.current_goals,
            "constraints": context.constraints,
            "recent_patterns": patterns,
            "recent_metrics": recent_metrics,
            "relationship_level": context.relationship_level,
            "timestamp": _utcnow().isoformat(),
        }

    def add_insight(self, user_id: str, insight: str) -> UserContext:
        context = self.get_or_create_context(user_id)
        context.last_insights.insert(0, insight)
        if len(context.last_insights) > 15:
            context.last_insights.pop()
        context.last_updated = _utcnow()
        self._save(user_id, context)
        return context

    def memory_reference(self, user_id: str, message: str) -> str | None:
        context = self.get_or_create_context(user_id)
        if context.relationship_level < 2 or not context.last_insights:
            return None
        lower = message.lower()
        if any(token in lower for token in ("tired", "recovery", "sleep", "exhausted")):
            return f"Last time you felt like this, we focused on recovery — {context.last_insights[0]}"
        return None

    def _save(self, user_id: str, context: UserContext) -> None:
        key = keys.aria_context_key(user_id)
        dynamodb.put_item(
            {
                "pk": key["pk"],
                "sk": key["sk"],
                "payload": context.to_dict(),
            }
        )