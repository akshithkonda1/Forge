import XCTest
import ForgeCore

/// Acceptance bar: these drive `AriaKokoroEnginePath` — the same load /
/// synthesize / play path the iOS mouth uses — not a stubbed
/// `synthesizeWithPackage`. Swift CI runs them via `swift test`.
final class AriaKokoroAudioPolicyTests: XCTestCase {

    func testNormalReplyReturnsNonEmptyAudio() async {
        let expected: [Float] = [0.12, -0.08, 0.05, 0.0, -0.02]
        var rendered: [Float] = []
        var played: [Float] = []
        var path = AriaKokoroEnginePath()
        let ok = await path.speak(
            "Hello from ARIA. Sleep was short.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0,
            modelPresent: true,
            load: { true },
            render: { text, voiceID, speed in
                XCTAssertFalse(text.isEmpty)
                XCTAssertEqual(voiceID, AriaKokoroVoice.ariaPreset)
                XCTAssertEqual(speed, 1.0)
                rendered = expected
                return expected
            },
            play: { samples in
                played = samples
                return true
            }
        )
        XCTAssertTrue(ok, "a normal Kokoro reply must count as speech")
        XCTAssertFalse(rendered.isEmpty, "synthesis must return non-empty audio")
        XCTAssertTrue(AriaKokoroAudioPolicy.isPlayable(rendered))
        XCTAssertEqual(AriaKokoroAudioPolicy.decide(rendered), .play)
        XCTAssertEqual(played, expected)
        XCTAssertEqual(
            AriaKokoroAudioPolicy.playableSamples(from: expected),
            expected
        )
    }

    func testEmptyAudioIsASilentFailureAndIsNotPlayed() async {
        var renderCount = 0
        var playCount = 0
        var path = AriaKokoroEnginePath()
        let ok = await path.speak(
            "Hello from ARIA.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0,
            modelPresent: true,
            load: { true },
            render: { _, _, _ in
                renderCount += 1
                return []
            },
            play: { _ in
                playCount += 1
                return true
            }
        )
        XCTAssertFalse(ok, "empty Kokoro audio must not count as speech")
        XCTAssertEqual(playCount, 0, "empty audio must never be scheduled")
        XCTAssertEqual(AriaKokoroAudioPolicy.decide([]), .silentFailure)
        XCTAssertFalse(AriaKokoroAudioPolicy.shouldPlay([]))
        XCTAssertFalse(AriaKokoroAudioPolicy.shouldPlay([0, 0, 0]))
        XCTAssertEqual(
            AriaKokoroAudioPolicy.playableSamples(from: [0, 0, 0]),
            []
        )
        XCTAssertEqual(
            AriaKokoroVoice.loadFailedMessage,
            "Voice could not load. The text reply is shown."
        )

        var zeroPlayCount = 0
        var zeros = AriaKokoroEnginePath()
        let zeroOk = await zeros.speak(
            "Hello from ARIA.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0,
            modelPresent: true,
            load: { true },
            render: { _, _, _ in [0, 0, 0] },
            play: { _ in
                zeroPlayCount += 1
                return true
            }
        )
        XCTAssertFalse(zeroOk)
        XCTAssertEqual(zeroPlayCount, 0)
        XCTAssertEqual(
            renderCount,
            1 + AriaKokoroAudioPolicy.synthesisRetryLimit,
            "empty synthesis retries exactly once"
        )
    }

    func testLoadAndSynthesisRetryHappenExactlyOnce() async {
        var loads = 0
        var path = AriaKokoroEnginePath()
        let failLoad: () async -> Bool = {
            loads += 1
            return false
        }

        XCTAssertFalse(await path.prepare(modelPresent: true, load: failLoad))
        XCTAssertEqual(loads, 1)
        XCTAssertTrue(path.loadState.hardFailure)
        XCTAssertFalse(
            await path.prepare(modelPresent: true, load: failLoad),
            "a hard failure must not reload by itself"
        )
        XCTAssertEqual(loads, 1)

        path.allowRetryAfterLoad()
        XCTAssertFalse(await path.prepare(modelPresent: true, load: failLoad))
        XCTAssertEqual(loads, 2, "load retries exactly once after the runtime lands")
        XCTAssertEqual(path.loadState.retriesUsed, AriaKokoroLoadState.retryLimit)

        path.allowRetryAfterLoad()
        XCTAssertFalse(await path.prepare(modelPresent: true, load: failLoad))
        XCTAssertEqual(loads, 2, "a second grant must not load again")

        var renders = 0
        var plays = 0
        var synth = AriaKokoroEnginePath()
        let empty = await synth.speak(
            "Hello from ARIA.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0,
            modelPresent: true,
            load: { true },
            render: { _, _, _ in
                renders += 1
                return []
            },
            play: { _ in
                plays += 1
                return true
            }
        )
        XCTAssertFalse(empty)
        XCTAssertEqual(renders, 1 + AriaKokoroAudioPolicy.synthesisRetryLimit)
        XCTAssertEqual(plays, 0)

        var recoveredRenders = 0
        var recovered = AriaKokoroEnginePath()
        let ok = await recovered.speak(
            "Hello from ARIA.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0,
            modelPresent: true,
            load: { true },
            render: { _, _, _ in
                recoveredRenders += 1
                if recoveredRenders == 1 { return [] }
                return [0.2, -0.1, 0.05]
            },
            play: { samples in
                XCTAssertTrue(AriaKokoroAudioPolicy.isPlayable(samples))
                return true
            }
        )
        XCTAssertTrue(ok, "the single synthesis retry may recover")
        XCTAssertEqual(recoveredRenders, 2)
    }
}
