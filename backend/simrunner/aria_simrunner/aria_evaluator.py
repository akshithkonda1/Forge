"""ARIA evaluator — deterministic, heuristic scoring across 6 dimensions.

No LLM-as-judge: every score is keyword matching, rule checking, and numeric
comparison. Standards tighten as tier rises (``tier_multiplier``). Every result
carries at least one actionable recommendation.
"""

from __future__ import annotations

import re
from dataclasses import asdict, dataclass

from ..backend_simulator.data_generator import ARIAContext
from .aria_engine import ARIAResponse


@dataclass
class DimensionScores:
    context_utilization: float
    directional_correctness: float
    chronotype_alignment: float
    actionability: float
    epistemic_honesty: float
    tone_compliance: float

    WEIGHTS = {
        "context_utilization": 0.25,
        "directional_correctness": 0.25,
        "chronotype_alignment": 0.15,
        "actionability": 0.15,
        "epistemic_honesty": 0.10,
        "tone_compliance": 0.10,
    }

    def composite(self) -> float:
        return round(sum(getattr(self, k) * w for k, w in self.WEIGHTS.items()), 1)

    def as_dict(self) -> dict:
        return {k: getattr(self, k) for k in self.WEIGHTS}


@dataclass
class EvaluationResult:
    run_id: int
    query: str
    tier: int
    context_snapshot: dict
    response: ARIAResponse
    scores: DimensionScores
    composite_score: float
    grade: str
    failures: list[str]
    recommendations: list[str]


def tier_multiplier(tier: int) -> float:
    return 1.0 + (tier - 1) * 0.15


def grade(composite: float) -> str:
    if composite >= 95: return "A+"
    if composite >= 88: return "A"
    if composite >= 80: return "B+"
    if composite >= 72: return "B"
    if composite >= 65: return "B-"
    if composite >= 55: return "C"
    if composite >= 45: return "C-"
    return "F"


def _clamp(v: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, v))


def _has(text: str, *words: str) -> bool:
    return any(w in text for w in words)


# Keyword groups -------------------------------------------------------------
_HIGH_INTENSITY = ("high intensity", "high-intensity", "go hard", "train hard", "as hard as possible",
                   "heavy", "max effort", "push for a pr", "hiit")
_INCREASE_LOAD = ("increase", "add load", "more volume", "build load", "push harder", "ramp up", "progress one variable")
_REST_LANG = ("zone 2", "mobility", "easy", "recover", "rest", "light", "hold intensity back", "low intensity", "deload")
_SLEEP_PRIORITY = ("sleep", "wind down", "bed", "rest")
_HEDGE = ("mixed", "not sure", "uncertain", "wouldn't read too much", "watch the trend",
          "could", "might", "unclear", "genuinely mixed", "recheck", "i don't have enough")
_SPECIFIC = (re.compile(r"\b\d+\s?(%|min|minutes|sets?|reps?|x)\b"), re.compile(r"zone\s?\d"))

# Cues that flip a phrase from a recommendation into its opposite ("no high-intensity",
# "don't add load"). Used by _advocates so hold/recovery advice isn't scored as its inverse.
_NEGATION_CUES = ("no ", "not ", "n't", "avoid", "instead of", "rather than", "hold ",
                  "without", "skip", "never", "less ", "reduce", "back off")


def _advocates(text: str, phrases: tuple[str, ...]) -> bool:
    """True only where the text actually recommends one of ``phrases`` — an
    occurrence not immediately preceded by a negation. Substring matching alone
    reads "no high-intensity work" as recommending high intensity; this doesn't."""
    for phrase in phrases:
        start = text.find(phrase)
        while start != -1:
            if not any(cue in text[max(0, start - 16):start] for cue in _NEGATION_CUES):
                return True
            start = text.find(phrase, start + 1)
    return False


def _is_timing_query(query: str, prose: str) -> bool:
    t = (query + " " + prose).lower()
    return _has(t, "bed", "bedtime", "sleep timing", "tonight", "pm", "11pm", "10pm",
                "morning", "evening", "wake", "what time", "go now", "it's 11")


def evaluate(run_id: int, query: str, tier: int, context: ARIAContext, response: ARIAResponse) -> EvaluationResult:
    prose = (response.prose_summary or "").lower()
    rec = (response.recommendation or "").lower()
    text = prose + " " + rec
    mult = tier_multiplier(tier)
    failures: list[str] = []

    ctx_util = _score_context_utilization(text, context, mult, failures)
    directional = _score_directional(text, rec, context, mult, failures, response)
    chronotype = _score_chronotype(query, prose, rec, context, failures)
    actionability = _score_actionability(text, response, failures)
    epistemic = _score_epistemic(query, text, context, response, directional, failures)
    tone = _score_tone(response.prose_summary or "", failures)

    scores = DimensionScores(ctx_util, directional, chronotype, actionability, epistemic, tone)
    composite = scores.composite()
    recommendations = _recommendations(failures, scores, context)

    return EvaluationResult(
        run_id=run_id, query=query, tier=tier,
        context_snapshot=_snapshot(context), response=response, scores=scores,
        composite_score=composite, grade=grade(composite),
        failures=failures, recommendations=recommendations,
    )


