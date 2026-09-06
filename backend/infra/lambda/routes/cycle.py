from __future__ import annotations

import os
import re
import uuid
from datetime import datetime, timedelta, timezone

from responses import RouteError, ok

# Keep the object tiny so a leaked URL is a day of storage, not a warehouse.
_MAX_PDF_BYTES = 2 * 1024 * 1024
_PUT_EXPIRES = 15 * 60
_GET_EXPIRES = 24 * 60 * 60
_PREFIX = "cycle-reports/"
_SAFE_USER = re.compile(r"[^A-Za-z0-9._-]+")


def handle_post_cycle_report_upload(
    user_id: str,
    body: dict,
    *,
    s3_client=None,
    bucket_name: str | None = None,
    now: datetime | None = None,
) -> dict:
    """Mint a presigned PUT/GET for an on-device Apple Cycle PDF.

    The Lambda never receives the PDF. Dynamo is not written. Lifecycle on
    ``cycle-reports/`` expires the object so this stays cheap as usage grows.
    """
    content_type = (body.get("contentType") or "").strip() or "application/pdf"
    if content_type != "application/pdf":
        raise RouteError(400, "Only application/pdf is accepted.")

    try:
        byte_length = int(body.get("byteLength") or 0)
    except (TypeError, ValueError) as exc:
        raise RouteError(400, "byteLength must be an integer.") from exc
    if byte_length <= 0 or byte_length > _MAX_PDF_BYTES:
        raise RouteError(400, f"PDF must be between 1 and {_MAX_PDF_BYTES} bytes.")

    bucket = bucket_name or os.getenv("UPLOADS_BUCKET_NAME")
    if not bucket:
        raise RouteError(
            503,
            "Temporary links are unavailable. Share the PDF from this iPhone.",
            code="uploads_unconfigured",
        )

    client = s3_client or _s3_client()
    safe_user = _SAFE_USER.sub("-", user_id)[:64] or "user"
    key = f"{_PREFIX}{safe_user}/{uuid.uuid4().hex}.pdf"
    stamp = now or datetime.now(timezone.utc)
    expires_at = stamp + timedelta(seconds=_GET_EXPIRES)

    put_url = client.generate_presigned_url(
        "put_object",
        Params={
            "Bucket": bucket,
            "Key": key,
            "ContentType": "application/pdf",
        },
        ExpiresIn=_PUT_EXPIRES,
    )
    get_url = client.generate_presigned_url(
        "get_object",
        Params={
            "Bucket": bucket,
            "Key": key,
            "ResponseContentDisposition": 'attachment; filename="forge-cycle-report.pdf"',
            "ResponseContentType": "application/pdf",
        },
        ExpiresIn=_GET_EXPIRES,
    )

    return ok(
        {
            "putUrl": put_url,
            "getUrl": get_url,
            "expiresAt": expires_at.replace(microsecond=0).isoformat().replace("+00:00", "Z"),
            "objectKey": key,
            "expiresInSeconds": _GET_EXPIRES,
        }
    )


def _s3_client():
    try:
        import boto3
    except ModuleNotFoundError as exc:
        raise RouteError(
            503,
            "Temporary links are unavailable. Share the PDF from this iPhone.",
            code="s3_unavailable",
        ) from exc
    region = os.getenv("AWS_REGION") or os.getenv("AWS_DEFAULT_REGION") or "us-east-1"
    return boto3.client("s3", region_name=region)
