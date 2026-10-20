# ARIA voice

One provider. One speak path. Voice profiles are how ARIA sounds — not who
she is.

## Architecture

Fish Audio is the only TTS. The ElevenLabs ConvAI path
(`elevenlabs_voice.py`, `/ai/voice/bootstrap`, `/ai/voice/tool`,
`/ai/voice/design`) is removed. The Hex alias `/ai/voice/fish-tts` is
removed. Clients speak through:

| Method | Path | Role |
| --- | --- | --- |
| `GET` | `/ai/voice` | Featured profiles + Fish library page |
| `PUT` | `/ai/voice` | Persist the selected voice on the account |
| `POST` | `/ai/voice/speak` | Already-guarded prose → `{format, model, audio_base64, voice_id}` |

The Fish key stays on Lambda (`FISH_AUDIO_API_KEY`). The phone never
receives it. Dummy / on-device speech stays the default until
`ARIA_FISH_VOICE_ENABLED` is truthy.

Speak does not fuse, remember, observe, or touch personality
(Coach / Friend / Drill Sergeant). Safety rails are unchanged.

## Model

Exact API ids from [Fish models](https://docs.fish.audio/developer-guide/models-pricing/models-overview)
and [pricing](https://docs.fish.audio/developer-guide/models-pricing):

| Spoken name | API id | Price | Default |
| --- | --- | --- | --- |
| S2.1 Pro (free) | `s2.1-pro-free` | $0 | Yes |
| S2.1 Pro | `s2.1-pro` | $15 / M UTF-8 bytes | Off |

`FISH_AUDIO_USE_PAID=true` (or `FISH_AUDIO_MODEL=s2.1-pro`) is the single
server-side switch to the paid id. It is off by default.

`s1` (OpenAudio S1) is deprecated and retires 31 Dec 2026. This stack
never selects it. Fish speech-to-text (`transcribe-1-pro`) is a different
product and is not this mouth.

The model header is sent on TTS (`POST https://api.fish.audio/v1/tts`)
and on the voice list (`GET https://api.fish.audio/model`).

## Voice list

The backend fetches Fish's model/voice listing with the server key,
caches it in-process for 15 minutes, and pages at most four pages of 50.
Clients may filter with `?q=` and page with `?page=` / `?page_size=`.

If Fish is down, unconfigured, or the flag is off, `GET /ai/voice`
returns `source: fallback`: featured recipes with no voice ids, and speak
uses Fish's default voice (no `reference_id`). No placeholder ids are
hardcoded.

## Featured profiles

A small curated set sits on top of the full library. Each row is a trait
recipe. Live `voice_id` values are matched from the Fish list (title /
tags / description). Character-like rows are original voices described
by traits. UI names must not use trademarked characters or real actors.

| id | UI name | Traits | Speed |
| --- | --- | --- | --- |
| `warm` | Warm | Close, unhurried, a woman in the room | 1.00 |
| `calm` | Calm | Even, low, a man who is not in a hurry | 0.95 |
| `neutral` | Neutral | Clear and even, not styled as a man or a woman | 1.00 |
| `spark` | Spark | Brighter, a little faster | 1.08 |
| `ember` | Ember | Blunt, gruff, confident young tomboy coach | 1.05 |

Inspiration for Ember (docs only, never in UI): a blunt earthbender
energy in the spirit of Toph from Avatar — an original Fish voice, not a
clone and not that name.

Featured matching skips titles/tags that look like a cloned character
(including "Toph" / "Avatar"). The full library is still listed as Fish
returns it.

## Settings

The picker lives in Settings next to ARIA personality / Aria's memory.
Choosing a profile persists to the account (`ARIA#VOICE_PROFILE`) and
applies to the next spoken reply — no restart. A short sample uses
`POST /ai/voice/speak` with `preview: true`.

Personality and voice are independent. Changing Ember does not change
Coach / Friend / Drill Sergeant, and the reverse is also true.

## Busy slot

Starter allows 5 concurrent Fish requests and returns `429` with no
`Retry-After`. Speak retries with exponential backoff (0.25s, 0.5s, 1s)
and then returns `fish_voice_busy`: "Voice is busy. The text reply is
shown." The chat line is already on screen.

## What was removed

- `backend/infra/lambda/services/elevenlabs_voice.py`
- `GET /ai/voice/bootstrap`
- `POST /ai/voice/tool`
- `POST /ai/voice/design`
- `POST /ai/voice/fish-tts`

Terraform still has unused ElevenLabs SSM parameter names. This PR does
not apply AWS / Terraform changes. The owner can drop those parameters
in a later infra PR.
