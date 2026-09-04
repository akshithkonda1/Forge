"""Behavior engine — derive a 30-day synthetic data stream from a persona.

Given a ``behavioral_profile``, produce one ``DailyRecord`` per day that reflects
how that persona actually lives: consistency drives sleep variance, training
load suppresses HRV, ACWR spikes when workouts cluster, and the ``season`` shapes
the 30-day arc. Everything is seeded, so a given profile + seed is reproducible
to the byte.

Two optional profile keys model real wearable imperfection, both off by default
so every existing archetype's output stays byte-identical: ``data_completeness``
(0-1, the per-field odds a day's sleep/HRV/resting-HR actually got captured —
real devices miss nights and skip staging far more than they miss steps) and
``source_conflict`` (a same-metric divergence on resting HR, mirroring the real
backend's own observation that HRV and resting HR are the only two metrics it
blends across sources today). Every new RNG draw these introduce is gated behind
the profile opting in, never rolled-and-discarded, so a profile that never sets
either key consumes the RNG stream identically to before this existed.
"""

from __future__ import annotations

import datetime
import math
import os
import random
from dataclasses import dataclass


@dataclass
class DailyRecord:
    date: str                       # ISO, Day 1 = today - 29 days
    total_sleep_hours: float | None
    deep_sleep_minutes: int | None
    rem_sleep_minutes: int | None
    sleep_score: int | None         # 0-100
    hrv: int | None                 # ms
    resting_hr: int | None
    readiness_score: int            # 0-100, computed from sleep + hrv + recovery — always present
    steps: int
    active_calories: int
    workout_logged: bool
    workout_type: str | None        # "strength" | "cardio" | "hiit" | "rest" | None
    workout_duration_minutes: int | None
    workout_intensity: str | None   # "low" | "moderate" | "high" | "max"
    training_load: float
    acwr: float                     # acute:chronic workload ratio (7d:28d) — always present
    notes: str | None


_CHRONOTYPE_SLEEP_TARGET = {"bear": 8.0, "lion": 7.5, "wolf": 7.5, "dolphin": 6.5}
_INTENSITY_LOAD = {"low": 0.6, "moderate": 1.0, "high": 1.5, "max": 2.0}
_DAYS = 30

# Sleep staging (deep/REM) fails to capture more often than gross duration does
# on real wearables — a device can log "you slept 7h" while missing the stage
# breakdown far more easily than it can miss the night's sleep entirely.
_STAGE_CAPTURE_FACTOR = 0.75
_SOURCE_CONFLICT_PROBABILITY = 0.35
_SOURCE_CONFLICT_MAGNITUDE = (6, 14)  # bpm swing applied to resting_hr on a conflict day


def _reference_today(reference_date: "datetime.date | None" = None) -> datetime.date:
    """Resolve 'today' — explicit arg, then SIMRUNNER_TODAY env (ISO date), then
    the real calendar day. Pinning a date makes report files byte-reproducible."""
    if reference_date is not None:
        return reference_date
    pinned = os.getenv("SIMRUNNER_TODAY")
    if pinned:
        try:
            return datetime.date.fromisoformat(pinned)
        except ValueError:
            pass
    return datetime.date.today()


def _stable_hash(text: str) -> int:
    """Deterministic FNV-1a hash (stdlib `hash()` is salted per process)."""
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h


def _profile_seed(profile: dict, seed: int) -> int:
    canonical = ";".join(f"{k}={profile[k]}" for k in sorted(profile))
    return (seed ^ _stable_hash(canonical)) & 0x7FFFFFFF


def _clamp(value: float, low: float, high: float) -> float:
    return max(low, min(high, value))


def _season_load_factor(season: str, day: int, total: int) -> float:
    """Multiplier on training load across the arc (day is 0-indexed)."""
    progress = day / max(1, total - 1)
    if season == "build":
        return 0.75 + 0.5 * progress
    if season == "recovery":
        return 1.15 - 0.55 * progress
    if season == "peak":
        return 1.25 if progress < 0.8 else 1.25 - (progress - 0.8) * 3.0  # taper at the end
    if season == "irregular":
        return 0.7 + 0.6 * (0.5 + 0.5 * math.sin(day * 1.3))
    return 1.0  # maintenance


