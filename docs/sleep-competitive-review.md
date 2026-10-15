# Forge Sleep — competitive review

Prepared for the Sleep Management System DRAFT PR. Sources: Quill / Forge Deep Research internal brief (14 Oct 2026, 6 pages, prepared for Akshith) plus first-party and press pages fetched the same day. Unverified items from the brief stay labeled.

Forge rules applied throughout: lifestyle coach, not a doctor; no “recovery” in public copy; no health data in iCloud (App Store 5.1.3(ii)); no ads on or sale of health data.

## How to read this

Weights appear only where a vendor publishes them. Reddit lines quote thread titles from the brief (comment bodies were blocked). Wearable stage accuracy is fair-to-moderate vs polysomnography; treat stages as estimates.

## 1. Twelve products

### Oura

**Measure / score.** Sleep Score 0–100 from seven contributors: Total Sleep, Efficiency, Restfulness, REM, Deep, Latency, Timing. Bands: 85+ Optimal, 70–84 Good, 60–69 Fair, under 60 Pay Attention. 100s are “designed to be rare.” Current weights are unpublished; a 2021 paper reported older API weights (duration 0.35, then 0.10 each for REM / deep / efficiency / latency / timing, 0.05 each for three disturbance terms). Treat those as historical.

**Baselines / calibration.** Readiness takes up to two weeks to learn averages. A Sleep Score needs 7 nights in the last 14; Sleep Debt needs 5 of 14; sleep need and chronotype use a 90-day window.

**Debt / energy.** Sleep Balance covers two weeks against baseline and 7–9 h AASM guidance. Body Clock uses 90 days.

**Smart wake.** Unverified first-party. No confirmed smart alarm.

**Surfaces.** iPhone widgets. Watch companion updates after iPhone sync. Live Activity for activity tracking only.

**Reviews.** Thread titles: “Sleep score never matching how I feel,” “Sleep score much higher than what I feel” (r/ouraring).

### WHOOP

**Measure / score.** Sleep Performance = hours slept / sleep need. Need is four published terms: baseline + strain + debt − naps (WHOOP API). States: PENDING_SCORE and UNSCORABLE.

**Baselines.** 30-day baseline; some metrics show immediately. Sleep Planner uses 28 days of bed and wake times.

**Smart wake.** Strap haptics that wake “when you're fully rested, or at a specific time.”

**Surfaces.** Lock Screen widgets and Live Activities cited by a third party (unverified first-party).

### Eight Sleep

**Measure / score.** Sleep Fitness Score 0–100 from quality, routine, and time slept. Weights unpublished.

**System.** Autopilot sets each side’s temperature from stages, biometrics, and room temperature.

**Smart wake.** Lightest stage inside the wake window, then chest-level vibration and warmth (search summary; treat details as unverified).

### Rise Science

**Measure / score.** Personal sleep need from up to 365 nights of “sleep rebound,” bounded by research limits, user-editable.

**Debt.** 14 nights; last night is 15% of the weight. Rise calls this “a product choice, not a published formula.” Suggests keeping debt under 5 h.

**Energy timeline.** Biomathematical circadian model (sleep times, light, activity): grogginess, morning peak, afternoon dip, evening peak, wind-down, melatonin window. High debt mutes peaks. Predictions improve with use.

**Wind-down.** Notifications for last caffeine, wind-down, and bedtime.

**Reviews (Tom’s Guide).** Praise: energy peaks/dips felt accurate; after a heavy weekend Rise “added 25 minutes to my nightly sleep need.” Complaints: 4:45 am wake “seemed a bit extreme”; no sensors so no stages; daily nudges risk orthosomnia. Price $69.99/yr after a 7-day trial.

### Sleep Cycle (with Luma)

**Measure.** Phone-only sound and motion. Smart alarm: 30 min window on iOS by default; up to 90 min advertised on Android (unverified). Snore and cough detection.

**Luma.** AI coach on OpenAI that remembers context (partners, pets) without a documented memory editor.

**Reviews.** Phone-based stages called imprecise (LivingOutlook, unverified fetch).

### Apple Sleep / Vitals / Sleep Focus / StandBy

