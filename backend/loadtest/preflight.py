"""Shared refuse-to-run checks for the Dummy loadtest harness."""

from __future__ import annotations

from urllib.parse import urlparse

LOOPBACK_HOSTS = frozenset({"127.0.0.1", "localhost", "::1"})
REQUIRED_FALSE = ("ARIA_BEDROCK_ENABLED", "ARIA_VOICE_ENABLED")


def assert_disabled_flags(env: dict[str, str]) -> None:
    """Require the live flags to be the string ``false``. Unset is not enough."""
    missing = [name for name in REQUIRED_FALSE if env.get(name) != "false"]
    if missing:
        raise ValueError(
            "loadtest refuses to run unless "
            + " and ".join(f"{name}=false" for name in REQUIRED_FALSE)
            + f" (bad: {', '.join(missing)})"
        )


def assert_loopback_host(host: str) -> None:
    cleaned = (host or "").strip().lower().strip("[]")
    if cleaned not in LOOPBACK_HOSTS:
        raise ValueError(
            f"loadtest host must be localhost/127.0.0.1, got {host!r}"
        )


def assert_local_base_url(raw: str) -> str:
    if not raw or not raw.strip():
        raise ValueError("BASE_URL is required and must be a localhost URL")
    parsed = urlparse(raw.strip())
    if parsed.scheme not in {"http", "https"}:
        raise ValueError(f"BASE_URL must be http(s), got {raw!r}")
    host = (parsed.hostname or "").strip().lower()
    if host not in LOOPBACK_HOSTS:
        raise ValueError(
            f"BASE_URL must target localhost/127.0.0.1, got host {parsed.hostname!r}"
        )
    return raw.strip().rstrip("/")


def validate_run_env(env: dict[str, str]) -> str:
    """Return the normalized BASE_URL or raise ValueError."""
    assert_disabled_flags(env)
    return assert_local_base_url(env.get("BASE_URL", ""))
