# ARIA voice

The mouth is **Kokoro-82M on this iPhone**. There is no fallback chain.
Fish, Polly, and ElevenLabs are not on the runtime path. TTS text never
leaves the phone. This replaces the Fish-preferred stack on PR #496.

## Architecture

| Method | Path | Role |
| --- | --- | --- |
| `GET` | `/ai/voice` | Shipped Kokoro presets + the account selection |
| `PUT` | `/ai/voice` | Persist the selected Kokoro preset |
| `POST` | `/ai/voice/speak` | **Gone.** Hex does not synthesize speech. |

The phone never receives a vendor TTS key. Dummy / local testing /
dummy-offline / live all use the same on-device engine. If Kokoro cannot
load, the line stays on screen and the failure is logged locally. There
is no Apple-voice fallback.

Speak does not fuse, remember, observe, or touch personality
(Coach / Friend / Drill Sergeant). Safety rails are unchanged. Bedrock
stays off.

## Mouth

`services/voice_provider.py` always returns `kokoro`. Cloud flags are
ignored.

1. **Kokoro-82M** — the only mouth. Preset voices only. ARIA's locked
   preset is `af_heart` (Warm).
2. **Load failure** — show the text. Log locally. Do not switch voices.

## Package and licenses

| Piece | Source | License |
| --- | --- | --- |
| Weights | [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) | Apache-2.0 |
| Swift / Core ML package | [mattmireles/kokoro-coreml](https://github.com/mattmireles/kokoro-coreml) (`KokoroTTS`) | Apache-2.0 |
| G2P assets | FluidInference/kokoro-82m-coreml | Apache-2.0 |

The package is iOS 18+ / macOS 15+, Apple Silicon. WatchOS is not
supported, so ForgeCore does not link it. The iOS target uses
`#if canImport(KokoroTTS)` and a bundled starter model. Hugging Face is
never contacted at speak time.

## App-size impact

| Bundle | Size | What it includes |
| --- | --- | --- |
| Starter | ~210 MB | `af_heart` + one 15 s bucket |
| Full voice set | larger | Not shipped |

The starter bundle is lazy-loaded on first speak. It is not downloaded
in Dummy / offline. If the bundle is missing (CI, a fresh simulator),
speak fails quietly.

## Featured presets

| Recipe | Kokoro id | Notes |
| --- | --- | --- |
| Warm (ARIA) | `af_heart` | Locked default |
| Calm | `am_michael` | Even, low |
| Neutral | `af_sarah` | Clear |
| Spark | `af_aoede` | Brighter |
| Ember | `af_bella` | Blunt, confident |

UI names must not use trademarked characters. No cloning. No custom
uploads.

## Zero leakage

Text is still sanitized (`services/tts_privacy.py`, `AriaTTSPrivacy`)
so a future leak toward a cloud TTS API fails closed. Names, emails,
phones, street addresses, and health-metric numbers never appear in a
vendor URL, header, body, or log. The runtime never posts TTS.

## Config

There are no live Fish / Polly / ElevenLabs switches. Those env names
are unused. `FISH_AUDIO_*` and `ELEVENLABS_*` are not loaded from
Secrets Manager. `generate_client_config` still refuses to ship those
markers in Info-Add.plist.

This PR does not enable Bedrock and does not apply Terraform.

## Dummy / offline / over-quota

Kokoro only. No network. Tests patch `socket` closed around catalog and
the retired speak route.

## What PR #480 already removed

- ConvAI routes: `/ai/voice/bootstrap`, `/ai/voice/tool`, `/ai/voice/design`
- Hex alias `/ai/voice/fish-tts`

This PR also removes `POST /ai/voice/speak`.

## Open question for Akshith

Keeping the iOS system voice as an **emergency-only** fallback (Kokoro
failed to load, user still wants to hear the line) is **not** in this
PR. The current behavior matches the ask: fail quietly and show the
text. Worth a one-line decision if silent Dummy-offline on a device
without the 210 MB bundle is too quiet for TestFlight.
