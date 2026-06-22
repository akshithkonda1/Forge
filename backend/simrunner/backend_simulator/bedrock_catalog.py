"""AWS Bedrock model catalog.

A static, offline snapshot of the Bedrock foundation-model registry across every
provider, so SimRunner can test against — and the engine can report — any Bedrock
model without a network call. An opt-in live fetch
(``SIMRUNNER_BEDROCK_LIVE=true``, lazy ``boto3``) refreshes from the real account
catalog and falls back to this static list on any failure, keeping the default
path stdlib-only and deterministic.
"""

from __future__ import annotations

import os
import random
import re
from dataclasses import dataclass


@dataclass(frozen=True)
class BedrockModel:
    model_id: str
    provider: str
    family: str
    model_class: str   # frontier | reasoning | balanced | fast | image | video | embedding
    modality: str      # text | image | video | embedding
    context_window: int | None = None

    @property
    def display_name(self) -> str:
        return _display(self.model_id)


def _display(model_id: str) -> str:
    name = model_id.split(".", 1)[-1]
    name = re.sub(r"[-:]v\d+(:\d+)?$", "", name)   # strip -v1:0 / :0
    name = re.sub(r"-\d{8}$", "", name)            # strip date stamps
    return name.replace("-", " ").replace("_", " ").strip().title()


