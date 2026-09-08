"""ARIA's self-training critic — lives with the live learner, not the dummy.

The dummy orchestrator must never import this module (not even at function
level). ``contextual_learner`` calls it from ``observe_turn``,
``commit_action``, and ``reinforce``. Deleting the dummy leaves this file,
the learner, and Dynamo ``ARIA#PERSONA`` in place.

What it does:

  * Records a predicted reward at commit (current Q, stance probability,
    which sources were hot).
  * Self-labels conversation so ARIA can train without waiting for a
    workout ("that helped" / "that didn't help").
  * Judges predicted vs actual: right, wrong, or mixed.
  * Meta-optimizes ``td_alpha`` with a deterministic RPROP-style step
    (same-sign TD error → learn faster; sign flip → shrink).
  * Credits hot sources (event / ingest / conversation / body).
  * Heats softmax temperature when calibration is low so an overconfident
    policy flattens. Still no ε-greedy randomness.

Stdlib only. Deterministic. Lambda hot path.
"""

from __future__ import annotations

from typing import Any, Iterable

SOURCE_KEYS = ("event", "ingest", "conversation", "body")
SOURCE_W_MIN = 0.4
SOURCE_W_MAX = 2.0
ALPHA_MIN = 0.08
ALPHA_MAX = 0.55
ETA_PLUS = 1.18
ETA_MINUS = 0.82
CALIB_EMA = 0.15
MIXED_ABS = 0.08
WEAK_PRED_ABS = 0.05
CONVO_REWARD = 0.65
TD_SIGN_FLOOR = 0.02

RIGHT_CUES = (
    "that helped",
    "that worked",
    "you're right",
    "youre right",
    "good call",
    "nailed it",
    "exactly",
    "perfect",
    "that's it",
    "thats it",
    "much better",
)
WRONG_CUES = (
    "didn't help",
    "didnt help",
    "didn't work",
    "didnt work",
    "too much",
    "too hard",
    "too easy",
    "you're wrong",
    "youre wrong",
    "not what i",
    "still exhausted",
    "still tired",
    "i skipped",
    "too long",
    "wrong call",
)


def default_source_w() -> dict[str, float]:
    return {key: 1.0 for key in SOURCE_KEYS}


def _clip(value: float, lo: float, hi: float) -> float:
    return lo if value < lo else hi if value > hi else value


def conversation_reward(message: str) -> float | None:
    """Self-label from what they just said. None = not a verdict."""
    text = (message or "").strip().lower()
    if not text:
        return None
    n_right = sum(1 for cue in RIGHT_CUES if cue in text)
    n_wrong = sum(1 for cue in WRONG_CUES if cue in text)
    if n_right == 0 and n_wrong == 0:
        return None
    if n_right == n_wrong:
        return None
    return CONVO_REWARD if n_right > n_wrong else -CONVO_REWARD


def judge(predicted: float, actual: float) -> str:
    """Was the last coaching call right, wrong, or mixed?"""
    pred = float(predicted)
    act = float(actual)
    if abs(act) < MIXED_ABS:
        return "mixed"
    if abs(pred) < WEAK_PRED_ABS:
        if act > 0:
            return "right"
        if act < -MIXED_ABS:
            return "wrong"
        return "mixed"
    if (pred > 0) == (act > 0):
        return "right"
    return "wrong"


def td_sign(delta: float) -> int:
    if delta > TD_SIGN_FLOOR:
        return 1
    if delta < -TD_SIGN_FLOOR:
        return -1
    return 0


def step_alpha(state: Any, delta: float, default_alpha: float) -> float:
    """RPROP-style: first nonzero sign is recorded; same sign grows alpha."""
    try:
        alpha = float(getattr(state, "td_alpha", default_alpha) or default_alpha)
    except (TypeError, ValueError):
        alpha = float(default_alpha)
    sign = td_sign(delta)
    if sign == 0:
        state.td_alpha = round(_clip(alpha, ALPHA_MIN, ALPHA_MAX), 6)
        return state.td_alpha
    last = int(getattr(state, "last_td_sign", 0) or 0)
    if last == 0:
        state.last_td_sign = sign
        state.td_alpha = round(_clip(alpha, ALPHA_MIN, ALPHA_MAX), 6)
        return state.td_alpha
    if sign == last:
        alpha *= ETA_PLUS
    else:
        alpha *= ETA_MINUS
    state.last_td_sign = sign
    state.td_alpha = round(_clip(alpha, ALPHA_MIN, ALPHA_MAX), 6)
    return state.td_alpha


def credit_sources(state: Any, verdict: str, sources: Iterable[str] | None) -> None:
    sw = getattr(state, "source_w", None)
    if not isinstance(sw, dict):
        return
    hot = [s for s in (sources or ()) if s in SOURCE_KEYS]
    if not hot:
        return
    if verdict == "right":
        for key in hot:
            try:
                current = float(sw.get(key, 1.0))
            except (TypeError, ValueError):
                current = 1.0
            sw[key] = round(_clip(current + 0.08, SOURCE_W_MIN, SOURCE_W_MAX), 4)
    elif verdict == "wrong":
        for key in hot:
            try:
                current = float(sw.get(key, 1.0))
            except (TypeError, ValueError):
                current = 1.0
            sw[key] = round(_clip(current * 0.92, SOURCE_W_MIN, SOURCE_W_MAX), 4)


def heat_from_calibration(calibration: float) -> float:
    """>1 when miscalibrated — flattens softmax. Never random."""
    cal = _clip(float(calibration), 0.0, 1.0)
    return 1.0 + 0.55 * (1.0 - cal)


def record_prediction(
    state: Any,
    predicted: float,
    stance_p: float,
    sources: Iterable[str] | None,
) -> None:
    state.last_predicted_reward = float(predicted)
    try:
        state.last_stance_p = float(stance_p or 0.0)
    except (TypeError, ValueError):
        state.last_stance_p = 0.0
    state.last_sources = tuple(
        str(s) for s in (sources or ()) if s in SOURCE_KEYS
    )


def apply_judgment(
    state: Any,
    actual_reward: float,
    td_delta: float,
    default_alpha: float,
) -> str:
    """Update right/wrong counts, calibration, alpha, and source credit."""
    predicted = 0.0
    try:
        predicted = float(getattr(state, "last_predicted_reward", 0.0) or 0.0)
    except (TypeError, ValueError):
        predicted = 0.0
    verdict = judge(predicted, float(actual_reward))
    state.last_verdict = verdict
    state.n_self_train = int(getattr(state, "n_self_train", 0) or 0) + 1
    if verdict == "right":
        state.n_right = int(getattr(state, "n_right", 0) or 0) + 1
        hit = 1.0
    elif verdict == "wrong":
        state.n_wrong = int(getattr(state, "n_wrong", 0) or 0) + 1
        hit = 0.0
    else:
        hit = 0.5
    try:
        old = float(getattr(state, "calibration", 0.5) or 0.5)
    except (TypeError, ValueError):
        old = 0.5
    state.calibration = round((1.0 - CALIB_EMA) * old + CALIB_EMA * hit, 4)
    step_alpha(state, td_delta, default_alpha)
    credit_sources(state, verdict, getattr(state, "last_sources", ()) or ())
    return verdict
