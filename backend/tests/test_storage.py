"""Regression tests for storage.dynamodb.update_item.

PUT /me/profile used to read the full stored item, merge a patch in memory,
and write the whole thing back with put_item. Two callers patching different
fields both read the same pre-update snapshot; whichever wrote second
silently discarded the first's change even though the first request had
already returned success. update_item's field-level SET makes each field's
write independent of every other field's, which these tests prove directly
against the storage layer -- not just "it still works when called back to
back," which a read-modify-write would also pass.
"""

from __future__ import annotations

import threading
import unittest

import _bootstrap  # noqa: F401

from storage import dynamodb  # noqa: E402


class UpdateItemFieldIndependenceTests(unittest.TestCase):
    def setUp(self):
        dynamodb.clear_local_store()

    def test_two_writers_patching_different_fields_both_land(self):
        pk, sk = "USER#race-1", "PROFILE"
        dynamodb.update_item(pk, sk, {"name": "Riley"})
        dynamodb.update_item(pk, sk, {"coachingStyle": "aggressive"})

        item = dynamodb.get_item(pk, sk)
        self.assertEqual(item["name"], "Riley")
        self.assertEqual(item["coachingStyle"], "aggressive")

    def test_true_concurrent_writers_to_different_fields_do_not_lose_either(self):
        # A real read-modify-write PutItem loses one side of this: both
        # threads would read the same starting snapshot, and whichever
        # writes last would persist a full item missing the other thread's
        # field entirely. Sixteen threads released at once via a Barrier so
        # the interleaving is real, not scheduled by test ordering.
        pk, sk = "USER#race-2", "PROFILE"
        thread_count = 16
        barrier = threading.Barrier(thread_count)
        errors: list[Exception] = []

        def writer(index: int) -> None:
            barrier.wait()
            try:
                dynamodb.update_item(pk, sk, {f"field{index}": index})
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=writer, args=(i,)) for i in range(thread_count)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(errors, [])
        item = dynamodb.get_item(pk, sk)
        for i in range(thread_count):
            self.assertEqual(item[f"field{i}"], i, f"field{i} was lost to a concurrent write")

    def test_update_item_creates_when_missing(self):
        pk, sk = "USER#new", "PROFILE"
        self.assertIsNone(dynamodb.get_item(pk, sk))

        result = dynamodb.update_item(pk, sk, {"name": "Fresh"})

        self.assertEqual(result["name"], "Fresh")
        self.assertEqual(dynamodb.get_item(pk, sk)["name"], "Fresh")

    def test_update_item_never_writes_pk_sk_as_ordinary_fields(self):
        pk, sk = "USER#guard", "PROFILE"
        dynamodb.update_item(pk, sk, {"pk": "ignored", "sk": "ignored", "name": "Kept"})

        item = dynamodb.get_item(pk, sk)
        self.assertEqual(item["pk"], pk)
        self.assertEqual(item["sk"], sk)
        self.assertEqual(item["name"], "Kept")

    def test_empty_patch_returns_current_item_without_writing(self):
        pk, sk = "USER#empty", "PROFILE"
        dynamodb.update_item(pk, sk, {"name": "Stays"})

        result = dynamodb.update_item(pk, sk, {})

        self.assertEqual(result["name"], "Stays")


if __name__ == "__main__":
    unittest.main()
