import XCTest
@testable import ForgeCore

final class SupportedPersonMatchTests: XCTestCase {

    func testBindByCloudIDEvenWhenNamesDiffer() {
        let people = [
            SupportedPersonMatch.Record(name: "Maya", role: "romantic", cloudID: "owner-a"),
            SupportedPersonMatch.Record(name: "Ava", role: "child", cloudID: "owner-b"),
        ]
        XCTAssertEqual(
            SupportedPersonMatch.bindIndex(
                people: people,
                incomingName: "Someone",
                incomingRole: "romantic",
                incomingCloudID: "owner-b"
            ),
            1
        )
    }

    func testDoesNotBindPartnerSlotToDaughterShare() {
        let people = [
            SupportedPersonMatch.Record(name: "Maya", role: "romantic", cloudID: nil),
        ]
        XCTAssertNil(
            SupportedPersonMatch.bindIndex(
                people: people,
                incomingName: "Maya",
                incomingRole: "child",
                incomingCloudID: "owner-daughter"
            )
        )
    }

    func testBindsLocalNotesToLaterShareWhenNameAndRoleMatch() {
        let people = [
            SupportedPersonMatch.Record(name: "Maya", role: "romantic", cloudID: nil),
            SupportedPersonMatch.Record(name: "Ava", role: "child", cloudID: nil),
        ]
        XCTAssertEqual(
            SupportedPersonMatch.bindIndex(
                people: people,
                incomingName: "Ava",
                incomingRole: "child",
                incomingCloudID: "owner-ava"
            ),
            1
        )
    }

    func testEmptyIncomingIDNeverPicksTheFirstPerson() {
        let people = [
            SupportedPersonMatch.Record(name: "Maya", role: "romantic", cloudID: nil),
        ]
        XCTAssertNil(
            SupportedPersonMatch.bindIndex(
                people: people,
                incomingName: "Maya",
                incomingRole: "romantic",
                incomingCloudID: ""
            )
        )
    }

    func testUnnamedIncomingDoesNotAttachToTheOnlyLocalPerson() {
        let people = [
            SupportedPersonMatch.Record(name: "Maya", role: "romantic", cloudID: nil),
        ]
        XCTAssertNil(
            SupportedPersonMatch.bindIndex(
                people: people,
                incomingName: "",
                incomingRole: "romantic",
                incomingCloudID: "owner-unknown"
            )
        )
    }

    func testOtherRoleCanBindWhenNameMatches() {
        let people = [
            SupportedPersonMatch.Record(name: "Sam", role: "other", cloudID: nil),
        ]
        XCTAssertEqual(
            SupportedPersonMatch.bindIndex(
                people: people,
                incomingName: "Sam",
                incomingRole: "family",
                incomingCloudID: "owner-sam"
            ),
            0
        )
    }
}
