import XCTest
@testable import ForgeCore

final class RemindersWorkloadTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    /// Tuesday 29 September 2026, 15:00 UTC.
    private func at(_ day: Int, month: Int = 9, hour: Int = 0, minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
    }

    private var now: Date { at(29, hour: 15) }

    // MARK: Classification (table)

    func testClassificationRules() {
        let cases: [(title: String, list: String?, kind: ReminderKind)] = [
            ("Pick up prescription", nil, .health),
            ("Schedule dentist", nil, .health),
            ("Work out before standup", nil, .health),
            ("Book flight to Denver", nil, .travel),
            ("Packing list for the trip", nil, .travel),
            ("Send Q3 deck to client", nil, .work),
            ("Prep 1:1 with manager", nil, .work),
            ("Pay rent", nil, .finance),
            ("Buy birthday gift for Sam", nil, .social),
            ("RSVP to Maya's wedding", nil, .social),
            ("Do laundry", nil, .home),
            ("Buy milk", nil, .errand),
            ("Return the jacket", nil, .errand),
            ("Call about the thing", "Work", .work),
            ("Thing", "Groceries", .errand),
            ("Thing", "Household", .home),
            ("Random note", nil, .other),
            ("", nil, .other),
        ]
        for testCase in cases {
            XCTAssertEqual(
                RemindersClassifier.classify(title: testCase.title, listTitle: testCase.list),
                testCase.kind,
                "\(testCase.title) / \(testCase.list ?? "-")"
            )
        }
    }

    func testTitleWinsOverList() {
        XCTAssertEqual(RemindersClassifier.classify(title: "Refill meds", listTitle: "Work"), .health)
    }

    func testReminderItemKeepsNoText() {
        let item = ReminderItem(
            title: "Pick up Mom's prescription at Walgreens",
            listTitle: "Family stuff",
            dueDate: at(30),
            hasDueTime: false,
            priority: 1,
            isCompleted: false
        )
        XCTAssertEqual(item.kind, .health)
        let strings = Mirror(reflecting: item).children.compactMap { $0.value as? String }
        XCTAssertTrue(strings.isEmpty, "the title and list name are dropped after classification")
    }

    // MARK: Buckets

    func testWorkloadBuckets() {
        let items = [
            ReminderItem(kind: .work, dueDate: at(28), hasDueTime: false, priority: 0, isCompleted: false),
            ReminderItem(kind: .errand, dueDate: at(29, hour: 9), hasDueTime: true, priority: 5, isCompleted: false),
            ReminderItem(kind: .health, dueDate: at(29, hour: 18), hasDueTime: true, priority: 5, isCompleted: false),
            ReminderItem(kind: .home, dueDate: at(29), hasDueTime: false, priority: 9, isCompleted: false),
            ReminderItem(kind: .work, dueDate: at(30, hour: 10), hasDueTime: true, priority: 1, isCompleted: false),
            ReminderItem(kind: .travel, dueDate: at(9, month: 10), hasDueTime: false, priority: 0, isCompleted: false),
            ReminderItem(kind: .social, dueDate: at(19, month: 10), hasDueTime: false, priority: 1, isCompleted: false),
            ReminderItem(kind: .finance, dueDate: at(29, hour: 20), hasDueTime: true, priority: 1, isCompleted: true),
            ReminderItem(kind: .other, dueDate: nil, hasDueTime: false, priority: 1, isCompleted: false),
        ]
        let workload = RemindersWorkload.build(from: items, now: now, calendar: calendar)
        XCTAssertEqual(workload.overdueCount, 2, "yesterday, and 9am today when it is 3pm")
        XCTAssertEqual(workload.dueTodayCount, 2, "6pm today, and the all-day reminder")
        XCTAssertEqual(workload.dueTomorrowCount, 1)
        XCTAssertEqual(workload.highPriorityCount, 1, "completed, undated and beyond-horizon items do not count")
        XCTAssertEqual(workload.kindCounts, ["work": 2, "errand": 1, "health": 1, "home": 1, "travel": 1])
        XCTAssertEqual(workload.totalCount, 6)
    }

    func testAriaTagsAreCountsAndKindsOnly() {
        let workload = RemindersWorkload(
            overdueCount: 2, dueTodayCount: 3, dueTomorrowCount: 1, highPriorityCount: 1,
            kindCounts: ["work": 3, "health": 2, "unexpected key from disk": 9]
        )
        XCTAssertEqual(workload.ariaTags, [
            "reminders:overdue:2",
            "reminders:due_today:3",
            "reminders:due_tomorrow:1",
            "reminders:high_priority:1",
            "reminders:kind:health:2",
            "reminders:kind:work:3",
        ])
        XCTAssertEqual(RemindersWorkload.empty.ariaTags, ["reminders:clear"])
    }

    func testSummaryLines() {
        let workload = RemindersWorkload(overdueCount: 2, dueTodayCount: 3, dueTomorrowCount: 1, highPriorityCount: 1,
                                         kindCounts: ["work": 7])
        XCTAssertEqual(workload.summaryLine, "2 overdue · 3 today · 1 tomorrow · 1 high priority")
        XCTAssertEqual(workload.spokenLine, "Reminders: 2 overdue, 3 due today, 1 due tomorrow — I count them, I don't read the titles.")
        XCTAssertEqual(RemindersWorkload.empty.summaryLine, "Nothing due in the next two weeks")
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let workload = RemindersWorkload(overdueCount: 1, dueTodayCount: 2, dueTomorrowCount: 3, highPriorityCount: 4,
                                         kindCounts: ["travel": 1, "social": 2])
        let data = try JSONEncoder().encode(workload)
        XCTAssertEqual(try JSONDecoder().decode(RemindersWorkload.self, from: data), workload)
        let json = String(data: data, encoding: .utf8) ?? ""
        for key in ["overdueCount", "dueTodayCount", "dueTomorrowCount", "highPriorityCount", "kindCounts"] {
            XCTAssertTrue(json.contains(key), key)
        }
    }

    func testKindCodableUsesStableRawValues() throws {
        XCTAssertEqual(ReminderKind.allCases.map(\.rawValue),
                       ["health", "travel", "work", "social", "errand", "home", "finance", "other"])
        let data = try JSONEncoder().encode([ReminderKind.finance])
        XCTAssertEqual(String(data: data, encoding: .utf8), #"["finance"]"#)
    }
}
