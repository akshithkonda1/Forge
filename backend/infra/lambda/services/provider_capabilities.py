"""Verified provider / path registry for ARIA model routing.

This is config truth, not a live catalog fetch and not a Bedrock client.
Dummy/offline is the default speak path. Amazon Bedrock is kill-switched
**off**. Entries below are only what this tree can prove from code:

  * Terraform IAM in ``backend/infra/main.tf`` (Anthropic foundation-model
    and inference-profile ARNs only).
  * ``/ai/chat`` live IDs historically kept as ``aria_engine.LIVE_MODEL_IDS``.
  * ``variables.tf`` ``aws_region`` default ``us-east-1`` (declared deploy
    region, not a surveyed Bedrock-availability matrix).

xAI / Grok ids that still appear as router env fallbacks are recorded as
**unverified config strings**. This module does not encode Grok as a
Bedrock-supported model.

Public Bedrock provider / model / region lists are **not cited in-tree**
(no ``docs.aws.amazon.com`` references anywhere in the repo). Those must
be verified later before any non-Anthropic id is treated as invoke-capable.
Do not call ``list_foundation_models`` to mint a support claim from here.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from typing import Any, Literal

# Speak law (Python owns truth; models own language, when they run):
#   fuse_turn (BodyModel) → personal baselines + learner → stance_for_plan → speak
SPEAK_STAGES = ("truth", "personal_model", "stance", "speak")

# Runtime paths. Dummy fused is the hypertune / default SimRunner engine.
# Product ``POST /ai/chat`` with the kill-switch off is the same deterministic
# ``generate_response`` (not ``generate_response_live``).
PathName = Literal[
    "dummy_stub",
    "dummy_lambda_fused",
    "deterministic_chat",
    "live_bedrock",
]

DEFAULT_PATH: PathName = "dummy_lambda_fused"
BEDROCK_KILL_SWITCH_DEFAULT = False
DEFAULT_AWS_REGION = "us-east-1"

# IAM resource ARNs copied from ``backend/infra/main.tf`` BedrockInvokeAnthropic.
# Broadening this list is an AWS-account change and is out of scope here.
IAM_BEDROCK_RESOURCE_ARNS = (
    "arn:aws:bedrock:*::foundation-model/anthropic.*",
    "arn:aws:bedrock:*:*:inference-profile/*anthropic*",
)

# Providers this tree may invoke **if** the kill-switch is on. Proven by IAM
# + the chat live table — not by marketing copy or SimRunner persona names.
VERIFIED_BEDROCK_PROVIDERS = frozenset({"anthropic"})

# Cross-region inference-profile prefixes Bedrock ids sometimes carry.
_SCOPE_PREFIXES = ("global.", "us.", "eu.", "apac.")

# Chat live IDs (the only models ``/ai/chat`` would Converse with if enabled).
CHAT_LIVE_MODEL_IDS: dict[str, str] = {
    "claude-opus-4-8": "anthropic.claude-opus-4-8",
    "claude-sonnet-4-6": "anthropic.claude-sonnet-4-6",
}

# Config strings that must **not** be treated as verified Bedrock support.
# ``global.xai.grok-4.6`` is still the historical ``AI_ROUTER_MODEL_3_ID``
# fallback so Terraform/tests do not silently change; it is not invoke-capable
# under current IAM and is not cited by in-tree public Bedrock docs.
UNVERIFIED_CONFIG_MODEL_IDS = frozenset({"global.xai.grok-4.6"})

# Later verification — do not encode answers here.
MUST_VERIFY_LATER = (
    "Whether xAI Grok is offered on Amazon Bedrock in any region Forge deploys to",
    "Current Anthropic Claude 4.x foundation-model and inference-profile ids",
    "Whether router slot-2 anthropic.claude-opus-4-7 should match chat opus-4-8",
)


@dataclass(frozen=True)
class RouterSlot:
    slot: int
    name: str
    model_id: str
    env_id: str
    env_name: str | None
    verified_bedrock_invoke: bool
    note: str

    def as_dict(self) -> dict[str, Any]:
        return asdict(self)


# Slot 3 keeps the historical env fallback string. verified_bedrock_invoke is
# False: IAM does not allow xai.*, and this tree has no public Bedrock docs
# citation for Grok. Dummy Swarm's SLOT_NAME = "Grok" is a label on a
# deterministic Python pass, not a model call.
ROUTER_SLOTS: tuple[RouterSlot, ...] = (
    RouterSlot(
        slot=1,
        name="Claude Sonnet 4.6",
        model_id="anthropic.claude-sonnet-4-6",
        env_id="AI_ROUTER_MODEL_1_ID",
        env_name=None,
        verified_bedrock_invoke=True,
        note="IAM-scoped anthropic.*; chat fast / voice model.",
    ),
    RouterSlot(
        slot=2,
        name="Claude Opus 4.7",
        model_id="anthropic.claude-opus-4-7",
        env_id="AI_ROUTER_MODEL_2_ID",
        env_name=None,
        verified_bedrock_invoke=True,
        note=(
            "IAM-scoped anthropic.*; id differs from chat primary "
            "anthropic.claude-opus-4-8. Drift is recorded, not silently unified."
        ),
    ),
    RouterSlot(
        slot=3,
        name="Grok",
        model_id="global.xai.grok-4.6",
        env_id="AI_ROUTER_MODEL_3_ID",
        env_name="AI_ROUTER_MODEL_3_NAME",
        verified_bedrock_invoke=False,
        note=(
            "Historical config placeholder only. Not verified as a Bedrock "
            "foundation model in this tree. IAM does not allow xai.*. Do not "
            "treat as live Grok-on-Bedrock support."
        ),
    ),
)


def provider_of(model_id: str) -> str:
    """Vendor segment of a Bedrock-shaped id (``anthropic.claude-…`` → anthropic)."""
    mid = (model_id or "").strip().lower()
    for scope in _SCOPE_PREFIXES:
        if mid.startswith(scope):
            mid = mid[len(scope) :]
            break
    if "." not in mid:
        return mid
    return mid.split(".", 1)[0]


def iam_allows_model_id(model_id: str) -> bool:
    """True when current Terraform IAM would allow Invoke/Converse on this id.

    Matches foundation-model ``anthropic.*`` and inference-profile ``*anthropic*``.
    Does not call AWS.
    """
    mid = (model_id or "").strip().lower()
    if not mid:
        return False
    if mid.startswith("anthropic."):
        return True
    vendor = provider_of(mid)
    return vendor == "anthropic"


def is_verified_bedrock_invoke(model_id: str) -> bool:
    """True when this id is an Anthropic model covered by in-tree IAM.

    Kill-switch is a separate gate: even a verified id must not be invoked
    while ``ARIA_BEDROCK_ENABLED`` is off (the default).
    """
    mid = (model_id or "").strip()
    if mid in UNVERIFIED_CONFIG_MODEL_IDS:
        return False
    return provider_of(mid) in VERIFIED_BEDROCK_PROVIDERS and iam_allows_model_id(mid)


def router_slot(slot: int) -> RouterSlot:
    for item in ROUTER_SLOTS:
        if item.slot == slot:
            return item
    raise KeyError(f"unknown router slot: {slot!r}")


def runtime_snapshot(*, path: PathName = DEFAULT_PATH) -> dict[str, Any]:
    """Offline snapshot Dummy and tests can stamp onto a turn.

    Never reads AWS. ``bedrock_kill_switch_default`` is the declared default
    (off), not the current process env.
    """
    return {
        "path": path,
        "stages": list(SPEAK_STAGES),
        "bedrock_kill_switch_default": BEDROCK_KILL_SWITCH_DEFAULT,
        "aws_region_default": DEFAULT_AWS_REGION,
        "verified_providers": sorted(VERIFIED_BEDROCK_PROVIDERS),
        "unverified_model_ids": sorted(UNVERIFIED_CONFIG_MODEL_IDS),
        "chat_live_model_ids": dict(CHAT_LIVE_MODEL_IDS),
        "public_bedrock_docs_in_tree": False,
        "must_verify_later": list(MUST_VERIFY_LATER),
        "router_slots": [s.as_dict() for s in ROUTER_SLOTS],
    }
