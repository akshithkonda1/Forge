from __future__ import annotations

from services.aria_context import CoachContextEngine


class FeedbackEngine:
    """Layer 3 — reactions and outcomes update the living context and the learner."""

    def __init__(self, context_engine: CoachContextEngine | None = None) -> None:
        self.context_engine = context_engine or CoachContextEngine()

    def process_reaction(self, user_id: str, message_id: str, reaction: str) -> dict:
        updates: dict = {}
        if reaction in ("🔥", "💪", "thumbs_up", "love"):
            ctx = self.context_engine.get_or_create_context(user_id)
            updates["relationship_level"] = min(10, ctx.relationship_level + 1)
        if updates:
            self.context_engine.update_context(user_id, updates)
        self._learn_reaction(user_id, reaction)
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
        self._learn_workout(user_id, completed, feedback=feedback)
        return {"ok": True, "plan_id": plan_id, "completed": completed}

    def _learn_reaction(self, user_id: str, reaction: str) -> None:
        try:
            from services import contextual_learner

            persona = contextual_learner.load(user_id)
            contextual_learner.apply_reaction_outcome(persona, reaction)
            if reaction in ("🔥", "💪", "thumbs_up", "love", "up", "like"):
                ctx = self.context_engine.get_or_create_context(user_id)
                contextual_learner.observe_relationship(persona, ctx.relationship_level)
            contextual_learner.save(user_id, persona)
        except Exception:
            return

    def _learn_workout(self, user_id: str, completed: bool, feedback: str | None = None) -> None:
        try:
            from services import contextual_learner

            persona = contextual_learner.load(user_id)
            living = self.context_engine.get_or_create_context(user_id)
            cal = contextual_learner.parse_calendar(living.lifestyle_tags)
            contextual_learner.apply_workout_outcome(
                persona,
                completed=completed,
                evening_busy=cal.evening_busy,
                headline=bool(cal.headlines),
            )
            if feedback:
                contextual_learner.self_train_from_conversation(persona, feedback)
            contextual_learner.save(user_id, persona)
        except Exception:
            return
