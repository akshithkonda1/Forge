import XCTest
@testable import ForgeCore

/// The measurement half of Forge's performance story (the policy half is
/// ForgeRuntimeGuard, locked by ForgeStabilityTests). These tests keep the
/// signpost plumbing honest: spans begin and end without crashing, they
/// survive an await, measured blocks pass values and errors through, and
/// the category set stays the contract documented in
/// `ForgeSwift/docs/performance.md`.
///
/// They deliberately do not assert timings — on a shared CI Mac a wall-
/// clock assertion flakes. Durations are read in Instruments on a device;
/// budgets live in ForgeStabilityTests.
final class ForgePerfTests: XCTestCase {

    func testCategoriesAreTheDocumentedContract() {
        XCTAssertEqual(
            ForgePerf.Category.allCases.map(\.rawValue),
            ["launch", "healthkit", "aria", "store"]
        )
        XCTAssertEqual(ForgePerf.subsystem, "com.forge.core")
    }

    func testSpanBeginAndEndEmitWithoutCrashing() {
        let span = ForgePerf.begin("test.span", category: .store)
        span.end()
    }

    func testEventEmitsWithoutCrashing() {
        ForgePerf.event("test.event", category: .aria)
    }

    func testMeasurePassesThroughValue() {
        let value = ForgePerf.measure("test.sync", category: .launch) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testMeasureRethrows() {
        struct Boom: Error {}
        XCTAssertThrowsError(
            try ForgePerf.measure("test.throw", category: .launch) { throw Boom() }
        )
    }

    func testAsyncMeasureSpansAwait() async {
        let value = await ForgePerf.measure("test.async", category: .healthkit) {
            try? await Task.sleep(nanoseconds: 1_000_000)
            return "ok"
        }
        XCTAssertEqual(value, "ok")
    }

    func testAsyncThrowingMeasureRethrows() async {
        struct Boom: Error {}
        do {
            _ = try await ForgePerf.measure("test.asyncThrow", category: .aria) {
                try await Task.sleep(nanoseconds: 1_000_000)
                throw Boom()
            }
            XCTFail("expected a throw")
        } catch {}
    }
}
