import subprocess
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ForgeSwift" / "Scripts"))
import simctl_forge  # noqa: E402


class SimctlForgeTests(unittest.TestCase):
    def test_timeout_raises_simctl_timeout(self):
        with mock.patch.object(simctl_forge.subprocess, "run", side_effect=subprocess.TimeoutExpired(cmd=["xcrun"], timeout=1)):
            with self.assertRaises(simctl_forge.SimctlTimeout):
                simctl_forge.simctl("list", timeout=1)

    def test_erase_retries_after_unwedge(self):
        calls = []

        def fake_simctl(*args, **kwargs):
            calls.append(args)
            if args[0] == "shutdown":
                raise simctl_forge.SimctlTimeout("shutdown hung")
            if args[0] == "erase" and calls.count(("erase", "UDID")) == 1:
                raise simctl_forge.SimctlTimeout("erase hung")
            return subprocess.CompletedProcess(["xcrun", "simctl", *args], 0, "", "")

        with mock.patch.object(simctl_forge, "simctl", side_effect=fake_simctl), \
             mock.patch.object(simctl_forge, "unwedge") as unwedge:
            simctl_forge.erase("UDID")
        self.assertGreaterEqual(unwedge.call_count, 1)
        self.assertIn(("erase", "UDID"), calls)

    def test_list_booted_filters_watchos(self):
        payload = {
            "devices": {
                "com.apple.CoreSimulator.SimRuntime.iOS-27-0": [
                    {"udid": "phone", "state": "Booted", "name": "iPhone 17e"},
                ],
                "com.apple.CoreSimulator.SimRuntime.watchOS-27-0": [
                    {"udid": "watch", "state": "Booted", "name": "Apple Watch Series 11 (46mm)"},
                    {"udid": "off", "state": "Shutdown", "name": "Apple Watch SE"},
                ],
            }
        }
        result = subprocess.CompletedProcess(["xcrun"], 0, __import__("json").dumps(payload), "")
        with mock.patch.object(simctl_forge, "simctl", return_value=result):
            watches = simctl_forge.list_booted(runtime_substr="watchos")
        self.assertEqual([d["udid"] for d in watches], ["watch"])


if __name__ == "__main__":
    unittest.main()
