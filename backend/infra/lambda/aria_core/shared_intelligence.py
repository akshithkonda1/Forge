"""Shared intelligence sidecar for native clients.

iOS (Swift Charts, SwiftUI) and Android (Compose, Kotlin charts) render their
own UI. This module is the Python they both call: one JSON object of coaching
facts so neither frontend reimplements readiness, habits, sleep story, or
wind-down math.

Never invents missing vitals. Empty inputs yield empty optional fields.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from . import aria_day_brief
from . import aria_guidance_policy
from . import aria_personal_read
from . import circadian_rhythm as cr
from . import context_rules
from . import habit_engine
from . import habit_streak
from . import human_living_character
from . import hydration_engine
from . import metabolic_watch_signals as mws
from . import mindfulness_suggestion
from . import readiness_calculator
from . import sleep_story_engine
from . import sleep_wind_down_notice
from . import smart_stack_relevance
from . import workout_suggestion
from .quality_of_life import QualityOfLifeInputs, score as qol_score
from .watch_context import WatchContext


def _habit_dict(habit: habit_engine.DeepHabit) -> dict[str, Any]:
    return {
        "id": habit.id,
        "title": habit.title,
        "cue": habit.cue,
        "routine": habit.routine,
        "payoff": habit.payoff,
        "cost": habit.cost,
        "category": habit.category,
        "confidence": habit.confidence,
        "evidence": habit.evidence,
        "breaker": habit.breaker,
        "breakerAction": habit.breaker_action,
    }


def compute(
    *,
    watch: WatchContext | None = None,
    message: str = "",
    sleep_hours: float | None = None,
    deep_minutes: float | None = None,
    rem_minutes: float | None = None,
    awake_minutes: float | None = None,
    hrv_ms: float | None = None,
    hrv_baseline_ms: float | None = None,
    resting_hr: float | None = None,
    resting_hr_baseline: float | None = None,
    steps: int | None = None,
    active_calories: float | None = None,
    protein_grams: float | None = None,
    water_glasses: float | None = None,
    water_consumed_ml: float | None = None,
    weight_kg: float | None = None,
    qol_overall: int | None = None,
    lifestyle_tags: list[str] | None = None,
    habit_completed: int | None = None,
    habit_total: int | None = None,
    qualifying_days: list[str] | None = None,
    vo2_max: float | None = None,
    exercise_minutes: float | None = None,
    living_tags: list[str] | None = None,
    now: datetime | None = None,
    active_workout_phase: str | None = None,
    already_fired_desk_nudge: bool = False,
    sensor_source: str = "wearable",
) -> dict[str, Any]:
    """Build the sidecar native Home / Watch / Lifestyle screens decode."""
    moment = now or datetime.now(timezone.utc)
    ctx = watch or WatchContext(timestamp=moment)
    if sleep_hours is not None and ctx.sleep_minutes is None:
        ctx.sleep_minutes = sleep_hours * 60
    if deep_minutes is not None and ctx.deep_sleep_minutes is None:
        ctx.deep_sleep_minutes = deep_minutes
    if rem_minutes is not None and ctx.rem_sleep_minutes is None:
        ctx.rem_sleep_minutes = rem_minutes
    if hrv_ms is not None and ctx.hrv_recent_ms is None:
        ctx.hrv_recent_ms = hrv_ms

    night_hours = sleep_hours
    if night_hours is None and ctx.sleep_minutes:
        night_hours = ctx.sleep_minutes / 60.0

    glance = readiness_calculator.score(readiness_calculator.ReadinessInputs(
        hrv_ms=hrv_ms if hrv_ms is not None else ctx.hrv_recent_ms,
        hrv_baseline_ms=hrv_baseline_ms,
        resting_hr=resting_hr,
        resting_hr_baseline=resting_hr_baseline,
        sleep_minutes=ctx.sleep_minutes,
        deep_sleep_minutes=deep_minutes if deep_minutes is not None else ctx.deep_sleep_minutes,
        rem_sleep_minutes=rem_minutes if rem_minutes is not None else ctx.rem_sleep_minutes,
    ))
    if ctx.readiness_overall is None and glance.confidence > 0:
        ctx.readiness_overall = glance.overall
        if ctx.readiness_confidence is None:
            ctx.readiness_confidence = glance.confidence

    mindfulness = mindfulness_suggestion.suggest(ctx)
    greeting = mindfulness_suggestion.greeting(ctx)
    day_brief = aria_day_brief.line(ctx, mindfulness)
    training = workout_suggestion.suggest(ctx)
    event = workout_suggestion.event_plan(lifestyle_tags or [])
    qol_plan = workout_suggestion.qol_training_plan(lifestyle_tags or [], overall=qol_overall)

    personal = aria_personal_read.evaluate(
        night_hours=night_hours,
        deep_minutes=deep_minutes if deep_minutes is not None else ctx.deep_sleep_minutes,
        rem_minutes=rem_minutes if rem_minutes is not None else ctx.rem_sleep_minutes,
        awake_minutes=awake_minutes,
        hrv_ms=hrv_ms if hrv_ms is not None else ctx.hrv_recent_ms,
        hrv_baseline_ms=hrv_baseline_ms,
        readiness=ctx.readiness_overall or 0,
        qol_overall=qol_overall,
        qol_line=(
            None
            if qol_overall is None
            else f"Lifestyle QoL {qol_overall}/100"
        ),
        swarm_stance=None,
    )

    night = None
    if night_hours and night_hours > 0:
        night = sleep_story_engine.SleepNightStory(
            total_minutes=night_hours * 60,
            deep_minutes=deep_minutes or ctx.deep_sleep_minutes or 0,
            rem_minutes=rem_minutes or ctx.rem_sleep_minutes or 0,
            awake_minutes=awake_minutes or 0,
        )
    last_night = sleep_story_engine.story(
        night,
        readiness_overall=ctx.readiness_overall,
        factors=ctx.sleep_factors,
    )

    glasses = water_glasses
    if glasses is None and water_consumed_ml is not None:
        glasses = hydration_engine.glasses_from_milliliters(water_consumed_ml)
    hydration = None
    if glasses is not None or water_consumed_ml is not None:
        consumed = water_consumed_ml if water_consumed_ml is not None else hydration_engine.milliliters_from_glasses(glasses or 0)
        target = hydration_engine.target_milliliters(
            weight_kg,
            active_calories=active_calories or 0.0,
        )
        expected = hydration_engine.expected_milliliters(
            cr.hour_of_day(moment),
            target,
        )
        status = hydration_engine.status(consumed, target, expected)
        hydration = {
            "consumedMilliliters": consumed,
            "targetMilliliters": target,
            "expectedMilliliters": expected,
            "status": status,
            "guidance": hydration_engine.guidance(status, target - consumed, 8.0),
            "glasses": hydration_engine.glasses_from_milliliters(consumed),
        }

    habits_out: dict[str, Any] | None = None
    if steps is not None or protein_grams is not None or glasses is not None or night_hours is not None:
        signals = habit_engine.HabitSignals(
            # Missing sleep must not invent a short night. 8.0 is the engine's
            # "on target" value and will not fire sleep_variance without a
            # measured variance.
            sleep_average=night_hours if night_hours is not None else 8.0,
            steps=int(steps or 0),
            protein=float(protein_grams or 0),
            water_glasses=float(glasses or 0),
            total_calories=0,
            hrv=hrv_ms,
            hrv_baseline=hrv_baseline_ms,
            quality_of_life_score=qol_overall if qol_overall is not None else 80,
        )
        loops = habit_engine.analyze(signals)
        habits_out = {
            "loops": [_habit_dict(h) for h in loops],
            "companionLine": habit_engine.companion_line(loops),
            "lifestyleTags": habit_engine.lifestyle_tags(loops),
            "constraints": habit_engine.constraints(loops),
        }

    streak = None
    if qualifying_days is not None or (habit_completed is not None and habit_total is not None):
        days = list(qualifying_days or [])
        today_qualifies = (
            habit_streak.qualifies(habit_completed, habit_total)
            if habit_completed is not None and habit_total is not None
            else None
        )
        if today_qualifies is not None:
            days_dates = habit_streak.recording(moment.date(), today_qualifies, days)
            days = [d.isoformat() for d in days_dates]
        streak = {
            "length": habit_streak.length(days, today=moment.date()),
            "qualifyingShare": habit_streak.QUALIFYING_SHARE,
            "todayQualifies": today_qualifies,
            "qualifyingDays": days,
        }

    qol = None
    qol_inputs = QualityOfLifeInputs(
        sleep_hours=night_hours,
        deep_sleep_minutes=deep_minutes if deep_minutes is not None else ctx.deep_sleep_minutes,
        rem_sleep_minutes=rem_minutes if rem_minutes is not None else ctx.rem_sleep_minutes,
        steps=steps,
        active_calories=int(active_calories) if active_calories is not None else None,
        protein_grams=protein_grams,
        water_glasses=glasses,
        hrv_ms=hrv_ms,
        hrv_baseline_ms=hrv_baseline_ms,
        resting_hr=resting_hr,
        resting_hr_baseline=resting_hr_baseline,
        vo2_max=vo2_max,
        body_mass_kg=weight_kg,
    )
    computed_qol = qol_score(qol_inputs)
    if computed_qol.graded_aspects:
        qol = {
            "overall": computed_qol.overall,
            "confidence": computed_qol.confidence,
            "band": computed_qol.band,
            "pillars": computed_qol.pillar_scores,
            "isEstimate": computed_qol.is_estimate,
        }

    metabolic = mws.evaluate(
        mws.MetabolicWatchInputs(
            resting_hr_bpm=resting_hr or 0,
            hrv_ms=hrv_ms or 0,
            hrv_baseline_ms=hrv_baseline_ms or 0,
            vo2_max=vo2_max or 0,
            active_calories=active_calories or 0,
            exercise_minutes=exercise_minutes or 0,
            sleep_hours=night_hours or 0,
        ),
        source=sensor_source,
    )

    wind = sleep_wind_down_notice.fire_hour_minute(None)
    stack = smart_stack_relevance.score(
        active_workout_phase=active_workout_phase,
        recommended_practice=None,
        now=moment,
    )

    guidance = aria_guidance_policy.decide(message) if message else None

    circadian = None
    if night_hours and night_hours > 0:
        need = cr.sleep_need_hours_from_durations([night_hours])
        circadian = {
            "sleepNeedHours": need,
            "hourOfDay": cr.hour_of_day(moment),
        }

    return {
        "schemaVersion": 1,
        "source": "aria_core.shared_intelligence",
        "greeting": greeting,
        "dayBrief": day_brief,
        "mindfulness": mindfulness.to_dict(),
        "workoutSuggestion": training.to_dict(),
        "eventTraining": event.to_dict() if event else None,
        "qolTraining": qol_plan.to_dict() if qol_plan else None,
        "personalRead": personal.to_dict(),
        "sleepStory": last_night,
        "hydration": hydration,
        "habits": habits_out,
        "habitStreak": streak,
        "qualityOfLife": qol,
        "glanceReadiness": glance.to_dict(),
        "metabolicWatch": metabolic.to_dict() if metabolic.has_signals else None,
        "windDown": {"hour": wind[0], "minute": wind[1]},
        "smartStack": stack.to_dict() if stack else None,
        "guidance": guidance.to_dict() if guidance else None,
        "circadian": circadian,
        "contextRules": {
            "deskBlockNudgeDue": context_rules.desk_block_nudge_due(
                ctx.lifestyle_mode,
                ctx.minutes_in_current_mode,
                already_fired_desk_nudge,
            ),
            "eveningWindDownDue": context_rules.evening_wind_down_due(
                moment,
                None,
                ctx.lifestyle_mode,
                None,
            ),
            "inLongDeskBlock": ctx.in_long_desk_block,
            "justFinishedWorkout": ctx.just_finished_workout,
            "hrvIsDipping": ctx.hrv_is_dipping,
            "temperatureLooksHigh": ctx.temperature_looks_high,
        },
        "livingDecisionNote": human_living_character.living_decision_note(living_tags or []),
        "keepLight": personal.keep_light or (event.keep_light if event else False) or (
            qol_plan.keep_light if qol_plan else False
        ),
    }


def from_aria_context(ctx: Any, *, message: str = "", now: datetime | None = None) -> dict[str, Any]:
    """Duck-typed over ``ARIAContext`` so this module never imports aria_engine."""
    sleep = getattr(ctx, "sleep", None)
    readiness = getattr(ctx, "readiness", None)
    activity = getattr(ctx, "activity", None)
    nutrition = getattr(ctx, "nutrition", None)
    lifestyle = getattr(ctx, "lifestyle", None)
    body = getattr(ctx, "body", None)
    training = getattr(ctx, "training", None)

    duration = getattr(sleep, "duration_minutes", None) if sleep else None
    sleep_hours = (duration / 60.0) if duration else None
    recovery = getattr(readiness, "recovery_score", None) if readiness else None
    watch = WatchContext(
        timestamp=now or datetime.now(timezone.utc),
        readiness_overall=int(recovery) if isinstance(recovery, (int, float)) else None,
        readiness_confidence=0.8 if recovery is not None else None,
        hrv_trend_ms=getattr(readiness, "hrv_7day_trend", None) if readiness else None,
        sleep_minutes=duration,
        deep_sleep_minutes=getattr(sleep, "deep_minutes", None) if sleep else None,
        rem_sleep_minutes=getattr(sleep, "rem_minutes", None) if sleep else None,
        hours_since_last_workout=getattr(training, "hours_since_last_workout", None) if training else None,
        last_workout_type=getattr(training, "last_workout_type", None) if training else None,
    )
    tags = list(getattr(lifestyle, "tags", None) or []) if lifestyle else []
    qol = getattr(lifestyle, "quality_of_life_score", None) if lifestyle else None
    if now is None:
        stamp = getattr(ctx, "timestamp", None)
        if isinstance(stamp, datetime):
            now = stamp
        elif isinstance(stamp, str):
            try:
                now = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
            except ValueError:
                now = None
    return compute(
        watch=watch,
        message=message,
        sleep_hours=sleep_hours,
        deep_minutes=getattr(sleep, "deep_minutes", None) if sleep else None,
        rem_minutes=getattr(sleep, "rem_minutes", None) if sleep else None,
        hrv_ms=getattr(sleep, "hrv", None) if sleep else None,
        hrv_baseline_ms=getattr(readiness, "hrv_30day_baseline", None) if readiness else None,
        resting_hr=getattr(sleep, "resting_hr", None) if sleep else None,
        steps=_int(getattr(activity, "steps_3day_avg", None) if activity else None),
        active_calories=getattr(activity, "active_calories_3day_avg", None) if activity else None,
        protein_grams=getattr(nutrition, "protein_g_3day_avg", None) if nutrition else None,
        water_consumed_ml=getattr(nutrition, "hydration_ml_3day_avg", None) if nutrition else None,
        qol_overall=int(qol) if isinstance(qol, (int, float)) else None,
        lifestyle_tags=tags,
        vo2_max=getattr(body, "vo2_max", None) if body else None,
        now=now,
        living_tags=tags,
        weight_kg=getattr(body, "weight_kg", None) if body else None,
        exercise_minutes=getattr(training, "last_workout_duration_minutes", None) if training else None,
    )


def from_payload(payload: dict[str, Any] | None) -> dict[str, Any]:
    raw = payload if isinstance(payload, dict) else {}
    watch_raw = raw.get("watchContext") or raw.get("context") or raw
    watch = WatchContext.from_payload(watch_raw if isinstance(watch_raw, dict) else {})
    habits = raw.get("habits") if isinstance(raw.get("habits"), dict) else {}
    raw_days = habits.get("qualifyingDays") if "qualifyingDays" in habits else raw.get("qualifyingDays")
    qualifying_days = list(raw_days) if isinstance(raw_days, list) else None
    source = str(raw.get("sensorSource") or "wearable").strip() or "wearable"
    return compute(
        watch=watch,
        message=str(raw.get("message") or ""),
        sleep_hours=watch.sleep_minutes / 60.0 if watch.sleep_minutes else None,
        deep_minutes=watch.deep_sleep_minutes,
        rem_minutes=watch.rem_sleep_minutes,
        hrv_ms=watch.hrv_recent_ms,
        hrv_baseline_ms=_float(raw.get("hrvBaselineMs")),
        resting_hr=_float(raw.get("restingHR") or raw.get("restingHr")),
        resting_hr_baseline=_float(raw.get("restingHRBaseline")),
        steps=_int(raw.get("steps")),
        active_calories=_float(raw.get("activeCalories")),
        protein_grams=_float(raw.get("proteinGrams")),
        water_glasses=_float(raw.get("waterGlasses")),
        water_consumed_ml=_float(raw.get("waterConsumedMl") or raw.get("consumedMilliliters")),
        weight_kg=_float(raw.get("weightKg")),
        qol_overall=_int(raw.get("qualityOfLifeScore")),
        lifestyle_tags=list(raw.get("lifestyleTags") or []),
        habit_completed=_int(habits.get("completed")),
        habit_total=_int(habits.get("total")),
        qualifying_days=qualifying_days,
        vo2_max=_float(raw.get("vo2Max")),
        exercise_minutes=_float(raw.get("exerciseMinutes")),
        living_tags=list(raw.get("livingTags") or raw.get("lifestyleTags") or []),
        now=watch.timestamp,
        active_workout_phase=str(raw["activeWorkoutPhase"]) if raw.get("activeWorkoutPhase") else None,
        already_fired_desk_nudge=bool(raw.get("alreadyFiredDeskNudge")),
        sensor_source=source,
        awake_minutes=_float(raw.get("awakeMinutes")),
    )


def from_dashboard(
    *,
    profile: dict[str, Any] | None = None,
    readiness: dict[str, Any] | None = None,
    daily_metrics: dict[str, Any] | None = None,
    recent_sleep: list[dict[str, Any]] | None = None,
    today_workout: dict[str, Any] | None = None,
    now: datetime | None = None,
) -> dict[str, Any]:
    """Sidecar for ``GET /dashboard/today`` — same facts iOS and Android Home decode."""
    metrics = daily_metrics if isinstance(daily_metrics, dict) else {}
    night = recent_sleep[0] if recent_sleep else None
    if not isinstance(night, dict):
        night = None

    sleep_hours = _hours_from_metrics(metrics, night)
    deep = _float(metrics.get("deepSleep"))
    if deep is None and night is not None:
        deep = _float(night.get("deepMinutes"))
    rem = _float(night.get("remMinutes")) if night else None
    awake = _float(night.get("awakeMinutes")) if night else None
    hrv = _float(metrics.get("hrv"))
    rhr = _float(metrics.get("restingHR"))
    steps = _int(metrics.get("steps"))
    calories = _float(metrics.get("activeCalories"))

    name = str((profile or {}).get("name") or "").strip() or None
    overall = _int((readiness or {}).get("overall"))
    sleep_quality = _int((readiness or {}).get("sleepQuality"))
    if sleep_quality is None and night is not None:
        sleep_quality = _int(night.get("score"))

    watch = WatchContext(
        timestamp=now or datetime.now(timezone.utc),
        readiness_overall=overall,
        readiness_confidence=0.8 if overall is not None else None,
        hrv_recent_ms=hrv,
        sleep_minutes=sleep_hours * 60 if sleep_hours is not None else None,
        deep_sleep_minutes=deep,
        rem_sleep_minutes=rem,
        sleep_quality_score=sleep_quality,
        last_workout_type=str(today_workout["type"]) if isinstance(today_workout, dict) and today_workout.get("type") else None,
        user_name=name,
    )
    return compute(
        watch=watch,
        sleep_hours=sleep_hours,
        deep_minutes=deep,
        rem_minutes=rem,
        awake_minutes=awake,
        hrv_ms=hrv,
        resting_hr=rhr,
        steps=steps,
        active_calories=calories,
        now=watch.timestamp,
        sensor_source="wearable",
    )


def _hours_from_metrics(metrics: dict[str, Any], night: dict[str, Any] | None) -> float | None:
    total = _float(metrics.get("totalSleep"))
    if total is not None:
        return total / 60.0
    if night is None:
        return None
    hours = _float(night.get("totalHours"))
    if hours is not None:
        return hours
    minutes = _float(night.get("durationMinutes") or night.get("totalMinutes"))
    if minutes is not None:
        return minutes / 60.0
    return None


def _float(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _int(value: Any) -> int | None:
    number = _float(value)
    return int(number) if number is not None else None
