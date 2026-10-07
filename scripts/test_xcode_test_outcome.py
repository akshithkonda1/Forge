#!/usr/bin/env python3
"""xcodebuild test-log classifier — banners only, fail-closed."""

from __future__ import annotations

import importlib.util
import io
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "xcode_test_outcome.py"


def _load():
    spec = importlib.util.spec_from_file_location("xcode_test_outcome", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = _load()


class BannerSubstringTests(unittest.TestCase):
    def test_old_grep_misses_xcode_27_execute_banner(self):
        execute = "** TEST EXECUTE SUCCEEDED **"
        self.assertNotIn(
            "TEST SUCCEEDED",
            execute,
            "naive TEST SUCCEEDED grep is why Phase C false-redded",
        )
        self.assertEqual(mod.classify(execute + "\n"), "success")


class ClassifyTests(unittest.TestCase):
    def test_legacy_test_succeeded_banner(self):
        self.assertEqual(mod.classify("** TEST SUCCEEDED **\n"), "success")

    def test_execute_succeeded_banner(self):
        log = (
            "Test Suite 'All tests' passed at 2026-10-07 03:10:03.716.\n"
            "\t Executed 452 tests, with 0 failures (0 unexpected) in 63.926 seconds\n"
            "** TEST EXECUTE SUCCEEDED **\n"
        )
        self.assertEqual(mod.classify(log), "success")

    def test_prose_and_partial_phrases_are_incomplete(self):
        for line in (
            "NO TEST SUCCEEDED",
            "TEST SUCCEEDED TO START",
            "TEST EXECUTE SUCCEEDED TO ATTACH",
            "the test succeeded",
            "TEST SUCCEEDED",
            "TEST EXECUTE SUCCEEDED",
        ):
            self.assertEqual(mod.classify(line + "\n"), "incomplete", line)

    def test_empty_log_is_incomplete(self):
        self.assertEqual(mod.classify(""), "incomplete")

    def test_failure_banner_wins_over_success(self):
        log = "** TEST EXECUTE SUCCEEDED **\n** TEST FAILED **\n"
        self.assertEqual(mod.classify(log), "failed")

    def test_execute_failed_banner(self):
        self.assertEqual(mod.classify("** TEST EXECUTE FAILED **\n"), "failed")

    def test_build_failed_banner(self):
        self.assertEqual(mod.classify("** TEST BUILD FAILED **\n"), "failed")

    def test_xctassert_is_fail_closed(self):
        log = (
            "Test Case '-[ForgeCoreTests.StatsMosaicTests testHealth]' "
            "failed (0.309 seconds).\n"
            "XCTAssertEqual failed: (\"4\") is not equal to (\"5\")\n"
        )
        self.assertEqual(mod.classify(log), "failed")

    def test_test_case_failed_paren_is_fail_closed(self):
        line = "Test Case '-[ForgeSwiftTests.Foo testBar]' failed (0.012 seconds).\n"
        self.assertEqual(mod.classify(line), "failed")

    def test_test_runner_crashed_is_fail_closed(self):
        self.assertEqual(mod.classify("test runner crashed\n"), "failed")

    def test_passed_seconds_is_not_a_failure(self):
        log = (
            "Test Case '-[ForgeSwiftTests.AriaVoiceSessionTests "
            "testFishAudioMouthRequiresAConfiguredKey]' passed (0.001 seconds).\n"
        )
        self.assertEqual(mod.classify(log), "incomplete")


class CliTests(unittest.TestCase):
    def test_missing_log_is_incomplete(self):
        buf = io.StringIO()
        with redirect_stdout(buf):
            self.assertEqual(mod.main(["/tmp/forge-missing-ios-test.log"]), 0)
        self.assertEqual(buf.getvalue().strip(), "incomplete")

    def test_cli_prints_execute_success(self):
        with tempfile.NamedTemporaryFile("w", encoding="utf-8", suffix=".log", delete=False) as handle:
            handle.write("** TEST EXECUTE SUCCEEDED **\n")
            path = handle.name
        buf = io.StringIO()
        with redirect_stdout(buf):
            self.assertEqual(mod.main([path]), 0)
        self.assertEqual(buf.getvalue().strip(), "success")


if __name__ == "__main__":
    unittest.main()
