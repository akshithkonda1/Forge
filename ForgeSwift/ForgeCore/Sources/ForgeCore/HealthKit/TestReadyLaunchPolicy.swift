import Foundation

/// Test-Ready simulator ingest must not freeze Home.
///
/// A new process used to mint a new seed, then delete and rewrite 30 days of
/// HealthKit plus a year of EventKit on the main actor. That is what made
/// Simulator launches take minutes. Seed is stable for the process (Home +
/// Lifestyle share one pack); a new launch mints a new persona. HealthKit and
/// calendar rewrites happen only when that seed changes, and Home never waits
/// on them.
public enum TestReadyLaunchPolicy: Sendable {
    public static let seedDefaultsKey = "forge.testReady.sessionSeed.v2"
    public static let seedDayDefaultsKey = "forge.testReady.sessionDay.v2"
    public static let seedProcessTokenKey = "forge.testReady.sessionProcessToken.v1"
    public static let healthKitInstalledSeedKey = "forge.testReady.healthKit.installedSeed.v1"
    public static let calendarInstalledSeedKey = "forge.testReady.calendar.installedSeed.v1"

    /// Contract flags. Tests lock these to false. Launch code branches on them
    /// so flipping a flag back to "wait on Home" fails CI.
    public static let homeWaitsForHealthKitPackWrite = false
    public static let homeWaitsForCalendarYearWrite = false
    public static let homeWaitsForMedicationCatalog = false
    public static let homeWaitsForRemoteDashboard = false
    public static let homeWaitsForThirtyDayHealthQueries = false
    public static let homeWaitsForHealthKitAuthorizationSheet = false
    /// EventKit year writes must not run on MainActor. The old path committed
    /// ~120 events on the UI thread and froze Home for minutes.
    public static let calendarYearWriteRunsOnMainActor = false

    public static func dayStamp(_ date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            parts.year ?? 0,
            parts.month ?? 0,
            parts.day ?? 0
        )
    }

    /// New Health + calendar persona every Simulator process. Same process
    /// (Home + Lifestyle both asking) keeps one seed so the two packs match.
    /// Home still does not wait on the rewrite.
    public static func sessionSeed(
        now: Date,
        defaults: UserDefaults,
        calendar: Calendar = .current,
        processToken: String = ProcessInfo.processInfo.globallyUniqueString,
        generate: () -> Int
    ) -> Int {
        let day = dayStamp(now, calendar: calendar)
        if defaults.string(forKey: seedProcessTokenKey) == processToken,
           defaults.object(forKey: seedDefaultsKey) != nil {
            return defaults.integer(forKey: seedDefaultsKey)
        }
        let seed = generate()
        defaults.set(seed, forKey: seedDefaultsKey)
        defaults.set(day, forKey: seedDayDefaultsKey)
        defaults.set(processToken, forKey: seedProcessTokenKey)
        return seed
    }

    public static func shouldRewrite(installedSeed: Int?, sessionSeed: Int) -> Bool {
        installedSeed != sessionSeed
    }

    public static func storedSeed(_ defaults: UserDefaults, key: String) -> Int? {
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    public static func storeSeed(_ seed: Int?, defaults: UserDefaults, key: String) {
        if let seed {
            defaults.set(seed, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
