from __future__ import annotations

import json
import re
from typing import Any

from empty_state import empty_profile, empty_readiness
from security import demo_data_enabled
from seed_data import (
    default_personal_records,
    default_profile,
    default_sleep,
    default_workout,
    default_workout_history,
    today_iso,
)
from services import readiness, scoring
from storage import dynamodb, keys

# On-device PeopleDirectory tags: people:FirstName:relation (max 8).
# Phones, emails, and partner/cycle prefixes never qualify — same strip as
# sanitize_inbound_chat_payload / vault #307.
_PEOPLE_PREFIX = "people:"
_PEOPLE_COUNT = "count"
_PEOPLE_CAP = 8
_DENIED_PEOPLE_NAME = re.compile(
    r"(?i)^(?:partner_|support_cycle|partner_name|partner_phase|"
    r"partner_day|partner_cycle|cycle)"
)


def _strip_keys(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def _sleep_rows_from_body_snapshot(user_id: str) -> list[dict[str, Any]]:
    """The single latest night, derived from the persisted body snapshot --
    the same METRIC#-derived reality /ai/chat and /ai/observe already read
    via fusion.fuse_turn/save_body_snapshot -- for when no SLEEP# session-log
    row exists yet. Without this, a user who has been getting real coaching
    from ARIA elsewhere could still be told "you have no sleep logged" here,
    purely because this route reads a different DynamoDB source than the one
    that actually has their data (see aria_user_model.py's module docstring).

    Deliberately has no "score" field: BodyModel doesn't compute the 0-100
    sleep score a logged session does, and a row silently defaulting that to
    0 would make recovery_trend() report a fabricated "steady, 0" trend
    instead of the honest "not enough history yet" gather_user_context
    preserves by keeping this out of the recoveryTrend computation (see
    below) -- this is display-only data, not trend input.
    """
    try:
        from aria_core import fusion
    except Exception:
        return []
    try:
        snapshot = fusion.load_body_snapshot(user_id)
    except Exception:
        return []
    if not snapshot:
        return []
    sleep = (snapshot.get("aria_context") or {}).get("sleep") or {}
    duration_minutes = sleep.get("duration_minutes")
    if not isinstance(duration_minutes, (int, float)) or isinstance(duration_minutes, bool):
        return []
    row: dict[str, Any] = {"totalHours": round(duration_minutes / 60.0, 2)}
    deep = sleep.get("deep_minutes")
    if isinstance(deep, (int, float)) and not isinstance(deep, bool):
        row["deepMinutes"] = deep
    rem = sleep.get("rem_minutes")
    if isinstance(rem, (int, float)) and not isinstance(rem, bool):
        row["remMinutes"] = rem
    return [row]


def gather_user_context(user_id: str) -> dict[str, Any]:
    """Build the bounded context package the coach routes feed to the AI router.

    This is the block ``AI_SECURITY_DIRECTIVE`` clause 3 points at when it tells
    the model to use only the ground truth it is given and never to invent a
    user's data. Filling it with fixtures made the directive self-defeating: the
    model obediently reasoned over a stranger's sleep and lifts and reported them
    back as the reader's own. Outside a demo environment every field here is
    either something the account stored or empty.
    """
    demo = demo_data_enabled()

    profile_item = dynamodb.get_item(**keys.profile_key(user_id))
    if profile_item:
        profile = _strip_keys(profile_item)
    else:
        profile = default_profile() if demo else empty_profile()

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    if sleep_items:
        recent_sleep = [_strip_keys(i) for i in sleep_items]
    else:
        recent_sleep = default_sleep() if demo else []

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=14)
    if workout_items:
        recent_workouts = [_strip_keys(i) for i in workout_items]
    else:
        recent_workouts = default_workout_history() if demo else []

    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    if plan_item:
        today_plan = _strip_keys(plan_item)
    else:
        today_plan = default_workout() if demo else None

    readiness_item = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    if readiness_item:
        current_readiness = _strip_keys(readiness_item)
    elif recent_sleep:
        current_readiness = readiness.compute_readiness(recent_sleep)
    else:
        current_readiness = empty_readiness()

    personal_records = scoring.detect_personal_records(recent_workouts)
    if not personal_records and demo:
        personal_records = default_personal_records()

    # recovery_trend needs real, score-bearing session-log nights for its
    # 7-vs-7 comparison -- computed from recent_sleep (session logs only),
    # never the body-snapshot fallback below, so a user with no logged
    # nights still gets the honest {current:0, previous:0, delta:0} rather
    # than a trend derived from a single scoreless night.
    recovery_trend = scoring.recovery_trend(recent_sleep)
    has_logged_sleep = bool(recent_sleep)
    # recent_sleep is already demo fixture data here when demo mode is on
    # (set above), so this fallback is reached only when it's genuinely
    # empty -- a real, non-demo account with no logged nights.
    display_sleep = recent_sleep or _sleep_rows_from_body_snapshot(user_id)

    package = {
        "profile": profile,
        "readiness": current_readiness,
        "recentSleep": display_sleep[:7],
        "recentWorkouts": recent_workouts[:7],
        "todayPlan": today_plan,
        "trainingLoad": scoring.training_load_trend(recent_workouts),
        "recoveryTrend": recovery_trend,
        "personalRecords": personal_records,
        # True only for real logged nights -- lets a caller tell "nothing
        # anywhere" apart from "synced data exists, just not enough of it
        # with a score to trend yet" (see _sleep_rows_from_body_snapshot).
        "hasLoggedSleep": has_logged_sleep,
    }
    return _attach_predictions(package)


