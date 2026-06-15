from __future__ import annotations

import os
from typing import Any

_TABLE_NAME = os.getenv("APP_DATA_TABLE_NAME")
_local_store: dict[str, dict] = {}


def _composite(pk: str, sk: str) -> str:
    return f"{pk}|{sk}"


def _table():
    import boto3  # type: ignore[import]

    return boto3.resource("dynamodb").Table(_TABLE_NAME)


def get_item(pk: str, sk: str) -> dict | None:
    if not _TABLE_NAME:
        return _local_store.get(_composite(pk, sk))
    result = _table().get_item(Key={"pk": pk, "sk": sk})
    return result.get("Item")


def put_item(item: dict[str, Any]) -> None:
    if not _TABLE_NAME:
        _local_store[_composite(item["pk"], item["sk"])] = dict(item)
        return
    _table().put_item(Item=item)


def delete_item(pk: str, sk: str) -> None:
    if not _TABLE_NAME:
        _local_store.pop(_composite(pk, sk), None)
        return
    _table().delete_item(Key={"pk": pk, "sk": sk})


def context_key(user_id: str) -> dict[str, str]:
    return {"pk": f"USER#{user_id}", "sk": "ARIA#CONTEXT"}