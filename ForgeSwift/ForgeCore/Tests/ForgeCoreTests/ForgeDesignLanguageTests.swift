import XCTest
@testable import ForgeCore

final class ForgeDesignLanguageTests: XCTestCase {

    func testCharacteristicsLockWithoutTouchingType() {
        XCTAssertEqual(ForgeDesignLanguage.motif, "mosaic")
        XCTAssertEqual(ForgeDesignLanguage.tesseraRadius, ForgeDesignTokens.Radius.lg)
        XCTAssertEqual(ForgeDesignLanguage.hairline, ForgeDesignTokens.Stroke.hairline)
        XCTAssertTrue(ForgeDesignLanguage.motionEventOnly)
        XCTAssertFalse(ForgeDesignLanguage.liveGlowDefault)
        XCTAssertEqual(ForgeDesignLanguage.minTap, 44)
        XCTAssertTrue(ForgeDesignLanguage.skipAlwaysVisible)
        XCTAssertTrue(ForgeDesignLanguage.characteristics.contains("tessera"))
        XCTAssertTrue(ForgeDesignLanguage.mosaicLaw.lowercased().contains("tessera"))
        XCTAssertTrue(ForgeDesignLanguage.typeLaw.lowercased().contains("typography"))
        XCTAssertTrue(ForgeDesignLanguage.noSlopLaw.lowercased().contains("ai slop"))
        XCTAssertTrue(ForgeDesignLanguage.noSlopLaw.lowercased().contains("elevate"))
        XCTAssertTrue(ForgeDesignLanguage.noSlopLaw.lowercased().contains("glassmorphism"))
        XCTAssertFalse(ForgeDesignLanguage.mosaicLaw.lowercased().contains("hud"))
        XCTAssertFalse(ForgeDesignLanguage.motionLaw.lowercased().contains("hud"))
        XCTAssertEqual(ForgeDesignTokens.displayFamily, "instrument-serif")
        XCTAssertEqual(ForgeDesignTokens.bodyFamily, "geist")
    }
}
