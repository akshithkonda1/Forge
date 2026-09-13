import XCTest
@testable import ForgeSwift

/// Locks the welcome-chime gates and the unused AriaLogo still-frame name.
/// Live mark is the procedural ring-field — this file does not assert PNG paint.
/// Does not start AVAudioEngine.
final class AriaLogoPresenceTests: XCTestCase {

    func testFluidMarkUsesAriaLogoAssetWithoutARingCrop() {
        XCTAssertEqual(AriaWelcomeChime.assetName, "AriaLogo")
        XCTAssertEqual(AriaWelcomeChime.cropScale, 1.0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(
            AriaWelcomeChime.cropScale,
            1.05,
            "ARIA ring-field — do not zoom past its frame"
        )
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
        XCTAssertNotEqual(ForgePlaybackSession.spokenHandsFree, .spoken)
        XCTAssertEqual(ForgePlaybackSession.sleepMix, .sleepMix)
    }
}
