import XCTest
@testable import ForgeSwift
import ForgeCore

@MainActor
final class AriaMemoryControlsViewModelTests: XCTestCase {

    private var suite: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suite = "forge.aria.memory.vm.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        suite = nil
        super.tearDown()
    }

    func testViewModelAddEditDeleteAndMemoryOffKeepsNotes() throws {
        let model = AriaMemoryControlsViewModel(defaults: defaults)
        model.beginAdd(to: .goals)
        model.draftSummary = "Show up three mornings."
        XCTAssertTrue(model.commitDraft())
        XCTAssertEqual(model.facts(in: .goals).count, 1)

        let fact = try XCTUnwrap(model.facts(in: .goals).first)
        model.beginEdit(fact)
        model.draftSummary = "Show up four mornings."
        XCTAssertTrue(model.commitDraft())
        XCTAssertEqual(model.facts(in: .goals).first?.summary, "Show up four mornings.")

        model.setMemoryEnabled(false)
        XCTAssertFalse(model.memoryOn)
        XCTAssertEqual(model.facts(in: .goals).count, 1)
        XCTAssertTrue(model.controls.coachingFacts(in: .goals).isEmpty)

        model.beginAdd(to: .mood)
        model.draftSummary = "Feeling steady."
        XCTAssertTrue(model.commitDraft())
        XCTAssertEqual(model.facts(in: .mood).count, 1)

        model.beginAdd(to: .events)
        model.draftSummary = "Dinner with Maya at 12 Main Street"
        XCTAssertFalse(model.commitDraft())
        XCTAssertEqual(model.addError, AriaMemoryControlsViewModel.privacyRefusal)

        model.beginAdd(to: .lifestyle)
        model.draftSummary = "partner_name:sam"
        XCTAssertFalse(model.commitDraft())
        XCTAssertEqual(model.addError, AriaMemoryControlsViewModel.privacyRefusal)
        XCTAssertTrue(model.facts(in: .lifestyle).isEmpty)

        model.delete(try XCTUnwrap(model.facts(in: .goals).first))
        XCTAssertTrue(model.facts(in: .goals).isEmpty)
        XCTAssertEqual(model.facts(in: .mood).count, 1)
    }

    func testToneAndCheckInStayConsumer() {
        let model = AriaMemoryControlsViewModel(defaults: defaults)
        model.setTone(.space)
        model.setCheckInCadence(.daily)
        XCTAssertEqual(model.controls.prefs.tone, .space)
        XCTAssertEqual(model.controls.prefs.checkInCadence, .daily)
        XCTAssertFalse(model.controls.prefs.tone.line.localizedCaseInsensitiveContains("medical"))
        XCTAssertFalse(model.controls.prefs.checkInCadence.detail.localizedCaseInsensitiveContains("recovery"))
    }
}