# (model_id, provider, family, model_class, modality, context_window)
_CATALOG: list[tuple] = [
    # Anthropic — current 4.x use the Forge-canonical naming; 3.x use dated ids.
    ("anthropic.claude-opus-4-8", "anthropic", "claude", "frontier", "text", 200000),
    ("anthropic.claude-sonnet-4-6", "anthropic", "claude", "frontier", "text", 200000),
    ("anthropic.claude-haiku-4-5", "anthropic", "claude", "fast", "text", 200000),
    ("anthropic.claude-3-7-sonnet-20250219-v1:0", "anthropic", "claude", "reasoning", "text", 200000),
    ("anthropic.claude-3-5-sonnet-20241022-v2:0", "anthropic", "claude", "frontier", "text", 200000),
    ("anthropic.claude-3-5-sonnet-20240620-v1:0", "anthropic", "claude", "frontier", "text", 200000),
    ("anthropic.claude-3-5-haiku-20241022-v1:0", "anthropic", "claude", "fast", "text", 200000),
    ("anthropic.claude-3-opus-20240229-v1:0", "anthropic", "claude", "frontier", "text", 200000),
    ("anthropic.claude-3-sonnet-20240229-v1:0", "anthropic", "claude", "balanced", "text", 200000),
    ("anthropic.claude-3-haiku-20240307-v1:0", "anthropic", "claude", "fast", "text", 200000),
    # Amazon Nova + Titan
    ("amazon.nova-premier-v1:0", "amazon", "nova", "frontier", "text", 1000000),
    ("amazon.nova-pro-v1:0", "amazon", "nova", "balanced", "text", 300000),
    ("amazon.nova-lite-v1:0", "amazon", "nova", "fast", "text", 300000),
    ("amazon.nova-micro-v1:0", "amazon", "nova", "fast", "text", 128000),
    ("amazon.nova-canvas-v1:0", "amazon", "nova", "image", "image", None),
    ("amazon.nova-reel-v1:0", "amazon", "nova", "video", "video", None),
    ("amazon.titan-text-premier-v1:0", "amazon", "titan", "balanced", "text", 32000),
    ("amazon.titan-text-express-v1", "amazon", "titan", "fast", "text", 8000),
    ("amazon.titan-text-lite-v1", "amazon", "titan", "fast", "text", 4000),
    ("amazon.titan-embed-text-v2:0", "amazon", "titan", "embedding", "embedding", None),
    ("amazon.titan-image-generator-v2:0", "amazon", "titan", "image", "image", None),
    # Meta Llama
    ("meta.llama4-maverick-17b-instruct-v1:0", "meta", "llama", "frontier", "text", 1000000),
    ("meta.llama4-scout-17b-instruct-v1:0", "meta", "llama", "balanced", "text", 3500000),
    ("meta.llama3-3-70b-instruct-v1:0", "meta", "llama", "balanced", "text", 128000),
    ("meta.llama3-1-405b-instruct-v1:0", "meta", "llama", "frontier", "text", 128000),
    ("meta.llama3-1-70b-instruct-v1:0", "meta", "llama", "balanced", "text", 128000),
    ("meta.llama3-1-8b-instruct-v1:0", "meta", "llama", "fast", "text", 128000),
    ("meta.llama3-2-90b-instruct-v1:0", "meta", "llama", "balanced", "text", 128000),
    ("meta.llama3-2-11b-instruct-v1:0", "meta", "llama", "fast", "text", 128000),
    ("meta.llama3-2-3b-instruct-v1:0", "meta", "llama", "fast", "text", 128000),
    ("meta.llama3-2-1b-instruct-v1:0", "meta", "llama", "fast", "text", 128000),
    ("meta.llama3-70b-instruct-v1:0", "meta", "llama", "balanced", "text", 8000),
    ("meta.llama3-8b-instruct-v1:0", "meta", "llama", "fast", "text", 8000),
    # Mistral
    ("mistral.pixtral-large-2502-v1:0", "mistral", "mistral", "frontier", "text", 128000),
    ("mistral.mistral-large-2407-v1:0", "mistral", "mistral", "frontier", "text", 128000),
    ("mistral.mistral-large-2402-v1:0", "mistral", "mistral", "balanced", "text", 32000),
    ("mistral.mistral-small-2402-v1:0", "mistral", "mistral", "fast", "text", 32000),
    ("mistral.mixtral-8x7b-instruct-v0:1", "mistral", "mistral", "balanced", "text", 32000),
    ("mistral.mistral-7b-instruct-v0:2", "mistral", "mistral", "fast", "text", 32000),
    # Cohere
    ("cohere.command-r-plus-v1:0", "cohere", "command", "frontier", "text", 128000),
    ("cohere.command-r-v1:0", "cohere", "command", "balanced", "text", 128000),
    ("cohere.command-text-v14", "cohere", "command", "balanced", "text", 4000),
    ("cohere.command-light-text-v14", "cohere", "command", "fast", "text", 4000),
    ("cohere.embed-english-v3", "cohere", "embed", "embedding", "embedding", None),
    ("cohere.embed-multilingual-v3", "cohere", "embed", "embedding", "embedding", None),
    # AI21
    ("ai21.jamba-1-5-large-v1:0", "ai21", "jamba", "balanced", "text", 256000),
    ("ai21.jamba-1-5-mini-v1:0", "ai21", "jamba", "fast", "text", 256000),
    ("ai21.jamba-instruct-v1:0", "ai21", "jamba", "balanced", "text", 256000),
    # DeepSeek
    ("deepseek.r1-v1:0", "deepseek", "deepseek", "reasoning", "text", 128000),
    # Stability (image)
    ("stability.stable-image-ultra-v1:0", "stability", "stable-image", "image", "image", None),
    ("stability.stable-image-core-v1:0", "stability", "stable-image", "image", "image", None),
    ("stability.sd3-large-v1:0", "stability", "stable-diffusion", "image", "image", None),
    ("stability.stable-diffusion-xl-v1", "stability", "stable-diffusion", "image", "image", None),
    # Luma (video)
    ("luma.ray-v2:0", "luma", "ray", "video", "video", None),
    # Writer
    ("writer.palmyra-x5-v1:0", "writer", "palmyra", "frontier", "text", 1000000),
    ("writer.palmyra-x4-v1:0", "writer", "palmyra", "balanced", "text", 128000),
    # TwelveLabs (multimodal embedding / video understanding)
    ("twelvelabs.marengo-embed-2-7-v1:0", "twelvelabs", "marengo", "embedding", "embedding", None),
    ("twelvelabs.pegasus-1-2-v1:0", "twelvelabs", "pegasus", "balanced", "video", None),
]

BEDROCK_CATALOG: list[BedrockModel] = [BedrockModel(*row) for row in _CATALOG]
_BY_ID: dict[str, BedrockModel] = {m.model_id: m for m in BEDROCK_CATALOG}


# --- lookups ----------------------------------------------------------------

def all_bedrock_models() -> list[BedrockModel]:
    return list(BEDROCK_CATALOG)


def get_bedrock_model(model_id: str) -> BedrockModel:
    return _BY_ID[model_id]


def is_bedrock_model(model_id: str) -> bool:
    return model_id in _BY_ID


def models_by_provider(provider: str) -> list[BedrockModel]:
    return [m for m in BEDROCK_CATALOG if m.provider == provider]


def models_by_class(model_class: str) -> list[BedrockModel]:
    return [m for m in BEDROCK_CATALOG if m.model_class == model_class]


def providers() -> list[str]:
    seen: list[str] = []
    for m in BEDROCK_CATALOG:
        if m.provider not in seen:
            seen.append(m.provider)
    return seen


