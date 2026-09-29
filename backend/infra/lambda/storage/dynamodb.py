from __future__ import annotations

import os
import re
import threading
from typing import Any

_TABLE_NAME = os.getenv("APP_DATA_TABLE_NAME")

# In-memory store used when no DynamoDB table is configured (local dev / tests).
_local_store: dict[str, dict] = {}
_local_lock = threading.Lock()

_ATTR_NOT_EXISTS = re.compile(r"attribute_not_exists\(\s*([^)]+?)\s*\)\s*$", re.I)
_LT = re.compile(r"(\S+)\s*<\s*(\S+)\s*$")


class ConditionalCheckFailed(Exception):
    """Raised when an UpdateItem condition fails (local store or DynamoDB)."""


def _get_table():
    import boto3  # type: ignore[import]
    dynamodb = boto3.resource("dynamodb")
    return dynamodb.Table(_TABLE_NAME)


def _local_composite(pk: str, sk: str) -> str:
    return f"{pk}|{sk}"


def _resolve_name(token: str, names: dict[str, str]) -> str:
    token = token.strip()
    return names.get(token, token.lstrip("#"))


def _local_condition_holds(
    item: dict[str, Any],
    expression: str,
    names: dict[str, str],
    values: dict[str, Any],
) -> bool:
    """Evaluate the small Dynamo condition subset Forge actually uses."""
    clauses = re.split(r"\s+OR\s+", expression.strip(), flags=re.I)
    return any(
        _local_clause_holds(item, clause.strip(), names, values) for clause in clauses
    )


def _local_clause_holds(
    item: dict[str, Any],
    clause: str,
    names: dict[str, str],
    values: dict[str, Any],
) -> bool:
    match = _ATTR_NOT_EXISTS.fullmatch(clause)
    if match:
        return _resolve_name(match.group(1), names) not in item
    match = _LT.fullmatch(clause)
    if match:
        field = _resolve_name(match.group(1), names)
        bound_token = match.group(2)
        if bound_token not in values:
            raise KeyError(bound_token)
        if field not in item:
            return False
        return item[field] < values[bound_token]
    raise ValueError(f"Unsupported local condition clause: {clause}")


def _is_conditional_check_failed(exc: BaseException) -> bool:
    response = getattr(exc, "response", None) or {}
    code = (response.get("Error") or {}).get("Code")
    return code == "ConditionalCheckFailedException"


def get_item(pk: str, sk: str) -> dict | None:
    if not _TABLE_NAME:
        with _local_lock:
            return _local_store.get(_local_composite(pk, sk))
    table = _get_table()
    result = table.get_item(Key={"pk": pk, "sk": sk})
    return result.get("Item")


def put_item(item: dict[str, Any]) -> None:
    if not _TABLE_NAME:
        key = _local_composite(item["pk"], item["sk"])
        with _local_lock:
            _local_store[key] = dict(item)
        return
    table = _get_table()
    table.put_item(Item=item)


