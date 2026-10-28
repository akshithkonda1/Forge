import XCTest
import ForgeCore

final class AriaKokoroDeliveryTests: XCTestCase {

    func testConsentIsRequiredWhenTheModelIsMissing() {
        XCTAssertTrue(
            AriaKokoroDelivery.shouldAskToDownload(
                hasLocalModel: false,
                alreadyConsented: false,
                declined: false
            )
        )
        XCTAssertFalse(
            AriaKokoroDelivery.shouldAskToDownload(
                hasLocalModel: true,
                alreadyConsented: false,
                declined: false
            )
        )
        XCTAssertFalse(
            AriaKokoroDelivery.shouldAskToDownload(
                hasLocalModel: false,
                alreadyConsented: true,
                declined: false
            )
        )
        XCTAssertFalse(
            AriaKokoroDelivery.shouldAskToDownload(
                hasLocalModel: false,
                alreadyConsented: false,
                declined: true
            )
        )
        XCTAssertTrue(AriaKokoroDelivery.promptBody.contains("210 MB"))
        XCTAssertFalse(AriaKokoroVoice.usesOnDemandResources)
        XCTAssertFalse(AriaKokoroVoice.usesEspeak)
        XCTAssertEqual(AriaKokoroVoice.g2p, "MisakiSwift")
        XCTAssertEqual(AriaKokoroVoice.packageVersion, "2.0")
        XCTAssertEqual(AriaKokoroVoice.packageRevision, "e4242c94c0dc5be62258cc3cf15c86c37382c3d5")
        XCTAssertTrue(AriaKokoroDelivery.isPinnedRevision(AriaKokoroVoice.hostedRevision))
        XCTAssertEqual(
            AriaKokoroDelivery.hostedManifestURL()?.absoluteString.contains(AriaKokoroVoice.hostedRevision),
            true
        )
    }

    func testPrefetchStaysOffUntilConsentOrALocalCopy() {
        XCTAssertFalse(AriaKokoroDelivery.allowsPrefetch(hasLocalModel: false, consented: false))
        XCTAssertTrue(AriaKokoroDelivery.allowsPrefetch(hasLocalModel: true, consented: false))
        XCTAssertTrue(AriaKokoroDelivery.allowsPrefetch(hasLocalModel: false, consented: true))
    }

    func testLocatorPrefersTheFirstRootThatHasAManifest() {
        let missing = URL(fileURLWithPath: "/tmp/aria-kokoro-missing")
        let present = URL(fileURLWithPath: "/tmp/aria-kokoro-present")
        let locator = AriaKokoroRuntimeLocator(roots: [missing, present])
        let resolved = locator.resolvedRoot { url in
            url.path.contains("present")
        }
        XCTAssertEqual(resolved, present)
        XCTAssertNil(AriaKokoroRuntimeLocator(roots: [missing]).resolvedRoot { _ in false })
    }

    func testMissingModelIsNotAPermanentLoadFailure() {
        var state = AriaKokoroLoadState()
        XCTAssertFalse(state.shouldLoad(modelPresent: false))
        state.markMissing()
        XCTAssertFalse(state.isReady)
        XCTAssertTrue(state.missingModel)
        XCTAssertFalse(state.hardFailure)

        state.allowRetryAfterLoad()
        XCTAssertTrue(state.shouldLoad(modelPresent: true))
        state.markLoaded()
        XCTAssertTrue(state.isReady)
        XCTAssertFalse(state.shouldLoad(modelPresent: true))
        state.allowRetryAfterLoad()
        XCTAssertTrue(state.isReady, "a loaded engine must not be unloaded by a later grant")
        XCTAssertFalse(state.shouldLoad(modelPresent: true))
    }

    func testHardFailureRetriesExactlyOnce() {
        var state = AriaKokoroLoadState()
        XCTAssertTrue(state.shouldLoad(modelPresent: true))
        state.markHardFailure()
        XCTAssertTrue(state.hardFailure)
        XCTAssertEqual(state.loadAttempts, 1)
        XCTAssertFalse(
            state.shouldLoad(modelPresent: true),
            "a hard failure must not reload until a retry is granted"
        )

        state.allowRetryAfterLoad()
        XCTAssertFalse(state.hardFailure)
        XCTAssertTrue(state.shouldLoad(modelPresent: true), "exactly one retry after the runtime lands")
        state.markHardFailure()
        XCTAssertEqual(state.retriesUsed, AriaKokoroLoadState.retryLimit)
        XCTAssertFalse(state.shouldLoad(modelPresent: true))

        state.allowRetryAfterLoad()
        XCTAssertFalse(
            state.shouldLoad(modelPresent: true),
            "the load retry budget is one"
        )
    }

    func testChecksumCompareIsCaseInsensitive() {
        XCTAssertTrue(
            AriaKokoroDelivery.matchesChecksum(
                "F3ABD5811585B8C89F1C15E647409311731B4262DA4315242C69F88675BCED9D",
                expected: AriaKokoroVoice.hostedManifestSHA256
            )
        )
        XCTAssertFalse(
            AriaKokoroDelivery.matchesChecksum("deadbeef", expected: AriaKokoroVoice.hostedManifestSHA256)
        )
    }
}
