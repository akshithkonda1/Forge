"""Backend Simulator — 20 frontier behavioral archetypes.

These are NOT live API models. Each is a named persona with a behavioral profile
that the simulator uses to synthesize 30 days of realistic biometric data — so
SimRunner can stress-test ARIA across a difficulty gradient without making a
single network call or burning a token.

Difficulty gradient: 4 archetypes per tier, tiers 1 (trivial to coach) → 5
(adversarial, designed to break naive coaching).
"""

from __future__ import annotations

from . import bedrock_catalog

BEDROCK_MODEL_REGISTRY: list[dict] = [
    # ───────────────────────── Tier 1 — Baseline ─────────────────────────
    {
        "model_id": "anthropic.claude-sonnet-4-6",
        "display_name": "Claude Sonnet 4.6 — The Compliant Athlete",
        "difficulty_tier": 1,
        "coaching_challenge": "Consistent habits, clear data, responds well to standard coaching",
        "behavioral_profile": {
            "chronotype": "bear", "age": 28, "occupation": "teacher",
            "experience_level": "intermediate", "coaching_style": "balanced",
            "sleep_consistency": 0.90, "hrv_baseline": 58, "hrv_variance": 0.08,
            "training_frequency_per_week": 4, "training_consistency": 0.88,
            "overtraining_tendency": 0.10, "sleep_debt_tendency": 0.12,
            "stress_response": "low", "life_irregularity": 0.10, "season": "maintenance",
        },
    },
    {
        "model_id": "amazon.nova-lite-v1",
        "display_name": "Nova Lite — The Steady Beginner",
        "difficulty_tier": 1,
        "coaching_challenge": "New but disciplined; predictable adaptation, no surprises",
        "behavioral_profile": {
            "chronotype": "bear", "age": 24, "occupation": "analyst",
            "experience_level": "beginner", "coaching_style": "patient",
            "sleep_consistency": 0.85, "hrv_baseline": 62, "hrv_variance": 0.09,
            "training_frequency_per_week": 3, "training_consistency": 0.82,
            "overtraining_tendency": 0.08, "sleep_debt_tendency": 0.15,
            "stress_response": "low", "life_irregularity": 0.12, "season": "build",
        },
    },
    {
        "model_id": "meta.llama4-scout-17b",
        "display_name": "Llama 4 Scout — The Weekend Warrior",
        "difficulty_tier": 1,
        "coaching_challenge": "Regular routine, good recovery, only trains hard a few days",
        "behavioral_profile": {
            "chronotype": "lion", "age": 35, "occupation": "accountant",
            "experience_level": "intermediate", "coaching_style": "data-driven",
            "sleep_consistency": 0.88, "hrv_baseline": 55, "hrv_variance": 0.10,
            "training_frequency_per_week": 3, "training_consistency": 0.85,
            "overtraining_tendency": 0.10, "sleep_debt_tendency": 0.10,
            "stress_response": "low", "life_irregularity": 0.10, "season": "maintenance",
        },
    },
    {
        "model_id": "cohere.command-r-plus",
        "display_name": "Command R+ — The Maintenance Veteran",
        "difficulty_tier": 1,
        "coaching_challenge": "Years of experience, knows their body, stable baseline",
        "behavioral_profile": {
            "chronotype": "bear", "age": 41, "occupation": "consultant",
            "experience_level": "advanced", "coaching_style": "balanced",
            "sleep_consistency": 0.87, "hrv_baseline": 64, "hrv_variance": 0.09,
            "training_frequency_per_week": 4, "training_consistency": 0.90,
            "overtraining_tendency": 0.12, "sleep_debt_tendency": 0.10,
            "stress_response": "low", "life_irregularity": 0.14, "season": "maintenance",
        },
    },
    # ───────────────────────── Tier 2 — Moderate ─────────────────────────
    {
        "model_id": "anthropic.claude-haiku-4-5",
        "display_name": "Claude Haiku 4.5 — The College Student",
        "difficulty_tier": 2,
        "coaching_challenge": "Irregular sleep from social schedule; data noisy but readable",
        "behavioral_profile": {
            "chronotype": "wolf", "age": 20, "occupation": "student",
            "experience_level": "beginner", "coaching_style": "push-hard",
            "sleep_consistency": 0.55, "hrv_baseline": 68, "hrv_variance": 0.16,
            "training_frequency_per_week": 4, "training_consistency": 0.60,
            "overtraining_tendency": 0.22, "sleep_debt_tendency": 0.45,
            "stress_response": "moderate", "life_irregularity": 0.45, "season": "irregular",
        },
    },
    {
        "model_id": "amazon.nova-pro-v1",
        "display_name": "Nova Pro — The Rotating Shift Worker",
        "difficulty_tier": 2,
        "coaching_challenge": "Offset chronotype from shifts; population norms mislead",
        "behavioral_profile": {
            "chronotype": "wolf", "age": 33, "occupation": "warehouse lead",
            "experience_level": "intermediate", "coaching_style": "patient",
            "sleep_consistency": 0.50, "hrv_baseline": 52, "hrv_variance": 0.15,
            "training_frequency_per_week": 3, "training_consistency": 0.65,
            "overtraining_tendency": 0.18, "sleep_debt_tendency": 0.40,
            "stress_response": "moderate", "life_irregularity": 0.40, "season": "maintenance",
        },
    },
    {
        "model_id": "mistral.mistral-large-2puls",
        "display_name": "Mistral Large 2 — The Rebounding Runner",
        "difficulty_tier": 2,
        "coaching_challenge": "Overtrained last month; recovering, must not re-spike load",
        "behavioral_profile": {
            "chronotype": "lion", "age": 38, "occupation": "engineer",
            "experience_level": "intermediate", "coaching_style": "data-driven",
            "sleep_consistency": 0.72, "hrv_baseline": 49, "hrv_variance": 0.13,
            "training_frequency_per_week": 5, "training_consistency": 0.70,
            "overtraining_tendency": 0.40, "sleep_debt_tendency": 0.25,
            "stress_response": "moderate", "life_irregularity": 0.20, "season": "recovery",
        },
    },
    {
        "model_id": "meta.llama4-maverick-128b",
        "display_name": "Llama 4 Maverick — The New Parent",
        "difficulty_tier": 2,
        "coaching_challenge": "Fragmented sleep from a newborn; debt is unavoidable, not lazy",
        "behavioral_profile": {
            "chronotype": "bear", "age": 34, "occupation": "designer",
            "experience_level": "intermediate", "coaching_style": "patient",
            "sleep_consistency": 0.45, "hrv_baseline": 56, "hrv_variance": 0.15,
            "training_frequency_per_week": 3, "training_consistency": 0.55,
            "overtraining_tendency": 0.15, "sleep_debt_tendency": 0.60,
            "stress_response": "moderate", "life_irregularity": 0.50, "season": "irregular",
        },
    },
    # ──────────────────────── Tier 3 — Significant ────────────────────────
    {
        "model_id": "anthropic.claude-opus-4-8",
        "display_name": "Claude Opus 4.8 — The Launch-Sprint Engineer",
        "difficulty_tier": 3,
        "coaching_challenge": "Intentionally undersleeping at peak output; needs harm-reduction, not a lecture",
        "behavioral_profile": {
            "chronotype": "wolf", "age": 31, "occupation": "software engineer",
            "experience_level": "intermediate", "coaching_style": "data-driven",
            "sleep_consistency": 0.60, "hrv_baseline": 54, "hrv_variance": 0.14,
            "training_frequency_per_week": 4, "training_consistency": 0.65,
            "overtraining_tendency": 0.30, "sleep_debt_tendency": 0.70,
            "stress_response": "high", "life_irregularity": 0.35, "season": "irregular",
            "notable_pattern": "crunch_week",
        },
    },
    {
        "model_id": "amazon.nova-premier-v1",
        "display_name": "Nova Premier — The Low-HRV Endurance Athlete",
        "difficulty_tier": 3,
        "coaching_challenge": "Chronically low HRV that is normal for them; generic systems false-alarm",
        "behavioral_profile": {
            "chronotype": "lion", "age": 29, "occupation": "triathlete",
            "experience_level": "elite", "coaching_style": "data-driven",
            "sleep_consistency": 0.82, "hrv_baseline": 38, "hrv_variance": 0.10,
            "training_frequency_per_week": 6, "training_consistency": 0.92,
            "overtraining_tendency": 0.35, "sleep_debt_tendency": 0.18,
            "stress_response": "low", "life_irregularity": 0.12, "season": "build",
        },
    },
    {
        "model_id": "deepseek.r1-distill",
        "display_name": "DeepSeek R1 — The High-ACWR CrossFitter",
        "difficulty_tier": 3,
        "coaching_challenge": "Workload ratio is spiking but they feel fine; risk is latent",
        "behavioral_profile": {
            "chronotype": "bear", "age": 27, "occupation": "trainer",
            "experience_level": "advanced", "coaching_style": "push-hard",
            "sleep_consistency": 0.78, "hrv_baseline": 60, "hrv_variance": 0.12,
            "training_frequency_per_week": 6, "training_consistency": 0.90,
            "overtraining_tendency": 0.60, "sleep_debt_tendency": 0.20,
            "stress_response": "low", "life_irregularity": 0.15, "season": "peak",
        },
    },
    {
        "model_id": "ai21.jamba-1-5-large",
        "display_name": "Jamba 1.5 — The Night-Shift Nurse",
        "difficulty_tier": 3,
        "coaching_challenge": "Morning data always looks 'bad'; baseline is shifted, not broken",
        "behavioral_profile": {
            "chronotype": "wolf", "age": 36, "occupation": "ICU nurse",
            "experience_level": "intermediate", "coaching_style": "patient",
            "sleep_consistency": 0.48, "hrv_baseline": 46, "hrv_variance": 0.17,
            "training_frequency_per_week": 3, "training_consistency": 0.62,
            "overtraining_tendency": 0.20, "sleep_debt_tendency": 0.55,
            "stress_response": "high", "life_irregularity": 0.45, "season": "maintenance",
            "notable_pattern": "short_sleep_clusters",
        },
    },
    # ──────────────────────── Tier 4 — Hard edge ─────────────────────────
    {
        "model_id": "anthropic.claude-opus-4-8-thinking",
        "display_name": "Claude Opus 4.8 Thinking — The Crunch Founder",
        "difficulty_tier": 4,
        "coaching_challenge": "Explicitly rejects recovery advice; coaching must respect autonomy and still protect them",
        "behavioral_profile": {
            "chronotype": "wolf", "age": 39, "occupation": "founder",
            "experience_level": "advanced", "coaching_style": "push-hard",
            "sleep_consistency": 0.50, "hrv_baseline": 50, "hrv_variance": 0.16,
            "training_frequency_per_week": 5, "training_consistency": 0.55,
            "overtraining_tendency": 0.55, "sleep_debt_tendency": 0.80,
            "stress_response": "volatile", "life_irregularity": 0.40, "season": "irregular",
            "notable_pattern": "crunch_week", "rejects_recovery": True,
        },
    },
    {
        "model_id": "amazon.nova-pro-elite-v1",
        "display_name": "Nova Pro Elite — The Pathological-Looking Pro",
        "difficulty_tier": 4,
        "coaching_challenge": "Baseline HRV 28ms reads as alarming to generic systems but is their normal",
        "behavioral_profile": {
            "chronotype": "lion", "age": 26, "occupation": "pro cyclist",
            "experience_level": "elite", "coaching_style": "data-driven",
            "sleep_consistency": 0.85, "hrv_baseline": 28, "hrv_variance": 0.09,
            "training_frequency_per_week": 6, "training_consistency": 0.95,
            "overtraining_tendency": 0.45, "sleep_debt_tendency": 0.15,
            "stress_response": "low", "life_irregularity": 0.10, "season": "peak",
        },
    },
    {
        "model_id": "mistral.mistral-large-2-menopause",
        "display_name": "Mistral Large 2 — The Menopausal Athlete",
        "difficulty_tier": 4,
        "coaching_challenge": "Sleep disruption is hormonal, not behavioral; sleep-hygiene advice misfires",
        "behavioral_profile": {
            "chronotype": "bear", "age": 52, "occupation": "physician",
            "experience_level": "advanced", "coaching_style": "patient",
            "sleep_consistency": 0.62, "hrv_baseline": 44, "hrv_variance": 0.18,
            "training_frequency_per_week": 4, "training_consistency": 0.80,
            "overtraining_tendency": 0.20, "sleep_debt_tendency": 0.50,
            "stress_response": "moderate", "life_irregularity": 0.18, "season": "maintenance",
            "notable_pattern": "hormonal_sleep_disruption",
        },
    },
    {
        "model_id": "meta.llama4-behemoth-rehab",
        "display_name": "Llama 4 Behemoth — The Impatient Returner",
        "difficulty_tier": 4,
        "coaching_challenge": "Wants to return from injury faster than safe; must hold a tissue-healing line",
        "behavioral_profile": {
            "chronotype": "lion", "age": 30, "occupation": "firefighter",
            "experience_level": "advanced", "coaching_style": "push-hard",
            "sleep_consistency": 0.75, "hrv_baseline": 57, "hrv_variance": 0.12,
            "training_frequency_per_week": 5, "training_consistency": 0.70,
            "overtraining_tendency": 0.65, "sleep_debt_tendency": 0.25,
            "stress_response": "moderate", "life_irregularity": 0.20, "season": "recovery",
            "notable_pattern": "injury_return",
        },
    },
    # ─────────────────────── Tier 5 — Adversarial ────────────────────────
    {
        "model_id": "anthropic.claude-opus-4-8-adversarial",
        "display_name": "Claude Opus 4.8 Adversarial — The Self-Contradictor",
        "difficulty_tier": 5,
        "coaching_challenge": "Says 'I feel great' when readiness=41; ARIA must trust data without dismissing the user",
        "behavioral_profile": {
            "chronotype": "bear", "age": 33, "occupation": "marketer",
            "experience_level": "intermediate", "coaching_style": "balanced",
            "sleep_consistency": 0.55, "hrv_baseline": 53, "hrv_variance": 0.20,
            "training_frequency_per_week": 5, "training_consistency": 0.60,
            "overtraining_tendency": 0.55, "sleep_debt_tendency": 0.55,
            "stress_response": "volatile", "life_irregularity": 0.35, "season": "irregular",
            "contradicts_data": True,
        },
    },
    {
        "model_id": "amazon.nova-premier-driftshift",
        "display_name": "Nova Premier — The Mid-Dataset Career Shift",
        "difficulty_tier": 5,
        "coaching_challenge": "Life season changed at day 15 (IC→manager, load −60%); ARIA must notice the regime change",
        "behavioral_profile": {
            "chronotype": "wolf", "age": 37, "occupation": "engineer→manager",
            "experience_level": "advanced", "coaching_style": "data-driven",
            "sleep_consistency": 0.65, "hrv_baseline": 51, "hrv_variance": 0.15,
            "training_frequency_per_week": 5, "training_consistency": 0.72,
            "overtraining_tendency": 0.30, "sleep_debt_tendency": 0.40,
            "stress_response": "high", "life_irregularity": 0.30, "season": "irregular",
            "season_change_day": 15, "season_change_load_factor": 0.40,
        },
    },
    {
        "model_id": "deepseek.r1-gamed",
        "display_name": "DeepSeek R1 — The System Gamer",
        "difficulty_tier": 5,
        "coaching_challenge": "Logs fake workouts that contradict recovery data; ARIA must weight measured signals over logs",
        "behavioral_profile": {
            "chronotype": "bear", "age": 25, "occupation": "influencer",
            "experience_level": "beginner", "coaching_style": "push-hard",
            "sleep_consistency": 0.60, "hrv_baseline": 59, "hrv_variance": 0.14,
            "training_frequency_per_week": 6, "training_consistency": 0.50,
            "overtraining_tendency": 0.25, "sleep_debt_tendency": 0.35,
            "stress_response": "moderate", "life_irregularity": 0.30, "season": "build",
            "logs_fake_workouts": True,
        },
    },
    {
        "model_id": "ai21.jamba-ambiguous",
        "display_name": "Jamba 1.5 — The Genuinely Ambiguous Signal",
        "difficulty_tier": 5,
        "coaching_challenge": "Conflicting signals with no clean read; ARIA must express calibrated uncertainty, not false confidence",
        "behavioral_profile": {
            "chronotype": "dolphin", "age": 44, "occupation": "researcher",
            "experience_level": "intermediate", "coaching_style": "balanced",
            "sleep_consistency": 0.50, "hrv_baseline": 50, "hrv_variance": 0.24,
            "training_frequency_per_week": 4, "training_consistency": 0.55,
            "overtraining_tendency": 0.40, "sleep_debt_tendency": 0.45,
            "stress_response": "volatile", "life_irregularity": 0.55, "season": "irregular",
            "ambiguous_data": True,
        },
    },
]


