# ARIA: what each path can do, and how the Dummy leaves production

There are two Dummies, and production needs neither.

| Dummy | Lives in | Used by |
|---|---|---|
| Python Dummy orchestrator | `backend/ai/simrunner/aria_simrunner/dummy_orchestrator.py`, `backend/ai/aria_chat/`, `backend/ai/aria_cli.py` | SimRunner (the tier-1 ship gate), local Dummy chat, `aria_cli` |
| iOS Dummy orchestra | `ForgeSwift/ForgeSwift/Services/AriaDummyOrchestrator.swift`, `AriaDummyTurn.swift` | Debug / Device Hub tuning without cloud AI |

## One safety brain on every path

Emergencies, first aid, refer-out, voice-first triage and the relationship
check-in come from one classifier: `backend/infra/lambda/aria_core/guidance.py`.
The phone runs a generated copy of the same lexicon
(`ForgeCore/Intelligence/AriaSafetyLexicon.swift`, from
`scripts/generate_aria_safety_swift.py`) through `AriaSafetyTriage.swift`, which
mirrors guidance.py's control flow. `shared/aria-safety-corpus.json` pins it:
90 first turns, 26 triage answers, 15 check-ins and 25 care rows, asserted row
for row by Python (`backend/tests/test_safety_triage.py`) and Swift
(`AriaSafetyTriageTests`). CI fails if the Swift lexicon drifts from guidance.py
(repo-hygiene, "ARIA safety lexicon matches guidance.py").

## Capabilities by path

| | iOS Dummy orchestra | iOS Local testing | iOS Live (`/ai/chat`) | iOS offline fallback | Python Dummy chat | `/ai/chat` Lambda | `/ai/voice/tool` (ConvAI) |
|---|---|---|---|---|---|---|---|
| 911 / first aid / refer-out | on-device, before the Dummy runs | on-device | on-device, before the network | on-device | guidance.py | guidance.py | guidance.py, but the phone hands safety turns to chat first (below) |
| Voice-first triage (ask, then 911 / doctor / care line) | yes | yes | yes | yes | `safety` block (no audio) | `safety` block for the client | not here: the phone takes the turn over |
| Triage answer resolved against the open question | `pendingTriageTopic` | same | same, on-device, before the network | same | `triage_topic` | `triage_topic` (for clients that echo it) | no pending topic, which is why the phone takes over |
| Voice off + relationship check-in after resolution or escalation | yes | yes | yes | yes | `safety.check_in` | `safety.check_in` | n/a |
| Care line ("Sharp is the kind I take seriously…") leads a coaching reply | yes | yes | yes (backend and app, never twice) | yes | yes | yes | yes (same engine) |
| Memory / persona / Bedrock on a safety turn | skipped | skipped | skipped (`safety_lock`) | skipped | redacted in logs | skipped (`safety_lock`) | Bedrock skipped; nothing persisted |
| Cloud LLM | never | never | only with `ARIA_BEDROCK_ENABLED` | never | never (`assert_dummy_engine`) | only with `ARIA_BEDROCK_ENABLED` | Bedrock flag, as `/ai/chat` |

Voice: every 911 or triage session runs on this iPhone's own voice (Apple speech
out, on-device speech recognition in), whatever mode ARIA is in. On Live, a chat
turn never opens ConvAI for a safety session (`AriaVoiceTransport.keepingOnDevice`).
If a ConvAI conversation hits a safety turn, the tool call is decided on the phone
and handed to chat (`store.openChat`), so ARIA's copy is spoken verbatim and the
answer resolves case by case. The mic opens after the question, never before it.

Insight-mode turns (lifestyle cards, `mode == "insight"`) skip the on-device
safety check and the care line. They are not chat.

## Which ARIA a build runs

| Build | `FORGE_DUMMY_ORCHESTRA_CONDITION` | Dummy code in the binary | ARIA mode by default |
|---|---|---|---|
| Debug (Xcode, Device Hub) | `FORGE_DUMMY_ORCHESTRA` | yes | Dummy when `FORGEEnvironment=dummy`, loopback, or a Device Hub launch; otherwise Local testing |
| Release as checked in (TestFlight) | `FORGE_DUMMY_ORCHESTRA` | yes | Local testing |
| Production archive | empty | no | Local testing |

