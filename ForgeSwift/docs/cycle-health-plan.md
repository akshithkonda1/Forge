# Cycle Health: Point A → Point B

**Status (this branch):** Implemented. Cycle Vault, 12-month clinician Rhythm report, Discretion Mode, iMessage-only support (Partner / Relative / Parent, including parents of minors), high-accuracy learning, and ARIA lifestyle-goal training prescriptions.

Privacy tenet: wrapping key in Keychain (`AfterFirstUnlockThisDeviceOnly`), ciphertext in `Application Support/ForgeCycleVault/` (`live.box` + `months/YYYY-MM.box`, 12 retained), no Forge servers, SMS invites are not valid access.

Implementation:

- `ForgeCore/.../CycleVault.swift` — AES-GCM archive, 12-month boxes, wipe + month purge
- `ForgeCore/.../CycleRhythmModels.swift` — discretion, lifestyle goals, period training style, clinician text
- `MenstrualHealthStore+Vault.swift` — migrate off `UserDefaults`
- Settings → You → Cycle privacy — Discretion Mode + Vault + lock + high-accuracy
- My cycle — extra-care ping, training card, Vault report sheet
- Support invite — iPhone + iMessage only; CloudKit URL withheld from SMS

**North star:** the best personal cycle tracker *and* the best support product for the people around you, with privacy, security, and discretion as the product — not a footer.

**Wedge vs the market:** Flo and Clue win on symptom encyclopedias. Natural Cycles wins on contraception clearance. Apple Cycle Tracking wins on being on-device and boring. Forge’s unique shot is *personal rhythm intelligence + role-aware support + training/recovery*, with reproductive data that never lives on Forge servers.

---

## 1. Product thesis

Cycle Health has two users who must both feel it is the best thing they have used:

1. **The person whose cycle it is.** The app learns *their* bleed length, luteal length, ovulation signals, pain/symptom shape, and prediction error — then evaluates that cycle honestly (lifestyle, not diagnosis).
2. **The people who show up.** Mom, dad, brother, sister, boyfriend, girlfriend, wife, husband, friend. They get a job: *how to help today*. They do not get a diary.

Those two surfaces already exist as **My cycle** and **Support**. Support is the one that is most unfinished relative to the ambition. Privacy is the constraint that decides *how* we amplify it, not whether we do.

### The privacy promise we can actually keep

The request was: *your data never leaves; cybersecurity comparable to Apple’s.*

We should keep the *intent* and be precise in product copy. Today some data *does* leave the device, by design:

| Channel | What leaves | Who holds it | User control |
|---|---|---|---|
| Local logs | Nothing | This iPhone | Default |
| HealthKit | Flow / BBT / OPK samples the user already put in Apple Health | Apple, if iCloud Health is on | Apple’s Health privacy |
| CloudKit share | A **redacted** `PartnerCycleDigest` only | Apple CloudKit, invited Apple IDs | Invite, pause, revoke |
| ARIA / Bedrock | A **coaching snapshot** (`CycleAIContext`), not day-level logs | AWS as processor for that request | `Share with ARIA` off by default |

Forge DynamoDB / Lambda **must stay out of this**. There is no Forge-side pairing service and there must not be one. That is the real “your data never leaves *us*” guarantee, and it is already the architecture of `PartnerCycleSharing`.

We will **not** claim HIPAA coverage, Apple-level invincibility, or “impenetrable.” We *will* match Apple’s *model*: on-device first, hardware-backed encryption, user-gated sharing, lock-screen discretion, and nothing on Forge servers to subpoena.

Reproductive data is treated as the most sensitive class in the app regardless of whether Forge is a HIPAA covered entity. Post-Roe threat model: a leaked log is not an embarrassment; it is a legal and safety event.

---

## 2. Point A — what is already there

### 2.1 My cycle (tracker + engine)

This is further along than the Support tab. The local engine in `MenstrualCycleEngine` is already a serious FAM-style stack, not a 28-day cookie cutter.

**Learn (already shipping)**