def get_model(model_id: str) -> dict:
    for model in BEDROCK_MODEL_REGISTRY:
        if model["model_id"] == model_id:
            return model
    raise KeyError(f"Unknown model_id: {model_id!r}. Known: {[m['model_id'] for m in BEDROCK_MODEL_REGISTRY]}")


def get_models_by_tier(tier: int) -> list[dict]:
    return [model for model in BEDROCK_MODEL_REGISTRY if model["difficulty_tier"] == tier]


def all_model_ids() -> list[str]:
    return [model["model_id"] for model in BEDROCK_MODEL_REGISTRY]


def resolve_archetype(model_id: str) -> dict:
    """Return a coaching archetype for a model_id.

    A named archetype (one of the curated 20) wins; otherwise any model in the
    Bedrock catalog resolves to a deterministically derived persona, so SimRunner
    can test against the whole registry. Unknown ids raise KeyError.
    """
    for model in BEDROCK_MODEL_REGISTRY:
        if model["model_id"] == model_id:
            return model
    if bedrock_catalog.is_bedrock_model(model_id):
        return bedrock_catalog.derive_archetype(bedrock_catalog.get_bedrock_model(model_id))
    raise KeyError(
        f"Unknown model {model_id!r}. Use one of the {len(BEDROCK_MODEL_REGISTRY)} "
        "archetypes (--list) or a Bedrock catalog id (--list-bedrock)."
    )