def _intensity_level(raw: Any) -> int:
    key = str(raw or "moderate").lower()
    return {"low": 1, "moderate": 2, "high": 3, "max": 4}.get(key, 2)


def _session_strain(workout: dict[str, Any]) -> float:
    duration = float(workout.get("duration") or 0)
    raw = duration * _intensity_level(workout.get("intensity")) / 17.0
    return max(0.0, min(21.0, raw))


def _attach_predictions(context: dict[str, Any]) -> dict[str, Any]:
    """Tomorrow-readiness + working-model on the same package coach routes already send.

    Uses numbers already in this context. Missing signals degrade confidence,
    never invent a clinical claim.
    """
    try:
        from aria_core import readiness_forecast as rf
        from aria_core import user_working_model as uwm
        from aria_core import hobby_path as hp
        from aria_core import tomorrow_budgets as tb
        from aria_core import hobby_fit as hf
    except Exception:
        return context

    overall = readiness_overall(context) or 0
    sleep_rows = list(context.get("recentSleep") or [])
    last_sleep = sleep_rows[0] if sleep_rows else {}
    sleep_minutes = 0
    hours = last_sleep.get("totalHours")
    if isinstance(hours, (int, float)) and not isinstance(hours, bool):
        sleep_minutes = int(round(hours * 60))
    workouts = list(context.get("recentWorkouts") or [])
    today = today_iso()
    today_strain = 0.0
    if workouts and str(workouts[0].get("date") or "") == today:
        today_strain = _session_strain(workouts[0])
    plan = context.get("todayPlan") or {}
    planned = 0.0
    if plan and str(plan.get("date") or today) == today:
        planned = _session_strain(plan)

    readiness_item = context.get("readiness") or {}
    hrv = readiness_item.get("hrv") or last_sleep.get("hrv")
    rhr = readiness_item.get("restingHR") or last_sleep.get("restingHR")
    stress = readiness_item.get("stressLevel")
    fc = rf.forecast(rf.ForecastInput(
        current_readiness=overall or 0,
        sleep_minutes=sleep_minutes,
        hrv_ms=int(hrv) if isinstance(hrv, (int, float)) and not isinstance(hrv, bool) else 0,
        resting_hr=int(rhr) if isinstance(rhr, (int, float)) and not isinstance(rhr, bool) else 0,
        today_strain=today_strain,
        planned_strain=planned,
        stress_level=int(stress) if isinstance(stress, (int, float)) and not isinstance(stress, bool) else 30,
    ))

    scores: list[int] = []
    weekday: list[float] = []
    weekend: list[float] = []
    for row in sleep_rows:
        score = row.get("score")
        if isinstance(score, (int, float)) and not isinstance(score, bool):
            scores.append(int(score))
            day = str(row.get("date") or "")
            try:
                from datetime import date as _date
                wd = _date.fromisoformat(day[:10]).weekday()
            except Exception:
                wd = None
            if wd is not None:
                (weekend if wd >= 5 else weekday).append(float(score))

    heavy_on_thin = 0
    for workout in workouts[:14]:
        if _intensity_level(workout.get("intensity")) >= 3:
            heavy_on_thin += 1
    recovery = context.get("recoveryTrend") or {}
    if not (isinstance(recovery.get("delta"), (int, float)) and recovery.get("delta") < 0):
        heavy_on_thin = 0

    working = uwm.snapshot(uwm.WorkingInput(
        sleep_scores=scores,
        readiness_today=overall or None,
        high_strain_low_recovery_days=heavy_on_thin,
        weekday_sleep_avg=(sum(weekday) / len(weekday)) if weekday else None,
        weekend_sleep_avg=(sum(weekend) / len(weekend)) if weekend else None,
    ), tomorrow_posture=fc.posture)
    hobbies, social, wake = _hobby_inputs(context)
    known = _known_people(context)
    hobby = hp.snapshot(
        social, hobbies, working,
        tomorrow_posture=fc.posture,
        wake_hour=wake,
        known_people=known,
    )
    budgets = tb.snapshot(fc.posture, working.stance, hobby.people_energy)
    signal = hf.mentality_signal(hobby.social_band, hobby.people_energy, working)
    explicit = context.get("hobbies")
    if isinstance(explicit, list) and any(isinstance(item, dict) for item in explicit):
        fit_hobbies = hf.normalize_hobbies(explicit)
    else:
        fit_hobbies = hf.hobbies_from_living(hobbies)
    context["tomorrowForecast"] = fc.to_dict()
    context["workingModel"] = working.to_dict()
    context["hobbyPath"] = hobby.to_dict()
    context["tomorrowBudgets"] = budgets.to_dict()
    # Stable field for coach routes. Speech and memory use ``hobbyFit.speak``.
    context["mentality_signal"] = signal
    context["hobbies"] = fit_hobbies
    return context