- Period episodes clustered from flow days; cycle length = recency-weighted robust median of inter-start intervals, outlier-clipped per condition.
- Period length learned and clamped to 3–7 days (`CycleBiology`), so “how long is my period” and “am I still bleeding” cannot disagree.
- Ovulation hierarchy: LH surge → BBT 3-over-6 shift → peak fertile mucus → fallback `cycleLength − luteal`.
- Learned luteal days from confirmed cycles; EMA calibration offset from prediction error.
- Period-end confirmation vs observed stop vs projected end — UI must not present a projection as a fact.
- Period-end feedback → `PeriodCoachingPreferences` (recovery bias, heat, empathy tone, training lightness).
- Conditions change the model, not just the copy: PCOS / endometriosis / perimenopause / thyroid (`CycleCondition`).
- Goals: general wellness, TTC (two-week wait), family planning.
- High-accuracy mode nudges BBT + OPK in the fertile window.
- HealthKit import of menstrual flow and related samples.
- Honest accuracy: forecast archive scored against actual starts (MAE), data-quality grades from `CycleDataEvaluator`.
- Local ARIA analyst: Understand → Evaluate → Teach, available offline. Bedrock only if Share with ARIA is on, and only a redacted context.

**Evaluate (already shipping, under-surfaced)**

- Phase + lifecycle stage (still bleeding vs period finished).
- Next period as a *range* (earliest / median / latest), not a fake exact date.
- Separate confidence for period timing vs ovulation.
- Irregularity flag suppressed for PCOS / perimenopause unless variance is extreme.
- Signal conflict when LH and BBT disagree.
- Training / recovery notes tied to phase (`MenstrualPhase.trainingBias`).
- Insights list + accuracy explainer sheet.

**UI (already shipping)**

- Two-pane `MenstrualHealthView`: My cycle | Support.
- Phase orbit, stage card, quick log (flow, symptoms, BBT, OPK, mucus, pain 0–10, notes).
- Day strip, prediction grid, fertile score (self only), TWW card, history, settings, wipe.
- Home tile (`HomeCycleModule`) + support pulse card.
- Watch glance, Live Activities, lock-screen `CyclePhaseWidget`.

**What “best tracker” still lacks**

| Gap | Why it matters |
|---|---|
| Learning is mostly invisible | Users cannot *feel* the engine getting smarter. Flo/Clue win on “the app knows me.” We have MAE, luteal learning, and coaching prefs — they need a first-class **Rhythm report**. |
| No month calendar | Day strip is not how people scan a cycle. |
| No symptom-pattern cards | 20+ symptoms are logged; almost none are clustered (“cramps usually start 2 days before”). |
| No contraception *protocol* | Boolean `usesHormonalContraception` is not pill/IUD/implant/patch day tracking. |
| No pregnancy / postpartum / amenorrhea modes | Best-in-market trackers cover the whole reproductive arc. |
| One giant screen | Logging, predictions, ARIA, sexual health, sharing, and settings compete. |
| Web / Android = zero | `src/` has no cycle surface. iOS is the product for this feature. |
| Gendered support copy | `CycleStage.partnerLabel` says “her period.” That fails husbands/partners of people who don’t use she/her, and it fails sister/brother copy. |

### 2.2 Support tab

This is the distinctive product. The privacy architecture is unusually careful. The *experience* is still thinner than the ambition.

**Already shipping — keep this, do not regress it**

- Roles: romantic, child, family, friend, other (`CycleSupportRole`), with suggested labels (partner / wife / husband / girlfriend / boyfriend / daughter / sister / mom / friend).
- **First-class people**, not one “partner” slot: `SupportedPerson` list, each with own logs, settings, CloudKit owner id.
- Consent (adult) vs caregiver care (child) before logging.
- Two support modes:
  1. **They share with you** — CloudKit `CKShare`, dedicated zone `PartnerCycleDigest`, redacted digest only.
  2. **You log what they told you** — local notes on your phone, never written to their HealthKit.
