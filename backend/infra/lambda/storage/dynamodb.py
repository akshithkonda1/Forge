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


def update_item(pk: str, sk: str, patch: dict[str, Any]) -> dict[str, Any]:
    """Field-level SET update, not a read-modify-write PutItem.

    A caller that reads the full item, merges a patch in memory, and writes
    the whole thing back loses data under concurrency: two callers patching
    different fields both read the same snapshot, and whichever writes
    second silently discards the first's change even though the first
    request already returned success. SET-ing only the patched fields makes
    each field's write independent of every other field's — there is no
    snapshot to go stale. Creates the item if it doesn't exist yet (DynamoDB
    UpdateItem upserts). Returns the item's full attributes after the write.
    """
    fields = {k: v for k, v in patch.items() if k not in ("pk", "sk")}

    if not _TABLE_NAME:
        key = _local_composite(pk, sk)
        current = dict(_local_store.get(key) or {"pk": pk, "sk": sk})
        current.update(fields)
        _local_store[key] = current
        return current

    if not fields:
        return get_item(pk, sk) or {"pk": pk, "sk": sk}

    # Every attribute name goes through an ExpressionAttributeNames alias
    # rather than being inlined — DynamoDB reserves a long list of bare
    # words ("name", "date", "status", ...) that real Forge field names can
    # collide with, and an alias sidesteps that entirely rather than trying
    # to enumerate which names are currently safe.
    update_expr_parts: list[str] = []
    attr_names: dict[str, str] = {}
    attr_values: dict[str, Any] = {}
    for index, (field_name, value) in enumerate(fields.items()):
        name_token = f"#f{index}"
        value_token = f":v{index}"
        update_expr_parts.append(f"{name_token} = {value_token}")
        attr_names[name_token] = field_name
        attr_values[value_token] = value

    table = _get_table()
    result = table.update_item(
        Key={"pk": pk, "sk": sk},
        UpdateExpression="SET " + ", ".join(update_expr_parts),
        ExpressionAttributeNames=attr_names,
        ExpressionAttributeValues=attr_values,
        ReturnValues="ALL_NEW",
    )
    return dict(result.get("Attributes") or {})


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
