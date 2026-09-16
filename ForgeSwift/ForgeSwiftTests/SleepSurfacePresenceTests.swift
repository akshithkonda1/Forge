import XCTest
@testable import ForgeSwift
import ForgeCore

final class SleepSurfacePresenceTests: XCTestCase {

    func testNotConnectedEmptyCopyStaysHonest() {
        let presence = SleepSurfacePresence.make(
            healthConnected: false,
            isLoading: false,
            hasScoredNight: false,
            metricSources: []
        )
        XCTAssertEqual(presence.kind, .notConnected)
        XCTAssertEqual(presence.liveDot, .off)
        XCTAssertEqual(presence.emptyTitle, "Connect Apple Health to unlock sleep")
        XCTAssertEqual(presence.emptyCTA, "Reconnect Apple Health")
        XCTAssertTrue(presence.emptyMessage.localizedCaseInsensitiveContains("apple health"))
        XCTAssertTrue(presence.emptyMessage.localizedCaseInsensitiveContains("wearable"))
        XCTAssertFalse(presence.emptyMessage.localizedCaseInsensitiveContains("oura"))
        XCTAssertFalse(presence.emptyMessage.localizedCaseInsensitiveContains("whoop"))
        XCTAssertEqual(presence.statusCaption, "Apple Health is off")
        XCTAssertTrue(presence.lastNightEmptyMessage.localizedCaseInsensitiveContains("connect apple health"))
    }

    func testConnectedEmptyDoesNotAskToReconnect() {
        let presence = SleepSurfacePresence.make(
            healthConnected: true,
            isLoading: false,
            hasScoredNight: false,
            metricSources: []
        )
        XCTAssertEqual(presence.kind, .connectedEmpty)
        XCTAssertEqual(presence.liveDot, .waiting)
        XCTAssertEqual(presence.emptyTitle, "No scored night yet")
        XCTAssertEqual(presence.emptyCTA, "Refresh from Apple Health")
        XCTAssertTrue(presence.emptyMessage.localizedCaseInsensitiveContains("in-bed"))
        XCTAssertFalse(presence.emptyMessage.localizedCaseInsensitiveContains("reconnect"))
        XCTAssertTrue(presence.lastNightEmptyMessage.localizedCaseInsensitiveContains("connected"))
        XCTAssertFalse(presence.lastNightEmptyMessage.localizedCaseInsensitiveContains("connect apple health and"))
        XCTAssertEqual(presence.sourceIDs, ["apple-health"])
        XCTAssertEqual(presence.sourceLabels, ["Apple Health"])
    }

    func testLiveShowsEveryIngestSourceWithoutCollapsingToOneWearable() {
        let presence = SleepSurfacePresence.make(
            healthConnected: true,
            isLoading: false,
            hasScoredNight: true,
            metricSources: ["apple-health", "oura", "whoop", "garmin"]
        )
        XCTAssertEqual(presence.kind, .live)
        XCTAssertEqual(presence.liveDot, .live)
        XCTAssertEqual(presence.sourceIDs, ["apple-health", "oura", "whoop", "garmin"])
        XCTAssertEqual(presence.sourceLabels, ["Apple Health", "Oura", "WHOOP", "Garmin"])
        XCTAssertTrue(presence.statusCaption.contains("Apple Health"))
        XCTAssertTrue(presence.statusCaption.contains("Oura"))
        XCTAssertTrue(presence.statusCaption.contains("WHOOP"))
        XCTAssertFalse(presence.statusCaption.localizedCaseInsensitiveContains("via terra"))
        XCTAssertFalse(presence.showsEmptyCard)
    }

    func testUnknownWearableStaysVisible() {
        let presence = SleepSurfacePresence.make(
            healthConnected: true,
            isLoading: false,
            hasScoredNight: true,
            metricSources: ["ringconn"]
        )
        XCTAssertTrue(presence.sourceIDs.contains("apple-health"))
        XCTAssertTrue(presence.sourceIDs.contains("ringconn"))
        XCTAssertTrue(presence.sourceLabels.contains(where: { $0.localizedCaseInsensitiveContains("ringconn") }))
    }

