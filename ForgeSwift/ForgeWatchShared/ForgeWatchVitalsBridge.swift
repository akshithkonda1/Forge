import Foundation

struct ForgeLiveVitalsSnapshot: Codable, Equatable {
    var heartRate: Int?
    var spO2: Int?
    var isWorkoutActive: Bool
    var workoutName: String
    var source: String
    var updatedAt: TimeInterval

    static let empty = ForgeLiveVitalsSnapshot(
        heartRate: nil,
        spO2: nil,
        isWorkoutActive: false,
        workoutName: "",
        source: "none",
        updatedAt: 0
    )

    var isFresh: Bool {
        guard updatedAt > 0 else { return false }
        return Date().timeIntervalSince1970 - updatedAt < 8
    }
}

enum ForgeWatchVitalsBridge {
    static let appGroupID = "group.com.forge.health"
    private static let vitalsKey = "forge.watch.liveVitals"
    private static let phoneWorkoutActiveKey = "forge.phone.workoutActive"
    private static let phoneWorkoutNameKey = "forge.phone.workoutName"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func publish(_ snapshot: ForgeLiveVitalsSnapshot) {
        guard let defaults,
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: vitalsKey)
        NotificationCenter.default.post(name: .forgeWatchVitalsUpdated, object: nil)
    }

    static func latest() -> ForgeLiveVitalsSnapshot? {
        guard let defaults,
              let data = defaults.data(forKey: vitalsKey),
              let snapshot = try? JSONDecoder().decode(ForgeLiveVitalsSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static func setPhoneWorkoutActive(_ active: Bool, workoutName: String = "") {
        guard let defaults else { return }
        defaults.set(active, forKey: phoneWorkoutActiveKey)
        defaults.set(workoutName, forKey: phoneWorkoutNameKey)
        NotificationCenter.default.post(name: .forgePhoneWorkoutStateChanged, object: nil)
    }

    static var isPhoneWorkoutActive: Bool {
        defaults?.bool(forKey: phoneWorkoutActiveKey) ?? false
    }

    static var phoneWorkoutName: String {
        defaults?.string(forKey: phoneWorkoutNameKey) ?? ""
    }
}

enum ForgeWatchDashboardReader {
    private static let readinessKey = "forge.readiness.overall"
    private static let workoutNameKey = "forge.workout.name"
    private static let hrvKey = "forge.metrics.hrv"
    private static let streakKey = "forge.streak"

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: ForgeWatchVitalsBridge.appGroupID)
    }

    static var readinessScore: Int {
        defaults?.integer(forKey: readinessKey) ?? 0
    }

    static var workoutName: String {
        let name = defaults?.string(forKey: workoutNameKey) ?? ""
        return name.isEmpty ? "Rest Day" : name
    }

    static var hrv: Int {
        defaults?.integer(forKey: hrvKey) ?? 0
    }

    static var streak: Int {
        defaults?.integer(forKey: streakKey) ?? 0
    }
}

extension Notification.Name {
    static let forgeWatchVitalsUpdated = Notification.Name("forge.watch.vitalsUpdated")
    static let forgePhoneWorkoutStateChanged = Notification.Name("forge.phone.workoutStateChanged")
}