def _schedule_workouts(profile: dict, rng: random.Random) -> list[bool]:
    """Decide which of 30 days carry a workout, with clustering for overtrainers."""
    freq = float(profile.get("training_frequency_per_week", 4))
    consistency = float(profile.get("training_consistency", 0.8))
    overtrain = float(profile.get("overtraining_tendency", 0.2))
    irregularity = float(profile.get("life_irregularity", 0.2))
    base_p = _clamp(freq / 7.0, 0.0, 1.0)

    schedule: list[bool] = []
    for day in range(_DAYS):
        p = base_p * (0.6 + 0.4 * consistency)
        # Overtrainers cluster workouts onto already-active stretches.
        if schedule[-2:] == [True, True] and rng.random() < overtrain:
            p += 0.35
        # Irregular lives miss otherwise-planned sessions.
        if rng.random() < irregularity * 0.4:
            p -= 0.4
        schedule.append(rng.random() < _clamp(p, 0.0, 1.0))
    return schedule


def _sleep_for_day(profile: dict, target: float, rng: random.Random, debt_active: bool) -> float:
    consistency = float(profile.get("sleep_consistency", 0.8))
    spread = (1.0 - consistency) * 2.2  # hours of std
    hours = rng.gauss(target, max(0.25, spread))
    if debt_active:
        hours -= rng.uniform(1.0, 2.5)
    return _clamp(hours, 3.0, 10.5)


