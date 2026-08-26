#!/usr/bin/env python3
"""Fail if a target calls a permission-gated API without declaring its usage string.

This is not a lint. A missing usage string is not a warning and not a denied
permission — the OS sends SIGABRT the moment the API is touched, so the app
terminates on the user's first tap. It cannot be caught by a build, only by
running the exact code path on a device.

It has reached `main` four times in this repo:

  * `SFSpeechRecognizer` and `AVAudioEngine` in `ChatView` and `VoiceCoachManager`
    with no `NSMicrophoneUsageDescription` and no `NSSpeechRecognitionUsageDescription`
  * `CNContactStore` behind "Find Workout Buddies" with no `NSContactsUsageDescription`
  * `CMMotionActivityManager` in the watch app's `ContextEngine` with no
    `NSMotionUsageDescription` — on a launch path, so the watch app aborted
    seconds after every cold start, before onboarding

The fourth got through a gate that already had the rule for it. The old version
scanned only `ForgeSwift/ForgeSwift` and checked declarations against the whole
project file as one string, on the stated assumption that "the watch and
extensions carry their own Info.plists and are checked separately by their own
build settings". Nothing checked them. This version resolves each target's own
build configurations, so a key set on the iOS target can no longer vouch for the
watch — and every target's sources are scanned, not just the app's.

Scope note: ForgeCore is deliberately not scanned. Every app target links it, so
attributing a call site there to all of them would demand a Health usage string
from the Messages and widget extensions, which never make that call. Linking a
module that contains a call is not making the call. Both targets that do call
HealthKit instantiate `HKHealthStore` in their own sources anyway, so nothing is
lost. False negatives are acceptable here; false positives are not — a gate
people learn to ignore is worse than no gate.

Exit 1 on any finding.
"""

from __future__ import annotations

import os
import re
import sys

# Symbol pattern -> the Info.plist key the OS demands before it may be touched.
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

PROJECT = "ForgeSwift/ForgeSwift.xcodeproj/project.pbxproj"
PROJECT_DIR = os.path.dirname(os.path.dirname(PROJECT))  # ForgeSwift/

# Each target's OWN sources. A subtree listed under one target is excluded from
# any ancestor listed under another (ForgeWatch/Complications is the widget
# extension, not the watch app).
TARGET_SOURCES: dict[str, list[str]] = {
    "ForgeSwift": ["ForgeSwift/ForgeSwift"],
    "ForgeWatch": ["ForgeSwift/ForgeWatch"],
    "ForgeWatchWidgets": ["ForgeSwift/ForgeWatch/Complications"],
    "ForgeWidgetExtension": ["ForgeSwift/ForgeWidgetExtension"],
    "ForgeMessagesExtension": ["ForgeSwift/ForgeMessagesExtension"],
}


def strip_comments(text: str) -> str:
    """Remove // and /* */ so a symbol named only in prose does not count."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def owned_roots(target: str) -> tuple[list[str], list[str]]:
    """This target's roots, and the roots belonging to other targets beneath them."""
    mine = TARGET_SOURCES[target]
    others = [
        root
        for name, roots in TARGET_SOURCES.items()
        if name != target
        for root in roots
        if any(root.startswith(m + os.sep) for m in mine)
    ]
    return mine, others


def swift_sources(target: str) -> list[str]:
    mine, excluded = owned_roots(target)
    found: list[str] = []
    for root in mine:
        for dirpath, dirnames, filenames in os.walk(root):
            dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
            if any(dirpath == e or dirpath.startswith(e + os.sep) for e in excluded):
                dirnames[:] = []
                continue
            found += [os.path.join(dirpath, f) for f in filenames if f.endswith(".swift")]
    return sorted(found)


# --- project.pbxproj -----------------------------------------------------------
#
# Objects are emitted at two tabs and closed by "\n\t\t};". That is enough
# structure for what this needs; a full plist parser is not warranted, and the
# repo already learned that lesson from the other direction (check-pbxproj.py).

_OBJECT_RE = re.compile(r"\n\t\t([0-9A-F]{24})(?: /\* (.*?) \*/)? = \{\n(.*?)\n\t\t\};", re.S)


def parse_objects(project: str) -> dict[str, tuple[str, str]]:
    """id -> (comment, body)."""
    return {m.group(1): (m.group(2) or "", m.group(3)) for m in _OBJECT_RE.finditer(project)}


