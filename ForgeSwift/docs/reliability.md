# Reliability telemetry

Forge measures its own reliability on each iPhone, first-party only, so a
rollout phase gate ("99.9% with no errors") is a number. No third-party SDK.
Nothing leaves the device unless a tester exports a report.

## The two gate metrics

**ARIA reply success rate** = turns the chosen path answered without an
error ÷ all ARIA turns (chat and insight cards). Cancelled turns are left
out. A cloud turn that failed and was rescued by the on-device fallback is a
miss: the person got a reply, the infrastructure didn't.

**Crash-free session rate** = foreground sessions that did not end with the
process dying on screen ÷ all foreground sessions. A session opens when Forge
becomes active and resumes if Forge comes back within 30 minutes. On the next
launch, a session still on screen when its process ended is counted as
abnormal (a crash, a watchdog kill or a foreground memory kill, all of which
look like a crash to the person). One that was in the background is counted
as clean. Sessions run under Xcode's debugger are recorded but never counted,
because pressing Stop looks exactly like a crash.

Both rates are exact over the whole window, because they come from counters.
Latency percentiles (p50 and p95, nearest rank) are computed over the most
recent 2,000 turns. The screen calls a metric "Meets 99.9%" only after
1,000 events; below that, one failure already misses the target and zero
failures doesn't prove much. (Rule of three: zero failures in N events
bounds the true failure rate under about 3/N at 95% confidence, so about
3,000 clean events backs a 99.9% claim.)

Apple's MetricKit numbers are an independent cross-check: crash-like
on-screen exits, launch time, hang time per hour, peak memory, and the
crash, hang, CPU, disk-write and slow-launch reports with their call
stacks.

## Where it lives

| Piece | File |
| --- | --- |
| Records, ledger, math, report | `ForgeCore/Sources/ForgeCore/Reliability/` |
| MetricKit subscriber | `ForgeCore/.../Reliability/ReliabilityMetricKit.swift` |
| Session lifecycle | `ForgeSwift/ReliabilityMonitor.swift` (started in `ForgeAppDelegate`) |
| ARIA turns | `AriaService.sendMessage` (`AriaTurnTrace`) |
| Screen | `ForgeSwift/ReliabilityView.swift` (Settings › About Forge › long-press the version) |
| Tests | `ReliabilityLogTests`, `ReliabilityPrivacyTests` |

The ledger is `Application Support/Forge/Reliability/reliability.json`:
excluded from backup, protected until first unlock. Console filter:
subsystem `com.forge.core`, category `reliability`. Instruments: the
`aria` signpost track now carries an `ariaTurn` interval per turn, plus
`ariaFailure` and `ariaFallback` events.

## Privacy rule

Outcome metadata only: enums, counts, durations, dates, HTTP statuses and
system error codes. Never a message, a health value, a name, a server
response body or an error's description. `ReliabilityPrivacyTests` pushes
user-shaped text through every error path and checks the ledger file and the
exported report.

## Adding a cloud path later

The report is `Codable` (`ReliabilityReport`, format
`forge-reliability-report` v1). A later upload would POST the report (or the
summary alone) to an endpoint behind Forge's own AWS backend, which writes
CloudWatch metrics (for example `AriaReplySuccess` and `CrashFreeSession`
by app version) and alarms on the 99.9% gate. That needs an opt-in, a
privacy-manifest entry (Crash Data, Performance Data, Other Diagnostic Data:
not linked, not tracking), and the matching App Store privacy answers. None
of that is in this change.
