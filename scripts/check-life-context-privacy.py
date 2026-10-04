#!/usr/bin/env python3
"""Life Context privacy boundary, decided from the source text.

Reminders and shared conversations are the most personal things Forge reads.
The rules below are each one line of code away from being broken, none of them
fails a build, and a unit test can only check the paths it thinks to call —
so they are checked here, by grep, on every pull request:

  * no private Messages access anywhere: no ChatStorage / sms.db / chat.db,
    no Library/SMS path, no IMCore / ChatKit / IMDPersistence;
  * `MessageTurn` and `ReminderItem` (the only types that ever carry message
    text or a reminder's title) are never Codable, so they cannot be written;
  * no logging, no networking, and no file writes in the Life Context sources
    — the one writer is LifeContextVault, which only writes sealed boxes;
  * no `EKReminder` is ever published or stored on RemindersManager;
  * Life Context tags are built per payload and never merged into ARIA's
    persisted context, and the remote-inference strip removes them from both
    tags and patterns;
  * the Share extension's only entitlement is the app group.

Exit 1 on any finding.
"""

from __future__ import annotations

import os
import plistlib
import re
import sys

ROOT = "ForgeSwift"

LIFE_CONTEXT_SOURCES = [
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/LifeContextText.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/LifeContextDateResolver.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/MessageContextEngine.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/SharedConversationParser.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/LifeContextBrief.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/LifeOpsDigest.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Models/LifeContextModels.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Models/RemindersWorkload.swift",
    "ForgeSwift/ForgeCore/Sources/ForgeCore/Security/LifeContextVault.swift",
    "ForgeSwift/ForgeSwift/Services/RemindersManager.swift",
    "ForgeSwift/ForgeSwift/Services/LifeOpsBoard.swift",
    "ForgeSwift/ForgeSwift/Services/MessageIngestionProvider.swift",
    "ForgeSwift/ForgeSwift/Services/SyntheticMessageProvider.swift",
    "ForgeSwift/ForgeSwift/Services/MessageContextStore.swift",
    "ForgeSwift/ForgeSwift/LifeContextSettingsView.swift",
    "ForgeSwift/ForgeShareExtension/ShareViewController.swift",
    "ForgeSwift/ForgeShareExtension/ShareExtensionProvider.swift",
]

# The only file allowed to write bytes to disk: it writes ciphertext.
SEALED_WRITERS = {"ForgeSwift/ForgeCore/Sources/ForgeCore/Security/LifeContextVault.swift"}

PRIVATE_MESSAGES = re.compile(
    r"ChatStorage|sms\.db|chat\.db|Library/SMS|\bIMCore\b|\bChatKit\b|\bIMDPersistence\b"
)
LOGGING = re.compile(r"\bprint\(|\bdebugPrint\(|\bdump\(|\bNSLog\(|\bos_log\(|\bLogger\(")
NETWORK = re.compile(r"\bURLSession\b|\bURLRequest\b|\bNWConnection\b")
FILE_WRITE = re.compile(r"\.write\(to:|createFile\(atPath:|FileHandle\(forWritingTo")
NOT_CODABLE = {
    "MessageTurn": "ForgeSwift/ForgeCore/Sources/ForgeCore/Models/LifeContextModels.swift",
    "ReminderItem": "ForgeSwift/ForgeCore/Sources/ForgeCore/Models/RemindersWorkload.swift",
}

SHARE_ENTITLEMENTS = "ForgeSwift/ForgeShareExtension/ForgeShareExtension.entitlements"
POLICY = "ForgeSwift/ForgeSwift/Services/AriaOnDeviceHealthPolicy.swift"
CONTEXT_STORE = "ForgeSwift/ForgeSwift/Services/AriaContextStore.swift"
REMINDERS_MANAGER = "ForgeSwift/ForgeSwift/Services/RemindersManager.swift"


def strip_comments(text: str) -> str:
    """Remove // and /* */ so a rule named in prose (as these headers do) is not a finding."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def read(path: str) -> str:
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def swift_files(root: str) -> list[str]:
    out: list[str] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in {".build", "build", "DerivedData"}]
        out += [os.path.join(dirpath, f) for f in filenames if f.endswith(".swift")]
    return sorted(out)


def main() -> int:
    findings: list[str] = []

    for path in swift_files(ROOT):
        if PRIVATE_MESSAGES.search(strip_comments(read(path))):
            findings.append(f"{path}: reaches for a private Messages store or framework")

    for path in LIFE_CONTEXT_SOURCES:
        if not os.path.exists(path):
            findings.append(f"{path}: listed Life Context source is missing")
            continue
        code = strip_comments(read(path))
        if LOGGING.search(code):
            findings.append(f"{path}: logs — Life Context sources must not print or log")
        if NETWORK.search(code):
            findings.append(f"{path}: networking in a Life Context source")
        if path not in SEALED_WRITERS and FILE_WRITE.search(code):
            findings.append(f"{path}: writes a file — only LifeContextVault writes, and only ciphertext")

    for type_name, path in NOT_CODABLE.items():
        code = strip_comments(read(path))
        declaration = re.search(rf"struct {type_name}\b[^{{]*", code)
        if declaration is None:
            findings.append(f"{path}: {type_name} not found")
        elif re.search(r"\b(Codable|Encodable|Decodable)\b", declaration.group(0)):
            findings.append(f"{path}: {type_name} must not be Codable — it carries raw text")
        for path_any in swift_files(ROOT):
            if re.search(rf"extension {type_name}\b[^{{]*\b(Codable|Encodable)\b", strip_comments(read(path_any))):
                findings.append(f"{path_any}: makes {type_name} Codable")

    manager = strip_comments(read(REMINDERS_MANAGER))
    if re.search(r"(@Published|\bvar\b|\blet\b)[^\n=]*\bEKReminder\b", manager):
        findings.append(f"{REMINDERS_MANAGER}: stores or publishes EKReminder — only counts may leave the fetch")

    store = strip_comments(read(CONTEXT_STORE))
    for line in store.splitlines():
        if re.search(r"context\.(lifestyleTags|recentPatterns)\s*(=|\+=|\.append)", line) and re.search(
            r"lifeContext|RemindersManager|MessageContextStore", line
        ):
            findings.append(f"{CONTEXT_STORE}: Life Context written into ARIA's persisted context: {line.strip()}")
    if "lifeContextTags" not in store:
        findings.append(f"{CONTEXT_STORE}: Life Context tags no longer built per payload")

    policy = strip_comments(read(POLICY))
    if policy.count("isOnDeviceOnlyLifeContext(") < 3:
        findings.append(f"{POLICY}: remote strip must drop Life Context from tags and patterns")
    if "life_ops" not in policy:
        findings.append(f"{POLICY}: remote strip must also drop Life Ops tags")

    with open(SHARE_ENTITLEMENTS, "rb") as handle:
        entitlements = plistlib.load(handle)
    if set(entitlements) != {"com.apple.security.application-groups"}:
        findings.append(f"{SHARE_ENTITLEMENTS}: only the app group is allowed, found {sorted(entitlements)}")

    if findings:
        print("Life Context privacy boundary broken:\n")
        for finding in findings:
            print(f"  {finding}")
        return 1
    print(f"check-life-context-privacy: boundary intact ({len(LIFE_CONTEXT_SOURCES)} source(s) scanned)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
