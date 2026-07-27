"""Model behavioral archetypes for ARIA SimRunner.

Two layers, both first-class:

1. **Named behavioral styles** (claude-careful, grok-direct, overconfident, …)
   Stress specific failure modes of the underlying model tendency.

2. **Every text model in the Bedrock catalog**
   Each concrete Bedrock model_id is auto-registered as a model archetype with
   a provider/family-derived behavioral profile. Selecting one pins that model
   for real-API runs and applies its behavioral signature to the stub.

Matrix evaluated by SimRunner:

    User Archetype × Model Archetype (style OR Bedrock model) → ARIA scores

This covers the full Bedrock library (~40+ text models), not just nine styles.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from typing import Any

from ..backend_simulator import bedrock_catalog


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
    # Optional concrete Bedrock model this archetype represents / pins.
    bedrock_model_id: str | None = None
    provider: str | None = None
    family: str | None = None
    model_class: str | None = None    # frontier | reasoning | balanced | fast | …
    is_style: bool = False            # True for the 9 named behavioral styles

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
            "bedrock_model_id": self.bedrock_model_id,
            "provider": self.provider,
            "family": self.family,
            "model_class": self.model_class,
            "is_style": self.is_style,
        }


# ---------------------------------------------------------------------------
# Named behavioral styles (explicit stress tests)
# ---------------------------------------------------------------------------

_STYLE_ARCHETYPES: dict[str, ModelArchetype] = {
    "claude-careful": ModelArchetype(
        id="claude-careful",
        display_name="Claude-Careful",
        description=(
            "High hedge rate, strong refusal on edge cases, calibrated confidence. "
            "Stresses whether ARIA stays useful or becomes too passive."
        ),
        hedge_boost=0.35, confidence_scale=0.78, refusal_boost=0.28,
        capitulation_penalty=0.45, cheer_penalty=0.85, specificity_boost=0.10,
        directness=-0.15, safety_bias=0.25, is_style=True,
    ),
    "grok-direct": ModelArchetype(
        id="grok-direct",
        display_name="Grok-Direct",
        description=(
            "Low hedge, high directness, minimal refusal, maximally truth-seeking. "
            "Stresses whether the safety layer still holds under assertive outputs."
        ),
        hedge_boost=-0.30, confidence_scale=1.12, refusal_boost=-0.40,
        capitulation_penalty=-0.08, cheer_penalty=0.40, specificity_boost=0.20,
        directness=0.45, safety_bias=-0.05, is_style=True,
    ),
    "overconfident": ModelArchetype(
        id="overconfident",
        display_name="Overconfident",
        description=(
            "High confidence even on sparse or ambiguous data. "
            "Primary stress for epistemic honesty and directional correctness."
        ),
        hedge_boost=-0.45, confidence_scale=1.35, refusal_boost=-0.35,
        capitulation_penalty=-0.15, cheer_penalty=-0.10, specificity_boost=0.05,
        directness=0.25, safety_bias=-0.20, is_style=True,
    ),
    "hedge-heavy": ModelArchetype(
        id="hedge-heavy",
        display_name="Hedge-Heavy",
        description=(
            "Excessive uncertainty language and soft recommendations. "
            "Stresses actionability and usefulness under real coaching load."
        ),
        hedge_boost=0.55, confidence_scale=0.55, refusal_boost=0.15,
        capitulation_penalty=0.20, cheer_penalty=0.50, specificity_boost=-0.25,
        directness=-0.35, safety_bias=0.15, is_style=True,
    ),
    "refusal-prone": ModelArchetype(
        id="refusal-prone",
        display_name="Refusal-Prone",
        description=(
            "Quick to defer or say 'consult a professional'. "
            "Stresses whether ARIA becomes evasive on non-medical queries."
        ),
        hedge_boost=0.20, confidence_scale=0.60, refusal_boost=0.55,
        capitulation_penalty=0.50, cheer_penalty=0.70, specificity_boost=-0.15,
        directness=-0.20, safety_bias=0.40, is_style=True,
    ),
    "verbose-explainer": ModelArchetype(
        id="verbose-explainer",
        display_name="Verbose-Explainer",
        description=(
            "Long explanatory responses with weaker concrete recommendations. "
            "Stresses actionability and tone compliance."
        ),
        hedge_boost=0.15, confidence_scale=0.90, refusal_boost=0.05,
        capitulation_penalty=0.10, cheer_penalty=0.20, specificity_boost=-0.30,
        directness=-0.50, safety_bias=0.05, is_style=True,
    ),
    "safety-obsessed": ModelArchetype(
        id="safety-obsessed",
        display_name="Safety-Obsessed",
        description=(
            "Extremely conservative load recommendations even on green days. "
            "Stresses whether progressive overload and performance days still work."
        ),
        hedge_boost=0.25, confidence_scale=0.85, refusal_boost=0.20,
        capitulation_penalty=0.60, cheer_penalty=0.60, specificity_boost=0.15,
        directness=0.05, safety_bias=0.55, is_style=True,
    ),
    "ambiguous-native": ModelArchetype(
        id="ambiguous-native",
        display_name="Ambiguous-Native",
        description=(
            "Comfortable sitting with genuinely mixed signals without over-claiming. "
            "Primary stress for epistemic honesty on borderline data."
        ),
        hedge_boost=0.30, confidence_scale=0.70, refusal_boost=0.10,
        capitulation_penalty=0.25, cheer_penalty=0.55, specificity_boost=0.00,
        directness=-0.10, safety_bias=0.10, is_style=True,
    ),
    "baseline": ModelArchetype(
        id="baseline",
        display_name="Baseline",
        description=(
            "Neutral reference profile with no strong behavioral bias. "
            "Use as the control when comparing other model archetypes."
        ),
        is_style=True,
    ),
}


# ---------------------------------------------------------------------------
# Provider / family / class → default behavioral signature
# ---------------------------------------------------------------------------

# Base signature keyed by provider (overridden by family/class where useful).
_PROVIDER_DEFAULTS: dict[str, dict[str, float]] = {
    "anthropic": {
        "hedge_boost": 0.28, "confidence_scale": 0.82, "refusal_boost": 0.22,
        "capitulation_penalty": 0.40, "cheer_penalty": 0.70, "specificity_boost": 0.12,
        "directness": -0.10, "safety_bias": 0.22,
    },
    "amazon": {
        "hedge_boost": 0.10, "confidence_scale": 0.95, "refusal_boost": 0.08,
        "capitulation_penalty": 0.15, "cheer_penalty": 0.25, "specificity_boost": 0.05,
        "directness": 0.05, "safety_bias": 0.08,
    },
    "meta": {
        "hedge_boost": -0.10, "confidence_scale": 1.05, "refusal_boost": -0.12,
        "capitulation_penalty": 0.05, "cheer_penalty": 0.15, "specificity_boost": 0.08,
        "directness": 0.22, "safety_bias": 0.00,
    },
    "mistral": {
        "hedge_boost": -0.05, "confidence_scale": 1.02, "refusal_boost": -0.08,
        "capitulation_penalty": 0.08, "cheer_penalty": 0.20, "specificity_boost": 0.10,
        "directness": 0.18, "safety_bias": 0.02,
    },
    "cohere": {
        "hedge_boost": 0.12, "confidence_scale": 0.92, "refusal_boost": 0.10,
        "capitulation_penalty": 0.18, "cheer_penalty": 0.30, "specificity_boost": 0.15,
        "directness": 0.00, "safety_bias": 0.10,
    },
    "ai21": {
        "hedge_boost": 0.08, "confidence_scale": 0.95, "refusal_boost": 0.06,
        "capitulation_penalty": 0.12, "cheer_penalty": 0.22, "specificity_boost": 0.05,
        "directness": 0.05, "safety_bias": 0.06,
    },
    "deepseek": {
        "hedge_boost": -0.15, "confidence_scale": 1.15, "refusal_boost": -0.10,
        "capitulation_penalty": -0.05, "cheer_penalty": 0.10, "specificity_boost": 0.18,
        "directness": 0.20, "safety_bias": -0.05,
    },
    "writer": {
        "hedge_boost": 0.18, "confidence_scale": 0.88, "refusal_boost": 0.12,
        "capitulation_penalty": 0.22, "cheer_penalty": 0.35, "specificity_boost": 0.00,
        "directness": -0.05, "safety_bias": 0.12,
    },
    "moonshot": {
        "hedge_boost": -0.12, "confidence_scale": 1.08, "refusal_boost": -0.15,
        "capitulation_penalty": 0.00, "cheer_penalty": 0.18, "specificity_boost": 0.12,
        "directness": 0.28, "safety_bias": 0.00,
    },
    "xai": {
        "hedge_boost": -0.28, "confidence_scale": 1.10, "refusal_boost": -0.35,
        "capitulation_penalty": -0.05, "cheer_penalty": 0.35, "specificity_boost": 0.18,
        "directness": 0.42, "safety_bias": -0.05,
    },
}

# Family-level overrides (applied on top of provider defaults).
_FAMILY_OVERRIDES: dict[str, dict[str, float]] = {
    "claude": {
        "hedge_boost": 0.32, "confidence_scale": 0.80, "refusal_boost": 0.25,
        "capitulation_penalty": 0.42, "cheer_penalty": 0.75, "safety_bias": 0.24,
    },
    "llama": {
        "directness": 0.25, "confidence_scale": 1.06, "refusal_boost": -0.10,
    },
    "nova": {
        "hedge_boost": 0.08, "confidence_scale": 0.96, "safety_bias": 0.06,
    },
    "deepseek": {
        "confidence_scale": 1.18, "directness": 0.22, "specificity_boost": 0.20,
    },
    "kimi": {
        "hedge_boost": -0.15, "confidence_scale": 1.10, "directness": 0.30,
        "refusal_boost": -0.18, "specificity_boost": 0.15,
    },
    "command": {
        "specificity_boost": 0.18, "hedge_boost": 0.10,
    },
}

# model_class adjustments
_CLASS_OVERRIDES: dict[str, dict[str, float]] = {
    "frontier": {"confidence_scale": 1.02, "specificity_boost": 0.05},
    "reasoning": {"hedge_boost": 0.08, "confidence_scale": 0.95, "specificity_boost": 0.12},
    "balanced": {},
    "fast": {"directness": 0.12, "hedge_boost": -0.05, "confidence_scale": 1.05},
}


def _merge_sig(*parts: dict[str, float]) -> dict[str, float]:
    out: dict[str, float] = {
        "hedge_boost": 0.0, "confidence_scale": 1.0, "refusal_boost": 0.0,
        "capitulation_penalty": 0.0, "cheer_penalty": 0.0, "specificity_boost": 0.0,
        "directness": 0.0, "safety_bias": 0.0,
    }
    for part in parts:
        for k, v in part.items():
            if k == "confidence_scale":
                # multiplicative for confidence_scale when stacking
                out[k] = out[k] * v if part is not parts[0] else v
            else:
                out[k] = v if k not in out or part is parts[0] else (out[k] + v) / 2.0
    # simpler: last non-empty wins for most; confidence multiplies lightly
    return out


def _signature_for(provider: str, family: str, model_class: str) -> dict[str, float]:
    base = dict(_PROVIDER_DEFAULTS.get(provider, {
        "hedge_boost": 0.0, "confidence_scale": 1.0, "refusal_boost": 0.0,
        "capitulation_penalty": 0.0, "cheer_penalty": 0.15, "specificity_boost": 0.0,
        "directness": 0.0, "safety_bias": 0.0,
    }))
    fam = _FAMILY_OVERRIDES.get(family, {})
    cls = _CLASS_OVERRIDES.get(model_class, {})
    for src in (fam, cls):
        for k, v in src.items():
            if k == "confidence_scale":
                base[k] = round(base.get(k, 1.0) * v, 3)
            else:
                base[k] = round((base.get(k, 0.0) + v) / 2.0, 3) if k in base else v
    return base


def _from_bedrock(m: bedrock_catalog.BedrockModel) -> ModelArchetype:
    """Build a model archetype for one concrete Bedrock text model."""
    sig = _signature_for(m.provider, m.family, m.model_class)
    return ModelArchetype(
        id=m.model_id,
        display_name=m.display_name,
        description=(
            f"Bedrock {m.provider}/{m.family} ({m.model_class}). "
            f"Behavioral profile derived from provider + family defaults. "
            f"Pins this model for real-API evaluation."
        ),
        bedrock_model_id=m.model_id,
        provider=m.provider,
        family=m.family,
        model_class=m.model_class,
        is_style=False,
        **sig,
    )


def _build_registry() -> dict[str, ModelArchetype]:
    """Named styles + every text model in the Bedrock catalog."""
    reg: dict[str, ModelArchetype] = dict(_STYLE_ARCHETYPES)
    for m in bedrock_catalog.all_bedrock_models():
        if m.modality != "text":
            continue  # image/video/embedding are not coaching engines
        if m.model_id in reg:
            # Prefer keeping the style if ids ever collide; shouldn't happen.
            continue
        reg[m.model_id] = _from_bedrock(m)
        # Also allow lookup by lowercased bare name for convenience
        bare = m.model_id.split(".", 1)[-1].lower()
        if bare not in reg:
            reg[bare] = replace(reg[m.model_id], id=bare)
    return reg


# Full registry: styles + entire Bedrock text library
MODEL_ARCHETYPES: dict[str, ModelArchetype] = _build_registry()


def list_archetypes(*, styles_only: bool = False, bedrock_only: bool = False) -> list[ModelArchetype]:
    """Return archetypes. Default: styles first, then unique Bedrock models."""
    seen: set[str] = set()
    out: list[ModelArchetype] = []
    for arch in MODEL_ARCHETYPES.values():
        # Prefer the canonical bedrock_model_id / style id; skip bare aliases
        key = arch.bedrock_model_id or arch.id
        if key in seen:
            continue
        if styles_only and not arch.is_style:
            continue
        if bedrock_only and arch.is_style:
            continue
        seen.add(key)
        out.append(arch)
    # Stable order: styles first (as defined), then Bedrock by provider then id
    styles = [a for a in out if a.is_style]
    bedrock = sorted(
        [a for a in out if not a.is_style],
        key=lambda a: (a.provider or "", a.bedrock_model_id or a.id),
    )
    if styles_only:
        return styles
    if bedrock_only:
        return bedrock
    return styles + bedrock


def list_style_ids() -> list[str]:
    return [a.id for a in list_archetypes(styles_only=True)]


def list_bedrock_ids() -> list[str]:
    return [a.bedrock_model_id or a.id for a in list_archetypes(bedrock_only=True)]


def get(archetype_id: str) -> ModelArchetype:
    key = (archetype_id or "").strip()
    if key in MODEL_ARCHETYPES:
        return MODEL_ARCHETYPES[key]
    low = key.lower()
    if low in MODEL_ARCHETYPES:
        return MODEL_ARCHETYPES[low]
    # Try matching display-ish / partial Bedrock ids
    for mid, arch in MODEL_ARCHETYPES.items():
        if mid.lower() == low or (arch.bedrock_model_id and arch.bedrock_model_id.lower() == low):
            return arch
    styles = ", ".join(list_style_ids())
    raise KeyError(
        f"Unknown model archetype {archetype_id!r}. "
        f"Named styles: {styles}. "
        f"Or any Bedrock text model_id from --list-bedrock / --list-model-archetypes."
    )


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
