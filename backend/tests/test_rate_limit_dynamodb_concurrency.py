"""Per-user rate limiter on the DynamoDB path, under concurrency.

The k6 Dummy loadtest only exercised ``storage.dynamodb._local_store`` because
``APP_DATA_TABLE_NAME`` was unset. Deployed Lambda sets that env var
(``backend/infra/main.tf:548``), so production uses DynamoDB.

``enforce_user_rate_limit`` currently does a non-atomic read-then-write
(``backend/infra/lambda/security.py:275`` ``get_item``, then
``security.py:279`` ``put_item``). There is no ``ConditionExpression`` and no
atomic ``UpdateItem`` ADD. moto serializes Dynamo calls in-process, which can
hide that race — so the concurrent test interlocks every storage get before
any storage write. If the increment is later made atomic, that interlock is a
no-op (no get happens, or the write itself is conditional) and the test must
pass for the right reason: exactly ``limit`` admissions.

Never calls Bedrock or ElevenLabs. Non-DynamoDB boto3 clients fail closed.
"""

from __future__ import annotations

import os
import threading
import unittest
from typing import Any, Callable
from unittest.mock import patch

# Dummy AWS + provider kill-switches before any boto3 / limiter import.
os.environ["AWS_ACCESS_KEY_ID"] = "testing"
os.environ["AWS_SECRET_ACCESS_KEY"] = "testing"
os.environ["AWS_SECURITY_TOKEN"] = "testing"
os.environ["AWS_SESSION_TOKEN"] = "testing"
os.environ["AWS_DEFAULT_REGION"] = "us-east-1"
os.environ["AWS_REGION"] = "us-east-1"
os.environ["AWS_EC2_METADATA_DISABLED"] = "true"
os.environ["ARIA_BEDROCK_ENABLED"] = "false"
os.environ["ARIA_VOICE_ENABLED"] = "false"

def _import_moto_mock_aws():
    """Load moto without letting Lambda ``responses.py`` shadow PyPI ``responses``.

    ``_bootstrap`` puts ``backend/infra/lambda`` on ``sys.path``. That folder
    ships a local ``responses`` module (HTTP helpers). moto imports the PyPI
    package of the same name; if the Lambda path is first, moto crashes.
    """
    import sys
    from pathlib import Path

    lambda_dir = str((Path(__file__).resolve().parents[1] / "infra" / "lambda").resolve())
    saved_path = sys.path[:]
    sys.path = [p for p in sys.path if str(Path(p).resolve()) != lambda_dir]
    prior_responses = sys.modules.get("responses")
    sys.modules.pop("responses", None)
    try:
        from moto import mock_aws as _mock_aws

        return _mock_aws
    finally:
        sys.path[:] = saved_path
        # Evict PyPI ``responses`` so later Lambda imports keep the local module.
        sys.modules.pop("responses", None)
        if prior_responses is not None:
            sys.modules["responses"] = prior_responses


try:
    mock_aws = _import_moto_mock_aws()
except ImportError:  # pragma: no cover - CI installs backend/requirements-dev.txt
    mock_aws = None  # type: ignore[misc, assignment]

import _bootstrap  # noqa: E402, F401

from security import _rate_window_id, enforce_user_rate_limit  # noqa: E402
from storage import dynamodb  # noqa: E402
from storage.keys import rate_limit_key  # noqa: E402

try:
    import pytest
except ImportError:  # pragma: no cover
    pytest = None  # type: ignore[misc, assignment]


TABLE_NAME = "forge-ci-app-data"
REGION = "us-east-1"
LIMIT = 60
WORKERS = 200
ACTION = "aria-chat"

_XFAIL_REASON = (
    "read-then-write increment at backend/infra/lambda/security.py:275 "
    "(dynamodb.get_item) then security.py:279 (dynamodb.put_item); "
    "no ConditionExpression, no UpdateItem ADD — concurrent containers over-admit"
)


def _strict_xfail(reason: str) -> Callable[[Callable[..., Any]], Callable[..., Any]]:
    """unittest.expectedFailure + pytest.mark.xfail(strict=True) when pytest exists."""

    def decorator(fn: Callable[..., Any]) -> Callable[..., Any]:
        wrapped = unittest.expectedFailure(fn)
        if pytest is not None:
            wrapped = pytest.mark.xfail(strict=True, reason=reason)(wrapped)
        return wrapped

    return decorator


