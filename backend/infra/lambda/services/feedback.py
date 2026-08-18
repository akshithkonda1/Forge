from __future__ import annotations

from services.aria_context import CoachContextEngine


class FeedbackEngine:
    """Layer 3 — reactions and outcomes update the living context."""

    def __init__(self, context_engine: CoachContextEngine | None = None) -> None:
        self.context_engine = context_engine or CoachContextEngine()

    def process_reaction(self, user_id: str, message_id: str, reaction: str) -> dict:
        updates: dict = {}
        if reaction in ("🔥", "💪", "thumbs_up", "love"):
            ctx = self.context_engine.get_or_create_context(user_id)
            updates["relationship_level"] = min(10, ctx.relationship_level + 1)
        if updates:
            self.context_engine.update_context(user_id, updates)
        return {"ok": True, "message_id": message_id, "updates": updates}

    def process_plan_outcome(
        self,
        user_id: str,
        plan_id: str,
        completed: bool,
        feedback: str | None = None,
    ) -> dict:
        if completed:
            self.context_engine.add_insight(user_id, f"Completed plan: {plan_id}")
        else:
            self.context_engine.add_insight(user_id, f"Skipped plan: {plan_id}")
        if feedback:
            self.context_engine.add_insight(user_id, f"Plan feedback: {feedback}")
        return {"ok": True, "plan_id": plan_id, "completed": completed}