- Share depth chosen by the owner: On period? / Support coach (recommended) / Timing too. Fertile window, ovulation, TTC, flow volume, symptoms, BBT, notes are **never** in any tier.
- Fertile + ovulatory days collapse into “Energy building” so a digest cannot become a conception calendar.
- `PartnerSupportLens`: intimacy copy only for romantic roles; parent playbook only for child; “What you can’t see” always last.
- Invites expire in 14 days. iMessage bubble is deliberately vague (`would like your support`). Pause publishes an empty digest instead of leaving a stale “still on their period.” Stale after 3 days.
- Per-person revoke. Watch/lock **support** glance is lock-safe: “Kind” / “OK” — never “period,” never a day count (`PartnerSupportGlance`).
- CI gate: `scripts/check-partner-redaction.sh` forbids `MenstrualCycleSnapshot` in supporter-facing files. Tests in `PartnerCycleDigestTests` + `PartnerInvitePayloadTests`.
- Role-aware coaching (`PartnerSupportCoach`) for romantic / parent / family-friend, including the period-finished hand-off.
- Launch routing: non-female profiles with tracking off open Support, not My cycle (`CycleHealthLaunch`).

**What “amplified support” still lacks**

| Gap | Why it matters |
|---|---|
| Roles are too coarse | Dad, brother, sister, and mom all dump into **Family** (or Child). The user named those people on purpose — they need different jobs, not one “family” essay. |
| Internal name is still “partner” | Pane `.partner`, `partnerContent`, `partnerSnapshot`. The UI says Support; the code still thinks spouse. That leaks into copy and makes a brother-shaped feature feel like a boyfriend feature. |
| Coaching is our script, not their voice | Owner has `PeriodCoachingPreferences`. Supporters never see “how I like to be helped.” The missing object is an owner-authored **Support card** that *is* the share, not a diary leak. |
| Incoming vs outgoing mixed | One tab is: people I support locally, digests shared *with* me, and “invite someone to support *me*” (which actually lives on My cycle). A dad and a girlfriend do not have the same job. |
| Manual logging vs live share feels the same | Logging a daughter’s start because she told you is care. Logging a partner’s fertility signs is surveillance — the store already comments this line. The UI does not make that line loud enough. |
| No “I need extra care” signal | Owner must either share more data or text separately. A one-bit, no-details ping is the highest-leverage support feature that still respects the redaction boundary. |
| No supporter literacy track | A brother who has never bought pads needs *education*, not a phase clock. Right now we jump to “how to show up today” with no onboarding for the supporter. |
| Templates do not learn | Same four moves every luteal week. After three cycles a husband should see what *this* person actually wanted last time — from the owner’s Support card + period-end feedback, never from symptom logs. |
| Home / widgets can over-share for the *owner* | Support complications are lock-safe. `CyclePhaseWidget` prints **Period / Fertile / Ovulation / Day N** on the lock screen. Home tile shows phase + day. That is the opposite of discretion. |

### 2.3 Privacy, security, discretion — honest audit

**Designed well**

- Device-first logs. No Forge backend for cycle records.
- CloudKit-only sharing; dedicated zone so a share root cannot grow into other records.
- Single redaction crossing: `PartnerCycleDigest.init(redacting:)`. Memberwise init is `private`. Headline is derived from coarse fields so prose cannot smuggle fertility.
- ARIA gated by `shareWithAria`. System directive forbids secondary use.
- Wipe exists. Privacy acknowledgment before tracking.
- Invite payload designed so a leaked iMessage does not reveal that the sender menstruates.

**Not Apple-grade yet — this is the real security gap**

Cycle logs, settings, supported-people rows, prediction feedback, and coaching prefs persist in **`UserDefaults`** (`forge.menstrual.logs.v1` and friends). That is an unencrypted plist in the app container. It rides along in unencrypted backups. `SecureStoreMigration` already moved *some* sensitive keys to Keychain — including `forge.cycle.sharing.digest` and `forge.menstrual.quiet.sync.at` — and the comment on that list calls reproductive health “the most consequential.” The actual logs were never migrated.

