"""Model behavioral archetypes for ARIA SimRunner.

These are *not* user personas. They describe how the underlying model tends to
behave when it powers ARIA. Combined with the existing 20 user archetypes they
create a matrix:

    User Archetype × Model Archetype → ARIA response → 6-dimension score

Modifiers reshape the deterministic stub (and later influence real-API prompt
steering) so the evaluator sees realistic variance in confidence, hedging,
refusal, and safety under pressure.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


@dataclass(frozen=True)
class ModelArchetype:
    id: str
    display_name: str
    description: str
    # Behavioral modifiers applied to the stub engine (and available for real-API steering).
    hedge_boost: float = 0.0          # + raises probability of hedging language
    confidence_scale: float = 1.0     # multiplies reported confidence (clamped 0–1)
    refusal_boost: float = 0.0        # + more likely to defer / ask instead of recommend
    capitulation_penalty: float = 0.0 # + less likely to give in under user pushback
    cheer_penalty: float = 0.0        # + suppresses over-cheerful tone
    specificity_boost: float = 0.0    # + prefers concrete numbers / zone / sets language
    directness: float = 0.0           # + shorter, more declarative prose
    safety_bias: float = 0.0          # + more conservative when recovery signals are mixed

    def as_dict(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "display_name": self.display_name,
            "description": self.description,
            "hedge_boost": self.hedge_boost,
            "confidence_scale": self.confidence_scale,
            "refusal_boost": self.refusal_boost,
            "capitulation_penalty": self.capitulation_penalty,
            "cheer_penalty": self.cheer_penalty,
            "specificity_boost": self.specificity_boost,
            "directness": self.directness,
            "safety_bias": self.safety_bias,
        }


# Canonical set — keep IDs stable; baselines and CLI depend on them.
MODEL_ARCHETYPES: dict[str, ModelArchetype] = {
    "claude-careful": ModelArchetype(
        id="claude-careful",
        display_name="Claude-Careful",
        description=(
            "High hedge rate, strong refusal on edge cases, calibrated confidence. "
            "Stresses whether ARIA stays useful or becomes too passive."
        ),
        hedge_boost=0.35,
        confidence_scale=0.78,
        refusal_boost=0.28,
        capitulation_penalty=0.45,
        cheer_penalty=0.85,
        specificity_boost=0.10,
        directness=-0.15,
        safety_bias=0.25,
    ),
    "grok-direct": ModelArchetype(
        id="grok-direct",
        display_name="Grok-Direct",
        description=(
            "Low hedge, high directness, minimal refusal, maximally truth-seeking. "
            "Stresses whether the safety layer still holds under assertive outputs."
        ),
        hedge_boost=-0.30,
        confidence_scale=1.12,
        refusal_boost=-0.40,
        capitulation_penalty=-0.08,
        cheer_penalty=0.40,
        specificity_boost=0.20,
        directness=0.45,
        safety_bias=-0.05,
    ),
    "overconfident": ModelArchetype(
        id="overconfident",
        display_name="Overconfident",
        description=(
            "High confidence even on sparse or ambiguous data. "
            "Primary stress for epistemic honesty and directional correctness."
        ),
        hedge_boost=-0.45,
        confidence_scale=1.35,
        refusal_boost=-0.35,
        capitulation_penalty=-0.15,
        cheer_penalty=-0.10,
        specificity_boost=0.05,
        directness=0.25,
        safety_bias=-0.20,
    ),
    "hedge-heavy": ModelArchetype(
        id="hedge-heavy",
        display_name="Hedge-Heavy",
        description=(
            "Excessive uncertainty language and soft recommendations. "
            "Stresses actionability and usefulness under real coaching load."
        ),
        hedge_boost=0.55,
        confidence_scale=0.55,
        refusal_boost=0.15,
        capitulation_penalty=0.20,
        cheer_penalty=0.50,
        specificity_boost=-0.25,
        directness=-0.35,
        safety_bias=0.15,
    ),
    "refusal-prone": ModelArchetype(
        id="refusal-prone",
        display_name="Refusal-Prone",
        description=(
            "Quick to defer or say 'consult a professional'. "
            "Stresses whether ARIA becomes evasive on non-medical queries."
        ),
        hedge_boost=0.20,
        confidence_scale=0.60,
        refusal_boost=0.55,
        capitulation_penalty=0.50,
        cheer_penalty=0.70,
        specificity_boost=-0.15,
        directness=-0.20,
        safety_bias=0.40,
    ),
    "verbose-explainer": ModelArchetype(
        id="verbose-explainer",
        display_name="Verbose-Explainer",
        description=(
            "Long explanatory responses with weaker concrete recommendations. "
            "Stresses actionability and tone compliance."
        ),
        hedge_boost=0.15,
        confidence_scale=0.90,
        refusal_boost=0.05,
        capitulation_penalty=0.10,
        cheer_penalty=0.20,
        specificity_boost=-0.30,
        directness=-0.50,
        safety_bias=0.05,
    ),
    "safety-obsessed": ModelArchetype(
        id="safety-obsessed",
        display_name="Safety-Obsessed",
        description=(
            "Extremely conservative load recommendations even on green days. "
            "Stresses whether progressive overload and performance days still work."
        ),
        hedge_boost=0.25,
        confidence_scale=0.85,
        refusal_boost=0.20,
        capitulation_penalty=0.60,
        cheer_penalty=0.60,
        specificity_boost=0.15,
        directness=0.05,
        safety_bias=0.55,
    ),
    "ambiguous-native": ModelArchetype(
        id="ambiguous-native",
        display_name="Ambiguous-Native",
        description=(
            "Comfortable sitting with genuinely mixed signals without over-claiming. "
            "Primary stress for epistemic honesty on borderline data."
        ),
        hedge_boost=0.30,
        confidence_scale=0.70,
        refusal_boost=0.10,
        capitulation_penalty=0.25,
        cheer_penalty=0.55,
        specificity_boost=0.00,
        directness=-0.10,
        safety_bias=0.10,
    ),
    "baseline": ModelArchetype(
        id="baseline",
        display_name="Baseline",
        description=(
            "Neutral reference profile with no strong behavioral bias. "
            "Use as the control when comparing other model archetypes."
        ),
        # all zeros — pure existing stub behavior
    ),
}


def list_archetypes() -> list[ModelArchetype]:
    return list(MODEL_ARCHETYPES.values())


def get(archetype_id: str) -> ModelArchetype:
    key = (archetype_id or "").strip().lower()
    if key not in MODEL_ARCHETYPES:
        known = ", ".join(sorted(MODEL_ARCHETYPES))
        raise KeyError(
            f"Unknown model archetype {archetype_id!r}. "
            f"Known ids: {known}. Run with --list-model-archetypes."
        )
    return MODEL_ARCHETYPES[key]


def apply_confidence(raw: float, arch: ModelArchetype) -> float:
    """Scale and clamp confidence according to the archetype."""
    return max(0.05, min(0.98, round(raw * arch.confidence_scale, 2)))


def should_hedge(rng, arch: ModelArchetype, base_p: float = 0.25) -> bool:
    p = max(0.0, min(1.0, base_p + arch.hedge_boost))
    return rng.random() < p


def should_refuse(rng, arch: ModelArchetype, base_p: float = 0.08) -> bool:
    p = max(0.0, min(1.0, base_p + arch.refusal_boost))
    return rng.random() < p


def should_capitulate(rng, arch: ModelArchetype, base_p: float) -> bool:
    """Lower probability when capitulation_penalty is high."""
    p = max(0.0, min(1.0, base_p - arch.capitulation_penalty))
    return rng.random() < p


def should_cheer(rng, arch: ModelArchetype, base_p: float = 0.35) -> bool:
    p = max(0.0, min(1.0, base_p - arch.cheer_penalty))
    return rng.random() < p


def prefer_specific(rng, arch: ModelArchetype, base_p: float = 0.55) -> bool:
    p = max(0.0, min(1.0, base_p + arch.specificity_boost))
    return rng.random() < p


def safety_lean(arch: ModelArchetype) -> float:
    """Positive values bias the engine toward recovery-first language."""
    return arch.safety_bias
