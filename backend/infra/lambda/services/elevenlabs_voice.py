"""ElevenLabs Voice Design + Conversational AI client for ARIA's live mouth.

Dummy / Device Hub never imports this. The iOS dummy session short-circuits
before ``GET /ai/voice/bootstrap``. This module is the live path: a locked
Voice Design prompt, a saved ``voice_id`` named ARIA, a ConvAI agent whose
tools hit ``aria_engine``, and a short-lived signed WebSocket URL so the
phone never sees ``ELEVENLABS_API_KEY``.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable

from responses import RouteError
from services import aria_engine
from services.provider_secrets import load_ai_provider_secret

ELEVEN_API = "https://api.elevenlabs.io"

# Keep this byte-for-byte identical to ``AriaCharacterVoice.designPrompt``.
ARIA_DESIGN_PROMPT = (
    "American English. Woman, early 30s. Warm low-mid pitch, close-mic, dry, "
    "unhurried. Sounds like a sharp coach in the room, not a customer-service "
    "agent, GPS, or audiobook narrator. Slight smile, no valley-girl uptalk, "
    "no theatrical breathiness."
)

ARIA_DESIGN_PREVIEW_TEXT = (
    "I'm ARIA. Let's look at how you actually slept and what that means for "
    "training today. One next move, not a new identity."
)

ARIA_VOICE_NAME = "ARIA"

# Locked live-mouth stack. Dummy / Device Hub never uses these.
# Keep names identical to ``AriaCharacterVoice`` on iOS.
TTS_MODEL_ID = "eleven_v3_conversational"
ASR_PROVIDER = "scribe_realtime"  # Scribe v2 Realtime. ``elevenlabs`` is deprecated.
TURN_MODEL = "turn_v3"
VOICE_DESIGN_MODEL_ID = "eleven_ttv_v3"
CONVAI_LLM = "claude-sonnet-4-6"  # Same family as the Bedrock primary slot.

# Boost Scribe on coaching terms so "HRV" / "readiness" survive noisy mics.
ASR_KEYWORDS = [
    "ARIA",
    "Forge",
    "HRV",
    "readiness",
    "VO2",
    "REM",
    "zone two",
    "RPE",
    "hydration",
    "luteal",
    "follicular",
]

# Coach-shaped tags only. Theatrical tags would fight the design prompt.
EXPRESSIVE_TAGS = [
    {"tag": "warm", "description": "Close, unhurried, in the room."},
    {"tag": "focused", "description": "One next move, not a pep talk."},
    {"tag": "dry", "description": "Slight smile, no breathy narrator."},
]


HttpFn = Callable[[str, str, dict[str, str], bytes | None], tuple[int, dict[str, Any]]]


def _headers(api_key: str) -> dict[str, str]:
    return {
        "xi-api-key": api_key,
        "accept": "application/json",
        "content-type": "application/json",
    }


def _stdlib_http(
    method: str, url: str, headers: dict[str, str], body: bytes | None
) -> tuple[int, dict[str, Any]]:
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            raw = response.read().decode("utf-8")
            payload = json.loads(raw) if raw else {}
            if not isinstance(payload, dict):
                payload = {"value": payload}
            return int(response.status), payload
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            payload = json.loads(raw) if raw else {}
        except json.JSONDecodeError:
            payload = {"message": raw[:400]}
        if not isinstance(payload, dict):
            payload = {"message": raw[:400]}
        return int(exc.code), payload


def credentials(*, get_secret_value=None) -> dict[str, str]:
    return load_ai_provider_secret(get_secret_value=get_secret_value)


def require_api_key(*, get_secret_value=None) -> str:
    key = credentials(get_secret_value=get_secret_value).get("ELEVENLABS_API_KEY") or ""
    if not key:
        raise RouteError(
            503,
            "ARIA's designed voice is not configured. Seed ELEVENLABS_API_KEY "
            "in the ai_provider secret. Dummy / Device Hub does not need this.",
            code="elevenlabs_unconfigured",
        )
    return key


def living_context_block(user_id: str, body: dict[str, Any] | None = None) -> str:
    """Same sources ``POST /ai/chat`` uses, compressed for the live mouth."""
    payload = dict(body or {})
    payload["user_id"] = user_id
    context = aria_engine.ARIAContext.from_payload(payload)
    permissions = aria_engine.DataPermissions.from_payload(
        (body or {}).get("permissions")
    )
    sanitized, restricted = aria_engine.apply_permissions(context, permissions)
    memory = ""
    try:
        from services.aria_context import CoachContextEngine

        if permissions.allows("lifestyle"):
            memory = CoachContextEngine().memory_prompt_block(user_id) or ""
    except Exception:  # noqa: BLE001 - context is additive
        memory = ""
    ground = sanitized.user_model_block(restricted)
    return "\n".join(
        part for part in (aria_engine.live_system_prompt(), ground, memory) if part
    )


def mint_signed_url(
    *,
    user_id: str,
    body: dict[str, Any] | None = None,
    http: HttpFn | None = None,
    get_secret_value=None,
) -> dict[str, Any]:
    """Short-lived ConvAI WebSocket URL. The API key does not leave the Lambda."""
    creds = credentials(get_secret_value=get_secret_value)
    key = require_api_key(get_secret_value=get_secret_value)
    agent_id = creds.get("ELEVENLABS_ARIA_AGENT_ID") or ""
    voice_id = creds.get("ELEVENLABS_ARIA_VOICE_ID") or ""
    if not agent_id:
        raise RouteError(
            503,
            "ARIA's ConvAI agent is not saved yet. Run POST /ai/voice/design "
            "once, then store ELEVENLABS_ARIA_AGENT_ID next to the API key.",
            code="elevenlabs_agent_missing",
        )

    query = urllib.parse.urlencode({"agent_id": agent_id})
    url = f"{ELEVEN_API}/v1/convai/conversation/get-signed-url?{query}"
    caller = http or _stdlib_http
    status, payload = caller("GET", url, _headers(key), None)
    if status >= 400:
        raise RouteError(
            503,
            "Could not mint a voice session.",
            code="elevenlabs_token_failed",
        )
    signed = str(payload.get("signed_url") or payload.get("token") or "")
    if not signed:
        raise RouteError(
            503,
            "Could not mint a voice session.",
            code="elevenlabs_token_failed",
        )
    if signed == key or key in signed or "xi-api-key" in signed.lower():
        raise RouteError(
            500,
            "Voice bootstrap refused to return the API key.",
            code="elevenlabs_key_leak",
        )
    return {
        "transport": "live",
        "signed_url": signed,
        "conversation_id": payload.get("conversation_id"),
        "voice_name": ARIA_VOICE_NAME,
        "voice_id": voice_id or None,
        "sample_rate": 16000,
        "prompt_context": living_context_block(user_id, body),
        "models": live_models(),
    }


def run_tool(body: dict[str, Any], *, user_id: str) -> dict[str, Any]:
    """Ground the live mouth in Forge's brain (``aria_engine``)."""
    message = str(body.get("message") or body.get("query") or "").strip()
    if not message:
        params = body.get("parameters")
        if isinstance(params, dict):
            message = str(params.get("message") or params.get("query") or "").strip()
    if not message:
        raise RouteError(400, "message is required.")

    payload = dict(body)
    payload["user_id"] = user_id
    context = aria_engine.ARIAContext.from_payload(payload)
    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))
    if aria_engine.bedrock_enabled():
        envelope = aria_engine.generate_response_live(
            message, context, permissions=permissions, voice_mode=True
        )
    else:
        envelope = aria_engine.generate_response(
            message, context, permissions=permissions, voice_mode=True
        )
    prose = str(envelope.get("prose_summary") or envelope.get("message") or "").strip()
    envelope["result"] = prose
    envelope["user_id"] = user_id
    return envelope