App Group `UserDefaults` also holds `PartnerSupportGlance` and watch cycle snapshots in the clear.

Until logs live in a hardware-backed or file-protected vault, “comparable to Apple” is not true, no matter how good the CloudKit redaction is.

**Discretion holes**

- Owner lock-screen widget names the period and fertile window.
- Live Activity for fertile window is useful for TTC and dangerous for stealth.
- Notifications for period / fertile window (settings exist) can appear on a lock screen the user does not control (shared phone, work Watch).
- No PIN / biometric gate on the Cycle Health page itself.
- No stealth app label / hide-from-recents option.

---

## 3. Point B — what “locked and loaded” means

A user should be able to say all of the following, and have the app make them true:

1. **It learned me.** After ~3 cycles I can open a Rhythm report and see *my* median, *my* variability, *my* usual bleed, *my* luteal, *my* symptom timing, and how many days off last month’s prediction was — in language that never diagnoses me.
2. **It evaluates this cycle.** “This bleed is a day longer than your median, still in your normal band” vs “this is outside what we’ve seen — talk to a clinician if it keeps happening.” Lifestyle, not ICD-10.
3. **The people who love me know how to show up — and nothing else.** Dad gets a supply + dignity playbook. Brother gets literacy + “don’t joke.” Partner gets comfort + (if romantic) intimacy that is *not* a conception calendar. Sister gets peer support. All of them can be paused or cut off in one tap.
4. **I am not in the transcript.** Lock screens, widgets, Watch, iMessage, and screenshots cannot out me. Sharing is opt-in, tiered, revocable, and stale-aware.
5. **Forge cannot sell, train on, or be forced to produce my chart** because Forge does not have it.

---

## 4. Suggestions — pick before we write code

Five packages. They stack. **Vault is the foundation**; shipping richer sharing on top of plaintext `UserDefaults` is the wrong order.

### S1 — Cycle Vault (security foundation)

**Do this first.** Makes the privacy tenet real.

- Move `forge.menstrual.*` logs, settings, people, feedback, forecasts, coaching prefs out of `UserDefaults` into `SecureStore` / encrypted file (`NSFileProtectionComplete` + CryptoKit; Keychain for the wrapping key; `ThisDeviceOnly` so iCloud backups do not carry a plaintext chart).
- Extend `SecureStoreMigration.sensitiveKeys` and delete the plist originals only after a successful write (same pattern already used for tokens).
- Stop writing full cycle phase into the App Group snapshot used by lock-screen widgets unless Discretion Mode allows it.
- Product copy rewrite: “Forge never stores your cycle. It stays on this iPhone. If you invite someone, Apple CloudKit holds a support view you chose — not your log. ARIA sees cycle context only if you turn that on, and only for that chat.”
- Threat-model page in Settings (devices, backups, sharing, ARIA) with a one-tap wipe.

**Not in scope:** claiming HIPAA, SOC2 theatre, or “impenetrable.”

### S2 — Support OS (amplify the second tab)

This is the feature that can actually be “the best on the market,” because almost nobody else is building it.

**Role packs, not one Family bucket**

| Pack | Job | Never |
|---|---|---|
| Partner / spouse | Comfort, load-sharing, (romantic only) intimacy & consent | Fertility calendar, mood-as-ammunition |
| Girlfriend / boyfriend | Same as partner, lighter household assumptions | Same |
| Mom / sister | Peer, supplies, “I’ve been there” | Commentary on their body |
| Dad / brother | Literacy + practical help + dignity | Jokes, asking “are you on your period?”, any sexual content |
| Friend / roommate | Logistics, cover, quiet | Medical questions |
| Parent / caregiver (minor) | Supplies, school/sports flexibility, when to escalate pain | Body commentary, intimacy section (already gated — keep the test) |

Concrete UI:

