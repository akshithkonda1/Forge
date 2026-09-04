import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif

// ============================================================
// MARK: - Home / Lock Screen widget snapshot
// ============================================================

/// One payload every iOS Home Screen and Lock Screen widget reads.
///
/// The app writes this into the shared App Group whenever readiness, sleep,
/// hydration or cycle changes. WidgetKit providers never query HealthKit —
/// they decode this struct. That is the same contract Watch complications
/// already use, and it is why a drink logged in Forge can appear on the
/// Home Screen without the widget doing any work.
public struct HomeWidgetSnapshot: Codable, Equatable, Sendable {
    public var readiness: Int
    public var readinessLabel: String
    public var sleepHours: Double
    public var sleepScore: Int?
    public var sleepWindowTitle: String?
    public var hydrationMl: Double
    public var hydrationTargetMl: Double
    public var cyclePhase: String?
    public var cycleDay: Int?
    public var qol: Int
    public var topRecommendation: String?
    public var workoutName: String?
    public var updatedAt: Date

    public init(
        readiness: Int = 0,
        readinessLabel: String = "—",
        sleepHours: Double = 0,
        sleepScore: Int? = nil,
        sleepWindowTitle: String? = nil,
        hydrationMl: Double = 0,
        hydrationTargetMl: Double = HydrationEngine.targetMilliliters(weightKilograms: nil),
        cyclePhase: String? = nil,
        cycleDay: Int? = nil,
        qol: Int = 0,
        topRecommendation: String? = nil,
        workoutName: String? = nil,
        updatedAt: Date = Date()
    ) {
        self.readiness = readiness
        self.readinessLabel = readinessLabel
        self.sleepHours = sleepHours
        self.sleepScore = sleepScore
        self.sleepWindowTitle = sleepWindowTitle
        self.hydrationMl = hydrationMl
        self.hydrationTargetMl = hydrationTargetMl
        self.cyclePhase = cyclePhase
        self.cycleDay = cycleDay
        self.qol = qol
        self.topRecommendation = topRecommendation
        self.workoutName = workoutName
        self.updatedAt = updatedAt
    }

    public var hydrationFraction: Double {
        guard hydrationTargetMl > 0 else { return 0 }
        return min(1, max(0, hydrationMl / hydrationTargetMl))
    }

    public var hydrationGlasses: Double {
        HydrationEngine.glasses(fromMilliliters: hydrationMl)
    }

    public static let preview = HomeWidgetSnapshot(
        readiness: 84,
        readinessLabel: "Ready",
        sleepHours: 7.4,
        sleepScore: 88,
        sleepWindowTitle: "Morning peak",
        hydrationMl: 1_420,
        hydrationTargetMl: 2_310,
        cyclePhase: "follicular",
        cycleDay: 8,
        qol: 81,
        topRecommendation: "Add 30g protein before dinner",
        workoutName: "Lower Body Strength"
    )
}

public enum HomeWidgetSnapshotStore {
    public static let appGroupID = WatchSnapshotStore.appGroupID
    public static let key = "forge.home.widget.snapshot.v1"

    public static func load() -> HomeWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(HomeWidgetSnapshot.self, from: data)
    }

    public static func save(_ snapshot: HomeWidgetSnapshot, reloadWidgets: Bool = true) {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        #if canImport(WidgetKit)
        if reloadWidgets {
            WidgetCenter.shared.reloadAllTimelines()
        }
        #endif
    }

    public static func update(reloadWidgets: Bool = true, _ mutate: (inout HomeWidgetSnapshot) -> Void) {
        var snapshot = load() ?? HomeWidgetSnapshot()
        mutate(&snapshot)
        snapshot.updatedAt = Date()
        save(snapshot, reloadWidgets: reloadWidgets)
    }
}

// ============================================================
// MARK: - Pending water (widget → app → HealthKit)
// ============================================================

