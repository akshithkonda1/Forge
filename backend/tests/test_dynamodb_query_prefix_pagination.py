"""BH-06: storage.dynamodb.query_prefix must follow LastEvaluatedKey.

DynamoDB Query returns at most 1 MB per call and sets LastEvaluatedKey when
more items match. query_prefix (storage/dynamodb.py) used to make one call and
return result["Items"], so everything past page 1 was silently dropped. For the
ascending chat thread (routes/chat.py) that means the NEWEST messages vanish.

query_prefix_desc has the same 1 MB cap; fusion METRIC# history uses it.

The table is a fake that pages on its own; no real 1 MB data and no AWS needed.
"""
from __future__ import annotations

import sys
import types
import unittest
from unittest import mock

from _bootstrap import *  # noqa: F401,F403  (puts the Lambda package on sys.path)


def _fake_conditions_module():
    class _Cond:
        def __and__(self, other):
            return self

    class Key:
        def __init__(self, name):
            self.name = name

        def eq(self, _v):
            return _Cond()

        def begins_with(self, _v):
            return _Cond()

    boto3 = types.ModuleType("boto3")
    ddb = types.ModuleType("boto3.dynamodb")
    cond = types.ModuleType("boto3.dynamodb.conditions")
    cond.Key = Key
    boto3.dynamodb = ddb
    ddb.conditions = cond
    return {"boto3": boto3, "boto3.dynamodb": ddb, "boto3.dynamodb.conditions": cond}


class _PagedTable:
    """Serves items one page at a time, like a Query that hit the 1 MB cap."""

    def __init__(self, pages):
        self._pages = pages
        self.calls = []

    def query(self, **kwargs):
        self.calls.append(kwargs)
        start = kwargs.get("ExclusiveStartKey")
        idx = 0 if start is None else start["_page"]
        out = {"Items": list(self._pages[idx])}
        if idx + 1 < len(self._pages):
            last = self._pages[idx][-1]
            out["LastEvaluatedKey"] = {"pk": last["pk"], "sk": last["sk"], "_page": idx + 1}
        return out


PK = "USER#bh06-quin-7f3a"
PREFIX = "CHAT#thread-bh06#MSG#"
PAGE1 = [
    {"pk": PK, "sk": f"{PREFIX}2026-10-28T09:00:0{i}Z", "content": f"older-{i}"}
    for i in range(3)
]
PAGE2 = [
    {"pk": PK, "sk": f"{PREFIX}2026-10-28T09:05:00Z", "content": "NEWEST-bh06-sentinel"},
]

METRIC_PREFIX = "METRIC#"
METRIC_PAGE1 = [
    {"pk": PK, "sk": f"{METRIC_PREFIX}hrv#2026-10-01T0{i}:00:00Z", "content": f"old-metric-{i}"}
    for i in range(3)
]
METRIC_PAGE2 = [
    {"pk": PK, "sk": f"{METRIC_PREFIX}hrv#2026-10-28T09:05:00Z", "content": "NEWEST-metric-bh06"},
]


class QueryPrefixPaginationTests(unittest.TestCase):
    def setUp(self):
        from storage import dynamodb as ddb

        self.ddb = ddb
        self.table = _PagedTable([PAGE1, PAGE2])
        patches = [
            mock.patch.object(ddb, "_TABLE_NAME", "forge-test-bh06"),
            mock.patch.object(ddb, "_get_table", return_value=self.table),
        ]
        try:
            import boto3.dynamodb.conditions  # noqa: F401
        except ImportError:
            patches.append(mock.patch.dict(sys.modules, _fake_conditions_module()))
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def test_query_prefix_returns_items_from_every_page(self):
        items = self.ddb.query_prefix(PK, PREFIX)
        contents = [i["content"] for i in items]
        self.assertIn(
            "NEWEST-bh06-sentinel",
            contents,
            "query_prefix dropped page 2: LastEvaluatedKey was not followed",
        )
        self.assertEqual(len(items), 4)

    def test_query_prefix_passes_exclusive_start_key_on_follow_up(self):
        self.ddb.query_prefix(PK, PREFIX)
        self.assertEqual(len(self.table.calls), 2, "expected a second Query for page 2")
        self.assertEqual(self.table.calls[1]["ExclusiveStartKey"]["_page"], 1)
        self.assertTrue(self.table.calls[1]["ScanIndexForward"])


class QueryPrefixDescPaginationTests(unittest.TestCase):
    def setUp(self):
        from storage import dynamodb as ddb

        self.ddb = ddb
        self.table = _PagedTable([METRIC_PAGE1, METRIC_PAGE2])
        patches = [
            mock.patch.object(ddb, "_TABLE_NAME", "forge-test-bh06-desc"),
            mock.patch.object(ddb, "_get_table", return_value=self.table),
        ]
        try:
            import boto3.dynamodb.conditions  # noqa: F401
        except ImportError:
            patches.append(mock.patch.dict(sys.modules, _fake_conditions_module()))
        for p in patches:
            p.start()
            self.addCleanup(p.stop)

    def test_query_prefix_desc_returns_items_from_every_page(self):
        items = self.ddb.query_prefix_desc(PK, METRIC_PREFIX, limit=100)
        contents = [i["content"] for i in items]
        self.assertIn(
            "NEWEST-metric-bh06",
            contents,
            "query_prefix_desc dropped page 2: LastEvaluatedKey was not followed",
        )
        self.assertEqual(len(items), 4)

    def test_query_prefix_desc_passes_exclusive_start_key_on_follow_up(self):
        self.ddb.query_prefix_desc(PK, METRIC_PREFIX, limit=100)
        self.assertEqual(len(self.table.calls), 2, "expected a second Query for page 2")
        self.assertEqual(self.table.calls[1]["ExclusiveStartKey"]["_page"], 1)
        self.assertFalse(self.table.calls[1]["ScanIndexForward"])


if __name__ == "__main__":
    unittest.main()