**Sleep Score (watchOS, Sep 2025).** Duration 50, bedtime consistency 30 (last 13 nights), interruptions 20. Bands: Very Low 0–40, Low 41–60, OK 61–80, High 81–95, Very High 96+. First score after one night. Built from ~5M nights in the Apple Heart and Movement Study. Series 6+, SE 2+, Ultra.

**Vitals.** Alerts when two or more overnight metrics fall outside the personal typical range.

**Sleep apnea notifications.** Breathing disturbances in 30-day windows, ≥10 nights, notify when >50% of nights are elevated. Apple says it is not a diagnosis. **Forge must never imitate this or sound like it.**

**StandBy / AlarmKit.** AlarmKit (iOS 26+) rings a real system alarm through Silent and Focus, on Lock Screen, Dynamic Island, StandBy, and a paired Watch. Per-app authorization (`NSAlarmKitUsageDescription`). The system draws the alert UI.

**Reviews.** Macworld: earning 100 “doesn't necessarily equate to a perfect or even good night's sleep”; the score ignores RHR, HRV, and Vitals; prefers a “body battery” blend. AppleInsider and Apple Support document the 50/30/20 split.

### AutoSleep

**System.** Sleep Bank (debt and credit) settles after about a week. Readiness from HRV and waking pulse needs about a week of Watch nights. Calibration settings for sleep detection.

**Reviews.** Thread title: “Have to manually edit the data every day? :/” (r/AutoSleep). Aggregated complaints about confusing rings and conflicting readiness (unverified fetch).

### Pillow

**System.** Watch HR and motion plus iPhone audio. Smart wake 15 or 30 min early in a lighter stage. Alarms need an active Pillow session.

**Reliability.** Help article “My Alarm Did Not Go Off” — evidence that pre-AlarmKit alarms were fragile.

### Garmin (Body Battery)

**Sleep Score.** 0–100 from duration, quality (stages, awakenings, restlessness, stress during sleep), and an HRV-based term (Firstbeat). Weights unpublished.

**Sleep Coach.** Clamped to 7–9 h, updated through the day as you nap or move.

**Body Battery.** 5–100. Inputs: HRV, stress, sleep, activity. Food and caffeine have “no impact” (fēnix 9 manual). HRV status takes about 3 weeks (unverified first-party).

**Onboarding.** User picks a sleep schedule; the watch enters Do Not Disturb during it.

### Fitbit / Google Health

**Sleep Score.** Redesigned Apr 2026 around six metrics: duration, time to sound sleep, sound sleep, restlessness, full awakenings, interruptions. Personalized by age, sex, and sleep time. Weights unpublished. The older 25/50 split is not current documentation.

**Debt.** User-set sleep goal, not a computed personal need.

### Calm / Headspace

Wind-down content, not hardware scoring. Calm: Sleep Stories and soundscapes. Headspace: Sleepcasts 45–55 min that change nightly; Ebb suggests content. For Forge these are outbound links, not competitors on scoring.

### SleepScore

Phone sonar (speaker + microphone) for breathing and movement, nightly SleepScore, smart alarm. Weights and calibration unpublished (unverified).

## 2. Pattern matrix

| App | Published weights | Calibration state | Dynamic need | Smart wake | Energy timeline |
| --- | --- | --- | --- | --- | --- |
| Apple | Yes (50/30/20) | 1 night | No (fixed goal) | No (fixed alarm) | No |
| Oura | Historical only | 7/14 nights; 90 d | 90-d need | Unverified | Body Clock |
| WHOOP | Need terms via API | 30 d; PENDING / UNSCORABLE | Yes | Haptic | No |
| Rise | Debt weighting | Improves over time | 365-night need, editable | Smart wake time | Yes |
| Garmin | No | HRV ~3 wks (unverified) | Yes, 7–9 h clamp | Unverified | Body Battery |
| Sleep Cycle / Pillow / SleepScore | No | Unverified | No | Yes (window) | No |

Independent PSG validation (SLEEP Advances, 2025): consumer stage scoring is fair-to-moderate; Apple Watch Series 8 strongest among the six devices tested (κ = 0.53). Specificity for wake is weak across the set (29–52%). Forge should label stages as estimates and never present them as clinical.

## 3. Ranked lessons Forge is taking

