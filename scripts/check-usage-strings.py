#!/usr/bin/env python3
"""Fail if the app calls a permission-gated API without declaring its usage string.

This is not a lint. A missing usage string is not a warning and not a denied
permission — iOS sends SIGABRT the moment the API is touched, so the app
terminates on the user's first tap. It cannot be caught by a build, only by
running the exact code path on a device.

It has reached `main` three times in this repo:

  * `SFSpeechRecognizer` and `AVAudioEngine` in `ChatView` and `VoiceCoachManager`
    with no `NSMicrophoneUsageDescription` and no `NSSpeechRecognitionUsageDescription`
  * `CNContactStore` behind "Find Workout Buddies" with no `NSContactsUsageDescription`

Each shipped because adding a framework call and adding an Info.plist key are
separate edits in separate files, and nothing connected them. This connects them.

The mapping is deliberately conservative: only symbols that unambiguously require
a specific string. False negatives are acceptable here, false positives are not —
a gate people learn to ignore is worse than no gate.

Exit 1 on any finding.
"""

from __future__ import annotations

import os
import re
import sys

# Symbol pattern -> the Info.plist key iOS demands before it may be touched.
REQUIREMENTS: list[tuple[str, str, str]] = [
    (r"\bSFSpeechRecognizer\b|\bSFSpeechAudioBufferRecognitionRequest\b",
     "NSSpeechRecognitionUsageDescription",
     "speech recognition"),
    (r"\bAVAudioEngine\b|\brequestRecordPermission\b|\.record\b.*AVAudioSession|AVAudioSession.*\.record\b",
     "NSMicrophoneUsageDescription",
     "microphone capture"),
    (r"\bCNContactStore\b|\bCNMutableContact\b",
     "NSContactsUsageDescription",
     "the address book"),
    (r"\bCLLocationManager\b",
     "NSLocationWhenInUseUsageDescription",
     "location"),
    (r"\bHKHealthStore\b",
     "NSHealthShareUsageDescription",
     "Health data"),
    (r"\bAVCaptureSession\b|\bAVCaptureDevice\b",
     "NSCameraUsageDescription",
     "the camera"),
    (r"\bCMPedometer\b|\bCMMotionActivityManager\b",
     "NSMotionUsageDescription",
     "motion data"),
    (r"\bMPMediaLibrary\b|\bMPMusicPlayerController\b",
     "NSAppleMusicUsageDescription",
     "the music library"),
    (r"\bPHPhotoLibrary\b|\bPHAsset\b",
     "NSPhotoLibraryUsageDescription",
     "the photo library"),
]

SKIP_DIRS = {".git", "build", "DerivedData", ".build", "node_modules", "Tests"}

# Only the iOS app target's sources; the watch and extensions carry their own
# Info.plists and are checked separately by their own build settings.
SOURCE_ROOTS = ["ForgeSwift/ForgeSwift"]
PROJECT = "ForgeSwift/ForgeSwift.xcodeproj/project.pbxproj"


def strip_comments(text: str) -> str:
    """Remove // and /* */ so a symbol named only in prose does not count."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def swift_sources(roots: list[str]) -> list[str]:
    found: list[str] = []
    for root in roots:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            found += [os.path.join(dirpath, f) for f in filenames if f.endswith(".swift")]
    return sorted(found)


def main() -> int:
    if not os.path.exists(PROJECT):
        print(f"check-usage-strings: {PROJECT} not found", file=sys.stderr)
        return 1

    project = open(PROJECT, encoding="utf-8").read()

    # Which symbols does the app actually reach for, and where.
    users: dict[str, list[str]] = {}
    for path in swift_sources(SOURCE_ROOTS):
        try:
            body = strip_comments(open(path, encoding="utf-8").read())
        except (UnicodeDecodeError, OSError):
            continue
        for pattern, key, _ in REQUIREMENTS:
            if re.search(pattern, body):
                users.setdefault(key, []).append(path)

    findings: list[str] = []
    for pattern, key, human in REQUIREMENTS:
        callers = users.get(key)
        if not callers:
            continue
        # A usage string counts whether it is set as a build setting or written
        # into an Info.plist merged at build time.
        declared = (
            f"INFOPLIST_KEY_{key}" in project
            or f"<key>{key}</key>" in project
        )
        if not declared:
            where = ", ".join(sorted({os.path.basename(c) for c in callers})[:4])
            findings.append(
                f"{key} is required — the app touches {human} in {where} — "
                f"but no INFOPLIST_KEY_{key} is set."
            )

    if findings:
        print("Permission-gated APIs used without their usage string:\n")
        for f in findings:
            print(f"  {f}")
        print(f"\n{len(findings)} missing usage string(s). iOS terminates the process")
        print("the moment one of these APIs is touched — this is a crash on first use,")
        print("not a denied permission, and no build or simulator run will reveal it.")
        return 1

    checked = sum(len(v) for v in users.values())
    print(f"check-usage-strings: every permission-gated API has its usage string "
          f"({len(users)} permissions across {checked} call site(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