In every Release build, TestFlight included, ARIA resolves to Local testing (the
on-device brain), and this predates the flag. The Dummy auto-route needs
`ForgeAuthClient.canUseDevOverride`, which is Debug-only, and the Settings mode
picker is `#if DEBUG`. In TestFlight the Dummy is reachable only through an
operating-mode override persisted earlier. `FORGEEnvironment=dummy` there means
the offline client config (no backend), not the Dummy orchestra. Live is only
ever chosen by override. Stripping the Dummy does not move anyone to Live; that
is the separate WS1 cutover in `docs/testflight-readiness.md`.

## Cutting a production archive without the Dummy

1. Archive with the condition empty:

   ```sh
   xcodebuild -project ForgeSwift/ForgeSwift.xcodeproj -scheme ForgeSwift \
     -configuration Release -destination 'generic/platform=iOS' \
     archive -archivePath build/ForgeSwift.xcarchive \
     FORGE_DUMMY_ORCHESTRA_CONDITION=
   ```

   To make it permanent for App Store builds, give that configuration
   `FORGE_DUMMY_ORCHESTRA_CONDITION = ""` in the project instead. TestFlight can
   keep the Dummy by leaving Release as it is.

2. Prove the Dummy is gone. This is the check CI runs in "Build ForgeSwift
   (iOS, Release, Dummy stripped)":

   ```sh
   bin=build/ForgeSwift.xcarchive/Products/Applications/ForgeSwift.app/ForgeSwift
   ! grep -a -q -E "AriaDummyOrchestrator|AriaDummyTurn" "$bin" && echo "Dummy absent"
   ```

What changes in that build:

- `AriaDummyOrchestra.provider` is nil. It is the only door from chat into the Dummy.
- `AriaOperatingMode` never resolves to `.dummy`, including a `.dummy` override
  persisted by an older build. `setOverride(.dummy)` clears instead.
- Tester mode (`AriaService.shouldUseTestReadyDummy`) is off, so voice never
  picks the Dummy transport.
- The Debug Settings picker lists only Local testing and Live
  (`AriaOperatingMode.selectableCases`).
- Safety is unchanged: it never depended on the Dummy.

## Deleting the Dummy for good

iOS:

1. Delete `AriaDummyOrchestrator.swift`, `AriaDummyTurn.swift` and
   `ForgeSwiftTests/AriaDummyOrchestratorTests.swift`, each with
   `python3 scripts/pbxproj_files.py remove ForgeSwift/ForgeSwift.xcodeproj/project.pbxproj <File.swift>`.
2. Drop the `#if FORGE_DUMMY_ORCHESTRA` branch in `AriaDummyOrchestra.swift`,
   and the `#if FORGE_DUMMY_ORCHESTRA` test blocks in `TrainingHabitsTests`,
   `AriaCoachAgentRouterTests` and `CurrentPracticeAPITests`.
3. Remove `FORGE_DUMMY_ORCHESTRA_CONDITION` from the project and from the
   Release-stripped CI step.
4. `python3 scripts/check-pbxproj.py` must pass. It also fails on a Swift file
   left on disk that no target compiles.

`AriaSwarmSnapshot.from(store:)` is not Dummy code. It lives in
`AriaSwarmSnapshotStore.swift` because Local testing uses it.

Python: nothing to do for production. Terraform zips `backend/infra/lambda` and
nothing else (`archive_file.backend_lambda`), and
`backend/tests/test_dummy_removable.py` holds that line three ways:

- no Lambda module imports the Dummy, lazily or otherwise;
- the zip is the Lambda directory only;
- a copy of the Lambda package, run with the repo absent from `sys.path`,
  serves coaching, triage and escalation turns through the real handler.

Deleting the Python Dummy also deletes SimRunner's ship gate, which grades the
real engine through `DummyARIAEngine`. Replace the gate first.

## Verify

```sh
python3 -m unittest discover -s backend/tests -p "test_dummy_removable.py"
python3 -m unittest discover -s backend/tests -p "test_safety_triage.py"
python3 scripts/generate_aria_safety_swift.py --check
python3 scripts/check-pbxproj.py
SIMRUNNER_TODAY=2026-01-15 python3 -m backend.ai.simrunner --test-ready --tier 1 --gate
(cd ForgeSwift/ForgeCore && swift test --filter AriaSafetyTriageTests)
```
