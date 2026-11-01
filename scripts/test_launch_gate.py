#!/usr/bin/env python3
"""Launch-gate classifier and threshold pins.

Keeps thresholds.env from being loosened in this PR and pins the idle
parser so a dyld/sampler attach stall is not billed as a main-thread hang.
"""

from __future__ import annotations

import importlib.util
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "ForgeSwift" / "Scripts" / "launch-gate" / "launch_gate.py"
THRESHOLDS = ROOT / "ForgeSwift" / "Scripts" / "launch-gate" / "thresholds.env"
HEALTHKIT = ROOT / "ForgeSwift" / "ForgeSwift" / "HealthKitManager.swift"


def _load():
    spec = importlib.util.spec_from_file_location("launch_gate", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


lg = _load()


def _sample(body: str) -> str:
    return (
        "Call graph:\n"
        "    300 Thread_10823691   DispatchQueue + 0x0   com.apple.main-thread\n"
        f"{body}"
        "    12 Thread_10823692\n"
    )


def _busy(text: str):
    with mock.patch.object(lg, "run_sample", return_value=text):
        return lg.main_thread_busy_s(1, 3.0, "unit", 10)


class ThresholdPins(unittest.TestCase):
    def test_thresholds_are_not_loosened(self):
        raw = THRESHOLDS.read_text(encoding="utf-8")
        self.assertIn("FIRST_FRAME_MAX_S=8\n", raw)
        self.assertIn("FIRST_FRAME_CONSECUTIVE=2\n", raw)
        self.assertIn("PREP_WATCHDOG_S=60\n", raw)
        self.assertIn("MAIN_THREAD_BLOCK_MAX_S=2.0\n", raw)
        self.assertEqual(lg.T["FIRST_FRAME_MAX_S"], 8.0)
        self.assertEqual(lg.T["FIRST_FRAME_CONSECUTIVE"], 2.0)
        self.assertEqual(lg.T["PREP_WATCHDOG_S"], 60.0)
        self.assertEqual(lg.T["MAIN_THREAD_BLOCK_MAX_S"], 2.0)


class HealthKitShortCircuit(unittest.TestCase):
    def test_await_is_not_an_or_autoclosure(self):
        src = HEALTHKIT.read_text(encoding="utf-8")
        self.assertNotIn("|| await hasReadableHealthEvidence()", src)
        self.assertIn(
            "cachedReadable ? true : await hasReadableHealthEvidence()",
            src,
        )
        self.assertNotIn("shouldProbeStoreForLiveStatus(", src)


class HarnessDoesNotHideTheApp(unittest.TestCase):
    def test_launch_does_not_inject_light_root(self):
        src = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn('extra = {"FORGE_LAUNCH_LIGHT_ROOT": "1"}', src)
        self.assertNotIn("FORGE_LAUNCH_PREP_WEDGE", src)


class IdleClassifier(unittest.TestCase):
    def test_runloop_mach_msg_is_idle(self):
        text = _sample(
            "    + 300 start\n"
            "    +   300 CFRunLoopRun\n"
            "    +     300 __CFRunLoopRun\n"
            "    +       300 __CFRunLoopServiceMachPort\n"
            "    +         300 mach_msg2_trap\n"
        )
        busy, total, idle = _busy(text)
        self.assertEqual(total, 300)
        self.assertEqual(idle, 300)
        self.assertEqual(busy, 0.0)

    def test_sampler_dyld_stall_is_idle(self):
        text = _sample(
            "    + 300 start\n"
            "    +   153 CFRunLoopRun\n"
            "    +     153 __CFRunLoopServiceMachPort\n"
            "    +       153 mach_msg2_trap\n"
            "    +   147 dyld4::notifyDebuggerLoad\n"
            "    +     147 blockOnSynchronousEvent\n"
            "    +       147 mach_msg2_trap\n"
        )
        busy, total, idle = _busy(text)
        self.assertEqual(total, 300)
        self.assertEqual(idle, 300)
        self.assertLess(busy, lg.T["MAIN_THREAD_BLOCK_MAX_S"])
        self.assertAlmostEqual(busy, 0.0)

    def test_app_code_mach_msg_stays_busy(self):
        text = _sample(
            "    + 300 start\n"
            "    +   300 FakeHealthPack.generate\n"
            "    +     300 mach_msg2_trap\n"
        )
        busy, total, idle = _busy(text)
        self.assertEqual(total, 300)
        self.assertEqual(idle, 0)
        self.assertEqual(busy, 3.0)


if __name__ == "__main__":
    unittest.main()