def generate_stream(
    profile: dict, seed: int = 42, reference_date: "datetime.date | None" = None
) -> list[DailyRecord]:
    rng = random.Random(_profile_seed(profile, seed))
    target_sleep = _CHRONOTYPE_SLEEP_TARGET.get(profile.get("chronotype", "bear"), 8.0)
    hrv_baseline = float(profile.get("hrv_baseline", 55))
    hrv_cv = float(profile.get("hrv_variance", 0.1))
    season = profile.get("season", "maintenance")
    debt_tendency = float(profile.get("sleep_debt_tendency", 0.2))

    schedule = _schedule_workouts(profile, rng)
    today = _reference_today(reference_date)
    loads: list[float] = []
    records: list[DailyRecord] = []
    notes_added = 0

    # Multi-day sleep-debt clusters.
    debt_days = set()
    day = 0
    while day < _DAYS:
        if rng.random() < debt_tendency * 0.25:
            length = rng.randint(2, 4)
            for d in range(day, min(_DAYS, day + length)):
                debt_days.add(d)
            day += length
        else:
            day += 1

    # Persona-specific scripted events.
    pattern = profile.get("notable_pattern")
    crunch = set(range(17, 24)) if (pattern == "crunch_week" or profile.get("rejects_recovery")) else set()
    nurse_clusters = (set(range(8, 11)) | set(range(20, 23))) if pattern == "short_sleep_clusters" else set()
    change_day = profile.get("season_change_day")

    for day in range(_DAYS):
        date = (today - datetime.timedelta(days=_DAYS - 1 - day)).isoformat()
        note = None

        in_debt = day in debt_days or day in crunch or day in nurse_clusters
        sleep_hours = _sleep_for_day(profile, target_sleep, rng, in_debt)
        if pattern == "hormonal_sleep_disruption" and rng.random() < 0.4:
            sleep_hours = _clamp(sleep_hours - rng.uniform(0.5, 1.5), 3.0, 10.5)
            note = "hormonal sleep disruption — fragmented night"

        # Sleep architecture.
        efficiency = _clamp(rng.gauss(0.88, 0.05), 0.6, 0.98)
        total_min = sleep_hours * 60
        deep = int(_clamp(rng.gauss(0.18, 0.03), 0.08, 0.26) * total_min)
        rem = int(_clamp(rng.gauss(0.22, 0.04), 0.10, 0.30) * total_min)
        sleep_score = int(_clamp(
            (sleep_hours / target_sleep) * 70 + efficiency * 35 - (12 if in_debt else 0),
            0, 100,
        ))

        # Workout + training load.
        injury_block = pattern == "injury_return" and day < 6
        season_factor = _season_load_factor(season, day, _DAYS)
        if change_day is not None and day >= int(change_day):
            season_factor *= float(profile.get("season_change_load_factor", 0.4))

        do_workout = schedule[day] and not injury_block
        workout_type = workout_intensity = None
        duration = None
        load = 0.0
        if do_workout:
            workout_type = rng.choice(["strength", "cardio", "hiit", "strength", "cardio"])
            workout_intensity = rng.choices(
                ["low", "moderate", "high", "max"], weights=[2, 4, 3, 1])[0]
            duration = int(_clamp(rng.gauss(55, 15), 20, 110))
            load = duration / 60.0 * _INTENSITY_LOAD[workout_intensity] * season_factor

        # Gamers log sessions that the body never registers as stress.
        if profile.get("logs_fake_workouts") and not do_workout and rng.random() < 0.4:
            do_workout = True
            workout_type = rng.choice(["strength", "hiit"])
            workout_intensity = "high"
            duration = int(rng.uniform(45, 75))
            load = 0.05  # logged, but no real physiological cost
            note = "logged workout (no corroborating recovery cost)"

        loads.append(load)
        acwr = round(_acwr(loads), 2)  # round once so readiness is reproducible from the stored record

        # HRV: baseline noise + suppression from recent acute load + ambiguity.
        acute = sum(loads[-7:]) / min(7, len(loads))
        suppression = _clamp(acute / 2.5, 0.0, 0.22)
        hrv = hrv_baseline * (1.0 + rng.gauss(0.0, hrv_cv)) * (1.0 - suppression)
        if profile.get("ambiguous_data") and rng.random() < 0.5:
            hrv *= rng.choice([0.82, 1.18])  # signal that conflicts with sleep
        hrv_val = int(_clamp(hrv, 15, hrv_baseline * 1.4))
        resting_hr = int(_clamp(42 + (hrv_baseline - hrv_val) * 0.35 + rng.gauss(0, 2), 38, 90))
        # Two devices disagreeing on the same instantaneous metric — the real
        # backend's own ingestion pipeline treats HRV and resting HR as its
        # only two "blend across sources" metrics (services/daily_metrics.py),
        # so that's exactly where a source conflict would actually surface.
        # `ambiguous_data` already owns HRV-vs-sleep divergence thematically;
        # this targets resting_hr instead so the two traits stay distinct.
        if profile.get("source_conflict") and rng.random() < _SOURCE_CONFLICT_PROBABILITY:
            resting_hr = int(_clamp(
                resting_hr + rng.choice([-1, 1]) * rng.uniform(*_SOURCE_CONFLICT_MAGNITUDE), 38, 90))

        # --- Sparse/incomplete data: independent per-field presence rolls,
        # entirely skipped (no rng draw at all) when the profile doesn't opt
        # in, so a profile that never sets data_completeness consumes the RNG
        # stream identically to before this feature existed — every existing
        # archetype's output stays byte-for-byte unchanged.
        completeness = float(profile.get("data_completeness", 1.0))
        if completeness < 1.0:
            sleep_present = rng.random() < completeness
            total_sleep_hours_out = round(sleep_hours, 1) if sleep_present else None
            if sleep_present:
                stages_present = rng.random() < completeness * _STAGE_CAPTURE_FACTOR
                deep_out = deep if stages_present else None
                rem_out = rem if stages_present else None
                sleep_score_out = sleep_score
            else:
                deep_out = rem_out = sleep_score_out = None
            hrv_out = hrv_val if rng.random() < completeness else None
            resting_hr_out = resting_hr if rng.random() < completeness else None
        else:
            total_sleep_hours_out = round(sleep_hours, 1)
            deep_out, rem_out, sleep_score_out = deep, rem, sleep_score
            hrv_out, resting_hr_out = hrv_val, resting_hr

        # Readiness is computed from what actually reached the record, not
        # the true underlying physiology — this is what makes it genuinely
        # degrade on a sparse day instead of secretly staying fully-informed
        # while just not showing the user.
        readiness = _readiness(sleep_score_out, hrv_out, hrv_baseline, acwr)

        steps = int(_clamp(rng.gauss(8500 if not do_workout else 11000, 2500), 1500, 22000))
        active_cal = int(_clamp(load * 220 + rng.gauss(320, 90), 80, 1600))

        # Notable events from irregularity.
        if note is None:
            if day in crunch:
                note = "crunch week — launch sprint, sleeping short on purpose"
            elif day in nurse_clusters:
                note = "night shift — daytime sleep, short and fragmented"
            elif change_day is not None and day == int(change_day):
                note = "role change — training load dropped after promotion"
            elif rng.random() < float(profile.get("life_irregularity", 0.2)) * 0.35:
                note = rng.choice(["travel day", "late night out", "stress event at work", "missed planned session"])
        if note:
            notes_added += 1

        records.append(DailyRecord(
            date=date, total_sleep_hours=total_sleep_hours_out,
            deep_sleep_minutes=deep_out, rem_sleep_minutes=rem_out, sleep_score=sleep_score_out,
            hrv=hrv_out, resting_hr=resting_hr_out, readiness_score=readiness,
            steps=steps, active_calories=active_cal,
            workout_logged=do_workout, workout_type=workout_type,
            workout_duration_minutes=duration, workout_intensity=workout_intensity,
            training_load=round(load, 3), acwr=round(acwr, 2), notes=note,
        ))

    _guarantee_notable_events(records, notes_added, rng)
    return records