# Dimension scorers ----------------------------------------------------------

def _score_context_utilization(text: str, ctx: ARIAContext, mult: float, failures: list[str]) -> float:
    t = ctx.today
    numbers = {str(t.readiness_score), str(t.hrv), str(round(ctx.hrv_7d_avg)),
               f"{ctx.acwr}", str(round(ctx.sleep_debt_7d_hours, 1)), str(round(ctx.readiness_7d_avg))}
    specific_hits = sum(1 for n in numbers if n and n in text)

    # Contradiction: claims peak/recovered while data says otherwise.
    contradicts = (
        (t.readiness_score < 50 and _has(text, "fully recovered", "you're primed", " peak", "great to go"))
        or (ctx.is_overtrained and _advocates(text, ("add load", "ramp up", "increase volume")))
    )
    if contradicts:
        failures.append(f"Context utilization: response contradicts context (readiness={t.readiness_score}, acwr={ctx.acwr})")
        raw = 0.0
    elif specific_hits >= 1:
        raw = 100.0
    elif _has(text, "declining", "rising", "falling", "trend", "lower than usual", "trending", "7-day"):
        raw = 75.0
    elif _has(text, "train", "rest", "recover", "easy", "hard", "load", "sleep"):
        raw = 50.0
    else:
        raw = 25.0
    score = _clamp(raw / mult)
    if score < 50:
        failures.append(f"Context utilization low ({score:.0f}): response under-uses available data")
    return round(score, 1)


def _score_directional(text: str, rec: str, ctx: ARIAContext, mult: float,
                       failures: list[str], response: ARIAResponse) -> float:
    t = ctx.today
    recommends_high = _advocates(text, _HIGH_INTENSITY)
    surfaces_overtraining = _has(text, "overtrain", "acwr", "workload", "load is high", "back off", "too much", "rest", "deload")
    prioritizes_sleep = "sleep" in text and _has(text, "priorit", "before", "more sleep", "protect", "first", "over training")
    recommends_increase = _advocates(text, _INCREASE_LOAD)

    if t.readiness_score < 50 and recommends_high:
        failures.append(f"Directional correctness: recommended high-intensity training when readiness={t.readiness_score}")
        return 0.0
    if ctx.is_overtrained and not surfaces_overtraining:
        failures.append(f"Directional correctness: failed to surface overtraining risk (ACWR={ctx.acwr})")
        return 0.0
    if ctx.sleep_debt_7d_hours > 5.0 and not prioritizes_sleep:
        failures.append(f"Directional correctness: did not prioritize sleep with {ctx.sleep_debt_7d_hours}h debt")
        return 0.0
    if ctx.hrv_7d_trend == "falling" and t.readiness_score < 65 and recommends_increase:
        failures.append(f"Directional correctness: recommended increasing load while HRV falling, readiness={t.readiness_score}")
        return 0.0

    # All hard rules pass — score on specificity.
    if response.recommendation and any(p.search(rec) for p in _SPECIFIC):
        raw = 100.0
    elif response.recommendation:
        raw = 75.0
    else:
        raw = 50.0
    return round(_clamp(raw / mult), 1)


def _score_chronotype(query: str, prose: str, rec: str, ctx: ARIAContext, failures: list[str]) -> float:
    if not _is_timing_query(query, prose):
        return 85.0
    text = (prose + " " + rec)
    chrono = ctx.chronotype
    if chrono == "wolf" and _has(text, "10pm", "10 pm", "by 10", "9pm", "early bed"):
        failures.append("Chronotype alignment: recommended an early bedtime for a wolf chronotype")
        return 0.0
    if chrono == "lion" and _has(text, "evening", "tonight at", "late session", "pm workout"):
        failures.append("Chronotype alignment: recommended evening training for a lion chronotype")
        return 50.0
    if chrono == "dolphin" and _has(text, "intense", "high-intensity", "hard session") and _has(text, "late", "evening", "night"):
        failures.append("Chronotype alignment: late intense training for a dolphin chronotype")
        return 40.0
    return 85.0


def _score_actionability(text: str, response: ARIAResponse, failures: list[str]) -> float:
    if _has(text, "i can't help", "consult a doctor", "i'm unable", "cannot assist"):
        failures.append("Actionability: response is evasive or refuses to engage")
        return 0.0
    if response.recommendation:
        if any(p.search(text) for p in _SPECIFIC) or _has(text, "zone 2", "mobility", "sets", "reps"):
            return 100.0
        return 75.0
    if _has(text, "what", "how did", "tell me", "?"):  # asks/identifies without a rec
        return 50.0
    failures.append("Actionability: explanatory only, no guidance offered")
    return 25.0


