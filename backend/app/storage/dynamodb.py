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


def scan_sk(sk: str, *, limit: int = 200) -> list[dict]:
    """Return items with an exact sort key (cross-partition scan)."""
    if not _TABLE_NAME:
        results = [v for v in _local_store.values() if v.get("sk") == sk]
        results.sort(key=lambda item: item.get("pk", ""))
        return results[:limit]

    from boto3.dynamodb.conditions import Attr  # type: ignore[import]

    table = _get_table()
    response = table.scan(FilterExpression=Attr("sk").eq(sk), Limit=limit)
    items = response.get("Items", [])
    while "LastEvaluatedKey" in response and len(items) < limit:
        response = table.scan(
            FilterExpression=Attr("sk").eq(sk),
            ExclusiveStartKey=response["LastEvaluatedKey"],
            Limit=limit - len(items),
        )
        items.extend(response.get("Items", []))
    return items[:limit]


def scan_pk_prefix(pk_prefix: str, *, limit: int = 200) -> list[dict]:
    """Return items whose partition key starts with pk_prefix."""
    if not _TABLE_NAME:
        results = [
            v
            for key, v in _local_store.items()
            if v.get("pk", "").startswith(pk_prefix)
        ]
        results.sort(key=lambda item: item.get("sk", ""))
        return results[:limit]

    from boto3.dynamodb.conditions import Attr  # type: ignore[import]

    table = _get_table()
    response = table.scan(
        FilterExpression=Attr("pk").begins_with(pk_prefix),
        Limit=limit,
    )
    items = response.get("Items", [])
    while "LastEvaluatedKey" in response and len(items) < limit:
        response = table.scan(
            FilterExpression=Attr("pk").begins_with(pk_prefix),
            ExclusiveStartKey=response["LastEvaluatedKey"],
            Limit=limit - len(items),
        )
        items.extend(response.get("Items", []))
    return items[:limit]


def delete_partition(pk: str) -> int:
    """Delete all items in a partition key. Returns count removed."""
    if not _TABLE_NAME:
        keys_to_delete = [k for k, v in _local_store.items() if v.get("pk") == pk]
        for composite in keys_to_delete:
            _local_store.pop(composite, None)
        return len(keys_to_delete)

    from boto3.dynamodb.conditions import Key  # type: ignore[import]

    table = _get_table()
    response = table.query(KeyConditionExpression=Key("pk").eq(pk))
    items = list(response.get("Items", []))
    while "LastEvaluatedKey" in response:
        response = table.query(
            KeyConditionExpression=Key("pk").eq(pk),
            ExclusiveStartKey=response["LastEvaluatedKey"],
        )
        items.extend(response.get("Items", []))

    for item in items:
        table.delete_item(Key={"pk": item["pk"], "sk": item["sk"]})
    return len(items)


def clear_local_store() -> None:
    """Test helper: reset the in-memory store between test runs."""
    _local_store.clear()