def design_aria(
    *,
    preview_index: int = 0,
    http: HttpFn | None = None,
    get_secret_value=None,
) -> dict[str, Any]:
    """One-time Voice Design + save + ConvAI agent. Ops/debug only."""
    if os.getenv("FORGE_VOICE_DESIGN_ENABLED", "").strip().lower() not in {
        "1",
        "true",
        "yes",
        "on",
    }:
        from security import is_production_like

        if is_production_like():
            raise RouteError(
                403,
                "Voice design is ops-only. Set FORGE_VOICE_DESIGN_ENABLED to run it.",
                code="voice_design_disabled",
            )

    key = require_api_key(get_secret_value=get_secret_value)
    caller = http or _stdlib_http

    design_body = json.dumps(
        {
            "voice_description": ARIA_DESIGN_PROMPT,
            "text": ARIA_DESIGN_PREVIEW_TEXT,
            "auto_generate_text": False,
            "model_id": VOICE_DESIGN_MODEL_ID,
        }
    ).encode("utf-8")
    status, designed = caller(
        "POST",
        f"{ELEVEN_API}/v1/text-to-voice/design",
        _headers(key),
        design_body,
    )
    if status >= 400:
        raise RouteError(
            503,
            "Voice design failed.",
            code="elevenlabs_design_failed",
        )

    previews = designed.get("previews") or designed.get("generated_voice_previews") or []
    if not isinstance(previews, list) or not previews:
        raise RouteError(503, "Voice design returned no previews.", code="elevenlabs_design_failed")
    idx = max(0, min(preview_index, len(previews) - 1))
    chosen = previews[idx] if isinstance(previews[idx], dict) else {}
    generated_id = str(chosen.get("generated_voice_id") or chosen.get("voice_id") or "")
    if not generated_id:
        raise RouteError(503, "Voice design preview had no id.", code="elevenlabs_design_failed")

    save_body = json.dumps(
        {
            "voice_name": ARIA_VOICE_NAME,
            "voice_description": ARIA_DESIGN_PROMPT,
            "generated_voice_id": generated_id,
        }
    ).encode("utf-8")
    status, saved = caller(
        "POST",
        f"{ELEVEN_API}/v1/text-to-voice",
        _headers(key),
        save_body,
    )
    if status >= 400:
        raise RouteError(503, "Saving ARIA's voice failed.", code="elevenlabs_design_failed")
    voice_id = str(saved.get("voice_id") or generated_id)

    existing_agent = credentials(get_secret_value=get_secret_value).get(
        "ELEVENLABS_ARIA_AGENT_ID"
    ) or ""
    agent_body = json.dumps(_agent_payload(voice_id)).encode("utf-8")
    if existing_agent:
        status, agent = caller(
            "PATCH",
            f"{ELEVEN_API}/v1/convai/agents/{existing_agent}",
            _headers(key),
            agent_body,
        )
        if status >= 400:
            raise RouteError(
                503,
                "Updating ARIA's ConvAI agent failed.",
                code="elevenlabs_agent_failed",
            )
        agent_id = existing_agent
    else:
        status, agent = caller(
            "POST",
            f"{ELEVEN_API}/v1/convai/agents/create",
            _headers(key),
            agent_body,
        )
        if status >= 400:
            raise RouteError(
                503, "Creating ARIA's ConvAI agent failed.", code="elevenlabs_agent_failed"
            )
        agent_id = str(agent.get("agent_id") or agent.get("id") or "")

    slim_previews = []
    for item in previews:
        if not isinstance(item, dict):
            continue
        slim_previews.append(
            {
                "generated_voice_id": item.get("generated_voice_id") or item.get("voice_id"),
                "duration_secs": item.get("duration_secs"),
                "media_type": item.get("media_type"),
            }
        )

    return {
        "voice_name": ARIA_VOICE_NAME,
        "design_prompt": ARIA_DESIGN_PROMPT,
        "generated_voice_id": generated_id,
        "voice_id": voice_id,
        "agent_id": agent_id,
        "previews": slim_previews,
        "seed_secret": {
            "ELEVENLABS_ARIA_VOICE_ID": voice_id,
            "ELEVENLABS_ARIA_AGENT_ID": agent_id,
        },
        "models": live_models(),
    }


