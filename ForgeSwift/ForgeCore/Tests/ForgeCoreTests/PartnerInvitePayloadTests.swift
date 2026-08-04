import XCTest
@testable import ForgeCore

/// The invite payload is the one part of partner sharing that crosses a process
/// boundary — the app writes it, Messages carries it, the extension reads it —
/// and none of those three can be exercised in CI. These tests cover the part
/// that can be: the codec, the expiry rule, and the staging window.
///
/// The privacy assertions matter most. `testPayloadCarriesNoCycleData` fails if
/// anyone ever adds a cycle field to the payload, which is the specific
/// regression that would put reproductive data into an iMessage transcript.
final class PartnerInvitePayloadTests: XCTestCase {

    private let share = URL(string: "https://www.icloud.com/share/0abcDEF123456789")!

    /// Scratch domain, so the tests neither depend on the real app group being
    /// available to a test process nor leave anything behind in it.
    private var suiteName = ""
    private var previousStore: UserDefaults?

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "forge.tests.partnerInvite.\(UUID().uuidString)"
        let suite = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        previousStore = PartnerInviteBox.store
        PartnerInviteBox.store = suite
    }

    override func tearDownWithError() throws {
        PartnerInviteBox.store = previousStore
        UserDefaults().removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    private func payload(status: PartnerInvitePayload.Status = .pending,
                         created: Date = Date(),
                         expiresIn: TimeInterval = 60 * 60 * 24 * 14) -> PartnerInvitePayload {
        PartnerInvitePayload(shareURL: share,
                             fromDisplayName: "Sam",
                             roleRaw: "romantic",
                             roleLabel: "Partner",
                             status: status,
                             createdAt: created,
                             expiresAt: created.addingTimeInterval(expiresIn))
    }

    // MARK: - Round trip

    func testURLRoundTripPreservesEveryField() {
        let original = payload()
        let decoded = PartnerInvitePayload(url: original.url)

        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.version, original.version)
        XCTAssertEqual(decoded?.shareURL, original.shareURL)
        XCTAssertEqual(decoded?.fromDisplayName, original.fromDisplayName)
        XCTAssertEqual(decoded?.roleRaw, original.roleRaw)
        XCTAssertEqual(decoded?.roleLabel, original.roleLabel)
        XCTAssertEqual(decoded?.status, original.status)
        // Seconds precision: the wire format is epoch seconds, so sub-second
        // drift is expected and irrelevant.
        XCTAssertEqual(decoded?.createdAt.timeIntervalSince1970 ?? 0,
                       original.createdAt.timeIntervalSince1970,
                       accuracy: 1)
        XCTAssertEqual(decoded?.expiresAt.timeIntervalSince1970 ?? 0,
                       original.expiresAt.timeIntervalSince1970,
                       accuracy: 1)
    }

    func testDisplayNamesWithPunctuationSurviveEncoding() {
        // Names are user-supplied and end up in a query string. An ampersand or
        // a slash that is not escaped would truncate the payload and lose the
        // share URL.
        for name in ["Sam & Alex", "Ana/Maria", "J?e", "Zoë", "a+b", "100%", "李雷"] {
            let original = PartnerInvitePayload(shareURL: share,
                                                fromDisplayName: name,
                                                roleRaw: "friend",
                                                roleLabel: "Friend",
                                                expiresAt: Date().addingTimeInterval(3600))
            let decoded = PartnerInvitePayload(url: original.url)
            XCTAssertEqual(decoded?.fromDisplayName, name, "lost \(name) in the round trip")
            XCTAssertEqual(decoded?.shareURL, share, "share URL corrupted by \(name)")
        }
    }

    func testMalformedURLsDecodeToNilRatherThanADefaultedPayload() {
        let cases = [
            "forge://support-invite",                                 // no query at all
            "forge://support-invite?v=1&from=Sam",                    // no share URL
            "forge://something-else?v=1&share=x&from=S&role=r&status=pending",
            "https://example.com/?v=1&share=x&from=S&role=r&status=pending",
            "forge://support-invite?v=1&share=x&from=S&role=r&status=banana"
        ]
        for text in cases {
            let url = URL(string: text)!
            XCTAssertNil(PartnerInvitePayload(url: url), "should not have decoded \(text)")
        }
    }

    // MARK: - Expiry

    func testPendingInviteExpiresOnceItsWindowPasses() {
        let stale = payload(created: Date().addingTimeInterval(-60 * 60 * 24 * 20),
                            expiresIn: 60 * 60 * 24 * 14)
        XCTAssertEqual(stale.status, .pending, "stored status is untouched")
        XCTAssertEqual(stale.effectiveStatus, .expired, "but it must not read as live")
        XCTAssertFalse(stale.effectiveStatus.isActionable)
    }

    func testExpiryDoesNotOverrideAnAcceptedInvite() {
        // Acceptance already happened; the invite lapsing afterwards must not
        // make the transcript claim the share was never taken up.
        let accepted = payload(status: .accepted,
                               created: Date().addingTimeInterval(-60 * 60 * 24 * 20))
        XCTAssertEqual(accepted.effectiveStatus, .accepted)
    }

    func testOnlyPendingInvitesAreActionable() {
        XCTAssertTrue(PartnerInvitePayload.Status.pending.isActionable)
        for status in [PartnerInvitePayload.Status.accepted, .revoked, .expired] {
            XCTAssertFalse(status.isActionable, "\(status) must not read as a live offer")
        }
    }

    func testMissingExpiryIsTreatedAsExpiredNotAsPermanent() {
        var components = URLComponents(url: payload().url, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems?.filter { $0.name != "expires" }
        let decoded = PartnerInvitePayload(url: components.url!)
        XCTAssertEqual(decoded?.effectiveStatus, .expired)
    }

    // MARK: - Versioning

    func testPayloadFromANewerVersionIsNotTreatedAsReadable() {
        var components = URLComponents(url: payload().url, resolvingAgainstBaseURL: false)!
        components.queryItems = components.queryItems?.map {
            $0.name == "v" ? URLQueryItem(name: "v", value: "99") : $0
        }
        let decoded = PartnerInvitePayload(url: components.url!)
        XCTAssertNotNil(decoded, "it still decodes — the extension needs the version to explain itself")
        XCTAssertFalse(decoded!.isReadable)
    }

    func testUpdatingStatusChangesNothingElse() {
        let original = payload()
        let revoked = original.updating(status: .revoked)
        XCTAssertEqual(revoked.status, .revoked)
        XCTAssertEqual(revoked.shareURL, original.shareURL)
        XCTAssertEqual(revoked.fromDisplayName, original.fromDisplayName)
        XCTAssertEqual(revoked.roleRaw, original.roleRaw)
        XCTAssertEqual(revoked.createdAt, original.createdAt)
        XCTAssertEqual(revoked.expiresAt, original.expiresAt)
    }

    // MARK: - Privacy

    func testPayloadCarriesNoCycleData() {
        // The encoded URL is what lands in an iMessage transcript, an iCloud
        // backup and a lock-screen preview. Nothing in it may hint at what is
        // being tracked. If this fails, a field was added that should not exist.
        let encoded = payload().url.absoluteString.lowercased()
        let forbidden = ["cycle", "period", "menstrual", "flow", "fertile",
                         "ovulation", "symptom", "pregnan", "luteal", "follicular",
                         "phase", "energy", "conceive"]
        for term in forbidden {
            XCTAssertFalse(encoded.contains(term),
                           "invite URL leaks \"\(term)\": \(encoded)")
        }
    }

    func testBubbleTextNamesTheSenderAndNothingElse() {
        let text = payload().bubbleCaption
        XCTAssertTrue(text.contains("Sam"))
        for term in ["cycle", "period", "menstrual", "fertile"] {
            XCTAssertFalse(text.lowercased().contains(term),
                           "bubble caption leaks \"\(term)\"")
        }
    }

    // MARK: - Handoff staging

    func testStagedInviteIsReturnedInsideTheWindow() {
        PartnerInviteHandoff.clear()
        let fresh = payload()
        PartnerInviteHandoff.stage(fresh)
        defer { PartnerInviteHandoff.clear() }

        let staged = PartnerInviteHandoff.staged()
        XCTAssertEqual(staged?.shareURL, fresh.shareURL)
    }

    func testStagedInviteGoesStaleAfterTheStagingWindow() {
        PartnerInviteHandoff.clear()
        PartnerInviteHandoff.stage(payload())
        defer { PartnerInviteHandoff.clear() }

        // Staging says "the user is about to send this", not "the user may send
        // this whenever". Coming back tomorrow must send them through the app.
        let later = Date().addingTimeInterval(PartnerInviteHandoff.stagingWindow + 60)
        XCTAssertNil(PartnerInviteHandoff.staged(now: later))
    }

    func testClearingRemovesTheStagedInvite() {
        // This is the revoke path: once sharing stops, the extension must have
        // nothing left to hand out.
        PartnerInviteHandoff.stage(payload())
        PartnerInviteHandoff.clear()
        XCTAssertNil(PartnerInviteHandoff.staged())
    }

    func testAnAlreadyExpiredInviteIsNeverStaged() {
        PartnerInviteHandoff.clear()
        PartnerInviteHandoff.stage(payload(created: Date(), expiresIn: -60))
        defer { PartnerInviteHandoff.clear() }
        XCTAssertNil(PartnerInviteHandoff.staged())
    }

    // MARK: - Acceptance record

    func testAcceptanceIsRecordedAndForgotten() {
        let url = URL(string: "https://www.icloud.com/share/testAcceptance")!
        PartnerInviteAcceptance.forget(shareURL: url)
        XCTAssertFalse(PartnerInviteAcceptance.hasAccepted(shareURL: url))

        PartnerInviteAcceptance.record(shareURL: url)
        XCTAssertTrue(PartnerInviteAcceptance.hasAccepted(shareURL: url))

        PartnerInviteAcceptance.forget(shareURL: url)
        XCTAssertFalse(PartnerInviteAcceptance.hasAccepted(shareURL: url))
    }

    func testAcceptingOneShareDoesNotAcceptAnother() {
        let mine = URL(string: "https://www.icloud.com/share/mine")!
        let theirs = URL(string: "https://www.icloud.com/share/theirs")!
        PartnerInviteAcceptance.forget(shareURL: mine)
        PartnerInviteAcceptance.forget(shareURL: theirs)
        defer {
            PartnerInviteAcceptance.forget(shareURL: mine)
            PartnerInviteAcceptance.forget(shareURL: theirs)
        }

        PartnerInviteAcceptance.record(shareURL: mine)
        XCTAssertTrue(PartnerInviteAcceptance.hasAccepted(shareURL: mine))
        XCTAssertFalse(PartnerInviteAcceptance.hasAccepted(shareURL: theirs))
    }
}
