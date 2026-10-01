import XCTest
@testable import ForgeCore

final class TrainingLoadModelTests: XCTestCase {

    private func session(daysAgo: Int, duration: Int, intensity: Int, now: Date = Date()) -> TrainingLoadModel.Session {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: now) ?? now
        return TrainingLoadModel.Session(date: date, durationMinutes: duration, intensityLevel: intensity)
    }

    func testStrainScalesWithDurationAndIntensity() {
        let easy = TrainingLoadModel.Session(date: Date(), durationMinutes: 30, intensityLevel: 1)
        let hard = TrainingLoadModel.Session(date: Date(), durationMinutes: 90, intensityLevel: 4)
        XCTAssertLessThan(easy.strain, hard.strain)
        XCTAssertTrue((0...21).contains(easy.strain))
        XCTAssertTrue((0...21).contains(hard.strain))
    }

    func testSixtyMinuteHardSessionIsFourteen() {
        let s = TrainingLoadModel.Session(date: Date(), durationMinutes: 60, intensityLevel: 4)
        XCTAssertEqual(s.strain, 60 * 4 / 17.0, accuracy: 0.01)
    }

    func testIntensityClamps() {
        let low = TrainingLoadModel.Session(date: Date(), durationMinutes: 60, intensityLevel: 0)
        let high = TrainingLoadModel.Session(date: Date(), durationMinutes: 60, intensityLevel: 99)
        XCTAssertEqual(low.intensityLevel, 1)
        XCTAssertEqual(high.intensityLevel, 4)
    }

    func testPictureHasFourteenDays() {
        let picture = TrainingLoadModel.picture(sessions: [])
        XCTAssertEqual(picture.days.count, 14)
        XCTAssertTrue(picture.days.allSatisfy { $0.strain == 0 })
        XCTAssertNil(picture.acwr)
    }

    func testACWRDetectsSpike() {
        // 28 days of easy base (need ≥8 sessions for a ratio), then a huge week.
        var sessions: [TrainingLoadModel.Session] = []
        for d in 8...27 { sessions.append(session(daysAgo: d, duration: 30, intensity: 1)) }
        for d in 0...6 { sessions.append(session(daysAgo: d, duration: 90, intensity: 4)) }
        let picture = TrainingLoadModel.picture(sessions: sessions)
        XCTAssertNotNil(picture.acwr)
        XCTAssertGreaterThan(picture.acwr ?? 0, 1.5)
        XCTAssertTrue(picture.acwrVerdict?.contains("Danger zone") ?? false)
    }

    func testACWRSweetSpot() {
        // Consistent moderate training for 4 weeks.
        var sessions: [TrainingLoadModel.Session] = []
        for d in 0...27 { sessions.append(session(daysAgo: d, duration: 45, intensity: 2)) }
        let picture = TrainingLoadModel.picture(sessions: sessions)
        XCTAssertNotNil(picture.acwr)
        let ratio = picture.acwr ?? 0
        XCTAssertTrue((0.8..<1.3).contains(ratio), "ratio was \(ratio)")
        XCTAssertTrue(picture.acwrVerdict?.contains("Sweet spot") ?? false)
    }

    func testHeavyStreakCounts() {
        var sessions: [TrainingLoadModel.Session] = []
        for d in 0...2 { sessions.append(session(daysAgo: d, duration: 120, intensity: 4)) }
        let picture = TrainingLoadModel.picture(sessions: sessions)
        XCTAssertEqual(picture.heavyStreak, 3)
    }

    func testZoneClassification() {
        XCTAssertEqual(TrainingLoadModel.Zone.zone(for: 2), .rest)
        XCTAssertEqual(TrainingLoadModel.Zone.zone(for: 7), .light)
        XCTAssertEqual(TrainingLoadModel.Zone.zone(for: 12), .moderate)
        XCTAssertEqual(TrainingLoadModel.Zone.zone(for: 18), .heavy)
    }
}