def live_models() -> dict[str, str]:
    return {
        "tts": TTS_MODEL_ID,
        "asr": ASR_PROVIDER,
        "turn": TURN_MODEL,
        "voice_design": VOICE_DESIGN_MODEL_ID,
        "llm": CONVAI_LLM,
    }


def _agent_payload(voice_id: str) -> dict[str, Any]:
    prompt = (
        f"{aria_engine.live_system_prompt()}\n\n"
        "You are speaking, not reading. Always call the forge_coach tool with "
        "the user's latest utterance before you answer, then speak the tool "
        "result in ARIA's voice. Do not invent metrics the tool did not return. "
        "Numbers the tool returns must be spoken as words."
    )
    return {
        "name": ARIA_VOICE_NAME,
        "conversation_config": {
            "asr": {
                "quality": "high",
                "provider": ASR_PROVIDER,
                "user_input_audio_format": "pcm_16000",
                "keywords": list(ASR_KEYWORDS),
            },
            "turn": {
                "turn_model": TURN_MODEL,
                "turn_eagerness": "normal",
            },
            "agent": {
                "prompt": {
                    "prompt": prompt,
                    "llm": CONVAI_LLM,
                    "temperature": 0,
                    "tools": [_forge_coach_tool()],
                },
                "first_message": "",
                "language": "en",
            },
            "tts": {
                "model_id": TTS_MODEL_ID,
                "voice_id": voice_id,
                "agent_output_audio_format": "pcm_16000",
                "expressive_mode": True,
                "suggested_audio_tags": list(EXPRESSIVE_TAGS),
                "text_normalisation_type": "system_prompt",
            },
        },
        "platform_settings": {
            "auth": {"enable_auth": True},
        },
    }


def _forge_coach_tool() -> dict[str, Any]:
    return {
        "type": "client",
        "name": "forge_coach",
        "description": (
            "Ask Forge ARIA's coaching brain about this person's health, plan, "
            "and life. Always call this with the user's latest utterance before answering."
        ),
        "expects_response": True,
        "parameters": {
            "type": "object",
            "properties": {
                "message": {
                    "type": "string",
                    "description": "The user's latest utterance, or the question to ground.",
                }
            },
            "required": ["message"],
        },
    }
