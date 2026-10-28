import XCTest
import ForgeCore
@testable import ForgeSwift

@MainActor
final class AriaKokoroEngineTests: XCTestCase {

    override func tearDown() async throws {
        AriaKokoroEngine.resetForTests()
        AriaKokoroModelStore.shared.resetForTests()
        try await super.tearDown()
    }

    func testNormalReplyReturnsNonEmptyAudioOnTheRuntimeSynthesizer() async {
        let pcm: [Float] = [0.12, -0.08, 0.05, 0.0, -0.02]
        var rendered: [Float] = []
        var played: [Float] = []
        AriaKokoroRuntimeSynthesizer.shared.installTestBackend(
            AriaKokoroEngineTestBackend(
                modelPresent: true,
                load: { true },
                render: { _, _, _ in
                    rendered = pcm
                    return pcm
                },
                play: { samples in
                    played = samples
                    return true
                }
            )
        )
        let ok = await AriaKokoroEngine.speak("Hello from ARIA.")
        XCTAssertTrue(ok)
        XCTAssertFalse(rendered.isEmpty, "synthesis must return non-empty audio")
        XCTAssertTrue(AriaKokoroAudioPolicy.isPlayable(rendered))
        XCTAssertEqual(played, pcm)
        XCTAssertEqual(AriaKokoroRuntimeSynthesizer.shared.loadState.loadAttempts, 1)
    }

    func testEmptyAudioIsAFailedSpeakAndIsNotPlayed() async {
        var playCount = 0
        var renderCount = 0
        AriaKokoroRuntimeSynthesizer.shared.installTestBackend(
            AriaKokoroEngineTestBackend(
                modelPresent: true,
                load: { true },
                render: { _, _, _ in
                    renderCount += 1
                    return []
                },
                play: { _ in
                    playCount += 1
                    XCTFail("empty Kokoro audio must not reach the player")
                    return true
                }
            )
        )
        let ok = await AriaKokoroEngine.speak("Hello from ARIA.")
        XCTAssertFalse(ok, "empty Kokoro audio must not count as speech")
        XCTAssertEqual(playCount, 0)
        XCTAssertEqual(renderCount, 1 + AriaKokoroAudioPolicy.synthesisRetryLimit)
        XCTAssertEqual(AriaKokoroAudioPolicy.decide([]), .silentFailure)
    }

    func testLoadAndSynthesisRetryHappenExactlyOnce() async {
        var loads = 0
        AriaKokoroRuntimeSynthesizer.shared.installTestBackend(
            AriaKokoroEngineTestBackend(
                modelPresent: true,
                load: {
                    loads += 1
                    return false
                },
                render: { _, _, _ in
                    XCTFail("synthesis must not run when load failed")
                    return []
                },
                play: { _ in
                    XCTFail("play must not run when load failed")
                    return true
                }
            )
        )
        XCTAssertFalse(await AriaKokoroEngine.speak("Hello from ARIA."))
        XCTAssertEqual(loads, 1)
        XCTAssertFalse(await AriaKokoroEngine.speak("Hello from ARIA."))
        XCTAssertEqual(loads, 1, "hard failure must not reload by itself")

        AriaKokoroEngine.noteRuntimeBecameAvailable()
        XCTAssertFalse(await AriaKokoroEngine.speak("Hello from ARIA."))
        XCTAssertEqual(loads, 2, "load retries exactly once after the runtime lands")

        AriaKokoroEngine.noteRuntimeBecameAvailable()
        XCTAssertFalse(await AriaKokoroEngine.speak("Hello from ARIA."))
        XCTAssertEqual(loads, 2, "a second grant must not load again")

        var renders = 0
        AriaKokoroEngine.resetForTests()
        AriaKokoroRuntimeSynthesizer.shared.installTestBackend(
            AriaKokoroEngineTestBackend(
                modelPresent: true,
                load: { true },
                render: { _, _, _ in
                    renders += 1
                    return []
                },
                play: { _ in false }
            )
        )
        XCTAssertFalse(await AriaKokoroEngine.speak("Hello from ARIA."))
        XCTAssertEqual(renders, 1 + AriaKokoroAudioPolicy.synthesisRetryLimit)
    }

    func testDownloadConsentPolicyMatchesReviewRule() {
        XCTAssertTrue(
            AriaKokoroVoicePromptPolicy.shouldPresent(
                hasLocalModel: false,
                alreadyConsented: false,
                declined: false
            )
        )
        XCTAssertTrue(AriaKokoroVoicePromptPolicy.body.contains("210 MB"))
        XCTAssertFalse(AriaKokoroVoice.usesOnDemandResources)
        XCTAssertFalse(AriaKokoroVoice.allowsNetworkAtSpeakTime)
    }

    func testSynthesisProducesNonEmptyAudioWhenModelIsPresent() async throws {
        #if canImport(KokoroTTS)
        await AriaKokoroModelStore.shared.discover()
        guard AriaKokoroModelStore.shared.hasVerifiedRuntime else {
            throw XCTSkip("Kokoro-82M starter runtime is not on this CI host")
        }
        AriaKokoroEngine.resetForTests()
        let ready = await AriaKokoroRuntimeSynthesizer.shared.prepare()
        guard ready else {
            throw XCTSkip("Kokoro engine could not load the present runtime")
        }
        let samples = await AriaKokoroRuntimeSynthesizer.shared.renderPCM(
            "Hello.",
            voiceID: AriaKokoroVoice.ariaPreset,
            speed: 1.0
        )
        XCTAssertFalse(samples.isEmpty, "Kokoro synthesis returned empty audio")
        XCTAssertTrue(AriaKokoroAudioPolicy.isPlayable(samples))
        #else
        throw XCTSkip("KokoroTTS is not linked in this test host")
        #endif
    }
}