- Support tab splits into **People I support** and **People supporting me**.
- Adding a person starts with *who they are to you*, not a blank “partner” form.
- Rename pane `.partner` → `.support` in a dedicated refactor so copy cannot drift.
- Gender-neutral labels: use their name, never “her,” unless the owner set pronouns.

**Owner-authored Support card (the share-friendly object)**

The owner writes, once, things like:

- “Please don’t ask if I’m on my period. Just put the heating pad out.”
- “I want space the first two days.”
- “Help with dinner is the actual help.”

That card is *allowed* to travel in the digest because the owner composed it for supporters. Symptom logs still never travel. This is how support gets personal without becoming surveillance.

**Need Extra Care — one bit, no details**

A control on My cycle: “Let them know I could use extra care.” Sets `extraThoughtfulnessHelps = true` (already a digest field) without changing phase, day count, or copy that names a period. Pause still wins. Expires after 48 hours.

**Supporter first-run**

When someone accepts a share, they get a 60-second literacy track for *their* role (dad ≠ boyfriend), then today’s glance. No charts. No “learn her cycle.”

**Daily ritual for the supporter**

Three moves, generated on *their* device from digest + lens + Support card (`SupporterGuidance` already exists for this). Notification uses `PartnerSupportGlance.lockScreenLine` only.

### S3 — Rhythm intelligence (make the tracker *feel* like it learned you)

Do not bolt on 50 more symptoms. Surface the model we already run.

- **Rhythm report:** median cycle, MAD, usual bleed, learned luteal, prediction MAE, “this cycle vs you.”
- **Pattern cards:** “Cramps in 4 of your last 5 late-luteal windows.” Local, deterministic, from `CycleDayLog.symptoms`.
- **This-cycle evaluation:** in-band vs unusual vs “not enough history,” using `CycleDataEvaluator` + condition-specific ranges. Always lifestyle language; clinician nudge only for severe pain / haemorrhage-style flags we already treat as red flags in endometriosis copy.
- **Month calendar** for the owner only. Supporters never get a calendar.
- Make calibration visible: “We shifted next period by +1 day because last start was later than predicted.”

Keep the medical line we already have: not diagnosis, not contraception. TTC and family-planning goals stay self-only.

### S4 — Discretion Mode

Default-safe for a shared phone / work Watch.

- Cycle page behind Face ID (optional, off by default would be wrong — **on by default for cycle**, or at least prompted).
- Lock-screen / Watch / Live Activity: owner picks Stealth (hidden), Kind (support-style “take it easy”), or Clinical (today’s phase + day). Support glance stays Kind always.
- Notifications: never include the word period / fertile / ovulation in the title. Body is lock-safe; details in-app.
- Home tile in stealth: “Cycle Health” + padlock, not “Luteal · Day 22.”
- Invite SMS/iMessage already vague — keep the test that forbids cycle vocabulary in `PartnerInvitePayload`.

`CyclePhaseWidget` as it exists today is incompatible with Discretion Mode. It should read the same stealth setting or not be installed on the lock screen.

### S5 — What we should not build (on purpose)

- Sharing ovulation, fertile score, TTC, flow, BBT, or notes with anyone. The digest boundary is the product.
- A Forge account graph / phone-number pairing / DynamoDB “partner link.” CloudKit or nothing.
- Using support mode to reconstruct someone else’s fertility profile from “helpful” extra fields.
- App-as-contraception. Education is allowed; clearance is not the goal of this plan.
- Diagnosing PCOS / endo from logs. Conditions are *user-stated* and change interpretation.
- Auto-posting cycle phase into social, photos, or workout share cards.
- Web/Android cycle in this pass. iOS is where HealthKit, CloudKit, and Keychain make the privacy story true.

---

## 5. Recommended sequence (A → B)

Build in this order even if Support is the exciting part. Sharing more on a plaintext store is how “best tracker” becomes a headline for the wrong reasons.

