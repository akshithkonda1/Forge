import Foundation

// ============================================================
// MARK: - Apple Health–compatible device library
// ============================================================

/// A wearable or health tool Forge can treat as a source.
///
/// Connection here is not a proprietary vendor API. These devices already
/// speak iOS and (almost all of them) Apple Health. Forge reads what they
/// write to HealthKit. The catalog exists so Profile can show a real library
/// instead of a string list that always says "Connected".
public struct HealthDevice: Identifiable, Codable, Equatable, Sendable, Hashable {
    public let id: String
    public let name: String
    public let maker: String
    public let category: HealthDeviceCategory
    public let summary: String
    public let metrics: [String]
    public let writesToAppleHealth: Bool
    public let hasIOSApp: Bool
    public let worksWithAppleWatch: Bool
    public let appStoreURL: String?
    public let setupHint: String
    public let symbolName: String

    public init(
        id: String,
        name: String,
        maker: String,
        category: HealthDeviceCategory,
        summary: String,
        metrics: [String],
        writesToAppleHealth: Bool,
        hasIOSApp: Bool,
        worksWithAppleWatch: Bool,
        appStoreURL: String?,
        setupHint: String,
        symbolName: String
    ) {
        self.id = id
        self.name = name
        self.maker = maker
        self.category = category
        self.summary = summary
        self.metrics = metrics
        self.writesToAppleHealth = writesToAppleHealth
        self.hasIOSApp = hasIOSApp
        self.worksWithAppleWatch = worksWithAppleWatch
        self.appStoreURL = appStoreURL
        self.setupHint = setupHint
        self.symbolName = symbolName
    }

    public var appleHealthLabel: String {
        writesToAppleHealth ? "Writes to Apple Health" : "iOS app — enable Health sharing if offered"
    }
}

public enum HealthDeviceCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case apple
    case wearable
    case sleep
    case hydration
    case metabolic
    case training
    case body

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .apple:     return "Apple"
        case .wearable:  return "Wearables"
        case .sleep:     return "Sleep & recovery"
        case .hydration: return "Hydration"
        case .metabolic: return "Metabolic"
        case .training:  return "Training"
        case .body:      return "Body & scales"
        }
    }
}

public enum HealthDeviceCatalog {
    /// Resolve a stored id or a leftover display name from the old string list.
    public static func device(matching raw: String) -> HealthDevice? {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let exact = all.first(where: { $0.id == key || $0.name == key }) {
            return exact
        }
        let folded = key.lowercased()
        return all.first { device in
            folded.contains(device.name.lowercased()) ||
            device.name.lowercased().contains(folded) ||
            folded.contains(device.maker.lowercased())
        }
    }

    public static func devices(in category: HealthDeviceCategory) -> [HealthDevice] {
        all.filter { $0.category == category }
    }

