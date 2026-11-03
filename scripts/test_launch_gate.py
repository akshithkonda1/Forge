"""Linux-runnable checks for the launch-stability harness.

The macOS gate itself needs a simulator. These pin the two current main
failures without loosening thresholds.env: kill_relaunch's 2.50s sample
must not count the dyld attach stall as app busy time, and prep_wedge
must write dotted UserDefaults keys as literal names.
"""
import os
import plistlib
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ForgeSwift" / "Scripts" / "launch-gate"))
import launch_gate  # noqa: E402


SAMPLER_STALL_SAMPLE = """\
Sampling process 56523 for 3 seconds with 1 millisecond of run time between samples
Sample analysis of process 56523 written to file test.txt

Call graph:
    344 Thread_7701   DispatchQueue_1: com.apple.main-thread  (serial)
    + 344 start  (in ForgeSwift) + 0
    +   344 main  (in ForgeSwift) + 0
    +     344 UIApplicationMain  (in UIKitCore) + 0
    +       287 dyld4::notifyDebuggerLoad(...)  (in dyld) + 0
    +       ! 287 blockOnSynchronousEvent  (in dyld) + 0
    +       !   287 mach_msg2_trap  (in libsystem_kernel.dylib) + 0
    +       57 CFRunLoopRun  (in CoreFoundation) + 0
    +         57 __CFRunLoopRun  (in CoreFoundation) + 0
    +           57 __CFRunLoopServiceMachPort  (in CoreFoundation) + 0
    +             57 mach_msg2_trap  (in libsystem_kernel.dylib) + 0

Total number in stack (recursive counted multiple, when >=5):
    344       start
"""

APP_HANG_SAMPLE = """\
Sampling process 1 for 3 seconds with 1 millisecond of run time between samples

Call graph:
    344 Thread_1   DispatchQueue_1: com.apple.main-thread  (serial)
    + 344 start
    +   344 main
    +     287 refreshDailyData
    +     ! 287 semaphore_wait_trap
    +     57 CFRunLoopRun
    +       57 __CFRunLoopRun
    +         57 __CFRunLoopServiceMachPort
    +           57 mach_msg2_trap

Total number in stack:
    1 foo
"""


class ThresholdsUnchangedTests(unittest.TestCase):
    def test_gate_budgets_and_timeouts_stay_at_main_values(self):
        t = launch_gate.load_thresholds()
        self.assertEqual(t["MAIN_THREAD_BLOCK_MAX_S"], 2.0)
        self.assertEqual(t["SAMPLE_WINDOW_S"], 3)
        self.assertEqual(t["SAMPLE_WINDOWS"], 4)
        self.assertEqual(t["SAMPLE_TIMEOUT_S"], 60)
        self.assertEqual(t["SAMPLE_TIMEOUT_COLD_S"], 150)
        self.assertEqual(t["FIRST_FRAME_MAX_S"], 8)
        self.assertEqual(t["FIRST_FRAME_CONSECUTIVE"], 2)
        self.assertEqual(t["PREP_WATCHDOG_S"], 60)


class SamplerStallTests(unittest.TestCase):
    def test_dyld_attach_stall_is_idle_not_a_2_5s_hang(self):
        # Main's kill_relaunch sample 0 was 2.50s busy of 344 samples / 57 idle.
        # Replaying that shape with the attach stall treated as idle stays
        # under the 2.0s budget. A real app hang still counts (next test).
        busy, total, idle = launch_gate.parse_main_thread_busy(SAMPLER_STALL_SAMPLE, 3)
        self.assertEqual(total, 344)
        self.assertEqual(idle, 344)
        self.assertLessEqual(busy, launch_gate.T["MAIN_THREAD_BLOCK_MAX_S"])
        self.assertAlmostEqual(busy, 0.0)

    def test_app_hang_outside_runloop_stays_busy(self):
        busy, total, idle = launch_gate.parse_main_thread_busy(APP_HANG_SAMPLE, 3)
        self.assertEqual(total, 344)
        self.assertEqual(idle, 57)
        self.assertAlmostEqual(busy, 287 / 344 * 3, places=2)
        self.assertGreater(busy, launch_gate.T["MAIN_THREAD_BLOCK_MAX_S"])


class PrepWedgePlistTests(unittest.TestCase):
    def test_dotted_keys_stay_literal_not_a_key_path(self):
        with tempfile.TemporaryDirectory() as tmp:
            container = Path(tmp) / "data"
            prefs = container / "Library" / "Preferences" / f"{launch_gate.BUNDLE}.plist"
            with mock.patch.object(launch_gate, "app_data_container", return_value=str(container)):
                launch_gate.plist_write_bool("UDID", "forge.onboarding.interviewComplete", True)
                launch_gate.plist_write_bool("UDID", "forge.onboarding.completed", False)
                launch_gate.plist_write_bool("UDID", "forge.auth.session.v1", True)
                interview = launch_gate.plist_read("UDID", "forge.onboarding.interviewComplete")
                completed = launch_gate.plist_read("UDID", "forge.onboarding.completed")
            data = plistlib.loads(prefs.read_bytes())
            self.assertEqual(
                set(data),
                {
                    "forge.onboarding.interviewComplete",
                    "forge.onboarding.completed",
                    "forge.auth.session.v1",
                },
            )
            self.assertNotIn("forge", data)
            self.assertTrue(data["forge.onboarding.interviewComplete"])
            self.assertFalse(data["forge.onboarding.completed"])
            self.assertEqual(interview, "true")
            self.assertEqual(completed, "false")
            pending = launch_gate.pref_is_true(interview) and not launch_gate.pref_is_true(completed)
            self.assertTrue(pending, "wedge starts pending until the app clears the handoff")

    def test_watchdog_treats_plist_true_and_defaults_1_as_set(self):
        self.assertTrue(launch_gate.pref_is_true("true"))
        self.assertTrue(launch_gate.pref_is_true("1"))
        self.assertTrue(launch_gate.pref_is_true("YES"))
        self.assertFalse(launch_gate.pref_is_true("false"))
        self.assertFalse(launch_gate.pref_is_true("0"))
        self.assertFalse(launch_gate.pref_is_true(None))

    def test_launch_env_uses_simctl_child_prefix(self):
        seen = {}

        def fake_simctl(*args, extra_env=None, **kwargs):
            seen["args"] = args
            seen["env"] = extra_env
            return mock.Mock(stdout="com.forge.ForgeSwift: 99\n")

        with mock.patch.object(launch_gate, "simctl", side_effect=fake_simctl):
            pid, _ = launch_gate.launch("UDID", env={"FORGE_LAUNCH_PREP_WEDGE": "1"})
        self.assertEqual(pid, 99)
        self.assertEqual(seen["env"]["SIMCTL_CHILD_FORGE_LAUNCH_LIGHT_ROOT"], "1")
        self.assertEqual(seen["env"]["SIMCTL_CHILD_FORGE_LAUNCH_PREP_WEDGE"], "1")
        self.assertNotIn("--env", seen["args"])


if __name__ == "__main__":
    unittest.main()
