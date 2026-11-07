import XCTest
@testable import ForgeSwift
import ForgeCore

/// Locks picker-only people: no full-book read, tapped contacts go through
/// `PeopleDirectory.admit`, and the privacy line does not claim names stay
/// in Contacts or are never sent to ARIA.
final class ContactsPickerOnlyTests: XCTestCase {

    func testSourcesDoNotEnumerateTheAddressBook() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let needles = ["CNContact" + "FetchRequest", "enumerate" + "Contacts"]
        var hits: [String] = []
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let path = url.path
            if path.contains("/Tests/") || path.hasSuffix("Tests.swift") { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for needle in needles where text.contains(needle) {
                hits.append("\(url.lastPathComponent): \(needle)")
            }
        }
        XCTAssertTrue(hits.isEmpty, "Address-book enumeration is forbidden:\n\(hits.joined(separator: "\n"))")
    }

    func testPeopleScreenWiresTheSystemPicker() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ForgeSwift/LifestyleWellbeingView.swift")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("CNContactPickerViewController"))
        XCTAssertTrue(text.contains("predicateForSelectionOfContact"))
        XCTAssertTrue(text.contains("didSelect contacts"))
        XCTAssertTrue(text.contains("CNContactGivenNameKey"))
        XCTAssertTrue(text.contains("Pick from Contacts"))
        XCTAssertFalse(text.contains("Allow Contacts"))
        XCTAssertFalse(text.contains("requestAccess(for: .contacts)"))
        XCTAssertFalse(text.contains("CNContact" + "Store"))
    }

    func testPickerPicksAdmitThroughPeopleDirectory() {
        let directory = PeopleContactPicks.applying(
            [
                (givenName: "Maya Chen", identifier: "cn-maya"),
                (givenName: "Jo", identifier: "cn-jo"),
                (givenName: "sam@example.com", identifier: "cn-bad"),
            ],
            relation: .friend,
            to: PeopleDirectory.Directory()
        )
        XCTAssertTrue(directory.optedIn)
        XCTAssertEqual(directory.coachingPeople.map(\.firstName), ["Maya", "Jo"])
        XCTAssertEqual(directory.coachingPeople.map(\.contactIdentifier), ["cn-maya", "cn-jo"])
        let blob = directory.ariaTags.joined(separator: " ")
        XCTAssertTrue(blob.contains("people:Maya:friend"))
        XCTAssertFalse(blob.contains("cn-"))
        XCTAssertFalse(blob.contains("Chen"))
    }

    @MainActor
    func testConnectContactsPresentsPickerWithoutAddressBookAccess() {
        let coordinator = OnboardingCoordinator()
        coordinator.step = .health
        coordinator.connectContacts()
        XCTAssertTrue(coordinator.showContactsPicker)
        XCTAssertEqual(coordinator.contactsState, .requesting)
    }

    func testPrivacyCopyNamesAriaCoachingAndDoesNotClaimNamesStayPut() {
        let blob = [
            PeoplePrivacyCopy.savedLine,
            PeoplePrivacyCopy.coachingLine,
            PeoplePrivacyCopy.settingsHonesty,
            PeoplePrivacyCopy.sheetIntro,
            PeoplePrivacyCopy.emptyCard,
        ].joined(separator: " ").lowercased()
        XCTAssertTrue(blob.contains("only people you pick are saved"))
        XCTAssertTrue(blob.contains("aria"))
        XCTAssertTrue(blob.contains("coaching"))
        XCTAssertTrue(blob.contains("phone numbers") && blob.contains("emails"))
        XCTAssertFalse(blob.contains("not uploaded"))
        XCTAssertFalse(blob.contains("stay in contacts"))
    }
}
