import XCTest
@testable import ForgeSwift

/// Locks the circular ARIA mark contract: asset name, crop, and when the
/// welcome chime may fire. Does not start AVAudioEngine.
final class AriaLogoPresenceTests: XCTestCase {

    func testCircularClipUsesAriaLogoAssetAndZoomsPastTheGlassFrame() {
        XCTAssertEqual(AriaWelcomeChime.assetName, "AriaLogo")
        XCTAssertEqual(AriaWelcomeChime.cropScale, 1.52, accuracy: 0.001)
        XCTAssertGreaterThan(AriaWelcomeChime.cropScale, 1.2)
        XCTAssertEqual(AriaWelcomeChime.heroMinimumSize, 90)
    }

    func testHeroIdleMayChimeOnce() {
        XCTAssertTrue(
            AriaWelcomeChime.shouldPlay(
                size: 140,
                reduceMotion: false,
                quietMode: false,
                alreadyPlayed: false,
                isSpeaking: false
            )
        )
    }

    func testChimeDoesNotFireWhenReduceMotionQuietAlreadyPlayedSmallOrSpeaking() {
        XCTAssertFalse(
            AriaWelcomeChime.shouldPlay(
                size: 140,
                reduceMotion: true,
                quietMode: false,
                alreadyPlayed: false
            ),
            "Reduce Motion stays silent"
        )
        XCTAssertFalse(
            AriaWelcomeChime.shouldPlay(
                size: 140,
                reduceMotion: false,
                quietMode: true,
                alreadyPlayed: false
            ),
            "quiet_mode stays silent"
        )
        XCTAssertFalse(
            AriaWelcomeChime.shouldPlay(
                size: 140,
                reduceMotion: false,
                quietMode: false,
                alreadyPlayed: true
            ),
            "second hero in the same session must not double-chime"
        )
        XCTAssertFalse(
            AriaWelcomeChime.shouldPlay(
                size: 44,
                reduceMotion: false,
                quietMode: false,
                alreadyPlayed: false
            ),
            "tab-sized marks never chime"
        )
        XCTAssertFalse(
            AriaWelcomeChime.shouldPlay(
                size: 89,
                reduceMotion: false,
                quietMode: false,
                alreadyPlayed: false
            )
        )
        XCTAssertFalse(
            AriaWelcomeChime.shouldPlay(
                size: 140,
                reduceMotion: false,
                quietMode: false,
                alreadyPlayed: false,
                isSpeaking: true
            ),
            "do not cut ARIA speech"
        )
    }

    func testAriaSpeechPrepUnchanged() {
        XCTAssertEqual(AriaSpeechPrep.characterLimit, 900)
        XCTAssertNil(AriaSpeechPrep.clipped("   "))
        XCTAssertNil(AriaSpeechPrep.clipped(""))
        XCTAssertEqual(AriaSpeechPrep.clipped("  Hello ARIA  "), "Hello ARIA")
        let long = String(repeating: "a", count: AriaSpeechPrep.characterLimit + 40)
        XCTAssertEqual(AriaSpeechPrep.clipped(long)?.count, AriaSpeechPrep.characterLimit)
    }

    func testChimePlaybackSessionExistsAlongsideSpoken() {
        XCTAssertEqual(ForgePlaybackSession.chime, .chime)
        XCTAssertNotEqual(ForgePlaybackSession.chime, .spoken)
        XCTAssertEqual(ForgePlaybackSession.sleepMix, .sleepMix)
    }
}
