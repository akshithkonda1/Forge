# ARIA voice

The mouth is **Kokoro-82M on this iPhone**. There is no fallback chain.
Fish, Polly, and ElevenLabs are not on the runtime path. TTS text never
leaves the phone.

## Architecture

| Method | Path | Role |
| --- | --- | --- |
| `GET` | `/ai/voice` | Shipped Kokoro presets + the account selection |
| `PUT` | `/ai/voice` | Persist the selected Kokoro preset |
| `POST` | `/ai/voice/speak` | **Gone.** Hex does not synthesize speech. |

The phone never receives a vendor TTS key. Dummy / local testing /
dummy-offline / live all use the same on-device engine. If Kokoro cannot
load, or synthesis returns empty audio, the line stays on screen and the
failure is logged locally. There is no Apple-voice fallback. Speak never
opens a socket.

Speak does not fuse, remember, observe, or touch personality
(Coach / Friend / Drill Sergeant). Safety rails are unchanged. Bedrock
stays off.

## Mouth

`services/voice_provider.py` always returns `kokoro`. Cloud flags are
ignored.

1. **Kokoro-82M** — the only mouth. Preset voices only. ARIA's locked
   preset is `af_heart` (Warm).
2. **Empty or missing audio** — treat as failure. Do not play. Show the
   text. Log locally. Do not switch voices.
3. **Load / synthesis retry** — exactly once after the runtime lands, then
   fail closed.

## Package and licenses

| Piece | Source | License |
| --- | --- | --- |
| Weights | [hexgrad/Kokoro-82M](https://huggingface.co/hexgrad/Kokoro-82M) | Apache-2.0 |
| Swift / Core ML package | [mattmireles/kokoro-coreml](https://github.com/mattmireles/kokoro-coreml) v2.0 (`KokoroTTS`, revision `e4242c94c0dc5be62258cc3cf15c86c37382c3d5`) | Apache-2.0 |
| G2P | MisakiSwift (dictionary + neural, no eSpeak) | Apache-2.0 |

Pinned on the **iOS app target only**. WatchOS cannot build MisakiSwift /
MLX, so ForgeWatch and ForgeCore do not link `KokoroTTS`. FluidAudio is
rejected (docs list eSpeak-NG GPL-3.0). `mweinbach/kokoro-swift` is
rejected (no license). Older `mlalma/kokoro-ios` GPL / eSpeak-era commits
are rejected. `scripts/check-kokoro-licenses.py` fails the graph if
eSpeak, phonemizer, or FluidAudio appear.

A small ARIA lexicon expands HRV, VO₂ max, SpO₂, RHR, bpm, and RMSSD
before G2P. Long replies are split on sentences so a 30 s line cannot
peak past ~1 GB RAM.

## Model delivery (~210 MB)

| Bundle | Size | What it includes |
| --- | --- | --- |
| Starter | ~210 MB (`218,081,866` bytes) | `af_heart` + one 15 s bucket |
| Full voice set | larger | Not shipped |

Do **not** commit the weights. Search order:

1. Apple-hosted Background Assets pack `forge.aria.kokoro-82m-starter`
   (iOS 26+ `AssetPackManager`). On-Demand Resources are not used.
2. `Bundle.main` copy of `kokoro-82m-starter.bundle`, if present.
3. Application Support `Kokoro82M`, hydrated once after the 4.2.3(ii)
   consent prompt names the 210 MB size.

Hosted source: Hugging Face `mattmireles/kokoro-coreml` revision
`034f7741bf938fd6b4b9c75c22bc72cd795f908a`. SHA-256 of
`HostedManifest.json`:
`f3abd5811585b8c89f1c15e647409311731b4262da4315242c69f88675bced9d`.
Hugging Face is never contacted at speak time. Until the runtime is
present and verified, ARIA is text-only.

## Featured presets

| Recipe | Kokoro id | Notes |
| --- | --- | --- |
| Warm (ARIA) | `af_heart` | Locked default; the starter bundle's only voice |
| Calm | `am_michael` | Falls back to `af_heart` on the starter pack |
| Neutral | `af_sarah` | Falls back to `af_heart` on the starter pack |
| Spark | `af_aoede` | Falls back to `af_heart` on the starter pack |
| Ember | `af_bella` | Falls back to `af_heart` on the starter pack |

UI names must not use trademarked characters. No cloning. No custom
uploads.

## Device test

1. Launch Forge on a physical iPhone (Apple Silicon). First launch asks
   to download 210 MB. Accept.
2. Wait until Application Support contains `KokoroRuntimeManifest.json`.
3. Unmute ARIA, start a voice session, send a short chat line.
4. Confirm spoken audio, then force an empty synthesis (or delete the
   runtime) and confirm she stays silent with the text still on screen.
5. Settings → ARIA voice still offers "Download ARIA's voice (210 MB)"
   when the runtime is missing.

## Tests Swift CI actually runs

`swift test` in ForgeCore is the guaranteed nonzero count. The files are
listed in `ForgeSwift/ForgeCore/Package.swift` test sources:

- `AriaKokoroAudioPolicyTests.swift` — (1) non-empty audio for a normal
  reply, (2) empty audio is a silent failure and is not played, (3) load
  and synthesis retry exactly once. These drive `AriaKokoroEnginePath`,
  the same path `AriaKokoroRuntimeSynthesizer` uses, not a stubbed
  `synthesizeWithPackage`.
- `AriaKokoroVoiceTests.swift` — pin, MisakiSwift, no network at speak.
- `AriaKokoroDeliveryTests.swift` — consent, locator, checksum, retry
  budget.
- `AriaKokoroLexiconTests.swift` — HRV / VO2 expansions and sentence
  chunks.

`ForgeSwiftTests/AriaKokoroEngineTests.swift` repeats the three
assertions on the real `AriaKokoroRuntimeSynthesizer` class (injected
load/render/play, never a replacement synthesizer). A fourth case talks
to KokoroTTS when the 210 MB runtime is on the simulator and skips
otherwise.

## Zero leakage

Text is still sanitized (`services/tts_privacy.py`, `AriaTTSPrivacy`)
so a future leak toward a cloud TTS API fails closed. Names, emails,
phones, street addresses, and health-metric numbers never appear in a
vendor URL, header, body, or log. The runtime never posts TTS. Health
data never leaves the device.

## Config

There are no live Fish / Polly / ElevenLabs switches. Those env names
are unused. `FISH_AUDIO_*` and `ELEVENLABS_*` are not loaded from
Secrets Manager. `generate_client_config` still refuses to ship those
markers in Info-Add.plist.

This PR does not enable Bedrock and does not apply Terraform.

## Open risks

- No App Store Connect Background Assets pack is registered yet. Dev /
  TestFlight uses the consented Hugging Face hydrate. Speak still never
  hits the network.
- Starter pack has `af_heart` only. Other catalog presets fall back.
- `kokoro-coreml` pulls MLX / MisakiSwift. Xcode 27 CI needs that
  toolchain; Watch must stay unlinked.
- Core ML weights are a converted form of Kokoro-82M; Apple's runtime
  license is proprietary even though the package and weights are Apache-2.0.
- 30 s unchunked lines can exceed 1 GB peak. Sentence chunking is
  required, not optional.
