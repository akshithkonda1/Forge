# ARIA voice

Preferred live mouth: Fish Audio S2.1. Ordered fallbacks: Fish → Polly →
on-device. ElevenLabs stays as a disabled next-evolution slot behind the
same interface. This is the follow-up to merged PR #480.

## Architecture

| Method | Path | Role |
| --- | --- | --- |
| `GET` | `/ai/voice` | Featured profiles + Fish library page |
| `PUT` | `/ai/voice` | Persist the selected voice on the account |
| `POST` | `/ai/voice/speak` | Already-guarded prose → `{provider, format, model, audio_base64, …}` |

The phone never receives the Fish key. Dummy / local testing / dummy-offline
never call Fish, Polly, or ElevenLabs — they use on-device speech.

Speak does not fuse, remember, observe, or touch personality
(Coach / Friend / Drill Sergeant). Safety rails are unchanged.

## Provider selection

`services/voice_provider.py` is the single resolver:

1. **Fish** — preferred when `ARIA_FISH_VOICE_ENABLED` is on, a key is
   present, the free promo is still active (or paid / after-promo is on),
   and the line is clean and under the daily char cap.
2. **Polly** — only after a Fish error, timeout, 429 (concurrency 5), or
   promo expiry, and only if `ARIA_POLLY_VOICE_FALLBACK` is on.
3. **On-device** — Dummy, offline, over-quota, privacy-unguaranteed text,
   or any cloud failure when Polly is off.
4. **ElevenLabs** — registered slot (`ARIA_ELEVENLABS_VOICE_ENABLED`).
   Off by default. Not in the live fallback chain. `synthesize` refuses.

## Model

Exact API ids from [Fish models](https://docs.fish.audio/developer-guide/models-pricing/models-overview):

| Spoken name | API id | Price | Default |
| --- | --- | --- | --- |
| S2.1 Pro (free) | `s2.1-pro-free` | $0 | Yes |
| S2.1 Pro | `s2.1-pro` | $15 / M UTF-8 bytes | Off |

A missing or wrong `model` header silently bills paid `s2.1-pro`. Every
Fish request sets the header **and** the JSON `model` field. They are
always `s2.1-pro-free` unless `FISH_AUDIO_USE_PAID=true`. Setting
`FISH_AUDIO_MODEL=s2.1-pro` alone is not enough.

`s1` is never selected.

## Free promo expiry

`FISH_FREE_PROMO_ENDS` defaults to `2026-11-30`. After that date Fish is
not called unless `FISH_AUDIO_USE_PAID` or `ARIA_FISH_AFTER_PROMO` is
truthy. Speak then falls back to Polly / on-device.

Free-tier Fish is for development and internal TestFlight only. Fish
terms may train on requests, have no zero-retention, and limit free
accounts to non-commercial use.

## Zero leakage

Text is sanitized before any cloud TTS call (`services/tts_privacy.py`,
`AriaTTSPrivacy`, `sanitizeTTSText`). Names, emails, phones, street
addresses, and health-metric numbers (HRV, readiness, bpm, hours of
sleep, …) never appear in Fish or Polly URLs, headers, bodies, or logs.
If sanitization cannot guarantee the line is clean, the mouth is
on-device. TTS text is never request/response logged.

ARIA's spoken coaching copy itself still leaves the device to reach Fish
when the line is qualitative and the flag is on.

## Config (all live calls stay off until you flip the kill switch)

| Name | Where | Default | Role |
| --- | --- | --- | --- |
| `ARIA_FISH_VOICE_ENABLED` | Lambda env | off | Single kill switch for live Fish calls |
| `FISH_AUDIO_API_KEY` | SSM / Secrets Manager only | unset | Production key. Process env overlay is tests / local only |
| `FISH_AUDIO_API_KEY_PARAMETER_NAME` | Lambda env | unset | SSM name, e.g. `/forge-dev/ai/FISH_AUDIO_API_KEY` |
| `AI_PROVIDER_SECRET_ARN` | Lambda env | unset | Optional Secrets Manager JSON with `FISH_AUDIO_API_KEY` |
| `FISH_AUDIO_MODEL` | Lambda env | `s2.1-pro-free` | Ignored for paid unless the opt-in is on |
| `FISH_AUDIO_USE_PAID` | Lambda env | off | Explicit paid `s2.1-pro` opt-in |
| `FISH_FREE_PROMO_ENDS` | Lambda env | `2026-11-30` | Free-tier expiry |
| `ARIA_FISH_AFTER_PROMO` | Lambda env | off | Re-enable Fish after the promo without paid |
| `ARIA_FISH_DAILY_CHAR_CAP` | Lambda env | `20000` | Per-user daily UTF-8 char cap. `0` disables |
| `ARIA_POLLY_VOICE_FALLBACK` | Lambda env | off | Allow Polly after Fish error / timeout / 429 / promo |
| `POLLY_VOICE_ID` | Lambda env | `Joanna` | Polly voice |
| `POLLY_ENGINE` | Lambda env | `neural` | Polly engine |
| `ARIA_ELEVENLABS_VOICE_ENABLED` | Lambda env | off | Reserved slot. Does not call ElevenLabs |
| `ELEVENLABS_*` / `ELEVENLABS_*_PARAMETER_NAME` | existing SSM | unused | Reserved. This PR does not change AWS resources |

This PR does not enable live calls and does not apply Terraform or create
SSM parameters. Seed the Fish key out of band when you are ready.

## How to turn Fish on (dev / internal TestFlight)

1. Seed `/<name_prefix>/ai/FISH_AUDIO_API_KEY` (or the JSON secret) out
   of band. Do not commit it.
2. Point Lambda at it with `FISH_AUDIO_API_KEY_PARAMETER_NAME` (or
   `AI_PROVIDER_SECRET_ARN`).
3. Set `ARIA_FISH_VOICE_ENABLED=true` on the Lambda. Leave
   `FISH_AUDIO_USE_PAID` off so every request sends `s2.1-pro-free`.
4. Optional: `ARIA_POLLY_VOICE_FALLBACK=true` after Fish errors.
5. Dummy / Device Hub / dummy-offline stay on-device and never hit Fish.

## Busy slot

Starter allows 5 concurrent Fish requests and returns `429` with no
`Retry-After`. Speak retries with exponential backoff (0.25s, 0.5s, 1s)
and then falls back to Polly (if on) or on-device.

## Featured profiles

Unchanged from PR #480: Warm, Calm, Neutral, Spark, Ember. Live ids are
matched from the Fish list. UI names must not use trademarked characters.

## What PR #480 already removed

- ConvAI routes: `/ai/voice/bootstrap`, `/ai/voice/tool`, `/ai/voice/design`
- Hex alias `/ai/voice/fish-tts`

ElevenLabs Terraform parameters remain unused. This PR does not apply
AWS / Terraform changes.

## Privacy copy

Fish Audio's terms allow training on content with no opt-out. Product
privacy copy must not claim no-training until written terms are obtained.
The free tier may train on requests, has no zero-retention, and is
limited to non-commercial use — so live Fish here is for development and
internal TestFlight only.