def _acwr(loads: list[float]) -> float:
    acute = sum(loads[-7:]) / min(7, len(loads)) if loads else 0.0
    chronic_window = loads[-28:]
    chronic = sum(chronic_window) / len(chronic_window) if chronic_window else 0.0
    if chronic < 0.05:
        return 1.0
    return _clamp(acute / chronic, 0.0, 2.5)


def _readiness(sleep_score: int | None, hrv: int | None, hrv_baseline: float, acwr: float) -> int:
    """Weighted blend of sleep, HRV, and training load — always returns a real
    0-100 int, never None. When sleep_score and hrv are both present, this
    executes the exact original fixed-weight expression, unchanged (float
    addition isn't perfectly associative, so the fully-populated case is kept
    as its own branch rather than trusted to fall out of a general formula).
    When either is missing, its weight is dropped and the remaining weights
    renormalize — mirrors the real backend's "no HRV -> readiness scoring
    disabled, using sleep proxies" philosophy instead of crashing or ever
    propagating None. Worst case (both missing): degrades to acwr_penalty
    alone — "all we know is training load," never a fabricated number."""
    acwr_penalty = 100 - max(0.0, (acwr - 1.0) * 100)
    hrv_ratio = (min(hrv / hrv_baseline, 1.2) if hrv_baseline > 0 else 1.0) if hrv is not None else None

    if sleep_score is not None and hrv_ratio is not None:
        base = sleep_score * 0.4 + hrv_ratio * 100 * 0.35 + acwr_penalty * 0.25
    else:
        components: list[tuple[float, float]] = [(acwr_penalty, 0.25)]
        if sleep_score is not None:
            components.append((float(sleep_score), 0.40))
        if hrv_ratio is not None:
            components.append((hrv_ratio * 100, 0.35))
        weight = sum(w for _, w in components)
        base = sum(v * w for v, w in components) / weight
    return int(round(_clamp(base, 0, 100)))


def _guarantee_notable_events(records: list[DailyRecord], count: int, rng: random.Random) -> None:
    """Every stream surfaces at least 3 notable events."""
    fillers = ["travel day", "late night", "unusual stress", "schedule disruption"]
    day = 4
    while count < 3 and day < _DAYS:
        if records[day].notes is None:
            records[day].notes = rng.choice(fillers)
            count += 1
        day += 6
    # Backfill if spacing ran out.
    for record in records:
        if count >= 3:
            break
        if record.notes is None:
            record.notes = rng.choice(fillers)
            count += 1