class _ReadThenWriteInterlock:
    """Force every storage get to finish before any storage write.

    Read-then-write: all workers observe the same snapshot, then all write —
    over-admission is deterministic even though moto serializes each call.

    Atomic UpdateItem (no get, or a conditional increment): ``_any_read`` stays
    unset, writes are not delayed, and moto's per-call serialization of ADD /
    ConditionExpression still admits exactly ``limit``.
    """

    def __init__(self, workers: int) -> None:
        self.workers = workers
        self._reads = 0
        self._lock = threading.Lock()
        self._any_read = threading.Event()
        self._all_reads_done = threading.Event()

    def wrap_get(self, fn: Callable[..., Any]) -> Callable[..., Any]:
        def wrapped(*args: Any, **kwargs: Any) -> Any:
            item = fn(*args, **kwargs)
            self._any_read.set()
            with self._lock:
                self._reads += 1
                if self._reads >= self.workers:
                    self._all_reads_done.set()
            if not self._all_reads_done.wait(timeout=60):
                raise TimeoutError("rate-limit readers did not rendezvous")
            return item

        return wrapped

    def wrap_write(self, fn: Callable[..., Any]) -> Callable[..., Any]:
        def wrapped(*args: Any, **kwargs: Any) -> Any:
            if self._any_read.is_set():
                if not self._all_reads_done.wait(timeout=60):
                    raise TimeoutError("rate-limit writes released before all reads")
            return fn(*args, **kwargs)

        return wrapped


def _guarded_boto3_factory(original: Callable[..., Any]) -> Callable[..., Any]:
    def guarded(service_name: str, *args: Any, **kwargs: Any) -> Any:
        if service_name != "dynamodb":
            raise RuntimeError(
                f"boto3 {service_name!r} is forbidden in the DynamoDB rate-limit "
                "concurrency test (Bedrock/ElevenLabs/other AWS must not be called)"
            )
        return original(service_name, *args, **kwargs)

    return guarded


def _create_app_data_table() -> None:
    import boto3

    client = boto3.client("dynamodb", region_name=REGION)
    client.create_table(
        TableName=TABLE_NAME,
        KeySchema=[
            {"AttributeName": "pk", "KeyType": "HASH"},
            {"AttributeName": "sk", "KeyType": "RANGE"},
        ],
        AttributeDefinitions=[
            {"AttributeName": "pk", "AttributeType": "S"},
            {"AttributeName": "sk", "AttributeType": "S"},
        ],
        BillingMode="PAY_PER_REQUEST",
    )
    client.update_time_to_live(
        TableName=TABLE_NAME,
        TimeToLiveSpecification={"Enabled": True, "AttributeName": "ttl"},
    )