| Step | Package | What “done” looks like | Risk if skipped |
|---|---|---|---|
| **0** | S1 Vault | Logs + people + prefs not in `UserDefaults`; wipe still works; migration tested | Everything else sits on a plist |
| **1** | S4 Discretion (lock + widgets) | Lock screen cannot say “Period”; Face ID option; Home tile has a stealth state | Support amplification leaks via the owner’s own widgets |
| **2** | S2 Support OS | Role packs, split inbox, Support card, Need Extra Care, supporter first-run, de-gender copy | Support tab stays a thinner partner tracker |
| **3** | S3 Rhythm report | Owner can see what the engine learned and how this cycle compares | Tracker does not *feel* best-in-class |
| **4** | Rename / IA | `.partner` → `.support`; My cycle vs Support information architecture cleaned | Copy and bugs keep saying “partner” to a dad |

Each step is a shippable slice with tests. Do not batch 0–3 in one PR.

### Tests that already encode the law — do not weaken them

- `PartnerCycleDigestTests` — tiers, JSON denylist, fertile collapsed into rebuilding.
- `PartnerInvitePayloadTests` — invite text cannot contain cycle vocabulary.
- `scripts/check-partner-redaction.sh` — CI forbids snapshot types in supporter UI.
- `MenstrualCycleEngineTests` — period-end confirmation, condition ranges, ovulation hierarchy.
- `CycleHealthLaunchTests` — Support vs My cycle routing.

New tests to add as we implement: vault migration (UserDefaults emptied), stealth widget copy, Support card cannot contain engine fields, Need Extra Care does not change `phase` / `periodDay`.

---

## 6. Architecture (unchanged spine)

```
Owner iPhone                         Supporter iPhone
────────────                         ────────────────
CycleDayLog (vault)                  PartnerCycleDigest (CloudKit)
       │                                      │
MenstrualCycleEngine  ──redact──►  CKShare zone “PartnerCycleDigest”
       │                                      │
MenstrualCycleSnapshot               PartnerSupportLens + Support card
       │                                      │
My cycle UI                          Support UI + lock-safe glance
       │
Share with ARIA? ──no──► local CycleAriaAnalyst only
                 ──yes─► CycleAIContext (session processor, not storage)
```

Forge backend stays off this diagram.

---

## 7. Decision points for the next pass

Reply with which packages to implement, in which order. Suggested default if you just say “go”:

1. **S1 Cycle Vault** (privacy tenet becomes true)
2. **S4 Discretion Mode** for owner widgets / Home / notifications
3. **S2 Support OS** — role packs + Support card + Need Extra Care (the amplification)
4. **S3 Rhythm report** — learn/evaluate made visible

Questions that change the design if you have a preference:

- Should Discretion Mode be **on by default**, or prompted once?
- For dad/brother packs, is *any* bleed-day count too much, even on Support coach? (Today Support coach shares day 1–N while bleeding.)
- Is Need Extra Care allowed to notify immediately, or only on the next digest publish (~90s throttle)?
- Any roles besides the ones listed (coach, teammate, roommate already maps to friend)?

---

## 8. File map (for implementers)

| Area | Where it lives |
|---|---|
| Engine | `ForgeSwift/Services/MenstrualCycleEngine.swift` |
| Evaluate | `ForgeSwift/Services/CycleDataEvaluator.swift`, `Models/CycleQualityModels.swift` |
| Owner UI | `Views/Menstrual/MenstrualHealthView.swift` |
| Support UI | same file (`partnerContent`), `SupporterDigestView.swift`, `CycleSharingView.swift` |
| Redaction | `Models/PartnerCycleDigest.swift` |
| Sharing | `Services/PartnerCycleSharing.swift` |
| Guidance | `Services/SupporterGuidance.swift`, `PartnerSupportCoach.swift` |
| Persistence | `Services/MenstrualHealthStore+Vault.swift` → Cycle Vault (legacy `UserDefaults` is migrate-then-delete) |
| Vault | `ForgeCore/Security/CycleVault.swift`, `SecureStore.swift` |
| Privacy copy | `Models/CyclePrivacy.swift` |
| Lock-screen leak | `ForgeWidgetExtension/CyclePhaseWidget.swift` |
| Lock-safe support | `ForgeCore/Utils/PartnerSupportGlance.swift` |
| Invite discretion | `ForgeCore/Models/PartnerInvitePayload.swift` |
| CI gate | `scripts/check-partner-redaction.sh` |