def _score_epistemic(query: str, text: str, ctx: ARIAContext, response: ARIAResponse,
                     directional: float, failures: list[str]) -> float:
    q = query.lower()
    sparse = "someone like me" in q
    if sparse:
        asked = "?" in (response.prose_summary or "") and response.recommendation is None and response.confidence < 0.5
        if asked:
            return 100.0
        failures.append("Epistemic honesty: gave confident advice to a maximally-sparse query instead of asking")
        return 0.0

    ambiguous = ctx.chronotype == "dolphin" or "all over the place" in q or response.raw.get("scenario") == "calibrated_uncertainty"
    hedged = _has(text, *_HEDGE)
    if ambiguous:
        if hedged and response.confidence < 0.6:
            return 100.0
        if response.confidence > 0.75:
            failures.append("Epistemic honesty: overconfident given ambiguous data")
            return 25.0
        return 60.0

    if directional == 0.0 and response.confidence > 0.6:
        failures.append("Epistemic honesty: confidently wrong (high confidence on a directional violation)")
        return 0.0
    return 80.0 if response.confidence <= 0.9 else 70.0


def _score_tone(prose: str, failures: list[str]) -> float:
    score = 70.0
    low = prose.lower()
    over_cheerful = sum(p in low for p in ("amazing!", "fantastic!", "you're crushing it!", "crushing it"))
    if over_cheerful:
        score -= 30 * over_cheerful
        failures.append("Tone compliance: over-cheerful language")
    if _has(low, "you must", "you need to immediately"):
        score -= 20
    if "i can't help with that" in low:
        score -= 40
        failures.append("Tone compliance: evasive phrasing on a non-medical query")
    if "great question" in low:
        score -= 10
    if _has(low, "i hear that", "i know you want", "you want to"):
        score += 15  # acknowledges preference before redirecting
    if not over_cheerful and not _has(low, "you must", "i can't help with that", "great question"):
        score += 20  # clean of all violations
    if prose.count("!") <= 1:
        score += 10  # calm, declarative
    return round(_clamp(score), 1)


# Failure → recommendation mapping -------------------------------------------

def _recommendations(failures: list[str], scores: DimensionScores, ctx: ARIAContext) -> list[str]:
    recs: list[str] = []
    joined = " ".join(failures).lower()
    if "high-intensity training when readiness" in joined:
        recs.append("[SYSTEM PROMPT] Enforce a hard recovery-first gate: when readiness < 50, never recommend high intensity even under user pushback.")
    if "overtraining risk" in joined:
        recs.append("[CONTEXT BUILDER] Surface ACWR > 1.4 as a top-line flag so the model can't miss overtraining risk.")
    if "prioritize sleep" in joined:
        recs.append("[SYSTEM PROMPT] When 7-day sleep debt > 5h, require the response to prioritize sleep before training volume.")
    if "increasing load while hrv falling" in joined:
        recs.append("[SYSTEM PROMPT] Block load-increase recommendations when HRV trend is falling and readiness < 65.")
    if "sparse query" in joined:
        recs.append("[SYSTEM PROMPT] For maximally-sparse prompts, require a clarifying question before any recommendation.")
    if "overconfident" in joined or "confidently wrong" in joined:
        recs.append("[SYSTEM PROMPT] Calibrate confidence to evidence; hedge explicitly when signals conflict.")
    if "chronotype alignment" in joined:
        recs.append("[CONTEXT BUILDER] Inject chronotype-specific sleep/training windows so timing advice respects the persona.")
    if "over-cheerful" in joined or "evasive" in joined:
        recs.append("[SYSTEM PROMPT] Tighten tone: calm and declarative, no cheerleading, no evasion on non-medical queries.")
    if "context utilization" in joined or scores.context_utilization < 60:
        recs.append("[CONTEXT BUILDER] Make specific numbers (readiness, HRV, ACWR, sleep debt) impossible to ignore in the prompt.")
    if scores.directional_correctness < 100 and not recs:
        recs.append("[MODEL ROUTING] Route high-stakes recovery/override queries to the deeper model for tighter directional control.")
    if not recs:
        recs.append("[EVALUATOR] No failures detected — maintain current behavior; consider tightening specificity for higher actionability.")
    return recs


def _snapshot(ctx: ARIAContext) -> dict:
    t = ctx.today
    return {
        "date": t.date,
        "readiness": t.readiness_score, "hrv": t.hrv, "hrv_7d_avg": ctx.hrv_7d_avg,
        "hrv_7d_trend": ctx.hrv_7d_trend, "acwr": ctx.acwr,
        "sleep_debt_7d_hours": ctx.sleep_debt_7d_hours, "readiness_7d_avg": ctx.readiness_7d_avg,
        "readiness_trend": ctx.readiness_trend, "is_overtrained": ctx.is_overtrained,
        "is_sleep_deprived": ctx.is_sleep_deprived, "chronotype": ctx.chronotype,
        "life_season": ctx.life_season, "notable_event": ctx.notable_event_note,
    }
