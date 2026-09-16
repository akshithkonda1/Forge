"""Design stub for ARIA hybrid / model routing.

**Await Quill's table.** Do not encode Bedrock model IDs, inference
profiles, or regions here until Quill's full ID/region table lands.

Direction (Anton): multi-model Bedrock is Grok + latest Claude.
This stub records that intent and the runtime defaults only.

Defaults that must not drift:
  * Dummy / offline fused path is the speak path.
  * Bedrock kill-switch stays **off** (``ARIA_BEDROCK_ENABLED`` /
    ``aria_bedrock_enabled``).
  * No live Bedrock calls and no AWS apply.

Existing code still has its own model-id strings (``ai_router.default_models``,
``aria_engine.LIVE_MODEL_IDS``, Terraform env fallbacks). Those are
pre-existing call-site defaults, not this registry. Fill this module from
Quill's table later; until then Dummy remains default.

Speak law: fuse_turn (truth) → personal baselines + learner →
stance_for_plan → generate_response (deterministic speak).
"""

from __future__ import annotations

from typing import Any, Literal

SPEAK_STAGES = ("truth", "personal_model", "stance", "speak")

PathName = Literal[
    "dummy_stub",
    "dummy_lambda_fused",
    "deterministic_chat",
    "live_bedrock",
]

DEFAULT_PATH: PathName = "dummy_lambda_fused"
BEDROCK_KILL_SWITCH_DEFAULT = False
DO_NOT_INVOKE = True
AWAIT_QUILL_TABLE = True
DIRECTION = "grok_plus_latest_claude"


def invoke_now_allowed(model_id: str | None = None) -> bool:
    """Live invoke is off. Kill-switch default; this module never calls."""
    del model_id
    return False


def runtime_snapshot(*, path: PathName = DEFAULT_PATH) -> dict[str, Any]:
    """Offline snapshot Dummy/tests can stamp. Contains no model-id table."""
    return {
        "path": path,
        "stages": list(SPEAK_STAGES),
        "bedrock_kill_switch_default": BEDROCK_KILL_SWITCH_DEFAULT,
        "do_not_invoke": DO_NOT_INVOKE,
        "await_quill_table": AWAIT_QUILL_TABLE,
        "direction": DIRECTION,
        "note": (
            "Capability registry is design-only until Quill's full "
            "ID/region table lands. Dummy/offline default. Do not invoke."
        ),
    }