---

## 9. Competitive teardown — Drip, Flo, Clue, Apple, Natural Cycles

The job is not “more symptoms.” It is: **on-device reproductive data + a support OS nobody else has + training that respects the bleed.** Forge does not claim HIPAA, “impenetrable,” or app-as-contraception.

### Drip (the privacy gold standard we steal from, then beat)

What Drip gets right: no account, symptothermal math you can inspect, CSV export, optional password, data stays on the phone. That is the threat model.

Where Drip loses, and Forge ships the gap:

| Drip | Forge |
|---|---|
| Local DB, optional app password | **Cycle Vault** — Keychain wrapping key + AES-GCM files (`live.box`, 12 month boxes), `completeFileProtection`. Not a plist. |
| No clinician pack | Rolling **12-month Rhythm report** (counts/medians/pain/symptoms). Fertile timing, notes, sex, mucus, BBT stay out. Share sheet is user-initiated. |
| No support network | **Partner / Relative / Parent** (parents of minors allowed). CloudKit redacted digest only. |
| No invitation channel discipline | **iPhone + iMessage only.** SMS, email, and a pasted CloudKit URL are invalid access. Fallback copy carries no redeemable URL. |
| No lock-screen policy | **Discretion Mode** in Settings/You: Stealth / Kind / Clinical. Widgets, Home, notifications, Live Activity honor it. Face ID gate in stealth. |
| No coach | **ARIA** asks the training goal (running/endurance/strength/mixed) and a period style (skip / easy / shorter / usual). Example: loves running, hates running on her period → cap or skip miles while bleeding, rebuild after. |
| No high-accuracy learning | Binary high-accuracy toggle. When on, BBT/OPK cues fire and learned period-end prefs tighten today’s volume cap. |

Drip is a diary with integrity. Forge is a diary with integrity **plus** a job for the people who show up **plus** a training translation.

### Flo

Feature encyclopedia, community, predictions. Historically a **server-side** product with a privacy record that is the opposite of post-Roe. Flo wins on content volume. Forge wins on: Forge never holds the chart; supporters never see a chart; lock screens cannot out you; training is phase-aware without sending the log to train a model.

### Clue

Stronger science communication than Flo, EU posture, still an **account/cloud** cycle. No iMessage-gated support OS. No clinician 12-month vault. No “run X easy miles on your period, then rebuild.” Clue is a better tracker than most. It is not a support product.

### Apple Cycle Tracking

On-device, HealthKit, boring in the best way. No ARIA, no support invites, no Rhythm report you can hand a gynecologist, no discretion policy for the lock screen widget you install. Forge uses Apple’s model (device-first, hardware-backed keys) and then adds the product Apple will not ship: support + coaching.

### Natural Cycles

FDA-cleared contraception. **Explicit non-goal.** Forge must never compete here. TTC / family-planning goals stay self-only. Clinician report and ARIA copy both say Forge is not birth control.

### Euki / other local education apps

Local and educational. Not a FAM engine, not a support OS, not a training coach. Respect the lane; do not copy the encyclopedia.

### What “destroy” actually means in product copy

Do not trash competitors in the UI. Beat them in the architecture:

1. **Vault, not UserDefaults.** Drip’s privacy intent, Apple’s keychain model.
2. **Support nobody else has**, with a channel constraint (iMessage/iPhone) that is the access-control, not a preference.
3. **Rhythm report** a gynecologist can use as tracking evidence — not a diagnosis.
4. **ARIA translates goals** (especially running-on-period) instead of a static luteal essay.
5. **Discretion** so the owner’s own widgets cannot leak what the supporter glance already refuses to say.

Still not in this pass (on purpose): month calendar polish, symptom-pattern cards, contraception protocol, pregnancy/postpartum modes, web/Android cycle.