def readiness_overall(context: dict[str, Any]) -> int | None:
    """The readiness score if one was actually measured, else ``None``."""
    value = (context.get("readiness") or {}).get("overall")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return int(round(value))


def context_to_prompt_block(context: dict[str, Any]) -> str:
    """Serialize the context package into a compact JSON block for AI prompts."""
    has_data = bool(
        context.get("recentSleep")
        or context.get("recentWorkouts")
        or readiness_overall(context) is not None
    )
    compact = {
        # Stated outright rather than left for the model to infer from a wall of
        # nulls, so it can say "you have not logged anything yet" instead of
        # hedging around missing numbers.
        "hasLoggedData": has_data,
        "profile": context.get("profile"),
        "readiness": context.get("readiness"),
        "trainingLoad": context.get("trainingLoad"),
        "recoveryTrend": context.get("recoveryTrend"),
        "lastSleepScore": (context.get("recentSleep") or [{}])[0].get("score"),
        "lastWorkoutType": (context.get("recentWorkouts") or [{}])[0].get("type"),
        "todayPlanName": (context.get("todayPlan") or {}).get("name"),
    }
    forecast = context.get("tomorrowForecast") or {}
    if forecast.get("predictedScore") is not None:
        compact["tomorrowForecast"] = {
            "score": forecast.get("predictedScore"),
            "posture": forecast.get("posture"),
            "steeringLine": forecast.get("steeringLine"),
        }
    working = context.get("workingModel") or {}
    if working.get("tendency"):
        compact["workingModel"] = {
            "tendency": working.get("tendency"),
            "stance": working.get("stance"),
            "steeringLine": working.get("steeringLine"),
        }
    hobby = context.get("hobbyPath") or {}
    if hobby.get("path"):
        compact["hobbyPath"] = {
            "path": hobby.get("path"),
            "headline": hobby.get("headline"),
            "coachingLine": hobby.get("coachingLine"),
            "peopleEnergy": hobby.get("peopleEnergy"),
            "freeDayWindow": hobby.get("freeDayWindow"),
            "windowLine": hobby.get("windowLine"),
        }
    budgets = context.get("tomorrowBudgets") or {}
    if budgets.get("constraint"):
        compact["tomorrowBudgets"] = {
            "constraint": budgets.get("constraint"),
            "headline": budgets.get("headline"),
            "coachingLine": budgets.get("coachingLine"),
        }
    signal = context.get("mentality_signal")
    if signal:
        try:
            from aria_core import hobby_fit as hf
            phrase = hf.speak(str(signal))
        except Exception:
            phrase = ""
        if phrase:
            compact["hobbyFit"] = {
                "speak": phrase,
                "hobbies": [
                    {
                        "id": row.get("id"),
                        "label": row.get("label"),
                        "kind": row.get("kind"),
                        "interest": row.get("interest"),
                    }
                    for row in (context.get("hobbies") or [])[:6]
                    if isinstance(row, dict) and row.get("label")
                ],
            }
    return json.dumps(compact, separators=(",", ":"))


