"""Loadtest-only Bedrock / ElevenLabs / Fish Audio tripwire.

Loaded by ``run_server.py`` or ``sitecustomize`` when the Dummy backend is
started in loadtest mode. Production Lambda code is not imported from here
and is not patched unless this module is on the process path.

Any Bedrock client construction or invoke, and any ElevenLabs or Fish Audio
HTTP, raises and increments a counter. The report must show those counters
at 0.
"""

from __future__ import annotations

import builtins
import json
import os
import threading
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


COUNTER_PATH = Path(
    os.environ.get("FORGE_LOADTEST_GUARD_FILE", "/tmp/forge-loadtest-guard.json")
)

_LOCK = threading.Lock()
_INSTALLED = False
_COUNTS = {
    "bedrock_client": 0,
    "bedrock_invoke": 0,
    "elevenlabs_http": 0,
    "elevenlabs_api": 0,
    "fish_audio_http": 0,
    "fish_audio_api": 0,
}

_BEDROCK_SERVICES = frozenset(
    {
        "bedrock",
        "bedrock-runtime",
        "bedrock-agent",
        "bedrock-agent-runtime",
    }
)
_ELEVEN_HOSTS = ("elevenlabs.io", "elevenlabs.com")
_FISH_HOSTS = ("fish.audio",)


class LoadtestGuardError(RuntimeError):
    """Raised when a forbidden live client is constructed or invoked."""


def snapshot() -> dict[str, int]:
    with _LOCK:
        return dict(_COUNTS)


def total() -> int:
    return sum(snapshot().values())


def persist() -> dict[str, int]:
    data = snapshot()
    COUNTER_PATH.parent.mkdir(parents=True, exist_ok=True)
    COUNTER_PATH.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return data


def _bump(key: str) -> None:
    with _LOCK:
        _COUNTS[key] = _COUNTS.get(key, 0) + 1
    persist()


def _host_of(target: Any) -> str:
    if target is None:
        return ""
    raw = target if isinstance(target, str) else getattr(target, "full_url", "") or str(target)
    try:
        return (urlparse(raw).hostname or "").lower()
    except ValueError:
        return str(raw).lower()


def _host_matches(host: str, names: tuple[str, ...]) -> bool:
    return any(host == name or host.endswith("." + name) for name in names)


def _is_eleven_url(target: Any) -> bool:
    return _host_matches(_host_of(target), _ELEVEN_HOSTS)


def _is_fish_url(target: Any) -> bool:
    return _host_matches(_host_of(target), _FISH_HOSTS)


def _is_bedrock_service(name: Any) -> bool:
    return str(name or "").strip().lower() in _BEDROCK_SERVICES


def _wrap_boto3(mod: Any) -> None:
    if getattr(mod, "_forge_loadtest_guarded", False):
        return
    original_client = mod.client

    def client(service_name, *args, **kwargs):  # noqa: ANN001
        if _is_bedrock_service(service_name):
            _bump("bedrock_client")
            raise LoadtestGuardError(
                f"loadtest guard: boto3.client({service_name!r}) is forbidden"
            )
        real = original_client(service_name, *args, **kwargs)
        return _wrap_bedrock_client(real, service_name)

    mod.client = client
    mod._forge_loadtest_guarded = True


def _wrap_bedrock_client(client: Any, service_name: Any) -> Any:
    if not _is_bedrock_service(service_name):
        return client
    # Defense in depth if a caller already held a client reference.
    for method in (
        "converse",
        "converse_stream",
        "invoke_model",
        "invoke_model_with_response_stream",
        "invoke_model_with_bidirectional_stream",
    ):
        if not hasattr(client, method):
            continue

        def boom(*_a: Any, _method: str = method, **_k: Any) -> Any:
            _bump("bedrock_invoke")
            raise LoadtestGuardError(f"loadtest guard: Bedrock {_method} is forbidden")

        setattr(client, method, boom)
    return client


def _wrap_elevenlabs(mod: Any) -> None:
    if getattr(mod, "_forge_loadtest_guarded", False):
        return

    def boom(*_a: Any, **_k: Any) -> Any:
        _bump("elevenlabs_api")
        raise LoadtestGuardError("loadtest guard: ElevenLabs API is forbidden")

    for name in (
        "mint_signed_url",
        "run_tool",
        "design_aria",
        "require_api_key",
        "_stdlib_http",
    ):
        if hasattr(mod, name):
            setattr(mod, name, boom)
    mod._forge_loadtest_guarded = True