def _fire_limiter(
    *,
    user_id: str,
    n: int,
    limit: int = LIMIT,
    action: str = ACTION,
    interlock: bool = False,
) -> tuple[int, int, list[BaseException]]:
    """Release ``n`` threads at once. Each constructs its own DynamoDB resource."""
    import boto3

    start = threading.Barrier(n, timeout=60)
    admitted = 0
    rejected = 0
    errors: list[BaseException] = []
    lock = threading.Lock()

    def worker() -> None:
        nonlocal admitted, rejected
        # Fresh client per worker, matching a separate Lambda container.
        boto3.resource("dynamodb", region_name=REGION)
        start.wait()
        try:
            enforce_user_rate_limit(user_id, action=action, limit=limit, window_hours=1)
            with lock:
                admitted += 1
        except PermissionError:
            with lock:
                rejected += 1
        except BaseException as exc:  # noqa: BLE001 — surface unexpected failures
            with lock:
                errors.append(exc)

    gate = _ReadThenWriteInterlock(n) if interlock else None
    patches: list[Any] = []
    if gate is not None:
        patches = [
            patch.object(dynamodb, "get_item", gate.wrap_get(dynamodb.get_item)),
            patch.object(dynamodb, "put_item", gate.wrap_write(dynamodb.put_item)),
            patch.object(dynamodb, "update_item", gate.wrap_write(dynamodb.update_item)),
        ]
        for p in patches:
            p.start()
    try:
        threads = [threading.Thread(target=worker) for _ in range(n)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(timeout=90)
            if t.is_alive():
                errors.append(TimeoutError("rate-limit worker did not finish"))
    finally:
        for p in reversed(patches):
            p.stop()

    return admitted, rejected, errors


def _stored_rate_limit_item(user_id: str, action: str = ACTION) -> dict[str, Any] | None:
    bucket = f"{action}:{_rate_window_id(hours=1)}"
    key = rate_limit_key(user_id, bucket)
    return dynamodb.get_item(key["pk"], key["sk"])


@unittest.skipUnless(mock_aws is not None, "moto required (backend/requirements-dev.txt)")
class DynamoDBRateLimitConcurrencyTests(unittest.TestCase):
    def setUp(self) -> None:
        self._aws = mock_aws()
        self._aws.start()
        self.addCleanup(self._aws.stop)

        previous = os.environ.get("APP_DATA_TABLE_NAME")

        def _restore_table_env() -> None:
            if previous is None:
                os.environ.pop("APP_DATA_TABLE_NAME", None)
            else:
                os.environ["APP_DATA_TABLE_NAME"] = previous

        os.environ["APP_DATA_TABLE_NAME"] = TABLE_NAME
        self.addCleanup(_restore_table_env)

        table_patch = patch.object(dynamodb, "_TABLE_NAME", TABLE_NAME)
        table_patch.start()
        self.addCleanup(table_patch.stop)

        import boto3

        client_patch = patch.object(boto3, "client", _guarded_boto3_factory(boto3.client))
        resource_patch = patch.object(boto3, "resource", _guarded_boto3_factory(boto3.resource))
        client_patch.start()
        resource_patch.start()
        self.addCleanup(resource_patch.stop)
        self.addCleanup(client_patch.stop)

        _create_app_data_table()

    def test_sequential_dynamodb_path_admits_exactly_limit(self) -> None:
        uid = "rate-ddb-seq"
        admitted = 0
        for _ in range(LIMIT + 20):
            try:
                enforce_user_rate_limit(uid, action=ACTION, limit=LIMIT, window_hours=1)
                admitted += 1
            except PermissionError:
                pass
        self.assertEqual(admitted, LIMIT)

    def test_different_users_do_not_share_counters(self) -> None:
        user_a = "rate-ddb-user-a"
        user_b = "rate-ddb-user-b"
        for _ in range(LIMIT):
            enforce_user_rate_limit(user_a, action=ACTION, limit=LIMIT, window_hours=1)
        with self.assertRaises(PermissionError):
            enforce_user_rate_limit(user_a, action=ACTION, limit=LIMIT, window_hours=1)
        enforce_user_rate_limit(user_b, action=ACTION, limit=LIMIT, window_hours=1)
        item_a = _stored_rate_limit_item(user_a)
        item_b = _stored_rate_limit_item(user_b)
        self.assertIsNotNone(item_a)
        self.assertIsNotNone(item_b)
        self.assertEqual(int(item_a["count"]), LIMIT)
        self.assertEqual(int(item_b["count"]), 1)
        self.assertEqual(item_a["pk"], f"USER#{user_a}")
        self.assertEqual(item_b["pk"], f"USER#{user_b}")

    def test_window_key_and_ttl_attribute_written(self) -> None:
        uid = "rate-ddb-window"
        enforce_user_rate_limit(uid, action=ACTION, limit=LIMIT, window_hours=1)
        bucket = f"{ACTION}:{_rate_window_id(hours=1)}"
        key = rate_limit_key(uid, bucket)
        item = dynamodb.get_item(key["pk"], key["sk"])
        self.assertIsNotNone(item)
        self.assertEqual(item["pk"], key["pk"])
        self.assertEqual(item["sk"], key["sk"])
        self.assertEqual(item["sk"], f"RATELIMIT#{bucket}")
        self.assertEqual(item["window"], bucket)
        self.assertEqual(item["action"], ACTION)
        self.assertEqual(item["entity_type"], "rate_limit")
        self.assertEqual(int(item["count"]), 1)
        # Table TTL attribute is ``ttl`` (backend/infra/main.tf:366-368).
        # The current put_item payload at security.py:279-287 does not set it;
        # when present (a later increment that adds expiry), require a real epoch.
        if item.get("ttl") is not None:
            self.assertGreater(int(item["ttl"]), 0)

    @_strict_xfail(_XFAIL_REASON)
    def test_concurrent_same_user_admits_exactly_limit(self) -> None:
        uid = "rate-ddb-concurrent"
        admitted, rejected, errors = _fire_limiter(
            user_id=uid,
            n=WORKERS,
            limit=LIMIT,
            interlock=True,
        )
        self.assertEqual(errors, [], f"unexpected worker errors: {errors!r}")
        self.assertEqual(
            admitted,
            LIMIT,
            f"admitted {admitted}/{WORKERS} (rejected {rejected}); "
            f"expected exactly {LIMIT} on the DynamoDB path",
        )
        self.assertEqual(rejected, WORKERS - LIMIT)


if __name__ == "__main__":
    unittest.main()