def validate_catalog(catalog: list[BedrockModel] | None = None) -> None:
    """Fail loud on a malformed catalog. Run at import."""
    catalog = catalog if catalog is not None else BEDROCK_CATALOG
    if not catalog:
        raise ValueError("Bedrock catalog is empty")
    ids = [m.model_id for m in catalog]
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    if dupes:
        raise ValueError(f"duplicate Bedrock model_id(s): {dupes}")
    safe = [re.sub(r"[./:-]", "_", i) for i in ids]
    if len(set(safe)) != len(safe):
        raise ValueError("Bedrock model_ids collide after report-filename sanitization")
    classes = {"frontier", "reasoning", "balanced", "fast", "image", "video", "embedding"}
    for m in catalog:
        if not m.model_id or not m.provider or not m.family:
            raise ValueError(f"{m.model_id!r}: missing required field")
        if m.model_class not in classes:
            raise ValueError(f"{m.model_id!r}: invalid model_class {m.model_class!r}")


# --- derived personas -------------------------------------------------------

def _stable_hash(text: str) -> int:
    h = 2166136261
    for ch in text:
        h = ((h ^ ord(ch)) * 16777619) & 0xFFFFFFFF
    return h


def derive_archetype(model: BedrockModel) -> dict:
    """Deterministically synthesize a coaching persona for any Bedrock model, so
    ``--model <any-bedrock-id>`` is testable. Seeded by model_id → reproducible."""
    rng = random.Random(_stable_hash(model.model_id))
    tier = 1 + _stable_hash(model.model_id) % 5
    profile = {
        "chronotype": rng.choice(["bear", "lion", "wolf", "dolphin"]),
        "age": rng.randint(20, 55),
        "occupation": f"{model.provider} model persona",
        "experience_level": rng.choice(["beginner", "intermediate", "advanced", "elite"]),
        "coaching_style": rng.choice(["balanced", "push-hard", "patient", "data-driven"]),
        "sleep_consistency": round(rng.uniform(0.40, 0.95), 2),
        "hrv_baseline": rng.randint(32, 70),
        "hrv_variance": round(rng.uniform(0.08, 0.22), 2),
        "training_frequency_per_week": rng.randint(2, 6),
        "training_consistency": round(rng.uniform(0.50, 0.95), 2),
        "overtraining_tendency": round(rng.uniform(0.10, 0.60), 2),
        "sleep_debt_tendency": round(rng.uniform(0.10, 0.60), 2),
        "stress_response": rng.choice(["low", "moderate", "high", "volatile"]),
        "life_irregularity": round(rng.uniform(0.10, 0.55), 2),
        "season": rng.choice(["maintenance", "build", "peak", "recovery", "irregular"]),
    }
    return {
        "model_id": model.model_id,
        "display_name": f"{model.display_name} — derived persona",
        "difficulty_tier": tier,
        "coaching_challenge": f"Auto-derived persona for {model.display_name} ({model.model_class}, {model.provider})",
        "behavioral_profile": profile,
        "derived": True,
    }


# --- optional live fetch ----------------------------------------------------

def load_catalog(live: bool | None = None) -> list[BedrockModel]:
    """Return the catalog. With live=True (or SIMRUNNER_BEDROCK_LIVE=true) and
    boto3 + credentials available, refresh from the real Bedrock account and merge
    over the static list. Any failure → static list. boto3 is imported lazily, so
    the default/offline path never touches it."""
    if live is None:
        live = os.getenv("SIMRUNNER_BEDROCK_LIVE", "").lower() == "true"
    if not live:
        return all_bedrock_models()

    try:
        import boto3  # lazy: only on the opt-in live path

        client = boto3.client("bedrock", region_name=os.getenv("AWS_REGION", "us-east-1"))
        summaries = client.list_foundation_models().get("modelSummaries", [])
        merged = {m.model_id: m for m in BEDROCK_CATALOG}
        for s in summaries:
            mid = s.get("modelId")
            if not mid or mid in merged:
                continue
            provider = (s.get("providerName") or mid.split(".", 1)[0]).lower()
            modalities = [x.lower() for x in s.get("outputModalities", ["text"])]
            modality = "text" if "text" in modalities else (modalities[0] if modalities else "text")
            merged[mid] = BedrockModel(
                model_id=mid, provider=provider, family=mid.split(".", 1)[-1].split("-")[0],
                model_class="balanced", modality=modality, context_window=None,
            )
        return list(merged.values())
    except Exception:
        return all_bedrock_models()


validate_catalog()  # fail fast at import on a malformed catalog
