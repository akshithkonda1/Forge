import XCTest
@testable import ForgeCore

final class PeopleDirectoryTests: XCTestCase {

    private var suite = ""
    private var defaults: UserDefaults!

    override func setUp() {
        suite = "forge.people.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    func testNotOptedInIsAnEmptyGraphEvenIfStaleRowsExist() {
        var directory = PeopleDirectory.Directory(
            optedIn: false,
            contactsAccess: .denied,
            people: [PeopleDirectory.Person(firstName: "Sam", relation: .partner)]
        )
        XCTAssertTrue(directory.coachingPeople.isEmpty)
        XCTAssertTrue(directory.ariaTags.isEmpty)
        directory.optedIn = true
        XCTAssertEqual(directory.coachingPeople.map(\.firstName), ["Sam"])
        XCTAssertTrue(directory.ariaTags.contains("people:count:1"))
        XCTAssertTrue(directory.ariaTags.contains("people:Sam:partner"))
        XCTAssertFalse(directory.ariaTags.contains { $0.contains("@") || $0.contains("identifier") })
    }

    func testAdmitKeepsFirstNameAndDropsContactPII() {
        XCTAssertNil(PeopleDirectory.admit(rawName: "sam@example.com"))
        XCTAssertNil(PeopleDirectory.admit(rawName: "555-121-3344"))
        XCTAssertNil(PeopleDirectory.admit(rawName: "Sam 5551234567"))
        let person = PeopleDirectory.admit(rawName: "Sam Rivera", relation: .partner, contactIdentifier: "abc-123")
        XCTAssertEqual(person?.firstName, "Sam")
        XCTAssertEqual(person?.relation, .partner)
        XCTAssertEqual(person?.contactIdentifier, "abc-123")
        let tags = PeopleDirectory.Directory(optedIn: true, contactsAccess: .granted, people: [person!]).ariaTags
        XCTAssertFalse(tags.joined(separator: " ").contains("abc-123"))
        XCTAssertFalse(tags.joined(separator: " ").contains("Rivera"))
    }

    func testReservedPathNamesAKnownPersonWithoutDiagnosing() {
        let person = PeopleDirectory.Person(firstName: "Sam", relation: .partner)
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 2,
            currentHobbies: [],
            working: UserWorkingModel.snapshot(UserWorkingModel.Input(habitStreakDays: 6, weeklyMood0to10: 7, acwr: 1.0)),
            knownPeople: [person]
        )
        XCTAssertEqual(snap.path, .openGently)
        XCTAssertTrue(snap.coachingLine.contains("Sam"))
        XCTAssertTrue(snap.coachingLine.lowercased().contains("not a stranger"))
        let blob = snap.coachingLine.lowercased()
        for needle in ["diagnos", "disorder", "therap", "clinical", "anxiety"] {
            XCTAssertFalse(blob.contains(needle), needle)
        }
    }

    func testBurnedOutPathLeavesTheNamedPersonOffTheCalendar() {
        let person = PeopleDirectory.Person(firstName: "Jo", relation: .coworker)
        let working = UserWorkingModel.snapshot(UserWorkingModel.Input(
            habitStreakDays: 6,
            weeklyMood0to10: 3,
            acwr: 1.7,
            highStrainLowRecoveryDays: 4
        ))
        let snap = HobbyPathEngine.snapshot(
            socialEnergy0to10: 9,
            currentHobbies: [.gym],
            working: working,
            knownPeople: [person]
        )
        XCTAssertEqual(snap.path, .restoreQuiet)
        XCTAssertTrue(snap.coachingLine.contains("Leave Jo off the calendar"))
    }

    func testPictureCarriesConfirmedPeopleAndOmitsThemWhenForgotten() {
        let person = PeopleDirectory.Person(firstName: "Sam", relation: .roommate)
        let input = ReadinessForecastEngine.Input(
            currentReadiness: 72,
            sleepMinutes: 480,
            hrvMs: 60,
            hrvBaselineMs: 60,
            restingHR: 55,
            restingHRBaseline: 55,
            todayStrain: 8,
            stressLevel: 30
        )
        let working = UserWorkingModel.Input(habitStreakDays: 5, weeklyMood0to10: 7, acwr: 1.0)
        let withPeople = PredictiveCoach.picture(
            forecastInput: input,
            workingInput: working,
            socialEnergy0to10: 2,
            knownPeople: [person]
        )
        XCTAssertTrue(withPeople.ariaTags.contains("people:Sam:roommate"))
        XCTAssertTrue(withPeople.steeringLine.contains("Sam"))
        let denied = PredictiveCoach.picture(
            forecastInput: input,
            workingInput: working,
            socialEnergy0to10: 2,
            knownPeople: []
        )
        XCTAssertFalse(denied.ariaTags.contains { $0.hasPrefix("people:") })
    }

    func testForgetClearsTheOnDeviceGraph() {
        let person = PeopleDirectory.admit(rawName: "Sam", relation: .family)!
        PeopleDirectoryStore.save(
            PeopleDirectory.Directory(optedIn: true, contactsAccess: .granted, people: [person]),
            defaults: defaults
        )
        PeopleDirectoryStore.forget(defaults: defaults)
        let loaded = PeopleDirectoryStore.load(defaults: defaults)
        XCTAssertFalse(loaded.optedIn)
        XCTAssertTrue(loaded.people.isEmpty)
        XCTAssertTrue(loaded.coachingPeople.isEmpty)
    }

    func testPeopleQuestionDoesNotMatchATrainingAsk() {
        XCTAssertTrue(PeopleDirectory.isQuestion("who are my people"))
        XCTAssertFalse(PeopleDirectory.isQuestion("what should I train today"))
    }
}
