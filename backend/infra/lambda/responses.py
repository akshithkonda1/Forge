from __future__ import annotations

import base64
import json


class RouteError(Exception):
    def __init__(self, status_code: int, message: str, code: str | None = None) -> None:
        super().__init__(message)
        self.status_code = status_code
        self.message = message
        self.code = code

    def to_response(self) -> dict:
        body: dict = {"message": self.message}
        if self.code:
            body["code"] = self.code
        return body


def ok(body: dict) -> dict:
    return _build(200, body)


def ok_bytes(data: bytes, *, content_type: str = "audio/mpeg") -> dict:
    """API Gateway HTTP API binary response.

    Lambda's JSON event protocol cannot carry raw bytes, so the body is
    base64 and ``isBase64Encoded`` is true — API Gateway decodes that to
    ``audio/mpeg`` for the client. No existing route returned binary;
    this is the APIGW pattern rather than a JSON/base64 envelope.
    """
    if not isinstance(data, (bytes, bytearray)):
        raise TypeError("ok_bytes requires raw bytes")
    return {
        "statusCode": 200,
        "headers": {"content-type": content_type},
        "body": base64.b64encode(bytes(data)).decode("ascii"),
        "isBase64Encoded": True,
    }


def created(body: dict) -> dict:
    return _build(201, body)


def not_found(method: str, path: str) -> dict:
    return _build(404, {"message": "Route is not implemented.", "method": method, "path": path})


def error_response(exc: RouteError) -> dict:
    return _build(exc.status_code, exc.to_response())


def _build(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(body),
    }
