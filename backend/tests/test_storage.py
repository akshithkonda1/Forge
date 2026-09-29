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

    def test_conditional_add_is_atomic_under_the_local_lock(self):
        pk, sk = "USER#add-race", "RATELIMIT#aria-chat"
        admitted = 0
        denied = 0
        errors: list[Exception] = []
        lock = threading.Lock()
        thread_count = 80
        barrier = threading.Barrier(thread_count)

        def increment() -> None:
            nonlocal admitted, denied
            barrier.wait()
            try:
                dynamodb.update_item(
                    pk,
                    sk,
                    {"entity_type": "rate_limit"},
                    add={"count": 1},
                    condition_expression="attribute_not_exists(#c) OR #c < :limit",
                    expression_attribute_names={"#c": "count"},
                    expression_attribute_values={":limit": 10},
                )
                with lock:
                    admitted += 1
            except dynamodb.ConditionalCheckFailed:
                with lock:
                    denied += 1
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        threads = [threading.Thread(target=increment) for _ in range(thread_count)]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(errors, [])
        self.assertEqual(admitted, 10)
        self.assertEqual(denied, 70)
        self.assertEqual(int(dynamodb.get_item(pk, sk)["count"]), 10)

    def test_query_prefix_survives_concurrent_writes(self):
        """Iterating _local_store while writers mutate used to raise RuntimeError."""
        errors: list[Exception] = []
        stop = threading.Event()

        def writer(index: int) -> None:
            try:
                for step in range(40):
                    dynamodb.put_item(
                        {
                            "pk": "USER#scan-race",
                            "sk": f"ITEM#{index:03d}#{step:03d}",
                            "n": step,
                        }
                    )
                    dynamodb.update_item(
                        "USER#scan-race",
                        f"ITEM#{index:03d}#{step:03d}",
                        {"n": step},
                        add={"count": 1},
                    )
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        def reader() -> None:
            try:
                while not stop.is_set():
                    dynamodb.query_prefix("USER#scan-race", "ITEM#")
                    dynamodb.query_prefix_desc("USER#scan-race", "ITEM#")
                    dynamodb.get_item("USER#scan-race", "ITEM#000#000")
            except Exception as exc:  # noqa: BLE001
                errors.append(exc)

        writers = [threading.Thread(target=writer, args=(i,)) for i in range(8)]
        readers = [threading.Thread(target=reader) for _ in range(4)]
        for thread in readers:
            thread.start()
        for thread in writers:
            thread.start()
        for thread in writers:
            thread.join()
        stop.set()
        for thread in readers:
            thread.join()

        self.assertEqual(errors, [])
        found = dynamodb.query_prefix("USER#scan-race", "ITEM#")
        self.assertEqual(len(found), 8 * 40)


if __name__ == "__main__":
    unittest.main()
