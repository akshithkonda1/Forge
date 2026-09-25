"""POST /ingest/url — authenticated fetch-and-extract. No Bedrock."""

from __future__ import annotations

from typing import Any, Callable

from responses import RouteError, ok
from security import (
    MAX_CHAT_MESSAGE_CHARS,
    enforce_user_rate_limit,
    sanitize_user_text,
    validate_user_id,
)
from services import editable_memory
from services.aria_context import CoachContextEngine
from services import web_ingest
from routes.aria import sanitize_user_memory_text

_context = CoachContextEngine()

IngestFn = Callable[..., web_ingest.IngestResult]


def _sanitize_line(text: str) -> str:
    return web_ingest.scrub_untrusted_page_text(
        sanitize_user_memory_text(
            sanitize_user_text(str(text or ""), max_chars=MAX_CHAT_MESSAGE_CHARS)
        )
    )


def _sanitize_extract(extract: dict[str, Any]) -> dict[str, Any]:
    """Walk the typed extract and run Rowan/chat sanitizers on strings."""
    cleaned: dict[str, Any] = {}
    for key, value in extract.items():
        cleaned[key] = _sanitize_value(value)
    return cleaned


def _sanitize_value(value: Any) -> Any:
    if isinstance(value, str):
        return _sanitize_line(value)
    if isinstance(value, list):
        out = []
        for item in value:
            cleaned = _sanitize_value(item)
            if cleaned == "" or cleaned == [] or cleaned == {}:
                continue
            out.append(cleaned)
        return out
    if isinstance(value, dict):
        cleaned: dict[str, Any] = {}
        for key, inner in value.items():
            item = _sanitize_value(inner)
            if item in ("", [], {}):
                continue
            cleaned[key] = item
        return cleaned
    return value


def handle_post_ingest_url(
    user_id: str,
    body: dict[str, Any],
    *,
    ingest_fn: IngestFn | None = None,
) -> dict:
    if not isinstance(body, dict):
        raise RouteError(400, "Request body must be a JSON object.")
    try:
        user_id = validate_user_id(user_id)
    except ValueError as exc:
        raise RouteError(401, "Invalid user.", code="validation_failed") from exc
    url = str(body.get("url") or "").strip()
    persist = body.get("persistMemory") is True
    try:
        enforce_user_rate_limit(user_id, action="ingest-url", limit=20, window_hours=1)
    except ValueError as exc:
        raise RouteError(401, "Invalid user.", code="validation_failed") from exc
    except PermissionError as exc:
        raise RouteError(429, str(exc) or "Too many requests.", code="rate_limited") from exc

    run = ingest_fn or web_ingest.ingest_url
    result = run(url)
    extract = _sanitize_extract(result.extract)
    readable = _sanitize_line(result.readable_text)
    title = _sanitize_line(result.title) or extract.get("name") or extract.get("headline") or extract.get("title") or "Untitled"
    aria_feed = web_ingest.build_aria_feed(
        kind=result.kind,
        extract=extract,
        readable_text=readable,
        source_url=result.final_url,
        sanitize=_sanitize_line,
    )
    candidate_text = web_ingest.prepare_memory_note(
        _sanitize_line(
            web_ingest.memory_candidate_text(kind=result.kind, extract=extract, aria_feed=aria_feed)
        ),
        source_url=result.final_url,
    )
    folder = web_ingest.memory_folder_for(result.kind)
    category = web_ingest.memory_category_for(result.kind)
    persisted = False
    if persist and candidate_text:
        settings = editable_memory.get_settings(user_id)
        folder_ok = folder not in (settings.disabled_folders or [])
        if editable_memory.auto_ingest_allowed(settings) and folder_ok:
            item = _context.remember_short_term(
                user_id,
                candidate_text,
                source="web",
                category=category,
            )
            persisted = item is not None
    memory_candidate = {
        "text": candidate_text,
        "category": category,
        "folder": folder,
        "persisted": persisted,
    }
    payload = result.to_response(aria_feed=aria_feed, memory_candidate=memory_candidate)
    payload["title"] = title
    payload["extract"] = extract
    payload["readableText"] = readable
    return ok(payload)
