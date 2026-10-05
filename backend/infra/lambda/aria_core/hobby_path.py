"""Hobby path — Python port of ForgeCore HobbyPathEngine.

Lifestyle coach only. Reserved social energy gets solo hobbies that can
open light contact later; over-social / burned-out weeks get quieter
restorative ones. Also names tomorrow's people-energy and a circadian
free-day window so a night owl is not handed a 6am club. Never a diagnosis.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from . import user_working_model as uwm

RESERVED = "reserved"
SOCIABLE = "sociable"
BURNED_OUT = "burned_out"
MIXED = "mixed"

OPEN_GENTLY = "open_gently"
RESTORE_QUIET = "restore_quiet"
KEEP_RHYTHM = "keep_rhythm"
EXPLORE = "explore"

THIN = "thin"
ENOUGH = "enough"
OPEN = "open"

MORNING = "morning"
AFTERNOON = "afternoon"
EVENING = "evening"
ANYTIME = "anytime"

GENTLE = ["cooking", "outdoors", "making", "music"]
QUIET = ["reading", "rest", "making", "music"]

TITLES = {
    "outdoors": "Being outside",
    "gym": "The gym",
    "cooking": "Cooking",
    "making": "Making things",
    "music": "Music",
    "reading": "Reading",
    "games": "Games",
    "rest": "Resting at home",
}


@dataclass
class Suggestion:
    hobby: str
    why: str
    first_step: str


@dataclass
class Snapshot:
    path: str
    social_band: str
    people_energy: str
    free_day_window: str
    headline: str
    coaching_line: str
    suggestions: list[Suggestion]

    @property
    def aria_tags(self) -> list[str]:
        tags = [
            f"hobby_path:{self.path}",
            f"hobby_social:{self.social_band}",
            f"hobby_people:{self.people_energy}",
            f"hobby_window:{self.free_day_window}",
        ]
        for item in self.suggestions[:3]:
            tags.append(f"hobby:{item.hobby}")
        return tags

    @property
    def window_line(self) -> str:
        window, energy = self.free_day_window, self.people_energy
        if window == EVENING and energy == THIN:
            return "Tomorrow's people-energy looks thin. A free-day after the world goes quiet fits you."
        if window == MORNING and energy == THIN:
            return "Tomorrow's people-energy looks thin. Use your morning — not a crowded evening."
        if window == AFTERNOON and energy == THIN:
            return "Tomorrow's people-energy looks thin. The afternoon quiet is the work, not another plan."
        if window == ANYTIME and energy == THIN:
            return "Tomorrow's people-energy looks thin. Pick the quieter hobby, not a fuller calendar."
        if window == EVENING:
            return "Your clock leans later. Free-day belongs after the world goes quiet — not a 6am club."
        if window == MORNING:
            return "Your clock leans early. Free-day belongs in the morning, not a packed evening."
        if window == AFTERNOON:
            return "The afternoon slump is a free-day window, not a gap to fill with people."
        if energy == OPEN:
            return "People-energy is there if you want it — optional, not a quota."
        return "A free day still counts when it isn't training."

    @property
    def chat_prompt(self) -> str:
        return (
            "Help me pick a hobby that fits how I actually live, not a fitter "
            f"version of me. {self.coaching_line} {self.window_line}"
        )

    def to_dict(self) -> dict[str, Any]:
        return {
            "path": self.path,
            "socialBand": self.social_band,
            "peopleEnergy": self.people_energy,
            "freeDayWindow": self.free_day_window,
            "headline": self.headline,
            "coachingLine": self.coaching_line,
            "windowLine": self.window_line,
            "chatPrompt": self.chat_prompt,
            "ariaTags": self.aria_tags,
            "suggestions": [
                {"hobby": s.hobby, "why": s.why, "firstStep": s.first_step}
                for s in self.suggestions
            ],
        }


def parse_tag(token: str) -> str | None:
    parts = str(token or "").split(":")
    if len(parts) >= 2 and parts[0] == "hobby_path":
        if parts[1] in (OPEN_GENTLY, RESTORE_QUIET, KEEP_RHYTHM, EXPLORE):
            return parts[1]
    return None


def snapshot(
    social_energy_0_to_10: float | None,
    current_hobbies: list[str] | None,
    working: uwm.Snapshot,
    tomorrow_posture: str | None = None,
    wake_hour: float | None = None,
    known_people: list[dict] | None = None,
) -> Snapshot:
    hobbies = [h for h in (current_hobbies or []) if h in TITLES]
    band = _band(social_energy_0_to_10, working)
    path = _path(band, working, hobbies)
    energy = _people_energy(band, working, tomorrow_posture)
    window = _window(wake_hour, path)
    suggestions = _suggestions(path, hobbies, window)
    return Snapshot(
        path=path,
        social_band=band,
        people_energy=energy,
        free_day_window=window,
        headline=_headline(path),
        coaching_line=_coaching(path, suggestions) + _people_suffix(path, known_people or []),
        suggestions=suggestions,
    )


def _band(energy: float | None, working: uwm.Snapshot) -> str:
    if energy is not None:
        if energy <= 3.5:
            return RESERVED
        if energy >= 7.5:
            if working.tendency in (uwm.OVERREACHER, uwm.WEEKEND_DROP) or working.predicted_feel == uwm.FLAT:
                return BURNED_OUT
            return SOCIABLE
        return MIXED
    if working.tendency in (uwm.PROTECTOR, uwm.REBUILDING):
        return RESERVED
    if working.tendency in (uwm.OVERREACHER, uwm.WEEKEND_DROP):
        return BURNED_OUT
    return MIXED


def _people_energy(band: str, working: uwm.Snapshot, tomorrow_posture: str | None) -> str:
    if band in (RESERVED, BURNED_OUT):
        return THIN
    if tomorrow_posture in ("rest", "protect"):
        return THIN
    if working.predicted_feel == uwm.FLAT:
        return THIN
    if band == SOCIABLE and working.predicted_feel == uwm.AVAILABLE:
        return OPEN
    return ENOUGH


def _window(wake_hour: float | None, path: str) -> str:
    if wake_hour is not None:
        if wake_hour >= 9:
            return EVENING
        if wake_hour <= 6.5:
            return MORNING
        if path == RESTORE_QUIET:
            return AFTERNOON
        if path == OPEN_GENTLY:
            return EVENING
        return ANYTIME
    if path == OPEN_GENTLY:
        return EVENING
    if path == RESTORE_QUIET:
        return AFTERNOON
    return ANYTIME


def _path(band: str, working: uwm.Snapshot, hobbies: list[str]) -> str:
    if band == RESERVED:
        return OPEN_GENTLY
    if band == BURNED_OUT:
        return RESTORE_QUIET
    if band == SOCIABLE:
        return EXPLORE if not hobbies else KEEP_RHYTHM
    if working.tendency == uwm.OVERREACHER:
        return RESTORE_QUIET
    return EXPLORE if not hobbies else KEEP_RHYTHM


def _unique(items: list[str]) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for item in items:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def _window_clause(window: str) -> str:
    return {
        MORNING: " This fits your morning, not a crowded evening.",
        AFTERNOON: " Use the afternoon quiet — not another plan.",
        EVENING: " This fits after the world goes quiet.",
        ANYTIME: "",
    }.get(window, "")


def _suggestions(path: str, current: list[str], window: str) -> list[Suggestion]:
    if path == OPEN_GENTLY:
        preferred = _unique([h for h in current if h in GENTLE] + GENTLE)
    elif path == RESTORE_QUIET:
        preferred = _unique([h for h in current if h in QUIET] + QUIET)
    elif path == KEEP_RHYTHM:
        preferred = current[:3] if current else QUIET[:2]
    else:
        preferred = ["reading", "cooking", "outdoors"]
    clause = _window_clause(window)
    return [
        Suggestion(hobby=h, why=_why(h, path), first_step=_first(h, path) + clause)
        for h in preferred[:3]
    ]


def _headline(path: str) -> str:
    return {
        OPEN_GENTLY: "A hobby you can start alone",
        RESTORE_QUIET: "Quieter is the work this week",
        KEEP_RHYTHM: "Keep the free-day you already like",
        EXPLORE: "The healthiest version of you isn't only fitter",
    }.get(path, EXPLORE)


def _people_suffix(path: str, people: list[dict]) -> str:
    if not people:
        return ""
    first = people[0]
    name = str(first.get("firstName") or first.get("first_name") or "").strip()
    relation = str(first.get("relation") or "friend").replace("_", " ")
    if not name or "@" in name or any(ch.isdigit() for ch in name):
        return ""
    if path == OPEN_GENTLY:
        return (
            f" If you want company later, {name} ({relation}) is someone you already named — not a stranger."
        )
    if path == RESTORE_QUIET:
        return f" Leave {name} off the calendar this week."
    return ""


def _coaching(path: str, suggestions: list[Suggestion]) -> str:
    names = [TITLES.get(s.hobby, s.hobby).lower() for s in suggestions[:2]]
    listed = "a small free-day" if not names else " or ".join(names)
    if path == OPEN_GENTLY:
        return (
            "The healthiest version of you isn't a new personality. "
            f"Start {listed} alone; light contact can come later if you want it."
        )
    if path == RESTORE_QUIET:
        return (
            "The healthiest version of you isn't the most fit, and it isn't the fullest calendar. "
            f"Try {listed} — quiet on purpose."
        )
    if path == KEEP_RHYTHM:
        return f"You already have a free-day shape. Keep {listed} instead of adding a second identity."
    return (
        "Tell Lifestyle how a free day actually feels and I'll pick a hobby path "
        "that fits how you work — not a fitter costume."
    )


def _why(hobby: str, path: str) -> str:
    table = {
        (OPEN_GENTLY, "cooking"): "Solo first. Sharing a plate is optional, later.",
        (OPEN_GENTLY, "outdoors"): "A walk with no audience. One person can join another week.",
        (OPEN_GENTLY, "making"): "Hands busy, nobody watching. A class is a later chapter.",
        (OPEN_GENTLY, "music"): "Headphones now. Playing with people is a maybe.",
        (RESTORE_QUIET, "reading"): "A chapter with the phone in another room.",
        (RESTORE_QUIET, "rest"): "An hour at home that isn't a workout or a plan.",
        (RESTORE_QUIET, "making"): "Quiet hands. No audience, no streak.",
        (RESTORE_QUIET, "music"): "Listen. Don't perform.",
    }
    return table.get((path, hobby), "Fits how you actually spend a free day.")


def _first(hobby: str, path: str) -> str:
    table = {
        (OPEN_GENTLY, "cooking"): "Cook one thing you'd actually eat. That's the whole win.",
        (OPEN_GENTLY, "outdoors"): "Fifteen minutes outside. No route PR.",
        (OPEN_GENTLY, "making"): "Twenty minutes with your hands. Stop while it's still pleasant.",
        (OPEN_GENTLY, "music"): "One album, headphones on.",
        (RESTORE_QUIET, "reading"): "Ten pages. Phone in another room.",
        (RESTORE_QUIET, "rest"): "Protect one hour at home. Not a nap protocol — just quieter.",
        (RESTORE_QUIET, "making"): "Make something nobody will see.",
        (RESTORE_QUIET, "music"): "Sit and listen once today.",
    }
    return table.get((path, hobby), "Do the smallest version once this week.")
