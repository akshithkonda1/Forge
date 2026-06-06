from __future__ import annotations

import json
import os
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from integrations import terra_config

TERRA_API_BASE = os.getenv("TERRA_API_BASE", "https://api.tryterra.co/v2")


class TerraConfigError(RuntimeError):
    pass


class TerraAPIError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


def is_configured() -> bool:
    return terra_config.is_configured()


def _headers() -> dict[str, str]:
    dev_id = terra_config.dev_id()
    api_key = terra_config.api_key()
    if not dev_id or not api_key:
        raise TerraConfigError("Terra API credentials are not configured.")
    return {
        "dev-id": dev_id,
        "x-api-key": api_key,
        "Content-Type": "application/json",
        "Accept": "application/json",
    }


def _request(method: str, path: str, *, params: dict[str, Any] | None = None, body: dict | None = None) -> dict:
    query = f"?{urllib.parse.urlencode(params)}" if params else ""
    url = f"{TERRA_API_BASE}{path}{query}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    request = urllib.request.Request(url, data=data, headers=_headers(), method=method)
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = response.read().decode("utf-8")
            return json.loads(payload) if payload else {}
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise TerraAPIError(exc.code, detail or exc.reason) from exc


def generate_widget_session(
    *,
    reference_id: str,
    success_redirect_url: str,
    failure_redirect_url: str,
    language: str = "en",
) -> dict[str, Any]:
    return _request(
        "POST",
        "/auth/generateWidgetSession",
        body={
            "reference_id": reference_id,
            "auth_success_redirect_url": success_redirect_url,
            "auth_failure_redirect_url": failure_redirect_url,
            "language": language,
        },
    )


def ping_api() -> dict[str, Any]:
    """Lightweight credential probe — non-404 client errors imply bad credentials."""
    try:
        _request("GET", "/userInfo", params={"user_id": "forge-health-probe"})
        return {"ok": True, "message": "ok"}
    except TerraAPIError as exc:
        if exc.status in {400, 404, 422}:
            return {"ok": True, "message": "credentials_accepted"}
        if exc.status in {401, 403}:
            return {"ok": False, "message": "invalid_credentials"}
        return {"ok": False, "message": str(exc)}


def request_historical_data(
    *,
    data_type: str,
    terra_user_id: str,
    start_date: str,
    end_date: str | None = None,
    to_webhook: bool = True,
) -> dict[str, Any]:
    params: dict[str, Any] = {
        "user_id": terra_user_id,
        "start_date": start_date,
        "to_webhook": str(to_webhook).lower(),
    }
    if end_date:
        params["end_date"] = end_date
    return _request("GET", f"/{data_type}", params=params)