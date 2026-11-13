#!/usr/bin/env python3
"""Launch-gate classifier and threshold pins.

Keeps thresholds.env from being loosened in this PR and pins the idle
parser to run-loop waits only (no sampler-stall skip, no harness warmup).
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
CONTENT = ROOT / "ForgeSwift" / "ForgeSwift" / "ContentView.swift"
LAUNCH_STORYBOARD = ROOT / "ForgeSwift" / "ForgeSwift" / "LaunchScreen.storyboard"
APP = ROOT / "ForgeSwift" / "ForgeSwift" / "ForgeSwiftApp.swift"
AUTH = ROOT / "ForgeSwift" / "ForgeSwift" / "AppStore+Auth.swift"
PREP = ROOT / "ForgeSwift" / "ForgeSwift" / "AriaForgePrep.swift"
COORDINATOR = ROOT / "ForgeSwift" / "ForgeSwift" / "OnboardingCoordinator.swift"
CHAT = ROOT / "ForgeSwift" / "ForgeSwift" / "ChatView.swift"
ONBOARDING = ROOT / "ForgeSwift" / "ForgeSwift" / "OnboardingView.swift"
HOME = ROOT / "ForgeSwift" / "ForgeSwift" / "HomeView.swift"
PBXPROJ = ROOT / "ForgeSwift" / "ForgeSwift.xcodeproj" / "project.pbxproj"


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

    def test_gate_has_no_sampler_stall_or_warmup(self):
        src = SCRIPT.read_text(encoding="utf-8")
        self.assertNotIn("SAMPLER_STALL", src)
        self.assertNotIn("notifyDebuggerLoad", src)
        self.assertNotIn("warmup_screenshot_io", src)
        self.assertNotIn("warmup_app_launch", src)

    def test_app_has_no_light_root_or_reveal_delay(self):
        content = CONTENT.read_text(encoding="utf-8")
        app = APP.read_text(encoding="utf-8")
        self.assertNotIn("FORGE_LAUNCH_LIGHT_ROOT", content)
        self.assertNotIn("LaunchHarnessPolicy", content)
        self.assertNotIn("revealDelaySeconds", content)
        self.assertNotIn("LaunchHarnessPolicy", app)
        self.assertNotIn("FORGE_LAUNCH_LIGHT_ROOT", app)
        self.assertNotIn(
            "SecureStoreMigration.run(from: .standard, to: KeychainStore())",
            app.split("var body")[0],
        )
        self.assertIn("SecureStoreMigration.run(from: .standard, to: KeychainStore())", app)

    def test_restore_does_not_finish_leftover_prep_on_simulator(self):
        prep = PREP.read_text(encoding="utf-8")
        auth = AUTH.read_text(encoding="utf-8")
        self.assertNotIn("return launchPrepWedge && isDebugSimulator", prep)
        self.assertNotIn("FORGE_LAUNCH_PREP_WEDGE", auth)
        self.assertNotIn("launchPrepWedge:", auth)

    def test_launch_storyboard_is_blank_so_first_frame_is_swiftui(self):
        src = LAUNCH_STORYBOARD.read_text(encoding="utf-8")
        self.assertNotIn("forge-launch-mark", src)
        self.assertNotIn("constant=\"220\"", src)
        self.assertIn("0.03529411764705882", src)

    def test_first_commit_is_branded_not_a_solid_field(self):
        src = CONTENT.read_text(encoding="utf-8")
        self.assertIn("struct LaunchBrandField", src)
        self.assertIn("static let markSide: CGFloat = 220", src)
        self.assertIn("LaunchBrandField()", src)
        self.assertNotIn(
            "if !revealRoot {\n                    Color(red: 8 / 255, green: 8 / 255, blue: 12 / 255)",
            src,
        )

    def test_app_does_not_link_kokoro_at_process_start(self):
        pbx = PBXPROJ.read_text(encoding="utf-8")
        phase = pbx.split("AA0003000000000000000001 /* Frameworks */ = {", 1)[1]
        files = phase.split("files = (", 1)[1].split(");", 1)[0]
        self.assertNotIn("KokoroTTS in Frameworks", files)
        app_target = pbx.split('name = ForgeSwift;', 1)[1]
        deps = app_target.split("packageProductDependencies = (", 1)[1].split(");", 1)[0]
        self.assertNotIn("KokoroTTS", deps)
        self.assertIn("mattmireles/kokoro-coreml", pbx)

    def test_first_layout_does_not_mount_strike_chat_or_weekly_sheet(self):
        prep = PREP.read_text(encoding="utf-8")
        content = CONTENT.read_text(encoding="utf-8")
        coordinator = COORDINATOR.read_text(encoding="utf-8")
        chat = CHAT.read_text(encoding="utf-8")
        onboarding = ONBOARDING.read_text(encoding="utf-8")
        self.assertIn("static var splashMountsStrikeOnFirstCommit: Bool { false }", prep)
        self.assertIn("if showStrike {", content)
        self.assertIn("ForgeStrikeMark(playback:", content)
        self.assertIn(
            "guard LaunchFirstCommit.shouldOpenChatAfterPrep(leftoverResume: leftoverResume) else {",
            coordinator,
        )
        self.assertNotIn("weeklyReview.considerPresenting()", chat.split(".task")[0])
        self.assertIn("weeklyReview.considerPresenting()", chat)
        self.assertIn(
            "LaunchFirstCommit.promptsNotificationsOnOnboardingAppear",
            onboarding,
        )
        self.assertIn("static var promptsNotificationsOnOnboardingAppear: Bool { false }", prep)
        self.assertIn(
            "shouldAttachVoiceGatesOnLaunch(",
            content,
        )
        self.assertIn(
            "static var usesBrandFontsOnFirstCommit: Bool { false }",
            prep,
        )
        self.assertIn(
            "static var mountsHomeHeroOnFirstCommit: Bool { false }",
            prep,
        )
        home = HOME.read_text(encoding="utf-8")
        self.assertIn("LaunchFirstCommit.mountsHomeHeroOnFirstCommit", home)
        self.assertIn("useBrandFonts", content)

    def test_prep_has_a_wall_clock_fail_open(self):
        src = PREP.read_text(encoding="utf-8")
        self.assertIn("static func armLeftoverTimeout", src)
        self.assertIn("static let cap: TimeInterval = 55", src)
        self.assertIn("static let watchdog: TimeInterval = 60", src)
        self.assertIn(
            "defaults.set(false, forKey: interviewCompleteKey)",
            src,
        )
        self.assertIn("let defaults = UserDefaults.standard", src)
        self.assertNotIn(
            "UserDefaults.standard.removeObject(forKey: interviewCompleteKey)",
            src,
        )


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

    def test_sampler_dyld_stall_is_busy(self):
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
        self.assertEqual(idle, 153)
        self.assertAlmostEqual(busy, 147 / 300 * 3.0)

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