    func testLoadingKindAndPullingDot() {
        let presence = SleepSurfacePresence.make(
            healthConnected: true,
            isLoading: true,
            hasScoredNight: false,
            metricSources: []
        )
        XCTAssertEqual(presence.kind, .loading)
        XCTAssertEqual(presence.liveDot, .pulling)
        XCTAssertEqual(presence.statusCaption, "Pulling nights…")
    }

    func testLiveWinsOverPullingWhenANightIsAlreadyOnFile() {
        let presence = SleepSurfacePresence.make(
            healthConnected: true,
            isLoading: true,
            hasScoredNight: true,
            metricSources: ["oura"]
        )
        XCTAssertEqual(presence.kind, .live)
        XCTAssertEqual(presence.liveDot, .live)
        XCTAssertTrue(presence.sourceLabels.contains("Oura"))
    }

    func testDayEmptyCopyRoutesThroughPresence() {
        let connected = HealthKitSleepService.dayEmptyCopy(healthConnected: true)
        XCTAssertEqual(connected.title, "No scored night yet")
        XCTAssertEqual(connected.cta, "Refresh from Apple Health")
        XCTAssertTrue(connected.message.localizedCaseInsensitiveContains("in-bed"))

        let disconnected = HealthKitSleepService.dayEmptyCopy(healthConnected: false)
        XCTAssertEqual(disconnected.title, "Connect Apple Health to unlock sleep")
        XCTAssertEqual(disconnected.cta, "Reconnect Apple Health")
    }

    func testLifestyleCopyHasNoMedicalClaims() {
        let blob = [
            SleepLifestyleCopy.disclaimer,
            SleepLifestyleCopy.dimRoomCue,
            SleepLifestyleCopy.environmentHint,
            SleepSurfacePresence.make(
                healthConnected: true,
                isLoading: false,
                hasScoredNight: false,
                metricSources: []
            ).emptyMessage,
        ].joined(separator: " ")
        let banned = ["diagnos", "disease", "patient", "melatonin", "apnea", "insomnia", "treat"]
        for word in banned {
            XCTAssertFalse(
                blob.localizedCaseInsensitiveContains(word),
                "Sleep lifestyle copy must not claim \(word): \(blob)"
            )
        }
        XCTAssertTrue(SleepLifestyleCopy.disclaimer.localizedCaseInsensitiveContains("lifestyle"))
        XCTAssertTrue(SleepLifestyleCopy.disclaimer.localizedCaseInsensitiveContains("not medical"))
    }

    func testResearchHooksWaitForTheBrief() {
        XCTAssertEqual(SleepResearchHook.allCases.count, 3)
        for hook in SleepResearchHook.allCases {
            XCTAssertFalse(hook.waitsForBrief.isEmpty)
            XCTAssertTrue(
                hook.waitsForBrief.localizedCaseInsensitiveContains("brief")
                    || hook.waitsForBrief.localizedCaseInsensitiveContains("rise")
                    || hook.waitsForBrief.localizedCaseInsensitiveContains("pillow")
            )
        }
    }

    @MainActor
    func testAppStoreSurfaceUsesHealthAndSources() {
        let store = AppStore()
        store.healthKitLive = true
        store.isHealthKitPulling = false
        store.dataLoadState = .loaded
        store.sleepData = []
        store.metricSources = ["whoop", "oura"]
        let presence = store.sleepSurface
        XCTAssertEqual(presence.kind, .connectedEmpty)
        XCTAssertEqual(presence.sourceIDs.first, "apple-health")
        XCTAssertTrue(presence.sourceIDs.contains("whoop"))
        XCTAssertTrue(presence.sourceIDs.contains("oura"))
    }
}
