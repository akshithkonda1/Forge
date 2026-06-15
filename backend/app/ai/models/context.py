from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any


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
        }

    @classmethod
    def from_dict(cls, data: dict[str, Any]) -> UserContext:
        last_updated = data.get("last_updated")
        if isinstance(last_updated, str):
            parsed = datetime.fromisoformat(last_updated.replace("Z", "+00:00"))
        else:
            parsed = _utcnow()
        return cls(
            user_id=str(data.get("user_id", "")),
            lifestyle_tags=list(data.get("lifestyle_tags") or []),
            current_goals=list(data.get("current_goals") or []),
            constraints=list(data.get("constraints") or []),
            recent_patterns=list(data.get("recent_patterns") or []),
            last_insights=list(data.get("last_insights") or []),
            relationship_level=int(data.get("relationship_level") or 1),
            last_updated=parsed,
        )


@dataclass
class AriaChatRequest:
    user_id: str
    message: str
    recent_metrics: dict[str, float] = field(default_factory=dict)

    @classmethod
    def from_payload(cls, payload: dict[str, Any]) -> AriaChatRequest:
        metrics = payload.get("recent_metrics") or {}
        return cls(
            user_id=str(payload.get("user_id") or ""),
            message=str(payload.get("message") or "").strip(),
            recent_metrics={k: float(v) for k, v in metrics.items()},
        )


@dataclass
class AriaResponse:
    message: str
    rich_card: dict[str, Any] | None = None
    suggested_actions: list[str] | None = None
    context_updates: dict[str, int] | None = None
    confidence: float | None = None
    memory_reference: str | None = None

    def to_dict(self) -> dict[str, Any]:
        return {
            "message": self.message,
            "rich_card": self.rich_card,
            "suggested_actions": self.suggested_actions,
            "context_updates": self.context_updates,
            "confidence": self.confidence,
            "memory_reference": self.memory_reference,
        }