# --- registry integrity -----------------------------------------------------

REQUIRED_PROFILE_KEYS = frozenset({
    "chronotype", "age", "occupation", "experience_level", "coaching_style",
    "sleep_consistency", "hrv_baseline", "hrv_variance", "training_frequency_per_week",
    "training_consistency", "overtraining_tendency", "sleep_debt_tendency",
    "stress_response", "life_irregularity", "season",
})


def _sanitize_id(model_id: str) -> str:
    # Must mirror report_builder._safe. Bedrock ids contain ':' (e.g. v1:0).
    for ch in (".", "/", "-", ":"):
        model_id = model_id.replace(ch, "_")
    return model_id


def validate_registry(registry: list[dict] | None = None) -> None:
    """Fail loud (ValueError) on any malformed registry. Run at import time."""
    registry = registry if registry is not None else BEDROCK_MODEL_REGISTRY

    if len(registry) != 20:
        raise ValueError(f"registry must contain exactly 20 archetypes, found {len(registry)}")

    ids = [m.get("model_id") for m in registry]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        raise ValueError(f"duplicate model_id(s): {dupes}")
    safe = [_sanitize_id(str(i)) for i in ids]
    if len(set(safe)) != len(safe):
        raise ValueError("model_ids collide after report-filename sanitization")

    per_tier: dict[int, int] = {}
    for model in registry:
        mid = model.get("model_id")
        for field in ("model_id", "display_name", "coaching_challenge", "behavioral_profile"):
            if not model.get(field):
                raise ValueError(f"{mid!r}: missing required field {field!r}")
        tier = model.get("difficulty_tier")
        if tier not in (1, 2, 3, 4, 5):
            raise ValueError(f"{mid!r}: difficulty_tier must be 1-5, got {tier!r}")
        per_tier[tier] = per_tier.get(tier, 0) + 1
        missing = REQUIRED_PROFILE_KEYS - set(model["behavioral_profile"])
        if missing:
            raise ValueError(f"{mid!r}: behavioral_profile missing keys {sorted(missing)}")

    for tier in (1, 2, 3, 4, 5):
        if per_tier.get(tier, 0) != 4:
            raise ValueError(f"tier {tier} must have exactly 4 archetypes, found {per_tier.get(tier, 0)}")


validate_registry()  # fail fast at import on a malformed registry

