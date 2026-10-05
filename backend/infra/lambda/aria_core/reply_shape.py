"""What shaped this reply — Python port of ForgeCore ReplyShapeEngine.

Names the living signals that steered a turn. Never a medical claim.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from . import hobby_path as hp
from . import readiness_forecast as rf
from . import tomorrow_budgets as tb
from . import user_working_model as uwm

ESTIMATE = "shape:estimate"
HOBBY = "shape:hobby"
FORECAST = "shape:forecast"
WORKING = "shape:working"
SCOUT = "shape:scout"
LOCAL = "shape:local"
ASK = "shape:ask"


@dataclass
class Shape:
    headline: str
    detail: str
    lanes: list[str]

    @property
    def chip_label(self) -> str:
        return f"What shaped this · {self.headline}"

    def to_dict(self) -> dict[str, Any]:
        return {
            "headline": self.headline,
            "detail": self.detail,
            "chipLabel": self.chip_label,
            "lanes": self.lanes,
        }


def shape(
    prompt: str,
    aria_tags: list[str] | None,
    local_fallback: bool,
    scout_used: bool,
    estimate: bool,
) -> Shape:
    tags = list(aria_tags or [])
    if estimate:
        return Shape(
            headline="Estimate, not a lock",
            detail=(
                "I didn't have a clean enough replay to claim more. Ordinary day "
                "until more of yours is in — not a medical claim."
            ),
            lanes=[ESTIMATE],
        )

    lanes: list[str] = []
    bits: list[str] = []
    headline = "What you asked"
    lower = (prompt or "").lower()
    hobby_ask = any(
        needle in lower
        for needle in ("hobby", "hobbies", "free day", "free time", "besides the gym")
    )
    people_thin = "hobby_people:thin" in tags
    hobby_path = hp.parse_tag(next((t for t in tags if t.startswith("hobby_path:")), ""))
    working = None
    for token in tags:
        working = uwm.parse_tag(token)
        if working:
            break
    forecast = None
    for token in tags:
        forecast = rf.parse_tag(token)
        if forecast:
            break

    if hobby_ask or (people_thin and ("hobby" in lower or "free" in lower)):
        lanes.append(HOBBY)
        if people_thin:
            headline = "People-energy, not a score"
            bits.append(
                "Tomorrow's people-energy looked thin, so I steered quieter — not a fuller calendar."
            )
        elif hobby_path == hp.OPEN_GENTLY:
            headline = "Hobby path"
            bits.append("Solo-first hobby path. Light contact can come later if you want it.")
        elif hobby_path == hp.RESTORE_QUIET:
            headline = "Hobby path"
            bits.append("Restore-quiet hobby path this week. Calendar is not the win.")
        else:
            headline = "Hobby path"
            bits.append("A free-day path from how you actually live, not a fitter costume.")

    if "tomorrow" in lower and forecast:
        lanes.append(FORECAST)
        if headline == "What you asked":
            headline = "Tomorrow's readiness"
        bits.append(f"Tomorrow's forecast is {forecast[0]} ({forecast[1]}).")

    budget = next((parsed for token in tags if (parsed := tb.parse_tag(token))), None)
    if (
        budget
        and budget != tb.NEITHER
        and ("tomorrow" in lower or "split" in lower or "budget" in lower)
    ):
        lanes.append("shape:budget")
        if headline == "What you asked":
            headline = "Two budgets"
        bits.append(tb.coaching_line(budget))

    if working:
        tendency, stance = working
        if tendency == uwm.OVERREACHER or stance == uwm.CAP_HEROICS:
            lanes.append(WORKING)
            if headline == "What you asked":
                headline = "How you work"
            bits.append("You tend to push through a heavy week — I capped heroics.")
        elif tendency == uwm.WEEKEND_DROP:
            lanes.append(WORKING)
            if headline == "What you asked":
                headline = "How you work"
            bits.append("Weekdays hold and weekends slip — I kept a tiny weekend anchor.")
        elif tendency == uwm.REBUILDING:
            lanes.append(WORKING)
            if headline == "What you asked":
                headline = "How you work"
            bits.append("You're finding the rhythm again — showing up small is the win.")

    if scout_used:
        lanes.append(SCOUT)
        bits.append("Looked up outside the phone, then coached from your life — not from the article.")

    if local_fallback:
        lanes.append(LOCAL)
        bits.append("This turn stayed on this phone.")

    if not bits:
        bits.append("Ordinary coaching from what you asked. No extra steering.")

    return Shape(
        headline=headline,
        detail=" ".join(bits),
        lanes=lanes or [ASK],
    )
