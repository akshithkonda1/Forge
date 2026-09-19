import Foundation

/// Test-Ready simulator ingest must not freeze Home — or Apple Calendar.
///
/// A new process used to mint a new seed, then delete and rewrite 30 days of
/// HealthKit plus a year of EventKit on the main actor. That is what made
/// Simulator launches take minutes, and what launched `MobileCal` into a
/// 30s `0x8BADF00D` process-launch watchdog. Seed is stable for the process
/// (Home + Lifestyle share one pack); a new launch mints a new persona.
/// HealthKit rewrites happen only when that seed changes. EventKit year
/// writes do not run on Simulator; the same pack still becomes lifestyle
/// assets ARIA can sort. Home never waits on them.
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
    /// Simulator EventKit year writes wake Apple Calendar (`MobileCal`). On a
    /// loaded host that process dies at launch with `0x8BADF00D` (30s
    /// process-launch watchdog) before dyld finishes. ARIA still coaches from
    /// the in-memory pack; a physical phone still gets the Forge-owned year.
    public static let writesEventKitYearOnSimulator = false

    public static var isRunningOnSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        let env = ProcessInfo.processInfo.environment
        return env["SIMULATOR_UDID"] != nil || env["SIMULATOR_DEVICE_NAME"] != nil
        #endif
    }

    public static func shouldWriteEventKitYear(isSimulator: Bool) -> Bool {
        !isSimulator || writesEventKitYearOnSimulator
    }

    /// Test-Ready Simulator must not touch EventKit: a predicate fetch can
    /// still launch MobileCal. Memory week + horizon tags are enough.
    public static func skipsSimulatorEventKit(testReady: Bool, isSimulator: Bool) -> Bool {
        testReady && isSimulator && !writesEventKitYearOnSimulator
    }

    /// After Home is on screen, wait this long before Simulator HealthKit pack
    /// rewrite and 30-day queries. Immediate writes fight DeviceHub / dyld
    /// and Apple Calendar dies with `0x8BADF00D`.
    public static let simulatorBackgroundIngestDelaySeconds: Double = 2.5

    /// AppStore init and Home `.task` both call `refreshDailyData`. Coalesce
    /// the second launch pass so Home does not load twice.
    public static let launchRefreshCoalesceSeconds: Double = 2.0

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