1. **WHOOP + Garmin + Rise — sleep need from parts.** `baseline + loadAdj + debtAdj − napCredit`, clamped 7–9 h, each term in the “why,” user-overridable baseline.
2. **Oura + WHOOP — calibration as a real state.** Learning n/7, Ready, Not scorable. No published score before the minimum. One-tap “how did you feel?”
3. **Pillow + Sleep Cycle + AlarmKit — guaranteed alarm, then a smart window.** Fixed AlarmKit alarm as fallback; 15–30 min window with an earlier Watch haptic. Ask permission on first alarm set, not in onboarding. **Deferred** if AlarmKit is still risky on this SDK.
4. **Apple + Macworld — simple published score.** 50% duration vs need, 30% consistency, 20% interruptions. HRV, RHR, and training stay in ARIA’s narrative and readiness, not in the sleep score.
5. **Rise — 14-day debt with a capped payback.** Last night can weigh more; add about +25 min a night; never a guilt number. Copy: “short stretch,” not a deficit you owe.
6. **Rise + Garmin — energy timeline on glance surfaces.** Next peak/dip and wind-down on Lock Screen / StandBy / complication, labeled as estimates. **Live Activity and widget debt/need deferred**; `WindDownPlan` and `tonightWindDown` are now on the snapshot so they can follow.
7. **Rise / Tom’s Guide — at most two sleep nudges a day.** Caffeine cutoff + wind-down. Quiet-week toggle. Passive interruption level so Focus stays intact.
8. **Luma / 5.1.3(ii) — no “never leaves your phone” until `/ai/observe` is fixed.** Sleep memory stays in BodyModel, viewable. Snapshots stay on device (App Group / WatchConnectivity).

## 4. What app-store and press reviews praise vs complain about

**Praise.** Rise energy peaks/dips; Rise’s +25 min payback after a heavy weekend; Apple’s explainable 50/30/20; Oura’s unobtrusive ring; AutoSleep’s depth without a subscription; Sleep Cycle’s low-friction smart alarm; Garmin Body Battery for athletes.

**Complaints.** Score ≠ how I feel (Oura, Apple, AutoSleep). Opaque multi-factor scores. Orthosomnia from daily nudges. Alarm did not fire (Pillow). Extreme catch-up bedtimes (Rise 4:45 am). Phone-only stages feel imprecise (Sleep Cycle). Manual edits every morning (AutoSleep).

Forge’s response: one published score with weights on screen, a feeling check-in, a still-learning gate, a short-stretch meter in steel `missHex`, and at most two quiet nudges.

## 5. Sources

- Quill, Forge Deep Research. *Forge Sleep: Competitive Deep-Dive.* Internal brief, 14 Oct 2026 (6 pages). Cited throughout as the research-lead brief.
- [Apple Support — Sleep Score](https://support.apple.com/) (50/30/20, bands, one-night first score). Cross-checked via AppleInsider coverage of the Sep 2025 score.
- [Oura Sleep Health Hub](https://ouraring.com/) — 7 contributors, 7/14 and 5/14 calibration, 90-day Body Clock.
- [WHOOP developer API](https://developer.whoop.com/) — need terms, PENDING / UNSCORABLE.
- [Garmin Sleep Coach / Body Battery manuals](https://www.garmin.com/) — 7–9 h clamp, Body Battery inputs.
- [Rise Science help + Tom’s Guide review](https://www.risescience.com/) — 14-night debt, 15% last night, +25 min, energy schedule, orthosomnia warning.
- [Lifehacker — How Oura, Whoop, Garmin, Apple Watch, and Fitbit calculate sleep scores](https://lifehacker.com/health/how-your-sleep-score-is-actually-calculated)
- [SLEEP Advances (2025) — six wearables vs PSG](https://academic.oup.com/sleepadvances/article/6/2/zpaf021/8090472)
- [WWDC25 session 230 — AlarmKit](https://developer.apple.com/videos/)
- Macworld review of Apple Sleep Score (score ignores HRV / RHR / Vitals).
- Pillow help: “My Alarm Did Not Go Off.”
- Google Health Help / 9to5Google — Fitbit Sleep Score redesign (Apr 2026).

Unverified (brief §6): Oura’s current weights and smart alarm; Garmin’s 3-week HRV baseline; WHOOP widgets; Eight Sleep smart-wake details; Sleep Cycle 90-min Android window; Rise billing complaints; AutoSleep aggregated reviews; SleepScore weights.