def _wrap_fish_audio(mod: Any) -> None:
    if getattr(mod, "_forge_loadtest_guarded", False):
        return

    def boom(*_a: Any, **_k: Any) -> Any:
        _bump("fish_audio_api")
        raise LoadtestGuardError("loadtest guard: Fish Audio API is forbidden")

    for name in (
        "speak",
        "synthesize",
        "require_api_key",
        "_stdlib_http",
    ):
        if hasattr(mod, name):
            setattr(mod, name, boom)
    mod._forge_loadtest_guarded = True


def _wrap_urllib() -> None:
    original_urlopen = urllib.request.urlopen

    def urlopen(url, *args, **kwargs):  # noqa: ANN001
        if _is_eleven_url(url):
            _bump("elevenlabs_http")
            raise LoadtestGuardError(
                f"loadtest guard: HTTP to ElevenLabs is forbidden ({url!r})"
            )
        if _is_fish_url(url):
            _bump("fish_audio_http")
            raise LoadtestGuardError(
                f"loadtest guard: HTTP to Fish Audio is forbidden ({url!r})"
            )
        return original_urlopen(url, *args, **kwargs)

    urllib.request.urlopen = urlopen  # type: ignore[assignment]


_REAL_IMPORT = builtins.__import__


def _import(name, globals=None, locals=None, fromlist=(), level=0):  # noqa: ANN001
    module = _REAL_IMPORT(name, globals, locals, fromlist, level)
    if name == "boto3" or (fromlist and name == "boto3"):
        _wrap_boto3(module)
    if name == "services.elevenlabs_voice" or (
        name == "services" and fromlist and "elevenlabs_voice" in fromlist
    ):
        target = module
        if name == "services" and hasattr(module, "elevenlabs_voice"):
            target = module.elevenlabs_voice
        if getattr(target, "__name__", "") == "services.elevenlabs_voice":
            _wrap_elevenlabs(target)
    if name == "services.fish_audio_voice" or (
        name == "services" and fromlist and "fish_audio_voice" in fromlist
    ):
        target = module
        if name == "services" and hasattr(module, "fish_audio_voice"):
            target = module.fish_audio_voice
        if getattr(target, "__name__", "") == "services.fish_audio_voice":
            _wrap_fish_audio(target)
    if name == "ai_router" and hasattr(module, "BedrockGateway"):
        _wrap_gateway_class(module.BedrockGateway)
    return module


def _wrap_gateway_class(cls: Any) -> None:
    if getattr(cls, "_forge_loadtest_guarded", False):
        return
    original_get = getattr(cls, "_get_bedrock_client", None)
    original_converse = getattr(cls, "converse", None)

    if original_get is not None:

        def _get_bedrock_client(self, *args, **kwargs):  # noqa: ANN001
            _bump("bedrock_client")
            raise LoadtestGuardError(
                "loadtest guard: BedrockGateway client creation is forbidden"
            )

        cls._get_bedrock_client = _get_bedrock_client

    if original_converse is not None:

        def converse(self, *args, **kwargs):  # noqa: ANN001
            _bump("bedrock_invoke")
            raise LoadtestGuardError("loadtest guard: BedrockGateway.converse is forbidden")

        cls.converse = converse
    cls._forge_loadtest_guarded = True


def install() -> None:
    """Idempotent. Safe to call before or after Lambda imports."""
    global _INSTALLED
    if _INSTALLED:
        persist()
        return
    _INSTALLED = True
    persist()
    _wrap_urllib()
    builtins.__import__ = _import
    import sys

    if "boto3" in sys.modules:
        _wrap_boto3(sys.modules["boto3"])
    eleven = sys.modules.get("services.elevenlabs_voice")
    if eleven is not None:
        _wrap_elevenlabs(eleven)
    fish = sys.modules.get("services.fish_audio_voice")
    if fish is not None:
        _wrap_fish_audio(fish)
    ai_router = sys.modules.get("ai_router")
    if ai_router is not None and hasattr(ai_router, "BedrockGateway"):
        _wrap_gateway_class(ai_router.BedrockGateway)