/// Glasses logged from a widget cannot write HealthKit themselves. They
/// enqueue milliliters here; the app drains the queue on the next launch
/// or refresh and writes the sample for real.
public enum PendingWaterLog {
    public static let key = "forge.pending.water.ml"

    public static func enqueue(_ milliliters: Double) {
        guard milliliters > 0,
              let defaults = UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID) else { return }
        defaults.set(defaults.double(forKey: key) + milliliters, forKey: key)
    }

    @discardableResult
    public static func drain() -> Double {
        guard let defaults = UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID) else { return 0 }
        let value = defaults.double(forKey: key)
        defaults.set(0, forKey: key)
        return value
    }
}

// ============================================================
// MARK: - In-app Home widget board
// ============================================================

/// Widgets the user can pin on Forge Home. Readiness is the hero card
/// and is not in this list — pinning it twice would be a second ring
/// of the same number.
public enum HomePinnedWidgetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case hydration
    case sleep
    case cycle
    case workout
    case lifestyle

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .hydration: return "Hydration"
        case .sleep:     return "Sleep"
        case .cycle:     return "Cycle"
        case .workout:   return "Workout"
        case .lifestyle: return "Lifestyle"
        }
    }

    public var subtitle: String {
        switch self {
        case .hydration: return "Today's water against your need"
        case .sleep:     return "Last night and the window you are in"
        case .cycle:     return "Phase and day"
        case .workout:   return "Today's session"
        case .lifestyle: return "QOL and ARIA's top note"
        }
    }

    public var systemImage: String {
        switch self {
        case .hydration: return "drop.fill"
        case .sleep:     return "moon.stars.fill"
        case .cycle:     return "heart.circle.fill"
        case .workout:   return "dumbbell.fill"
        case .lifestyle: return "leaf.fill"
        }
    }

    public static let defaultPins: [HomePinnedWidgetKind] = [.hydration, .sleep, .workout]
}

public enum HomeWidgetBoardStore {
    public static let key = "forge.home.pinned.widgets.v1"

    public static func load() -> [HomePinnedWidgetKind] {
        guard let defaults = UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID),
              let data = defaults.data(forKey: key),
              let pins = try? JSONDecoder().decode([HomePinnedWidgetKind].self, from: data),
              !pins.isEmpty else {
            return HomePinnedWidgetKind.defaultPins
        }
        // Dedup while preserving order — a botched write should not
        // put two hydration cards on Home.
        var seen = Set<HomePinnedWidgetKind>()
        return pins.filter { seen.insert($0).inserted }
    }

    public static func save(_ pins: [HomePinnedWidgetKind]) {
        guard let defaults = UserDefaults(suiteName: HomeWidgetSnapshotStore.appGroupID),
              let data = try? JSONEncoder().encode(pins) else { return }
        defaults.set(data, forKey: key)
    }

    public static func add(_ kind: HomePinnedWidgetKind) {
        var pins = load()
        guard !pins.contains(kind) else { return }
        pins.append(kind)
        save(pins)
    }

    public static func remove(_ kind: HomePinnedWidgetKind) {
        save(load().filter { $0 != kind })
    }

    public static func availableToAdd(from pins: [HomePinnedWidgetKind] = load()) -> [HomePinnedWidgetKind] {
        HomePinnedWidgetKind.allCases.filter { !pins.contains($0) }
    }
}

// ============================================================
// MARK: - Deep links the widgets open
// ============================================================

public enum ForgeWidgetLink {
    public static let readiness = URL(string: "forge://home")!
    public static let hydration = URL(string: "forge://hydration")!
    public static let sleep     = URL(string: "forge://sleep")!
    public static let cycle     = URL(string: "forge://cycle")!
    public static let support   = URL(string: "forge://cycle/support")!
    public static let workout   = URL(string: "forge://workout")!
    public static let lifestyle = URL(string: "forge://lifestyle")!
    public static let today     = URL(string: "forge://home")!
}
