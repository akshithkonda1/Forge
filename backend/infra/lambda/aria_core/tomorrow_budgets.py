"""Tomorrow's two budgets — Python port of ForgeCore TomorrowBudgets.

Body readiness and people-energy are separate spends. This names which
one is actually scarce. Lifestyle coach only.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from . import readiness_forecast as rf

BOTH = "both"
PEOPLE = "people"
BODY = "body"
NEITHER = "neither"


@dataclass
class Snapshot:
    constraint: str
    headline: str
    coaching_line: str

    @property
    def aria_tags(self) -> list[str]:
        return [f"tomorrow_budget:{self.constraint}"]

    @property
    def is_split(self) -> bool:
        return self.constraint in (PEOPLE, BODY)

    def to_dict(self) -> dict[str, Any]:
        return {
            "constraint": self.constraint,
            "headline": self.headline,
            "coachingLine": self.coaching_line,
            "ariaTags": self.aria_tags,
            "isSplit": self.is_split,
        }


def parse_tag(token: str) -> str | None:
    parts = str(token or "").split(":")
    if len(parts) >= 2 and parts[0] == "tomorrow_budget":
        if parts[1] in (BOTH, PEOPLE, BODY, NEITHER):
            return parts[1]
    return None


def coaching_line(constraint: str) -> str:
    return {
        BOTH: "Tomorrow both budgets are thin. A short walk or nothing — no hero session, no extra plans.",
        PEOPLE: "Split day. Your body can take the session. Your people-budget can't take another packed calendar.",
        BODY: "Split day. People are fine if you want them. Don't stack a hard session on a thin body-budget.",
        NEITHER: "Neither budget is the limit. Spend one if you want — no need to burn both.",
    }.get(constraint, "")


def snapshot(posture: str, stance: str, people_energy: str) -> Snapshot:
    body_thin = rf.keep_light(posture) or stance == "cap_heroics"
    people_thin = people_energy == "thin"
    if body_thin and people_thin:
        constraint = BOTH
    elif people_thin:
        constraint = PEOPLE
    elif body_thin:
        constraint = BODY
    else:
        constraint = NEITHER
    headlines = {
        BOTH: "Both budgets are thin",
        PEOPLE: "Split day — people-budget is the limit",
        BODY: "Split day — body-budget is the limit",
        NEITHER: "Neither budget is the limit",
    }
    return Snapshot(
        constraint=constraint,
        headline=headlines[constraint],
        coaching_line=coaching_line(constraint),
    )