def update_item(
    pk: str,
    sk: str,
    patch: dict[str, Any],
    *,
    add: dict[str, Any] | None = None,
    condition_expression: str | None = None,
    expression_attribute_names: dict[str, str] | None = None,
    expression_attribute_values: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Field-level SET/ADD update, not a read-modify-write PutItem.

    A caller that reads the full item, merges a patch in memory, and writes
    the whole thing back loses data under concurrency: two callers patching
    different fields both read the same snapshot, and whichever writes
    second silently discards the first's change even though the first
    request already returned success. SET-ing only the patched fields makes
    each field's write independent of every other field's — there is no
    snapshot to go stale. ADD is atomic on Dynamo (and under the local
    store lock). Creates the item if it doesn't exist yet (DynamoDB
    UpdateItem upserts) unless a condition fails. Returns the item's full
    attributes after the write.

    ``condition_expression`` uses DynamoDB syntax. Names/values from
    ``expression_attribute_names`` / ``expression_attribute_values`` are
    merged with internally generated aliases (``#fN``/``:vN`` for SET,
    ``#aN``/``:aN`` for ADD). Reserved words such as ``count`` and ``ttl``
    must be passed through those aliases. A failed condition raises
    ``ConditionalCheckFailed``.
    """
    fields = {k: v for k, v in patch.items() if k not in ("pk", "sk")}
    add_fields = dict(add or {})
    extra_names = dict(expression_attribute_names or {})
    extra_values = dict(expression_attribute_values or {})

    if not _TABLE_NAME:
        with _local_lock:
            key = _local_composite(pk, sk)
            stored = _local_store.get(key)
            current = dict(stored or {"pk": pk, "sk": sk})
            if condition_expression and not _local_condition_holds(
                current, condition_expression, extra_names, extra_values
            ):
                raise ConditionalCheckFailed("The conditional request failed")
            if not fields and not add_fields:
                return current
            for field_name, delta in add_fields.items():
                current[field_name] = int(current.get(field_name) or 0) + int(delta)
            current.update(fields)
            _local_store[key] = current
            return dict(current)

    if not fields and not add_fields:
        return get_item(pk, sk) or {"pk": pk, "sk": sk}

    # Every attribute name goes through an ExpressionAttributeNames alias
    # rather than being inlined — DynamoDB reserves a long list of bare
    # words ("name", "date", "status", "count", "ttl", ...) that real Forge
    # field names can collide with, and an alias sidesteps that entirely
    # rather than trying to enumerate which names are currently safe.
    update_parts: list[str] = []
    attr_names: dict[str, str] = dict(extra_names)
    attr_values: dict[str, Any] = dict(extra_values)

    if add_fields:
        add_tokens: list[str] = []
        for index, (field_name, value) in enumerate(add_fields.items()):
            name_token = f"#a{index}"
            value_token = f":a{index}"
            add_tokens.append(f"{name_token} {value_token}")
            attr_names[name_token] = field_name
            attr_values[value_token] = value
        update_parts.append("ADD " + ", ".join(add_tokens))

    if fields:
        set_tokens: list[str] = []
        for index, (field_name, value) in enumerate(fields.items()):
            name_token = f"#f{index}"
            value_token = f":v{index}"
            set_tokens.append(f"{name_token} = {value_token}")
            attr_names[name_token] = field_name
            attr_values[value_token] = value
        update_parts.append("SET " + ", ".join(set_tokens))

    kwargs: dict[str, Any] = {
        "Key": {"pk": pk, "sk": sk},
        "UpdateExpression": " ".join(update_parts),
        "ReturnValues": "ALL_NEW",
    }
    if attr_names:
        kwargs["ExpressionAttributeNames"] = attr_names
    if attr_values:
        kwargs["ExpressionAttributeValues"] = attr_values
    if condition_expression:
        kwargs["ConditionExpression"] = condition_expression

    table = _get_table()
    try:
        result = table.update_item(**kwargs)
    except Exception as exc:
        if _is_conditional_check_failed(exc):
            raise ConditionalCheckFailed("The conditional request failed") from exc
        raise
    return dict(result.get("Attributes") or {})


def delete_item(pk: str, sk: str) -> None:
    if not _TABLE_NAME:
        with _local_lock:
            _local_store.pop(_local_composite(pk, sk), None)
        return
    table = _get_table()
    table.delete_item(Key={"pk": pk, "sk": sk})


def query_prefix(pk: str, sk_prefix: str) -> list[dict]:
    """Return all items whose sk starts with sk_prefix, sorted ascending by sk."""
    if not _TABLE_NAME:
        with _local_lock:
            results = [
                v
                for k, v in list(_local_store.items())
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
        with _local_lock:
            results = [
                v
                for k, v in list(_local_store.items())
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
    with _local_lock:
        _local_store.clear()
