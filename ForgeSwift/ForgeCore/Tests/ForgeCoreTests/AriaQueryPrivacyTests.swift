import XCTest
@testable import ForgeCore

/// Mirrors backend/tests/test_scout.py PrivacyTests — the phone and Scout scrub alike.
final class AriaQueryPrivacyTests: XCTestCase {

    func testStripsNamesNumbersContactsAndNarrative() {
        let q = AriaQueryPrivacy.scrub(
            "I'm 34, slept 5 hours, my wife Priya says my resting HR of 71 is high — should I skip leg day? email me at a@b.co or 555-123-4567",
            privateTerms: ["Priya"]
        )
        for banned in ["34", "71", "priya", "@", "555", "wife"] {
            XCTAssertFalse(q.contains(banned), "leaked \(banned) in \(q)")
        }
        for keep in ["resting", "skip", "leg"] {
            XCTAssertTrue(q.contains(keep), "dropped \(keep) from \(q)")
        }
    }

    func testKeepsDigitBearingHealthTerms() {
        let q = AriaQueryPrivacy.scrub("does vo2max improve with zone2 and omega-3 over 12 weeks")
        XCTAssertTrue(q.contains("vo2max"))
        XCTAssertTrue(q.contains("zone2"))
        XCTAssertTrue(q.contains("omega-3"))
        XCTAssertFalse(q.contains("12"))
    }

    func testNamedPersonAndEmpty() {
        XCTAssertFalse(AriaQueryPrivacy.scrub("my coach named Sam wants me to deload").contains("sam"))
        XCTAssertFalse(AriaQueryPrivacy.scrub("my name is Lee, how much protein").contains("lee"))
        XCTAssertEqual(AriaQueryPrivacy.scrub("   "), "")
        XCTAssertEqual(AriaQueryPrivacy.scrub("I am 30"), "")
    }

    func testCapsKeywords() {
        let words = "alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima"
        XCTAssertLessThanOrEqual(AriaQueryPrivacy.scrub(words).split(separator: " ").count, AriaQueryPrivacy.maxKeywords)
    }
}
