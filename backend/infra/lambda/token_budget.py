"""Per-user daily Bedrock request/token caps.

Caps are config (env). Defaults are conservative so a leaked JWT cannot
run up a Bedrock bill. Set a cap to ``0`` to disable that counter. Reservation
happens *before* Converse using ``max_tokens`` as the output-side estimate;
input tokens are not known until after the call, so this is a ceiling, not a
precise meter. There is no voice-char cap — Kokoro is on-device.
"""

from __future__ import annotations

import os

from responses import RouteError

DEFAULT_DAILY_REQUEST_CAP = 40
DEFAULT_DAILY_TOKEN_CAP = 20_000

_active_user = ""


def set_user(user_id: str | None) -> None:
    """Bind the authenticated principal for this invoke. Lambda is one request
    per execution environment; router worker threads share this value."""
    global _active_user
    _active_user = (user_id or "").strip()


def current_user() -> str:
    return _active_user


def daily_request_cap() -> int:
    return _env_int("ARIA_DAILY_REQUEST_CAP", DEFAULT_DAILY_REQUEST_CAP)


def daily_token_cap() -> int:
    return _env_int("ARIA_DAILY_TOKEN_CAP", DEFAULT_DAILY_TOKEN_CAP)


def reserve(*, tokens: int, user_id: str | None = None) -> None:
    """Raise ``RouteError(429)`` when this call would exceed a daily cap."""
    uid = (user_id or current_user()).strip()
    if not uid:
        return
    request_cap = daily_request_cap()
    token_cap = daily_token_cap()
    if request_cap <= 0 and token_cap <= 0:
        return
    tokens = max(0, int(tokens))
    if token_cap > 0 and tokens > token_cap:
        raise RouteError(
            429,
            "Daily ARIA token budget exceeded.",
            code="aria_daily_token_cap",
        )
    if request_cap > 0:
        _bump(uid, action="aria-daily-requests", delta=1, limit=request_cap, code="aria_daily_request_cap")
    if token_cap > 0 and tokens:
        _bump(uid, action="aria-daily-tokens", delta=tokens, limit=token_cap, code="aria_daily_token_cap")


def _env_int(name: str, default: int) -> int:
    raw = (os.getenv(name) or "").strip()
    if not raw:
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _bump(user_id: str, *, action: str, delta: int, limit: int, code: str) -> None:
    from security import _rate_window
    from storage import dynamodb
    from storage.keys import rate_limit_key

    window_id, ttl = _rate_window(hours=24)
    bucket = f"{action}:{window_id}"
    key = rate_limit_key(user_id, bucket)
    room = limit - delta
    try:
        dynamodb.update_item(
            key["pk"],
            key["sk"],
            {
                "action": action,
                "window": bucket,
                "entity_type": "rate_limit",
                "ttl": ttl,
            },
            add={"count": delta},
            condition_expression="attribute_not_exists(#c) OR #c <= :room",
            expression_attribute_names={"#c": "count"},
            expression_attribute_values={":room": room},
        )
    except dynamodb.ConditionalCheckFailed as exc:
        raise RouteError(429, "Daily ARIA usage budget exceeded.", code=code) from exc
