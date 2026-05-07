from __future__ import annotations

import os
from typing import Any

_TABLE_NAME = os.getenv("APP_DATA_TABLE_NAME")

# In-memory store used when no DynamoDB table is configured (local dev / tests).
_local_store: dict[str, dict] = {}


def _get_table():
    import boto3  # type: ignore[import]
    dynamodb = boto3.resource("dynamodb")
    return dynamodb.Table(_TABLE_NAME)


def _local_composite(pk: str, sk: str) -> str:
    return f"{pk}|{sk}"


def get_item(pk: str, sk: str) -> dict | None:
    if not _TABLE_NAME:
        return _local_store.get(_local_composite(pk, sk))
    table = _get_table()
    result = table.get_item(Key={"pk": pk, "sk": sk})
    return result.get("Item")


def put_item(item: dict[str, Any]) -> None:
    if not _TABLE_NAME:
        key = _local_composite(item["pk"], item["sk"])
        _local_store[key] = dict(item)
        return
    table = _get_table()
    table.put_item(Item=item)


def delete_item(pk: str, sk: str) -> None:
    if not _TABLE_NAME:
        _local_store.pop(_local_composite(pk, sk), None)
        return
    table = _get_table()
    table.delete_item(Key={"pk": pk, "sk": sk})


def query_prefix(pk: str, sk_prefix: str) -> list[dict]:
    """Return all items whose sk starts with sk_prefix, sorted ascending by sk."""
    if not _TABLE_NAME:
        results = [
            v
            for k, v in _local_store.items()
            if k.startswith(f"{pk}|{sk_prefix}")
        ]
        results.sort(key=lambda x: x.get("sk", ""))
        return results

    from boto3.dynamodb.conditions import Key  # type: ignore[import]
    table = _get_table()
    result = table.query(
        KeyConditionExpression=Key("pk").eq(pk) & Key("sk").begins_with(sk_prefix),
        ScanIndexForward=True,
    )
    return result.get("Items", [])


def query_prefix_desc(pk: str, sk_prefix: str, limit: int = 100) -> list[dict]:
    """Return items with sk_prefix sorted descending (newest first)."""
    if not _TABLE_NAME:
        results = [
            v
            for k, v in _local_store.items()
            if k.startswith(f"{pk}|{sk_prefix}")
        ]
        results.sort(key=lambda x: x.get("sk", ""), reverse=True)
        return results[:limit]

    from boto3.dynamodb.conditions import Key  # type: ignore[import]
    table = _get_table()
    result = table.query(
        KeyConditionExpression=Key("pk").eq(pk) & Key("sk").begins_with(sk_prefix),
        ScanIndexForward=False,
        Limit=limit,
    )
    return result.get("Items", [])


def clear_local_store() -> None:
    """Test helper: reset the in-memory store between test runs."""
    _local_store.clear()
