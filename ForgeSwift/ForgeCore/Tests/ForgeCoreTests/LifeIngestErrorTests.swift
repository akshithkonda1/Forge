import XCTest
@testable import ForgeCore

final class LifeIngestErrorTests: XCTestCase {
    func testExplainIncludesActionAndUnderlyingReason() {
        struct SampleError: LocalizedError {
            var errorDescription: String? { "calendar is read-only" }
        }

        let wrapped = LifeIngestError.explain(SampleError(), doing: "Couldn't write this week's calendar")
        XCTAssertEqual(
            wrapped,
            "Couldn't write this week's calendar: calendar is read-only"
        )
    }

    func testExplainDoesNotDuplicateAnAlreadyPrefixedReason() {
        struct Prefixed: LocalizedError {
            var errorDescription: String? {
                "Couldn't write the Forge test calendar: no writable EventKit source."
            }
        }
        XCTAssertEqual(
            LifeIngestError.explain(Prefixed(), doing: "Couldn't write the Forge test calendar"),
            "Couldn't write the Forge test calendar: no writable EventKit source."
        )
    }

    func testSkippedStatesThePolicyReason() {
        let skipped = LifeIngestError.skipped(
            doing: "Calendar ingest",
            because: "EventKit access is denied"
        )
        XCTAssertEqual(skipped, "Calendar ingest skipped: EventKit access is denied")
    }

    func testUnknownErrorFallsBackToTypeName() {
        struct Opaque: Error {}
        let wrapped = LifeIngestError.explain(Opaque(), doing: "Couldn't save HealthKit")
        XCTAssertTrue(wrapped.hasPrefix("Couldn't save HealthKit:"), wrapped)
        XCTAssertTrue(wrapped.contains("Opaque"), wrapped)
    }

    func testEmptyLocalizedDescriptionDoesNotCrashOrStayBlank() {
        struct Blank: LocalizedError {
            var errorDescription: String? { "   " }
        }
        let wrapped = LifeIngestError.explain(Blank(), doing: "Couldn't read Apple Health")
        XCTAssertTrue(wrapped.contains("Couldn't read Apple Health"), wrapped)
        XCTAssertFalse(wrapped.hasSuffix(":"), wrapped)
        XCTAssertNotEqual(wrapped.trimmingCharacters(in: .whitespaces), "")
    }

    func testCombineKeepsDistinctReasonsAndDropsDuplicates() {
        let health = "Couldn't write the Test-Ready Health pack: HealthKit denied"
        let calendar = "Calendar ingest skipped: denied"
        XCTAssertEqual(LifeIngestError.combine(existing: nil, incoming: health), health)
        XCTAssertEqual(
            LifeIngestError.combine(existing: health, incoming: calendar),
            health + " " + calendar
        )
        XCTAssertEqual(
            LifeIngestError.combine(existing: health + " " + calendar, incoming: health),
            health + " " + calendar
        )
        XCTAssertEqual(LifeIngestError.combine(existing: health, incoming: "  "), health)
        XCTAssertNil(LifeIngestError.combine(existing: nil, incoming: nil))
    }
}
