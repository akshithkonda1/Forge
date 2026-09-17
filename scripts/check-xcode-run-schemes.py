#!/usr/bin/env python3
"""Forge Run schemes must launch .app products — not tests or appex hosts.

Xcode autocreates schemes for every native target unless suppressed. Selecting
ForgeSwiftTests / Widgets / Messages turns the Run button into test/extension
host mode ("Waiting to attach"), which feels like the project only "tests".
This check locks the shared scheme graph we rely on for ⌘R.
"""

from __future__ import annotations

import plistlib
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(
    subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
)

SCHEME_DIR = ROOT / "ForgeSwift/ForgeSwift.xcodeproj/xcshareddata/xcschemes"
EXPECTED_SCHEMES = {"ForgeSwift.xcscheme", "ForgeCompanion.xcscheme", "ForgeWatch.xcscheme"}
FORBIDDEN_SCHEME_SUBSTRINGS = ("Tests", "Widget", "Messages", "appex")

# LaunchAction must run these apps.
LAUNCH_EXPECT = {
    "ForgeSwift.xcscheme": "ForgeSwift.app",
    "ForgeCompanion.xcscheme": "ForgeSwift.app",
    "ForgeWatch.xcscheme": "ForgeWatch.app",
}

SUPPRESS_IDS = {
    "1TEST00100000000000000A",  # ForgeSwiftTests
    "F0C100000000000000000002",  # ForgeWatchWidgets
    "F0C100000000000000000003",  # ForgeWidgetExtension
    "AA00050000000000000000C1",  # ForgeMessagesExtension
}

MANAGEMENT_PATHS = [
    SCHEME_DIR / "xcschememanagement.plist",
    ROOT / "Forge.xcworkspace/xcshareddata/xcschemes/xcschememanagement.plist",
]

WORKSPACE_SETTINGS = [
    ROOT / "ForgeSwift/ForgeSwift.xcodeproj/project.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings",
    ROOT / "Forge.xcworkspace/xcshareddata/WorkspaceSettings.xcsettings",
]


def launch_product(scheme_path: Path) -> str | None:
    tree = ET.parse(scheme_path)
    root = tree.getroot()
    launch = root.find("LaunchAction")
    if launch is None:
        return None
    ref = launch.find("./BuildableProductRunnable/BuildableReference")
    if ref is None:
        return None
    return ref.attrib.get("BuildableName")


def first_build_product(scheme_path: Path) -> str | None:
    tree = ET.parse(scheme_path)
    root = tree.getroot()
    entry = root.find("./BuildAction/BuildActionEntries/BuildActionEntry/BuildableReference")
    if entry is None:
        return None
    return entry.attrib.get("BuildableName")


def main() -> int:
    status = 0
    on_disk = {p.name for p in SCHEME_DIR.glob("*.xcscheme")}
    if on_disk != EXPECTED_SCHEMES:
        print(f"✗ shared schemes = {sorted(on_disk)}, expected {sorted(EXPECTED_SCHEMES)}")
        status = 1
    else:
        print(f"✓ shared schemes: {', '.join(sorted(on_disk))}")

    for name in sorted(on_disk):
        for bad in FORBIDDEN_SCHEME_SUBSTRINGS:
            if bad.lower() in name.lower() and name not in EXPECTED_SCHEMES:
                print(f"✗ forbidden shared scheme name: {name}")
                status = 1

    for scheme, expected in LAUNCH_EXPECT.items():
        path = SCHEME_DIR / scheme
        got = launch_product(path)
        if got != expected:
            print(f"✗ {scheme} LaunchAction runs {got!r}, expected {expected!r}")
            status = 1
        else:
            print(f"✓ {scheme} ⌘R → {got}")

    forge_swift = SCHEME_DIR / "ForgeSwift.xcscheme"
    first = first_build_product(forge_swift)
    if first != "ForgeSwift.app":
        print(f"✗ ForgeSwift.xcscheme first build entry is {first!r}, expected ForgeSwift.app")
        status = 1
    else:
        print("✓ ForgeSwift.xcscheme builds ForgeSwift.app first")

    tree = ET.parse(forge_swift)
    test_build = None
    for entry in tree.getroot().findall("./BuildAction/BuildActionEntries/BuildActionEntry"):
        ref = entry.find("BuildableReference")
        if ref is not None and ref.attrib.get("BuildableName") == "ForgeSwiftTests.xctest":
            test_build = entry
            break
    if test_build is None:
        print("✗ ForgeSwift.xcscheme missing ForgeSwiftTests build entry for ⌘U")
        status = 1
    elif test_build.attrib.get("buildForRunning") != "NO":
        print("✗ ForgeSwiftTests must not buildForRunning (would hijack ⌘R)")
        status = 1
    else:
        print("✓ ForgeSwiftTests is test-only (buildForRunning=NO)")

    # No watch auto-launch post-action on the plain Run scheme.
    post = tree.getroot().findall("./LaunchAction/PostActions/ExecutionAction")
    if post:
        print("✗ ForgeSwift.xcscheme should not auto-launch Watch on ⌘R "
              "(use ForgeCompanion for that)")
        status = 1
    else:
        print("✓ ForgeSwift.xcscheme has no Run post-actions")

    for path in MANAGEMENT_PATHS:
        if not path.is_file():
            print(f"✗ missing {path.relative_to(ROOT)}")
            status = 1
            continue
        data = plistlib.loads(path.read_bytes())
        suppress = data.get("SuppressBuildableAutocreation", {})
        missing = sorted(SUPPRESS_IDS - set(suppress))
        if missing:
            print(f"✗ {path.relative_to(ROOT)} missing SuppressBuildableAutocreation for {missing}")
            status = 1
        else:
            print(f"✓ {path.relative_to(ROOT)} suppresses test/extension autocreate")

    for path in WORKSPACE_SETTINGS:
        if not path.is_file():
            print(f"✗ missing {path.relative_to(ROOT)}")
            status = 1
            continue
        data = plistlib.loads(path.read_bytes())
        if data.get("IDEWorkspaceSharedSettings_AutocreateContextsIfNeeded") is not False:
            print(f"✗ {path.relative_to(ROOT)} must disable AutocreateContextsIfNeeded")
            status = 1
        else:
            print(f"✓ {path.relative_to(ROOT)} disables scheme autocreate")

    return status


if __name__ == "__main__":
    sys.exit(main())