def _hobby_inputs(context: dict[str, Any]) -> tuple[list[str], float | None, float | None]:
    """Read living chips the client already sends. Never invent a persona."""
    tokens: list[str] = []
    for blob in (
        context.get("lifestyleTags"),
        context.get("livingTags"),
        (context.get("lifestyle") or {}).get("tags"),
        (context.get("lifestyle") or {}).get("recentPatterns"),
        (context.get("profile") or {}).get("livingTags"),
    ):
        if isinstance(blob, list):
            tokens.extend(str(t) for t in blob)
    hobbies: list[str] = []
    social: float | None = None
    for token in tokens:
        if token.startswith("living:hobby:"):
            hobbies.append(token.split(":")[-1])
        elif token.startswith("living:social:"):
            try:
                social = float(token.split(":")[-1])
            except ValueError:
                pass
    wake: float | None = None
    chrono = context.get("chronotype") or {}
    label = chrono.get("typicalWakeTime") or chrono.get("typical_wake_time")
    if isinstance(label, str) and ":" in label:
        try:
            hours, minutes = label.split(":", 1)
            wake = int(hours) + int(minutes[:2]) / 60.0
        except ValueError:
            wake = None
    return hobbies, social, wake


def _admit_person_name(name: str) -> bool:
    """First name only. Reject phones, emails, URLs, and partner/cycle prefixes."""
    text = str(name or "").strip()
    if not text or not (1 <= len(text) <= 24):
        return False
    if "@" in text or ":" in text or any(ch.isdigit() for ch in text):
        return False
    if "http" in text.lower():
        return False
    return _DENIED_PEOPLE_NAME.match(text) is None


def _admit_relation(relation: str) -> bool:
    text = str(relation or "").strip()
    if not text or not (1 <= len(text) <= 24):
        return False
    if "@" in text or any(ch.isdigit() for ch in text) or "http" in text.lower():
        return False
    return _DENIED_PEOPLE_NAME.match(text) is None


def admit_people_tag(token: str) -> dict[str, str] | None:
    """Admit ``people:FirstName:relation``. Count rows and PII never qualify."""
    parts = str(token or "").strip().split(":")
    if len(parts) < 3 or parts[0] != "people" or parts[1] == _PEOPLE_COUNT:
        return None
    name, relation = parts[1].strip(), parts[2].strip()
    if not _admit_person_name(name) or not _admit_relation(relation):
        return None
    return {"firstName": name, "relation": relation}


def people_tag_is_dirty(token: str) -> bool:
    """True for a people: tag that must never be written or spoken raw."""
    text = str(token or "").strip()
    if not text.startswith(_PEOPLE_PREFIX):
        return False
    parts = text.split(":")
    if len(parts) >= 2 and parts[1] == _PEOPLE_COUNT:
        return False
    return admit_people_tag(text) is None


