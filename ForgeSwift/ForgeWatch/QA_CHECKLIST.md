# ForgeWatch — QA Checklist (Phase 5)

Run on a Mac with Xcode (watchOS + iOS platforms installed). Paired
simulators: iPhone 16/17 + Watch Ultra 2 (49mm) and Series 9/10 41mm.

## Visual matrix

| Screen | 41mm | 45/49mm | Always-On dim | Reduce Motion | Minimal Animation |
|---|---|---|---|---|---|
| Onboarding (3 pages) | ☐ | ☐ | n/a | ☐ | ☐ |
| Home (orb, greeting, cards) | ☐ | ☐ | ☐ orb frozen, ring dimmed | ☐ static orb | ☐ static orb |
| Mindfulness pre-session | ☐ | ☐ | n/a | ☐ | ☐ |
| Breathing session | ☐ 60s watch: no dropped frames | ☐ | ☐ paused canvas | ☐ opacity-only | ☐ opacity-only |
| Workout start / countdown | ☐ | ☐ | n/a | ☐ no scale pulse | ☐ |
| Workout metrics page | ☐ | ☐ | ☐ dimmed heart | ☐ | ☐ |
| Sleep summary + timeline | ☐ | ☐ | ☐ | ☐ | ☐ |
| Context screen (modes/places/settings) | ☐ | ☐ | n/a | ☐ | ☐ |
| 4 complications × 4 families | ☐ | ☐ | ☐ AOD legible | n/a | n/a |

Dynamic Type: repeat Home + Mindfulness + Workout metrics at the largest
watch text size — no clipped labels, the breathing instruction stays below
the orb (VStack, not offset).

## Behavior passes

- [ ] Onboarding shows exactly once; "Not now" path lands on honest empty states.
- [ ] HealthKit sheet strings match the calm copy (no truncation).
- [ ] 90s Physiological Sigh: haptics at every phase turn (Gentle + Strong),
      pause/resume keeps orb + haptics in sync, early end ≥30s still logs.
- [ ] Skip-with-note: all four reasons acknowledge warmly, nothing nags after.
- [ ] Mindful Minutes sample visible in Health after a session; NO workout
      entry from the discarded `.mindAndBody` sensor tap.
- [ ] Workout: countdown haptics → live HR/zone within ~15s in sim (Features →
      Heart Rate), zone bar tracks, coaching cue appears once per zone change
      (≥45s apart), rest timer counts with 3-2-1 clicks, End saves a real
      workout to Health, summary stats sane.
- [ ] Post-workout body-scan handoff: one tap → session starts; "Done for now"
      is guilt-free.
- [ ] Live Activity: appears on paired iPhone lock screen within ~5s of
      workout start, updates ~1 Hz, Dynamic Island compact + expanded render,
      ends (with 10-min linger) when the watch ends the session.
- [ ] Complications: add all 4; readiness/sleep update within ~2s of an app
      refresh; Mindful Reset deep-links into the pre-filled session; Active
      Workout flips live within seconds of starting.
- [ ] Sleep: summary renders stage timeline from last night's sim fixture;
      factor chips toggle and appear in the story; "Remind me" schedules one
      notification at the predicted time (Settings → Notifications on watch).
- [ ] Places: save Gym at current sim location (Features → Location → Custom),
      set HR high, relaunch → "Looks like gym?" suggestion; never auto-switches.
- [ ] VoiceOver: swipe order sane on every screen; scores read with
      supportive descriptors; breathing guide explains its haptic language.

## Battery & performance (Instruments, on-device)

- [ ] Time Profiler during a 3-min breathing session: main thread quiet
      between frames, Canvas draw < 2ms typical on S9.
- [ ] Energy log for a 30-min workout: no unexpected background HR polling
      (1 Hz publish path only while session runs).
- [ ] Complication timeline reloads: confirm only on phase changes + 1/min
      during workouts (os_log or breakpoint on reloadAllTimelines).
- [ ] App launch → Home meaningful paint < 1.5s on Series 9.

## Automated

- [ ] `swift test` in `ForgeSwift/ForgeCore` — all suites green
      (readiness, suggestion engines, sleep intelligence, context rules,
      workout models).
- [ ] CI `build` check green on the PR head.