    public static func search(_ query: String) -> [HealthDevice] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return all }
        return all.filter {
            $0.name.lowercased().contains(q) ||
            $0.maker.lowercased().contains(q) ||
            $0.metrics.contains { $0.lowercased().contains(q) } ||
            $0.summary.lowercased().contains(q)
        }
    }

    public static func migrateStoredIDs(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for raw in stored {
            let id = device(matching: raw)?.id ?? raw
            if seen.insert(id).inserted { out.append(id) }
        }
        return out
    }

    public static let all: [HealthDevice] = apple + wearables + sleep + hydration + metabolic + training + body

    private static let apple: [HealthDevice] = [
        HealthDevice(
            id: "apple-watch",
            name: "Apple Watch",
            maker: "Apple",
            category: .apple,
            summary: "The native wrist. Heart, workouts, sleep, mobility and cycle data land in Health automatically.",
            metrics: ["Heart rate", "HRV", "Workouts", "Sleep", "Activity rings", "Blood oxygen"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Wear the Watch and keep Health sharing on. Forge already reads what it writes.",
            symbolName: "applewatch"
        ),
        HealthDevice(
            id: "apple-health",
            name: "Apple Health",
            maker: "Apple",
            category: .apple,
            summary: "The ledger every other device on this list writes into. This is how Forge stays vendor-neutral.",
            metrics: ["All HealthKit types Forge is authorized for"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Tap Connect to re-request HealthKit. Nothing leaves the device except what you already allowed.",
            symbolName: "heart.text.square.fill"
        ),
        HealthDevice(
            id: "airpods-pro",
            name: "AirPods Pro",
            maker: "Apple",
            category: .apple,
            summary: "Hearing health and conversation boost live in Health. Not a trainer — still an Apple Health source.",
            metrics: ["Hearing level", "Headphone audio exposure"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Pair AirPods in Settings. Hearing Test and Headphone Notifications write to Health.",
            symbolName: "airpodspro"
        ),
    ]

    private static let wearables: [HealthDevice] = [
        device("oura-ring", "Oura Ring", "Oura", .wearable,
               "Sleep and recovery specialist. Stages, readiness, temperature and HRV sync to Health from the Oura iOS app.",
               ["Sleep stages", "Readiness", "HRV", "Resting HR", "Temperature", "Activity"],
               true, true, "https://apps.apple.com/app/oura/id1043837948",
               "In Oura → Settings → Data Sharing → Apple Health, turn on Sleep, Heart and Activity.",
               "circle.dashed.inset.filled"),
        device("whoop", "WHOOP", "WHOOP", .wearable,
               "24/7 strain and recovery band. The iOS app can share heart, sleep and workouts with Apple Health.",
               ["Strain", "Recovery", "Sleep", "HRV", "Resting HR"],
               true, true, "https://apps.apple.com/app/whoop/id937847611",
               "Open WHOOP → More → App Settings → Apple Health and enable the types you want Forge to see.",
               "waveform.path.ecg"),
        device("garmin", "Garmin", "Garmin", .wearable,
               "Watches and cycling computers. Garmin Connect writes workouts, heart, sleep and body composition to Health.",
               ["Workouts", "Heart rate", "Sleep", "Steps", "VO2 max", "Stress"],
               true, true, "https://apps.apple.com/app/garmin-connect/id583446403",
               "Garmin Connect → More → Settings → Health Stats → Apple Health. Enable write for the metrics you use.",
               "applewatch.side.right"),
        device("ultrahuman-ring", "Ultrahuman Ring AIR", "Ultrahuman", .wearable,
               "Light smart ring. The iOS app shares sleep, movement and recovery into Apple Health.",
               ["Sleep", "Movement", "Recovery", "HRV", "Temperature"],
               true, true, "https://apps.apple.com/app/ultrahuman/id1564655521",
               "In Ultrahuman → Profile → Integrations → Apple Health, enable Sleep and Heart.",
               "circle.fill"),
        device("polar", "Polar", "Polar", .wearable,
               "Sports watches and the H10 chest strap. Polar Flow writes workouts and nightly recharge to Health.",
               ["Workouts", "Heart rate", "HRV", "Sleep", "Nightly Recharge"],
               true, true, "https://apps.apple.com/app/polar-flow/id668016625",
               "Polar Flow → General Settings → Apple Health. Pair an H10 in the Polar Beat or Flow app.",
               "heart.fill"),
        device("fitbit", "Fitbit", "Google", .wearable,
               "Bands and Pixel Watch via the Fitbit iOS app. Activity, sleep and heart write to Health.",
               ["Steps", "Sleep", "Heart rate", "Workouts", "SpO2"],
               true, true, "https://apps.apple.com/app/fitbit-health-fitness/id462638897",
               "Fitbit app → Today tab → profile → Health & Fitness → Apple Health.",
               "applewatch.and.arrow.forward"),
        device("withings-scanwatch", "Withings ScanWatch", "Withings", .wearable,
               "Medical-grade hybrid watch. Health Mate writes ECG, SpO2, sleep and activity to Apple Health.",
               ["ECG", "SpO2", "Sleep", "Activity", "Heart rate"],
               true, true, "https://apps.apple.com/app/health-mate/id542701020",
               "Health Mate → Profile → Integrations → Apple Health. Approve each data type.",
               "watch.analog"),
        device("coros", "COROS", "COROS", .wearable,
               "Long-battery sports watches. The COROS app syncs training and heart data to Health.",
               ["Workouts", "Heart rate", "Training load"],
               true, true, "https://apps.apple.com/app/coros/id1280465736",
               "COROS app → Profile → Settings → Apple Health.",
               "applewatch"),
        device("amazfit", "Amazfit / Zepp", "Amazfit", .wearable,
               "Zepp OS watches and the Helio Ring. Zepp writes activity and sleep to Apple Health.",
               ["Activity", "Sleep", "Heart rate", "Workouts"],
               true, true, "https://apps.apple.com/app/zepp-formerly-amazfit/id1127269366",
               "Zepp → Profile → Add accounts → Apple Health.",
               "applewatch.radiowaves.left.and.right"),
    ]

    private static let sleep: [HealthDevice] = [
        device("eight-sleep", "Eight Sleep", "Eight Sleep", .sleep,
               "Pod cover that heats, cools and tracks sleep. The iOS app writes stages, HR and HRV to Health.",
               ["Sleep stages", "Heart rate", "HRV", "Respiratory rate"],
               true, true, "https://apps.apple.com/app/eight-sleep/id1052275603",
               "Eight Sleep app → Settings → Integrations → Apple Health.",
               "bed.double.fill"),
        device("withings-sleep", "Withings Sleep", "Withings", .sleep,
               "Under-mattress mat. Validated sleep tracking with nothing on your wrist. Writes to Health via Health Mate.",
               ["Sleep", "Heart rate", "Snoring", "Breathing"],
               true, true, "https://apps.apple.com/app/health-mate/id542701020",
               "Install Health Mate, add the Sleep mat, then enable Apple Health sharing.",
               "moon.zzz.fill"),
    ]

    private static let hydration: [HealthDevice] = [
        device("larq-bottle", "LARQ Bottle", "LARQ", .hydration,
               "Self-cleaning UV bottle with an iOS app. Log sips there; if Health sharing is on, Forge already counts dietary water.",
               ["Water intake", "Bottle cycles"],
               true, true, "https://apps.apple.com/app/larq/id1461752670",
               "Pair the bottle in the LARQ app. Settings → Apple Health → turn on Dietary Water so Forge can see it.",
               "drop.circle.fill"),
        device("hidratespark", "HidrateSpark", "Hidrate", .hydration,
               "Smart bottle that lights up when you fall behind. The iOS app is a first-class Apple Health water writer.",
               ["Water intake", "Hydration reminders"],
               true, true, "https://apps.apple.com/app/hidratespark/id961078587",
               "HidrateSpark app → Profile → Apple Health → Water. Forge's hydration card will pick it up live.",
               "drop.fill"),
    ]

    private static let metabolic: [HealthDevice] = [
        device("dexcom", "Dexcom G7 / Stelo", "Dexcom", .metabolic,
               "Continuous glucose. The Dexcom iOS apps can share glucose into Apple Health for Forge to read.",
               ["Blood glucose"],
               true, true, "https://apps.apple.com/app/dexcom-g7/id1600516211",
               "In the Dexcom app, enable Apple Health sharing for Blood Glucose.",
               "waveform.path.ecg.rectangle"),
        device("abbott-lingo", "Abbott Lingo / Libre", "Abbott", .metabolic,
               "Consumer and clinical CGMs. LibreLink / Lingo write glucose to Health when sharing is on.",
               ["Blood glucose"],
               true, true, "https://apps.apple.com/app/freestyle-librelink/id872652809",
               "LibreLink or Lingo → Account → Connected Apps → Apple Health.",
               "cross.vial.fill"),
    ]

    private static let training: [HealthDevice] = [
        device("peloton", "Peloton", "Peloton", .training,
               "Bike, tread and app classes. The Peloton iOS app writes workouts and heart rate to Health.",
               ["Workouts", "Heart rate", "Calories"],
               true, true, "https://apps.apple.com/app/peloton-fitness-workouts/id477996689",
               "Peloton → Profile → Health → connect Apple Health.",
               "bicycle"),
        device("strava", "Strava", "Strava", .training,
               "Social training log. Can both read and write workouts with Apple Health.",
               ["Workouts", "Routes", "Heart rate"],
               true, true, "https://apps.apple.com/app/strava-run-bike-hike/id426826309",
               "Strava → Settings → Applications, Devices and Integrations → Health.",
               "figure.run"),
        device("nike-run-club", "Nike Run Club", "Nike", .training,
               "Guided runs on iPhone and Watch. Writes running workouts to Health.",
               ["Runs", "Heart rate"],
               true, true, "https://apps.apple.com/app/nike-run-club/id387771637",
               "NRC → Profile → Settings → Apple Health.",
               "figure.run"),
    ]

    private static let body: [HealthDevice] = [
        device("withings-body", "Withings Body", "Withings", .body,
               "Wi-Fi scales. Weight, BMI, muscle and fat write to Health from Health Mate.",
               ["Weight", "BMI", "Body fat", "Muscle mass"],
               true, true, "https://apps.apple.com/app/health-mate/id542701020",
               "Health Mate → Integrations → Apple Health → Body Measurements.",
               "scalemass.fill"),
        device("garmin-index", "Garmin Index", "Garmin", .body,
               "Garmin's scale. Composition syncs through Garmin Connect into Health.",
               ["Weight", "Body fat", "BMI"],
               true, true, "https://apps.apple.com/app/garmin-connect/id583446403",
               "Garmin Connect → Settings → Health Stats → Apple Health → Body.",
               "scalemass"),
    ]

    private static func device(
        _ id: String,
        _ name: String,
        _ maker: String,
        _ category: HealthDeviceCategory,
        _ summary: String,
        _ metrics: [String],
        _ health: Bool,
        _ watch: Bool,
        _ url: String?,
        _ hint: String,
        _ symbol: String
    ) -> HealthDevice {
        HealthDevice(
            id: id,
            name: name,
            maker: maker,
            category: category,
            summary: summary,
            metrics: metrics,
            writesToAppleHealth: health,
            hasIOSApp: true,
            worksWithAppleWatch: watch,
            appStoreURL: url,
            setupHint: hint,
            symbolName: symbol
        )
    }
}
