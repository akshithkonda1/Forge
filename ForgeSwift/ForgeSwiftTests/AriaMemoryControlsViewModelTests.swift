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

        // A kind word plus a street is reduced to the kind. The address and
        // the guest name are not stored. A place with no kind is refused.
        model.beginAdd(to: .events)
        model.draftSummary = "Dinner with Maya at 12 Main Street"
        XCTAssertTrue(model.commitDraft())
        let kept = model.facts(in: .events).first?.summary ?? ""
        XCTAssertEqual(kept, "This week: dinner out.")
        XCTAssertFalse(kept.localizedCaseInsensitiveContains("street"))
        XCTAssertFalse(kept.localizedCaseInsensitiveContains("maya"))

        model.beginAdd(to: .events)
        model.draftSummary = "Meet Maya at 44 Oak Avenue"
        XCTAssertFalse(model.commitDraft())
        XCTAssertEqual(model.addError, AriaMemoryControlsViewModel.privacyRefusal)

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

    func testVoiceOverCopyAndReduceMotionFreeze() {
        XCTAssertFalse(AriaMemoryAccess.shouldAnimate(reduceMotion: true))
        XCTAssertTrue(AriaMemoryAccess.shouldAnimate(reduceMotion: false))
        XCTAssertEqual(AriaMemoryAccess.addNoteLabel(folder: .goals), "Add a note in Goals")
        XCTAssertEqual(AriaMemoryAccess.toneLabel(.space, selected: true), "Tone, Space, selected")
        XCTAssertEqual(AriaMemoryAccess.checkInLabel(.weekly, selected: false), "Check-in, Weekly")
        XCTAssertTrue(AriaMemoryAccess.rememberMeHint.localizedCaseInsensitiveContains("does not delete"))
        XCTAssertEqual(AriaMemoryAccess.rememberMeValue(isOn: false), "Off")
    }
}

/// Soul is observable and read per reply — a switch mid-conversation
/// changes the next directive with no restart.
@MainActor
final class AriaSoulStoreTests: XCTestCase {

    func testSwitchMidConversationChangesNextReplySoul() {
        let suite = "forge.aria.soul.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else {
            return XCTFail("defaults")
        }
        defaults.removePersistentDomain(forName: suite)
        let store = AriaSoulStore(defaults: defaults)
        store.setPersonality(.coach)
        let first = AriaSoul.nextReply(draft: "Next move is easy.", config: store.config)
        XCTAssertTrue(first.soul.contains("Coach"))
        store.setPersonality(.drillSergeant)
        let second = AriaSoul.nextReply(draft: "Next move is easy.", config: store.config)
        XCTAssertNotEqual(first.soul, second.soul)
        XCTAssertTrue(second.soul.contains("Drill Sergeant"))
        XCTAssertTrue(store.directive.contains("Drill Sergeant"))
        XCTAssertFalse(AriaSoul.containsRailBreak(second.spoken))
        defaults.removePersistentDomain(forName: suite)
    }
}
