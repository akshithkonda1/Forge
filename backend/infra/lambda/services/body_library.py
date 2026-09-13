"""Body-context exercise libraries + next-session suggestion.

Mirrors the iOS ``TargetMuscle.Region`` taxonomy (push / pull / legs / core /
conditioning) so ARIA can suggest a *session* — not just "train moderately" —
from what they did yesterday, what day it is, and what they know.

This is a compact library of representative lifts (names aligned with the
iOS ``ExerciseLibrary``), grouped by body region. The iOS catalog stays the
canonical gym floor; this module is the backend/SimRunner brain that picks
which *library* to open tomorrow.

Rules:
  * Same region does not come back within ~36 hours (tissue still in it).
  * After legs, the default complementary is push — or push+core (chest and
    abs) — or full body if they're a beginner / it's been several days.
  * User-named muscles win unless that region was yesterday.
  * Numbers live on the structured session, never forced into chat prose.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any, Iterable

REGIONS = ("push", "pull", "legs", "core", "conditioning")

# What usually follows a region. First choice is the default complementary.
_NEXT: dict[str, tuple[str, ...]] = {
    "legs": ("push", "core", "pull"),
    "push": ("pull", "legs", "core"),
    "pull": ("legs", "push", "core"),
    "core": ("push", "legs", "pull"),
    "conditioning": ("push", "pull", "legs"),
}

# Same-day / still-sore window. Under this, we will not re-hit the region.
FRESH_HOURS = 36.0
# After this, a beginner (or anyone with no recent split) can take full body.
FULL_BODY_HOURS = 72.0

_REGION_ALIASES: dict[str, tuple[str, ...]] = {
    "legs": (
        "leg", "legs", "squat", "lunge", "deadlift", "hinge", "quad",
        "hamstring", "glute", "calf", "lower body", "lower-body",
    ),
    "push": (
        "push", "chest", "bench", "press", "pec", "tricep", "shoulder",
        "delt", "overhead", "upper body push",
    ),
    "pull": (
        "pull", "row", "back", "lat", "chin", "bicep", "rear delt",
        "upper body pull",
    ),
    "core": ("core", "abs", "ab ", "oblique", "plank", "crunch"),
    "conditioning": (
        "cardio", "hiit", "run", "bike", "row erg", "conditioning",
        "full body", "full-body", "circuit", "metcon",
    ),
}

_TYPE_TO_REGION = {
    "strength": None,  # unknown split — infer from the name
    "cardio": "conditioning",
    "hiit": "conditioning",
    "yoga": "conditioning",
    "mobility": "conditioning",
    "isometric": None,
}


@dataclass(frozen=True)
class Move:
    name: str
    muscles: tuple[str, ...]
    level: str = "intermediate"  # beginner | intermediate | advanced
    sets: int = 3
    reps: str = "8-10"

    def to_dict(self) -> dict[str, Any]:
        return {
            "name": self.name,
            "muscles": list(self.muscles),
            "level": self.level,
            "sets": self.sets,
            "reps": self.reps,
        }


# Compact libraries — names match the iOS catalog so a plan can land on-device.
LIBRARIES: dict[str, tuple[Move, ...]] = {
    "push": (
        Move("Barbell Bench Press", ("chest", "triceps", "frontDelts"), "intermediate", 4, "5-8"),
        Move("Incline Dumbbell Press", ("chest", "frontDelts"), "intermediate", 3, "8-10"),
        Move("Overhead Press", ("frontDelts", "triceps"), "intermediate", 3, "6-8"),
        Move("Dumbbell Bench Press", ("chest", "triceps"), "beginner", 3, "8-12"),
        Move("Push-Up", ("chest", "triceps", "frontDelts"), "beginner", 3, "8-15"),
        Move("Cable Fly", ("chest",), "intermediate", 3, "10-12"),
        Move("Tricep Pushdown", ("triceps",), "beginner", 3, "10-12"),
        Move("Lateral Raise", ("sideDelts",), "beginner", 3, "12-15"),
    ),
    "pull": (
        Move("Barbell Row", ("upperBack", "lats", "biceps"), "intermediate", 4, "6-8"),
        Move("Lat Pulldown", ("lats", "biceps"), "beginner", 3, "8-12"),
        Move("Pull-Up", ("lats", "biceps"), "intermediate", 3, "5-8"),
        Move("Seated Cable Row", ("upperBack", "lats"), "beginner", 3, "8-12"),
        Move("Romanian Deadlift", ("hamstrings", "glutes", "lowerBack"), "intermediate", 3, "6-8"),
        Move("Face Pull", ("rearDelts", "upperBack"), "beginner", 3, "12-15"),
        Move("Dumbbell Curl", ("biceps",), "beginner", 3, "10-12"),
        Move("Inverted Row", ("upperBack", "biceps"), "beginner", 3, "8-12"),
    ),
    "legs": (
        Move("Back Squat", ("quads", "glutes"), "intermediate", 4, "5-8"),
        Move("Goblet Squat", ("quads", "glutes"), "beginner", 3, "8-12"),
        Move("Romanian Deadlift", ("hamstrings", "glutes"), "intermediate", 3, "6-8"),
        Move("Bulgarian Split Squat", ("quads", "glutes"), "intermediate", 3, "8/leg"),
        Move("Leg Press", ("quads", "glutes"), "beginner", 3, "10-12"),
        Move("Walking Lunge", ("quads", "glutes"), "beginner", 3, "10/leg"),
        Move("Leg Curl", ("hamstrings",), "beginner", 3, "10-12"),
        Move("Calf Raise", ("calves",), "beginner", 3, "12-15"),
    ),
    "core": (
        Move("Hanging Knee Raise", ("abs",), "intermediate", 3, "10-12"),
        Move("Cable Crunch", ("abs",), "beginner", 3, "12-15"),
        Move("Plank", ("abs", "obliques"), "beginner", 3, "30-45s"),
        Move("Dead Bug", ("abs",), "beginner", 3, "8/side"),
        Move("Pallof Press", ("obliques", "abs"), "intermediate", 3, "10/side"),
        Move("Side Plank", ("obliques",), "beginner", 3, "20-30s"),
        Move("Ab Wheel Rollout", ("abs",), "advanced", 3, "6-10"),
    ),
    "conditioning": (
        Move("Easy Bike", ("cardio", "fullBody"), "beginner", 1, "12-20 min"),
        Move("Row Erg", ("cardio", "fullBody"), "beginner", 1, "8-12 min"),
        Move("Farmer Carry", ("fullBody", "forearms"), "beginner", 3, "30-40s"),
        Move("Kettlebell Swing", ("glutes", "hamstrings", "fullBody"), "intermediate", 3, "12-15"),
        Move("Assault Bike", ("cardio", "fullBody"), "intermediate", 1, "6-10 min"),
        Move("Turkish Get-Up", ("fullBody",), "advanced", 3, "3/side"),
    ),
}


# Weekday 0 = Sunday … 6 = Saturday. Matches iOS ``weeklySchedule``.
_DAY_NAMES = ("Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday")
_DAY_ALIASES: dict[str, int] = {
    "sunday": 0, "sun": 0,
    "monday": 1, "mon": 1,
    "tuesday": 2, "tue": 2, "tues": 2,
    "wednesday": 3, "wed": 3,
    "thursday": 4, "thu": 4, "thur": 4, "thurs": 4,
    "friday": 5, "fri": 5,
    "saturday": 6, "sat": 6,
}

# Default walking week: Tuesday legs, Wednesday chest+abs, and so on.
# ``rotate`` still uses complementary history when they trained yesterday;
# this calendar is what the week *is* when they pick a day or start fresh.
DEFAULT_WEEK: tuple[dict[str, Any], ...] = (
    {"weekday": 0, "primary": "rest", "extra": None, "exerciseCount": 0},
    {"weekday": 1, "primary": "push", "extra": None, "exerciseCount": 5},
    {"weekday": 2, "primary": "legs", "extra": None, "exerciseCount": 6},
    {"weekday": 3, "primary": "push", "extra": "core", "exerciseCount": 6},
    {"weekday": 4, "primary": "pull", "extra": None, "exerciseCount": 5},
    {"weekday": 5, "primary": "full_body", "extra": None, "exerciseCount": 6},
    {"weekday": 6, "primary": "conditioning", "extra": None, "exerciseCount": 4},
)


@dataclass(frozen=True)
class WeekSlot:
    weekday: int  # 0=Sun
    primary: str  # rest | push | pull | legs | core | conditioning | full_body
    extra: str | None = None
    exercise_count: int = 5

    @property
    def is_rest(self) -> bool:
        return self.primary == "rest"

    def to_dict(self) -> dict[str, Any]:
        return {
            "weekday": self.weekday,
            "primary": self.primary,
            "extra": self.extra,
            "exerciseCount": self.exercise_count,
        }

    @classmethod
    def from_mapping(cls, raw: dict[str, Any] | None) -> "WeekSlot | None":
        if not isinstance(raw, dict):
            return None
        try:
            day = int(raw.get("weekday"))
        except (TypeError, ValueError):
            return None
        if day < 0 or day > 6:
            return None
        primary = str(raw.get("primary") or raw.get("region") or "push").lower()
        extra_raw = raw.get("extra")
        extra = str(extra_raw).lower() if extra_raw else None
        raw_count = raw.get("exerciseCount", raw.get("exercise_count", 5))
        try:
            count = 5 if raw_count is None else int(raw_count)
        except (TypeError, ValueError):
            count = 5
        return cls(weekday=day, primary=primary, extra=extra, exercise_count=max(0, min(8, count)))


def default_week() -> list[WeekSlot]:
    return [slot for raw in DEFAULT_WEEK if (slot := WeekSlot.from_mapping(raw))]


def parse_split(raw: Any) -> list[WeekSlot]:
    """Normalize a payload week; fill missing days from the default calendar."""
    by_day: dict[int, WeekSlot] = {s.weekday: s for s in default_week()}
    rows: Iterable[Any]
    if isinstance(raw, dict):
        rows = raw.values()
    elif isinstance(raw, (list, tuple)):
        rows = raw
    else:
        rows = ()
    for item in rows:
        slot = WeekSlot.from_mapping(item if isinstance(item, dict) else None)
        if slot is not None:
            by_day[slot.weekday] = slot
    return [by_day[i] for i in range(7)]


def slot_for(weekday: int, split: list[WeekSlot] | None = None) -> WeekSlot:
    week = split if split and len(split) == 7 else default_week()
    day = weekday % 7
    for slot in week:
        if slot.weekday == day:
            return slot
    return default_week()[day]


def infer_asked_weekday(message: str | None) -> int | None:
    """Named weekday in the ask ('do Tuesday', 'Wednesday's session')."""
    lower = (message or "").lower()
    if not lower.strip():
        return None
    hits = [(name, day) for name, day in _DAY_ALIASES.items() if name in lower]
    if not hits:
        return None
    hits.sort(key=lambda pair: len(pair[0]), reverse=True)
    return hits[0][1]


def wants_replay_prior(message: str | None) -> bool:
    lower = (message or "").lower()
    return any(
        p in lower
        for p in (
            "yesterday",
            "day prior",
            "prior day",
            "go back",
            "last day's",
            "last days",
            "do yesterday",
            "yesterday's session",
            "yesterdays session",
        )
    )


def sun0_from_iso(timestamp: str | None) -> int | None:
    """0=Sun from an ISO timestamp. None if unparseable."""
    if not timestamp:
        return None
    raw = str(timestamp).strip()
    if not raw:
        return None
    try:
        from datetime import datetime, timezone

        dt = datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return (dt.weekday() + 1) % 7
    except (TypeError, ValueError):
        return None


@dataclass
class SessionSuggestion:
    """A concrete next session drawn from the body libraries."""

    region: str
    title: str
    reason: str
    muscles: list[str]
    exercises: list[Move]
    alternatives: list[str] = field(default_factory=list)
    combo: list[str] = field(default_factory=list)  # e.g. ["push", "core"]
    avoided: str | None = None  # region we skipped because it's still fresh
    weekday: int | None = None  # 0=Sun when this came from a week slot
    planning_mode: str | None = None  # fixed | rotate

    def to_dict(self) -> dict[str, Any]:
        return {
            "region": self.region,
            "title": self.title,
            "reason": self.reason,
            "muscles": self.muscles,
            "exercises": [m.to_dict() for m in self.exercises],
            "alternatives": self.alternatives,
            "combo": self.combo,
            "avoided": self.avoided,
            "weekday": self.weekday,
            "planningMode": self.planning_mode,
            "exerciseCount": len(self.exercises),
        }

    def spoken(self) -> str:
        """One companion sentence — no sets/reps, no metric dump."""
        alts = ""
        if self.alternatives:
            pretty = " or ".join(_title(a) for a in self.alternatives[:2])
            alts = f" {pretty} also fits if you'd rather."
        return f"{self.reason} I'd go {self.title.lower()}.{alts}"


def _title(region: str) -> str:
    return {
        "push": "push (chest, shoulders, triceps)",
        "pull": "pull (back, biceps)",
        "legs": "legs",
        "core": "core",
        "conditioning": "conditioning",
        "full_body": "full body",
        "push_core": "chest and abs",
        "pull_core": "back and core",
    }.get(region, region.replace("_", " "))


def infer_region(*texts: str | None) -> str | None:
    """Best-effort region from a workout name, type, or user message."""
    blob = " ".join(t for t in texts if t).lower()
    if not blob.strip():
        return None
    # Longer / more specific aliases first so "full body" wins over "body".
    scored: list[tuple[int, str]] = []
    for region, aliases in _REGION_ALIASES.items():
        hits = [a for a in aliases if a in blob]
        if hits:
            scored.append((max(len(a) for a in hits), region))
    if scored:
        scored.sort(reverse=True)
        return scored[0][1]
    for raw, region in _TYPE_TO_REGION.items():
        if raw in blob and region:
            return region
    return None


def library(region: str, *, experience: str = "intermediate", limit: int = 6) -> list[Move]:
    """Moves from one body library, filtered to what they can reasonably do."""
    rows = list(LIBRARIES.get(region, ()))
    if not rows:
        return []
    rank = {"beginner": 0, "intermediate": 1, "advanced": 2}
    cap = rank.get((experience or "intermediate").lower(), 1)
    kept = [m for m in rows if rank.get(m.level, 1) <= cap]
    if len(kept) < 3:
        kept = rows
    # Beginners get the simpler names first; otherwise keep catalog order
    # (compounds already sit at the top of each library).
    if cap == 0:
        kept = sorted(kept, key=lambda m: rank.get(m.level, 1))
    return kept[:limit]


def _combo_session(
    primary: str,
    extra: str,
    *,
    experience: str,
    reason: str,
    avoided: str | None,
    alternatives: Iterable[str],
    primary_limit: int = 4,
    extra_limit: int = 2,
    weekday: int | None = None,
    planning_mode: str | None = None,
) -> SessionSuggestion:
    primary_moves = library(primary, experience=experience, limit=primary_limit)
    extra_moves = library(extra, experience=experience, limit=extra_limit)
    muscles: list[str] = []
    for move in (*primary_moves, *extra_moves):
        for m in move.muscles:
            if m not in muscles:
                muscles.append(m)
    key = f"{primary}_{extra}"
    title = {"push_core": "Chest and abs", "pull_core": "Back and core"}.get(
        key, f"{_title(primary)} + {_title(extra)}"
    )
    return SessionSuggestion(
        region=key,
        title=title,
        reason=reason,
        muscles=muscles,
        exercises=primary_moves + extra_moves,
        alternatives=list(alternatives),
        combo=[primary, extra],
        avoided=avoided,
        weekday=weekday,
        planning_mode=planning_mode,
    )


def session_from_slot(
    slot: WeekSlot,
    *,
    experience: str,
    reason: str,
    avoided: str | None = None,
    alternatives: Iterable[str] | None = None,
    planning_mode: str | None = None,
) -> SessionSuggestion:
    """Open the library for one weekday slot — X exercises, optional combo."""
    exp = (experience or "intermediate").lower()
    count = max(2, min(8, slot.exercise_count or 5))
    alts = list(alternatives or [])
    if slot.is_rest:
        moves = library("core", experience=exp, limit=min(4, count))
        return SessionSuggestion(
            region="core",
            title="Rest day",
            reason=reason,
            muscles=_muscles_of(moves),
            exercises=moves,
            alternatives=alts or ["conditioning"],
            avoided=avoided,
            weekday=slot.weekday,
            planning_mode=planning_mode,
        )
    if slot.primary == "full_body":
        per = max(1, count // 3)
        mix = (
            library("push", experience=exp, limit=per)
            + library("pull", experience=exp, limit=per)
            + library("legs", experience=exp, limit=max(1, count - 2 * per))
        )
        return SessionSuggestion(
            region="full_body",
            title="Full body",
            reason=reason,
            muscles=_muscles_of(mix),
            exercises=mix[:count],
            alternatives=alts or ["push", "legs"],
            combo=["push", "pull", "legs"],
            avoided=avoided,
            weekday=slot.weekday,
            planning_mode=planning_mode,
        )
    extra = slot.extra
    if extra and extra != slot.primary:
        extra_n = 2 if count >= 5 else 1
        primary_n = max(2, count - extra_n)
        return _combo_session(
            slot.primary,
            extra,
            experience=exp,
            reason=reason,
            avoided=avoided,
            alternatives=alts or _NEXT.get(slot.primary, ())[:2],
            primary_limit=primary_n,
            extra_limit=extra_n,
            weekday=slot.weekday,
            planning_mode=planning_mode,
        )
    moves = library(slot.primary, experience=exp, limit=count)
    return SessionSuggestion(
        region=slot.primary,
        title=_title(slot.primary).split(" (")[0].title(),
        reason=reason,
        muscles=_muscles_of(moves),
        exercises=moves,
        alternatives=alts or list(_NEXT.get(slot.primary, ())[:2]),
        avoided=avoided,
        weekday=slot.weekday,
        planning_mode=planning_mode,
    )


def _slot_reason(slot: WeekSlot, *, prefix: str | None = None) -> str:
    day = _DAY_NAMES[slot.weekday]
    if slot.is_rest:
        body = f"{day} on your week is a rest slot — easy core if you still want to move."
    elif slot.primary == "push" and slot.extra == "core":
        body = f"{day} on your week is chest and abs."
    elif slot.primary == "full_body":
        body = f"{day} on your week is full body."
    else:
        body = f"{day} on your week is {_title(slot.primary).split(' (')[0]}."
    if prefix:
        return f"{prefix} {body}"
    return body


def _next_open_slot(
    start: WeekSlot,
    split: list[WeekSlot],
    avoided: str | None,
) -> WeekSlot:
    """Walk forward when today's region is still yesterday's tissue."""
    if not avoided or start.is_rest:
        return start
    if start.primary != avoided:
        return start
    for delta in range(1, 7):
        nxt = slot_for((start.weekday + delta) % 7, split)
        if not nxt.is_rest and nxt.primary != avoided:
            return nxt
    return start


def suggest_session(
    *,
    last_region: str | None = None,
    last_label: str | None = None,
    hours_since: float | None = None,
    weekday: int | None = None,  # Mon=0 … Sun=6 (legacy weekend lean)
    hour: int | None = None,
    experience: str = "intermediate",
    readiness: int | None = None,
    asked_region: str | None = None,
    planning_mode: str | None = None,
    weekly_split: Any = None,
    sun0_weekday: int | None = None,  # 0=Sun … 6=Sat
    pick_weekday: int | None = None,
    replay_prior: bool = False,
    stance: str | None = None,
) -> SessionSuggestion:
    """Pick the session from the week, yesterday, the clock, and what they know."""
    exp = (experience or "intermediate").lower()
    hours = hours_since
    still_fresh = hours is not None and hours < FRESH_HOURS
    long_gap = hours is None or hours >= FULL_BODY_HOURS
    late = hour is not None and hour >= 21
    low = readiness is not None and readiness < 55
    # Learned stance is an action source: protect keeps the floor small even
    # when a raw recovery number would have green-lit a hard session.
    if (stance or "").strip().lower() == "protect":
        low = True
    beginner = exp == "beginner"
    mode = (planning_mode or "rotate").lower()
    if mode not in ("fixed", "rotate"):
        mode = "rotate"
    split = parse_split(weekly_split)
    today = sun0_weekday if sun0_weekday is not None else None
    if today is None and weekday is not None:
        # Legacy Mon=0 → Sun=0
        today = (int(weekday) + 1) % 7
    if today is not None:
        today = int(today) % 7

    avoided = last_region if still_fresh and last_region else None

    # Replay yesterday's slot, or a named weekday — user owns the calendar.
    chosen: int | None = None
    replay_prefix: str | None = None
    if replay_prior and today is not None:
        chosen = (today - 1) % 7
        replay_prefix = "Going back one day."
    elif pick_weekday is not None:
        chosen = int(pick_weekday) % 7
        replay_prefix = f"You picked {_DAY_NAMES[chosen]}."

    if chosen is not None:
        slot = slot_for(chosen, split)
        note = None
        if avoided and slot.primary == avoided:
            note = f"{_title(avoided).split(' (')[0].capitalize()} is still fresh — your call."
        reason = _slot_reason(slot, prefix=replay_prefix)
        if note:
            reason = f"{note} {reason}"
        suggestion = session_from_slot(
            slot,
            experience=exp,
            reason=reason,
            avoided=avoided,
            planning_mode=mode,
        )
        return suggestion

    # Explicit muscle/region ask — honor it unless that tissue is still yesterday's work.
    if asked_region and not (avoided and asked_region == avoided):
        moves = library(asked_region, experience=exp, limit=5 if not late else 3)
        return SessionSuggestion(
            region=asked_region,
            title=_title(asked_region).split(" (")[0].title(),
            reason="You asked for it, so that's the library I'm opening.",
            muscles=_muscles_of(moves),
            exercises=moves,
            alternatives=list(_NEXT.get(asked_region, ())[:2]),
            planning_mode=mode,
            weekday=today,
        )

    # Fixed week: today's slot walks the calendar. Still-fresh tissue skips ahead.
    if mode == "fixed" and today is not None:
        slot = slot_for(today, split)
        skipped = _next_open_slot(slot, split, avoided)
        prefix = None
        if skipped.weekday != slot.weekday:
            prefix = f"{_title(avoided or '').split(' (')[0].capitalize()} is still fresh, so I'm opening the next day on your week."
        return session_from_slot(
            skipped,
            experience=exp,
            reason=_slot_reason(skipped, prefix=prefix),
            avoided=avoided,
            planning_mode="fixed",
        )

    if low or (late and still_fresh):
        moves = library("core", experience=exp, limit=4)
        why = (
            "Recovery is asking for care, so I'm keeping the floor small."
            if low
            else "It's late, so a short core session beats a hero day."
        )
        return SessionSuggestion(
            region="core",
            title="Easy core",
            reason=why,
            muscles=_muscles_of(moves),
            exercises=moves,
            alternatives=["conditioning"],
            avoided=avoided,
            weekday=today,
            planning_mode=mode,
        )

    # Rotate with a known weekday and no last session — walk the calendar
    # (Tuesday legs, Wednesday chest+abs) instead of inventing a split.
    if last_region is None and today is not None:
        slot = slot_for(today, split)
        return session_from_slot(
            slot,
            experience=exp,
            reason=_slot_reason(slot),
            avoided=avoided,
            planning_mode=mode,
        )

    # Beginner / long gap → full body (mix of the three strength libraries).
    if beginner or long_gap:
        if avoided == "legs" and still_fresh:
            return _combo_session(
                "push", "core",
                experience=exp,
                reason=_yesterday_reason(last_region, last_label, hours),
                avoided=avoided,
                alternatives=["pull", "conditioning"],
            )
        mix = (
            library("push", experience=exp, limit=2)
            + library("pull", experience=exp, limit=2)
            + library("legs", experience=exp, limit=2)
        )
        return SessionSuggestion(
            region="full_body",
            title="Full body",
            reason=(
                "It's been a few days, so a full-body session from the libraries fits."
                if long_gap and not beginner
                else "Keeping it full-body — consistency beats a split you don't need yet."
            ),
            muscles=_muscles_of(mix),
            exercises=mix,
            alternatives=["push", "legs"],
            combo=["push", "pull", "legs"],
            avoided=avoided,
            weekday=today,
            planning_mode=mode,
        )

    # Complementary split. After legs, default to chest+abs (push+core) —
    # the exact "Tuesday legs → Wednesday chest and abs" case.
    if avoided == "legs":
        return _combo_session(
            "push", "core",
            experience=exp,
            reason=_yesterday_reason(last_region, last_label, hours),
            avoided="legs",
            alternatives=["pull", "full_body"],
        )

    nxt = "push"
    alts: list[str] = ["pull", "legs"]
    if last_region in _NEXT:
        nxt, *rest = _NEXT[last_region]
        alts = [r for r in rest if r != nxt]
        if still_fresh:
            alts = [r for r in alts if r != last_region]

    # Mid-week pull after a Monday push is the classic PPL; weekends lean fuller.
    if weekday is not None and weekday >= 5 and nxt != "legs":
        alts = ["full_body", *alts]

    moves = library(nxt, experience=exp, limit=5 if not late else 3)
    return SessionSuggestion(
        region=nxt,
        title=_title(nxt).split(" (")[0].title(),
        reason=_yesterday_reason(last_region, last_label, hours),
        muscles=_muscles_of(moves),
        exercises=moves,
        alternatives=alts[:2],
        avoided=avoided,
        weekday=today,
        planning_mode=mode,
    )


def _yesterday_reason(region: str | None, label: str | None, hours: float | None) -> str:
    what = label or (_title(region) if region else "your last session")
    if hours is not None and hours < 24:
        when = "yesterday"
    elif hours is not None and hours < 48:
        when = "about a day ago"
    else:
        when = "last time"
    if region:
        return f"{what.capitalize()} was {when}, so that tissue sits this one out."
    return f"{what.capitalize()} was {when} — I'll rotate the library rather than repeat it."


def _muscles_of(moves: Iterable[Move]) -> list[str]:
    out: list[str] = []
    for move in moves:
        for m in move.muscles:
            if m not in out:
                out.append(m)
    return out


def is_training_ask(message: str) -> bool:
    lower = (message or "").lower()
    return any(
        n in lower
        for n in (
            "train", "workout", "session", "lift", "gym", "exercise",
            "today's plan", "todays plan", "what should i do today",
            "leg day", "push day", "pull day",
            "yesterday's session", "yesterdays session", "do yesterday",
            "day prior", "this week's", "this weeks",
        )
    )


def maybe_suggest(
    message: str,
    *,
    last_workout_type: str | None = None,
    last_workout_name: str | None = None,
    hours_since: float | None = None,
    weekday: int | None = None,
    hour: int | None = None,
    experience: str = "intermediate",
    readiness: int | None = None,
    planning_mode: str | None = None,
    weekly_split: Any = None,
    sun0_weekday: int | None = None,
    stance: str | None = None,
) -> SessionSuggestion | None:
    """Entry used by ARIA / the dummy orchestra. None when this isn't a session ask."""
    if not is_training_ask(message):
        return None
    asked = infer_region(message)
    # A generic "what should I train" is not an asked region.
    if asked and not any(
        a in (message or "").lower()
        for a in _REGION_ALIASES.get(asked, ())
        if a not in ("train", "session", "workout")
    ):
        asked = None
    last = infer_region(last_workout_name, last_workout_type)
    asked_day = infer_asked_weekday(message)
    replay = wants_replay_prior(message)
    return suggest_session(
        last_region=last,
        last_label=last_workout_name or last_workout_type,
        hours_since=hours_since,
        weekday=weekday,
        hour=hour,
        experience=experience,
        readiness=readiness,
        asked_region=asked,
        planning_mode=planning_mode,
        weekly_split=weekly_split,
        sun0_weekday=sun0_weekday,
        pick_weekday=asked_day,
        replay_prior=replay,
        stance=stance,
    )