def field(body: str, name: str) -> str | None:
    """A scalar `name = value;` line, with any trailing /* comment */ removed.

    pbxproj writes the comment after the value (`= ID /* ... */;`), so it lands
    inside the capture and has to come back off.
    """
    match = re.search(rf"^\t*{re.escape(name)} = ([^;]+);", body, re.M)
    if match is None:
        return None
    value = re.sub(r"/\*.*?\*/", "", match.group(1))
    return value.strip().strip('"')


def build_settings_for(target: str, objects: dict[str, tuple[str, str]]) -> dict[str, str]:
    """Configuration name -> that configuration's buildSettings text."""
    target_body = None
    for _comment, body in objects.values():
        if "isa = PBXNativeTarget;" in body and field(body, "name") == target:
            target_body = body
            break
    if target_body is None:
        raise LookupError(f"target {target!r} not found in {PROJECT}")

    list_id = field(target_body, "buildConfigurationList")
    if list_id is None or list_id not in objects:
        raise LookupError(f"target {target!r} has no resolvable buildConfigurationList")

    _comment, list_body = objects[list_id]
    config_ids = re.findall(r"([0-9A-F]{24}) /\* .*? \*/,", list_body)

    settings: dict[str, str] = {}
    for config_id in config_ids:
        if config_id not in objects:
            continue
        _c, config_body = objects[config_id]
        name = field(config_body, "name") or config_id
        block = re.search(r"buildSettings = \{(.*?)\n\t*\};", config_body, re.S)
        settings[name] = block.group(1) if block else ""
    return settings


def plist_declares(settings_text: str, key: str) -> bool:
    """True when INFOPLIST_FILE for this configuration writes the key itself."""
    path = None
    match = re.search(r"^\t*INFOPLIST_FILE = ([^;]+);", settings_text, re.M)
    if match:
        path = match.group(1).strip().strip('"')
    if not path:
        return False
    full = os.path.join(PROJECT_DIR, path)
    if not os.path.exists(full):
        return False
    try:
        return f"<key>{key}</key>" in open(full, encoding="utf-8").read()
    except OSError:
        return False


def main() -> int:
    if not os.path.exists(PROJECT):
        print(f"check-usage-strings: {PROJECT} not found", file=sys.stderr)
        return 1

    objects = parse_objects(open(PROJECT, encoding="utf-8").read())

    findings: list[str] = []
    checked_sites = 0
    checked_permissions: set[tuple[str, str]] = set()

    for target in sorted(TARGET_SOURCES):
        # Which gated symbols does this target's own code reach for, and where.
        users: dict[str, list[str]] = {}
        for path in swift_sources(target):
            try:
                body = strip_comments(open(path, encoding="utf-8").read())
            except (UnicodeDecodeError, OSError):
                continue
            for pattern, key, _human in REQUIREMENTS:
                if re.search(pattern, body):
                    users.setdefault(key, []).append(path)

        if not users:
            continue

        try:
            configurations = build_settings_for(target, objects)
        except LookupError as exc:
            findings.append(f"[{target}] {exc}")
            continue

        for _pattern, key, human in REQUIREMENTS:
            callers = users.get(key)
            if not callers:
                continue
            checked_sites += len(callers)
            checked_permissions.add((target, key))

            # Every configuration must declare it. A key present only in Debug
            # ships a Release build that aborts on the same code path.
            missing = [
                name
                for name, text in configurations.items()
                if f"INFOPLIST_KEY_{key}" not in text and not plist_declares(text, key)
            ]
            if missing:
                where = ", ".join(sorted({os.path.basename(c) for c in callers})[:4])
                findings.append(
                    f"[{target}] {key} is required — {human} is touched in {where} — "
                    f"but it is not declared in: {', '.join(sorted(missing))}."
                )

    if findings:
        print("Permission-gated APIs used without their usage string:\n")
        for f in findings:
            print(f"  {f}")
        print(f"\n{len(findings)} missing usage string(s). The OS terminates the process")
        print("the moment one of these APIs is touched — this is a crash on first use,")
        print("not a denied permission, and no build or simulator run will reveal it.")
        return 1

    targets = len({t for t, _ in checked_permissions})
    print(f"check-usage-strings: every permission-gated API has its usage string "
          f"({len(checked_permissions)} permission(s) across {targets} target(s), "
          f"{checked_sites} call site(s))")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
