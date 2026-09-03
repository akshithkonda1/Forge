import XCTest
@testable import ForgeCore

final class FakeHealthPackTests: XCTestCase {

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return cal
    }

    private var pinnedNow: Date {
        var parts = DateComponents()
        parts.year = 2026
        parts.month = 8
        parts.day = 25
        parts.hour = 15
        parts.minute = 0
        return calendar.date(from: parts)!
    }

    func testShouldInstallOnlyWhenTestReadyAndEmpty() {
        XCTAssertTrue(
            FakeHealthPack.shouldInstall(debugBuild: true, testReady: true, hasRealHealthSignal: false)
        )
        XCTAssertFalse(
            FakeHealthPack.shouldInstall(debugBuild: true, testReady: true, hasRealHealthSignal: true),
            "real HealthKit samples must win"
        )
        XCTAssertFalse(
            FakeHealthPack.shouldInstall(debugBuild: false, testReady: true, hasRealHealthSignal: false)
        )
        XCTAssertFalse(
            FakeHealthPack.shouldInstall(debugBuild: true, testReady: false, hasRealHealthSignal: false)
        )
    }

    func testShouldSeedHealthKitEverySimulatorLaunch() {
        XCTAssertTrue(
            FakeHealthPack.shouldSeedHealthKit(
                debugBuild: true, testReady: true, isSimulator: true, healthAuthorized: true
            )
        )
        XCTAssertFalse(
            FakeHealthPack.shouldSeedHealthKit(
                debugBuild: true, testReady: true, isSimulator: true, healthAuthorized: false
            ),
            "wait for Connect Apple Health — first integration"
        )
        XCTAssertFalse(
            FakeHealthPack.shouldSeedHealthKit(
                debugBuild: true, testReady: true, isSimulator: false, healthAuthorized: true
            ),
            "never write the pack into a physical phone's Health store"
        )
        XCTAssertFalse(
            FakeHealthPack.shouldSeedHealthKit(
                debugBuild: false, testReady: true, isSimulator: true, healthAuthorized: true
            )
        )
        XCTAssertFalse(
            FakeHealthPack.shouldSeedHealthKit(
                debugBuild: true, testReady: false, isSimulator: true, healthAuthorized: true
            )
        )
    }

    func testGenerateIsDeterministic() {
        let a = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 7)
        let b = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 7)
        XCTAssertEqual(a.days.count, FakeHealthPack.dayCount)
        XCTAssertEqual(a.days.map(\.isoDate), b.days.map(\.isoDate))
        XCTAssertEqual(a.days.map(\.hrvMs), b.days.map(\.hrvMs))
        XCTAssertEqual(a.today?.night.totalMinutes, b.today?.night.totalMinutes)
    }

    func testTodayHasSleepHRVAndWaterARIACanCite() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        guard let today = pack.today else {
            return XCTFail("pack must have a today")
        }
        XCTAssertGreaterThan(today.night.totalMinutes, 5 * 60)
        XCTAssertGreaterThan(today.night.deepMinutes, 0)
        XCTAssertGreaterThan(today.night.remMinutes, 0)
        XCTAssertNotNil(today.night.start)
        XCTAssertNotNil(today.night.end)
        XCTAssertTrue((28...95).contains(today.hrvMs))
        XCTAssertTrue((48...78).contains(today.restingHR))
        XCTAssertGreaterThan(today.steps, 0)
        XCTAssertGreaterThan(today.hydrationMl, 0)
        XCTAssertEqual(today.isoDate, "2026-08-25")
    }

    func testStreamHasShortNightsAndWorkouts() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        let short = pack.days.filter { $0.night.totalMinutes < 6.5 * 60 }
        XCTAssertGreaterThanOrEqual(short.count, 2, "ARIA needs a sleep-debt story")
        let sessions = pack.days.compactMap(\.workout)
        XCTAssertGreaterThanOrEqual(sessions.count, 8)
        XCTAssertTrue(sessions.contains { $0.type == .strength })
    }

    func testReadinessInputsAreComplete() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        let inputs = pack.readinessInputs
        XCTAssertNotNil(inputs.hrvMs)
        XCTAssertNotNil(inputs.sleepMinutes)
        let score = ReadinessCalculator.score(from: inputs)
        XCTAssertGreaterThan(score.confidence, 0.5)
        XCTAssertTrue((1...100).contains(score.overall))
    }

    func testNightsAreNewestFirstAndDoNotShareDates() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar)
        let dates = pack.days.map(\.isoDate)
        XCTAssertEqual(dates.first, "2026-08-25")
        XCTAssertEqual(Set(dates).count, dates.count)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    // MARK: - Lifestyle history

    func testMonthShapeVariesWithSeedNotJustValues() {
        // The shape used to be hardcoded to the offset, so every seed told the
        // same month: same short nights, same rest days. Different seeds must
        // now produce different *stories*, not just different jitter.
        let a = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 11)
        let b = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 977)
        // Spelled out rather than chained: Set(enumerated().filter{}.map(\.offset))
        // is the same shape that blew the type-checker's budget in
        // AriaIntentResolver, and a test that will not compile is worth less
        // than no test.
        func shortNightIndices(_ pack: FakeHealthPack) -> Set<Int> {
            var out: Set<Int> = []
            for (index, day) in pack.days.enumerated() where day.night.totalMinutes < 6.5 * 60 {
                out.insert(index)
            }
            return out
        }
        let shortA = shortNightIndices(a)
        let shortB = shortNightIndices(b)
        XCTAssertNotEqual(shortA, shortB, "short nights must not land on the same days for every seed")

        let workoutsA = a.days.map { $0.workout?.name ?? "-" }
        let workoutsB = b.days.map { $0.workout?.name ?? "-" }
        XCTAssertNotEqual(workoutsA, workoutsB, "the training week must not always start on the same pack index")
    }

    func testGuaranteesHoldAcrossManySeeds() {
        // The app re-seeds per session now, so a guarantee that holds for the
        // tests' pinned seeds but not for arbitrary ones is a bug that ships and
        // never reproduces.
        for seed in stride(from: 1, through: 400, by: 7) {
            let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: seed)
            let short = pack.days.filter { $0.night.totalMinutes < 6.5 * 60 }
            XCTAssertGreaterThanOrEqual(short.count, 2, "seed \(seed) lost the sleep-debt story")
            XCTAssertGreaterThanOrEqual(pack.days.compactMap(\.workout).count, 8, "seed \(seed) lost sessions")
            XCTAssertTrue(pack.days.compactMap(\.workout).contains { $0.type == .strength }, "seed \(seed) lost strength")

            guard let today = pack.today else { return XCTFail("seed \(seed) has no today") }
            XCTAssertGreaterThan(today.night.totalMinutes, 5 * 60, "seed \(seed) made today uncitable")
            XCTAssertGreaterThan(today.night.deepMinutes, 0)
            XCTAssertTrue((28...95).contains(today.hrvMs), "seed \(seed) HRV out of range")
            XCTAssertTrue((48...78).contains(today.restingHR), "seed \(seed) RHR out of range")
            XCTAssertTrue(today.social.isEmpty, "today's evening has not happened yet")
        }
    }

    func testSocialEventsActuallyMoveTheBiometrics() {
        // A late night with drinks that left sleep and HRV untouched would be
        // worse than no social data: ARIA would learn to say things the numbers
        // contradict.
        var heavyNights = 0
        var quietNights = 0
        var heavyHRV = 0
        var quietHRV = 0
        for seed in stride(from: 3, through: 300, by: 11) {
            let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: seed)
            for day in pack.days.dropFirst() {
                if let event = day.social.first, event.drinks >= 3 {
                    heavyNights += 1
                    heavyHRV += day.hrvMs
                } else if day.social.isEmpty {
                    quietNights += 1
                    quietHRV += day.hrvMs
                }
            }
        }
        XCTAssertGreaterThan(heavyNights, 20, "not enough heavy nights generated to compare")
        XCTAssertGreaterThan(quietNights, 20)
        let heavyMean = Double(heavyHRV) / Double(heavyNights)
        let quietMean = Double(quietHRV) / Double(quietNights)
        XCTAssertLessThan(heavyMean, quietMean, "drinking nights must depress HRV relative to quiet ones")
    }

    func testDaysCarryPlacesAndSomeEvenings() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        XCTAssertTrue(pack.days.allSatisfy { !$0.markers.isEmpty }, "every day needs at least home")
        for day in pack.days {
            let arrivals: [Date] = day.markers.map(\.arrival)
            let ordered: [Date] = arrivals.sorted()
            XCTAssertEqual(arrivals, ordered, "markers must read in the order the day happened")
        }
        let social = pack.days.flatMap(\.social)
        XCTAssertFalse(social.isEmpty, "a month with no evenings in it is not an average person")
        let allMarkers: [FakeLifestyleMarker] = pack.days.flatMap(\.markers)
        XCTAssertTrue(allMarkers.contains { $0.kind == .gym })
    }

    func testPersonaIsAKnownHumanShape() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 41)
        XCTAssertTrue(FakeHealthPack.personaLabels.contains(pack.personaLabel))
        XCTAssertTrue(pack.days.allSatisfy { !$0.storyLine.isEmpty }, "every day needs a sentence ARIA can say")
        XCTAssertTrue(pack.days.allSatisfy { !$0.felt.isEmpty })
    }

    func testPinnedPersonaActuallyMovesTheBody() {
        // Same seed, same month-shape, different humans. If athlete and
        // stressed produce the same HRV curve the label is still a sticker.
        let athlete = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 41, persona: "athlete")
        let stressed = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 41, persona: "stressed")
        XCTAssertEqual(athlete.personaLabel, "athlete")
        XCTAssertEqual(stressed.personaLabel, "stressed")
        let athleteHRV = athlete.days.map(\.hrvMs).reduce(0, +)
        let stressedHRV = stressed.days.map(\.hrvMs).reduce(0, +)
        XCTAssertGreaterThan(athleteHRV, stressedHRV, "athlete baseline must sit above a stressed month")
        let athleteSteps = athlete.days.map(\.steps).reduce(0, +)
        let stressedSteps = stressed.days.map(\.steps).reduce(0, +)
        XCTAssertGreaterThan(athleteSteps, stressedSteps)
    }

    func testStoryFollowsTheNightItDescribes() {
        let pack = FakeHealthPack.generate(now: pinnedNow, calendar: calendar, seed: 41, persona: "balanced")
        for day in pack.days {
            if let event = day.social.first, event.drinks >= 3 || event.ranLate {
                XCTAssertTrue(
                    day.storyLine.localizedCaseInsensitiveContains(event.title)
                        || day.felt == "spent",
                    "a late/drinking night must show up in the story, not as a quiet rebuild"
                )
                XCTAssertFalse(day.storyLine.localizedCaseInsensitiveContains("actual rebuild"))
            }
        }
    }
}