def _people_tokens(context: dict[str, Any]) -> list[str]:
    tokens: list[str] = []
    lifestyle = context.get("lifestyle") if isinstance(context.get("lifestyle"), dict) else {}
    for blob in (
        context.get("lifestyleTags"),
        context.get("livingTags"),
        context.get("tags"),
        context.get("lifestyle_tags"),
        context.get("recentPatterns"),
        context.get("recent_patterns"),
        lifestyle.get("tags"),
        lifestyle.get("recentPatterns"),
        lifestyle.get("recent_patterns"),
        context.get("people"),
    ):
        if isinstance(blob, list):
            tokens.extend(str(t) for t in blob)
        elif isinstance(blob, str) and blob.startswith(_PEOPLE_PREFIX):
            tokens.append(blob)
    return tokens


def _known_people(context: dict[str, Any]) -> list[dict[str, str]]:
    """First name + label only. Contact ids, phones, and emails never qualify."""
    people: list[dict[str, str]] = []
    seen: set[str] = set()
    for token in _people_tokens(context):
        admitted = admit_people_tag(token)
        if admitted is None:
            continue
        key = f"{admitted['firstName'].lower()}:{admitted['relation'].lower()}"
        if key in seen:
            continue
        seen.add(key)
        people.append(admitted)
        if len(people) >= _PEOPLE_CAP:
            break
    return people


def people_payload_context(payload: dict[str, Any] | None) -> dict[str, Any]:
    """Flatten inbound chat / Dummy payload into the blob ``_known_people`` reads."""
    raw = payload if isinstance(payload, dict) else {}
    context = raw.get("context") if isinstance(raw.get("context"), dict) else {}
    lifestyle = {}
    if isinstance(context.get("lifestyle"), dict):
        lifestyle.update(context["lifestyle"])
    if isinstance(raw.get("lifestyle"), dict):
        lifestyle.update(raw["lifestyle"])
    return {
        "lifestyleTags": raw.get("lifestyleTags") or raw.get("lifestyle_tags") or context.get("lifestyle_tags"),
        "livingTags": raw.get("livingTags") or context.get("livingTags"),
        "tags": raw.get("tags") or context.get("tags"),
        "recentPatterns": raw.get("recentPatterns") or raw.get("recent_patterns"),
        "recent_patterns": raw.get("recent_patterns"),
        "lifestyle": lifestyle,
        "people": raw.get("people") or context.get("people"),
    }


def people_auto_file_allowed() -> bool:
    """Dummy / stub path only. Live Bedrock never auto-files people."""
    try:
        from services import provider_capabilities as caps
    except Exception:
        return True
    if caps.DEFAULT_PATH == "live_bedrock":
        return False
    return not caps.invoke_now_allowed()


def people_life_fact(person: dict[str, str]) -> str:
    """One durable fact. Never a raw people: tag or a dumped list."""
    name = str(person.get("firstName") or "").strip()
    relation = str(person.get("relation") or "friend").replace("_", " ").strip()
    if not name:
        return ""
    return f"{name} is a {relation}"


def file_people_tags(
    user_id: str,
    payload: dict[str, Any] | None,
    *,
    allow_ingest: bool,
    safety_lock: bool,
    engine: Any | None = None,
) -> list[dict[str, str]]:
    """Write named people into UserContext when Remember me is on.

    SAFETY_LOCK_BANDS and Remember-me off write nothing (off ≠ delete).
    Vault view/add/edit/delete stays on CoachContextEngine. Dummy/stub only.
    """
    if not people_auto_file_allowed() or not allow_ingest or safety_lock:
        return []
    uid = str(user_id or "").strip()
    if not uid:
        return []
    people = _known_people(people_payload_context(payload))
    if not people:
        return []
    if engine is None:
        from services.aria_context import CoachContextEngine

        engine = CoachContextEngine()
    context = engine.get_or_create_context(uid)
    patterns = list(context.recent_patterns or [])
    tags = [f"{_PEOPLE_PREFIX}{p['firstName']}:{p['relation']}" for p in people]
    changed = False
    for tag in tags:
        if tag not in patterns:
            patterns.append(tag)
            changed = True
    if changed:
        engine.update_context(uid, {"recent_patterns": patterns[:40]})
    try:
        from routes.aria import sanitize_user_memory_text
    except Exception:
        def sanitize_user_memory_text(text: str) -> str:
            return str(text or "").strip()

    for person in people:
        fact = sanitize_user_memory_text(people_life_fact(person))
        if fact:
            engine.record_life_fact(uid, fact)
    return people
