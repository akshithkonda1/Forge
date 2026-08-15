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
    /// Product family. Series 11 and Series 7 share `apple-watch-series`.
    public let line: String
    /// Cycle number inside that family. The catalog keeps the newest five.
    public let generation: Int
    public let releasedYear: Int
    /// False once Apple Health / the vendor app no longer support this SKU.
    public let stillCompatible: Bool
    /// Official product photo on the live catalog. Bundled SKUs use `photoAssetName`.
    public let photoURL: String?

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
        symbolName: String,
        line: String,
        generation: Int,
        releasedYear: Int,
        stillCompatible: Bool = true,
        photoURL: String? = nil
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
        self.line = line
        self.generation = generation
        self.releasedYear = releasedYear
        self.stillCompatible = stillCompatible
        self.photoURL = photoURL
    }

    public var appleHealthLabel: String {
        writesToAppleHealth ? "Writes to Apple Health" : "iOS app — enable Health sharing if offered"
    }

    /// Asset catalog name for the official product photo (`DevicePhoto-<id>`).
    public var photoAssetName: String { "DevicePhoto-\(id)" }

    /// Shape used only if the official photo is missing.
    public var artwork: HealthDeviceArtwork {
        let key = (id + " " + name).lowercased()
        if key.contains("pitcher") { return .pitcher }
        if key.contains("larq") || key.contains("hidrate") || key.contains("bottle") { return .bottle }
        if key.contains("ring") { return .ring }
        if key.contains("airpod") || key.contains("earbud") { return .earbuds }
        if key.contains("dexcom") || key.contains("stelo") || key.contains("libre") || key.contains("lingo") || key.contains("glucose") {
            return .sensor
        }
        if key.contains("eight") || (key.contains("sleep") && !key.contains("watch")) { return .bed }
        if key.contains("body") || key.contains("index") || key.contains("bpm") || key.contains("scale") { return .scale }
        if key.contains("whoop") || key.contains("fitbit") { return .band }
        if key.contains("bike") || key.contains("tread") || key.contains("edge") || key.contains("strava") || key.contains("nike") || key.contains("peloton") {
            return .bike
        }
        return .watch
    }
}

public enum HealthDeviceArtwork: String, Codable, CaseIterable, Sendable {
    case watch, ring, bottle, pitcher, band, scale, sensor, earbuds, bed, bike

    public var symbolName: String {
        switch self {
        case .watch:    return "applewatch"
        case .ring:     return "circle.dashed.inset.filled"
        case .bottle:   return "drop.circle.fill"
        case .pitcher:  return "cup.and.saucer.fill"
        case .band:     return "waveform.path.ecg"
        case .scale:    return "scalemass.fill"
        case .sensor:   return "waveform.path.ecg.rectangle"
        case .earbuds:  return "airpodspro"
        case .bed:      return "bed.double.fill"
        case .bike:     return "bicycle"
        }
    }
}

public struct HealthDeviceBrand: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let symbolName: String
    public let productCount: Int
    public let writesToAppleHealth: Bool
    public let primaryCategory: HealthDeviceCategory
    public let previewArtwork: [HealthDeviceArtwork]
    public let previewPhotoAssets: [String]
    public let newestYear: Int
    public let previewDevices: [HealthDevice]
}

/// Live shelf payload. The app merges this on top of the bundled list so a
/// new SKU can appear without waiting for an App Store release.
public struct HealthDeviceCatalogPayload: Codable, Equatable, Sendable {
    public var version: Int
    public var updatedAt: String?
    public var devices: [HealthDevice]
    public var retire: [String]?

    public init(
        version: Int = 1,
        updatedAt: String? = nil,
        devices: [HealthDevice] = [],
        retire: [String]? = nil
    ) {
        self.version = version
        self.updatedAt = updatedAt
        self.devices = devices
        self.retire = retire
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
    /// How many generations of a line stay on the shelf. Add Series 12 and
    /// Series 7 falls off by itself if it is no longer Health-compatible.
    public static let retainedProductCycles = 5

    /// Shipped with the app. Live remote rows and HealthKit discoveries layer on top.
    public static var bundled: [HealthDevice] {
        apple + wearables + sleep + hydration + metabolic + training + body
    }

    /// Browse list — newest five cycles per line. The archive (`all`) still
    /// resolves a watch someone already connected.
    public static var listing: [HealthDevice] {
        listed(from: all, keepCycles: retainedProductCycles)
    }

    public static func listed(
        from devices: [HealthDevice],
        keepCycles: Int = retainedProductCycles
    ) -> [HealthDevice] {
        let headByLine = Dictionary(grouping: devices, by: \.line).mapValues { family in
            family.map(\.generation).max() ?? 0
        }
        return devices.filter { device in
            let head = headByLine[device.line] ?? device.generation
            let age = head - device.generation
            if age < keepCycles { return true }
            // Past five cycles: drop anything that no longer talks to Health / iOS.
            return device.stillCompatible && device.writesToAppleHealth && device.hasIOSApp
        }
        .sorted {
            if $0.line != $1.line { return $0.line < $1.line }
            return $0.generation > $1.generation
        }
    }

    public static func isListed(_ device: HealthDevice, in devices: [HealthDevice] = all) -> Bool {
        listed(from: devices).contains { $0.id == device.id }
    }

    public static func devices(in category: HealthDeviceCategory) -> [HealthDevice] {
        listing.filter { $0.category == category }
    }

    public static func search(_ query: String) -> [HealthDevice] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let pool = listing
        guard !q.isEmpty else { return pool }
        return pool.filter {
            $0.name.lowercased().contains(q) ||
            $0.maker.lowercased().contains(q) ||
            $0.metrics.contains { $0.lowercased().contains(q) } ||
            $0.summary.lowercased().contains(q)
        }
    }

    public static func devices(fromMaker maker: String, listedOnly: Bool = true) -> [HealthDevice] {
        let pool = listedOnly ? listing : all
        return pool
            .filter { $0.maker.caseInsensitiveCompare(maker) == .orderedSame }
            .sorted { $0.generation > $1.generation }
    }

    /// Companies first. Products live under a maker so Profile is a store, not a dump.
    public static var brands: [HealthDeviceBrand] {
        brands(from: listing)
    }

    public static func brands(from devices: [HealthDevice]) -> [HealthDeviceBrand] {
        var order: [String] = []
        var seen = Set<String>()
        for device in devices {
            let key = device.maker
            if seen.insert(key.lowercased()).inserted {
                order.append(key)
            }
        }
        return order.map { maker in
            let products = devices
                .filter { $0.maker.caseInsensitiveCompare(maker) == .orderedSame }
                .sorted { $0.generation > $1.generation }
            let symbol = products.first?.symbolName ?? "sensor.tag.radiowaves.forward"
            let counts = Dictionary(grouping: products, by: \.category).mapValues(\.count)
            let primary = counts.max(by: { $0.value < $1.value })?.key ?? products.first?.category ?? .wearable
            var art: [HealthDeviceArtwork] = []
            for device in products where !art.contains(device.artwork) {
                art.append(device.artwork)
            }
            let preview = Array(products.prefix(3))
            return HealthDeviceBrand(
                id: maker.lowercased(),
                name: maker,
                symbolName: symbol,
                productCount: products.count,
                writesToAppleHealth: products.contains(where: \.writesToAppleHealth),
                primaryCategory: primary,
                previewArtwork: Array(art.prefix(3)),
                previewPhotoAssets: preview.map(\.photoAssetName),
                newestYear: products.map(\.releasedYear).max() ?? 0,
                previewDevices: preview
            )
        }
    }

    public static func searchBrands(_ query: String, category: HealthDeviceCategory? = nil) -> [HealthDeviceBrand] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return brands.filter { brand in
            if let category {
                let hasType = devices(fromMaker: brand.name).contains { $0.category == category }
                if !hasType { return false }
            }
            if q.isEmpty { return true }
            return brand.name.lowercased().contains(q) ||
                devices(fromMaker: brand.name).contains { device in
                    device.name.lowercased().contains(q) ||
                    device.metrics.contains { $0.lowercased().contains(q) }
                }
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

    /// Bundled + live remote + Health sources seen on this iPhone.
    public static var all: [HealthDevice] {
        overlays.lock.lock()
        defer { overlays.lock.unlock() }
        return merge(
            bundled: bundled,
            remote: overlays.remote,
            discovered: overlays.discovered,
            retire: overlays.retire
        )
    }

    public static func decodePayload(_ data: Data) throws -> HealthDeviceCatalogPayload {
        try JSONDecoder().decode(HealthDeviceCatalogPayload.self, from: data)
    }

    public static func encodePayload(_ payload: HealthDeviceCatalogPayload) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(payload)
    }

    public static func applyRemote(_ payload: HealthDeviceCatalogPayload) {
        overlays.lock.lock()
        overlays.remote = payload.devices
        overlays.retire = payload.retire ?? []
        overlays.lock.unlock()
    }

    public static func applyDiscovered(_ devices: [HealthDevice]) {
        overlays.lock.lock()
        overlays.discovered = devices
        overlays.lock.unlock()
    }

    public static func resetOverlays() {
        overlays.lock.lock()
        overlays.remote = []
        overlays.retire = []
        overlays.discovered = []
        overlays.lock.unlock()
    }

    /// Remote rows win on the same id. HealthKit discoveries fill gaps only.
    public static func merge(
        bundled: [HealthDevice],
        remote: [HealthDevice],
        discovered: [HealthDevice] = [],
        retire: [String] = []
    ) -> [HealthDevice] {
        var byID: [String: HealthDevice] = [:]
        for device in bundled { byID[device.id] = device }
        for device in remote { byID[device.id] = device }
        for id in Set(retire) { byID.removeValue(forKey: id) }

        var merged = Array(byID.values)
        for device in discovered where !isDuplicate(device, of: merged) {
            merged.append(device)
        }
        return merged.sorted { $0.id < $1.id }
    }

    /// Turn HealthKit source names into catalog rows when we don't already know them.
    public static func inferredDevices(
        fromHealthSources sources: [String],
        known: [HealthDevice]? = nil,
        year: Int = 0
    ) -> [HealthDevice] {
        let overlay = overlays.snapshot()
        let pool = known ?? merge(
            bundled: bundled,
            remote: overlay.remote,
            retire: overlay.retire
        )
        let released = year > 0 ? year : Calendar(identifier: .gregorian).component(.year, from: Date())
        var out: [HealthDevice] = []
        var seen = Set<String>()
        for raw in sources {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.count >= 2 else { continue }
            if shouldIgnoreHealthSource(name) { continue }
            if device(matching: name, in: pool + out) != nil { continue }
            guard let inferred = inferredDevice(fromSource: name, year: released) else { continue }
            if seen.contains(inferred.id) || isDuplicate(inferred, of: pool + out) { continue }
            seen.insert(inferred.id)
            out.append(inferred)
        }
        return out
    }

    public static func inferredDevice(fromSource source: String, year: Int) -> HealthDevice? {
        let name = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 2, !shouldIgnoreHealthSource(name) else { return nil }
        let slug = slugify(name)
        guard !slug.isEmpty else { return nil }
        let maker = inferredMaker(from: name)
        let category = inferredCategory(from: name, maker: maker)
        return HealthDevice(
            id: "discovered-\(slug)",
            name: name,
            maker: maker,
            category: category,
            summary: "Seen writing to Apple Health on this iPhone.",
            metrics: ["Apple Health"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: false,
            appStoreURL: nil,
            setupHint: "This source is already writing to Health. Add it so Forge treats it as yours.",
            symbolName: category == .hydration ? "drop.fill" : "sensor.tag.radiowaves.forward",
            line: "discovered-\(slug)",
            generation: 1,
            releasedYear: year,
            stillCompatible: true
        )
    }

    /// Resolve a stored id or a leftover display name from the old string list.
    public static func device(matching raw: String, in devices: [HealthDevice]? = nil) -> HealthDevice? {
        let pool = devices ?? all
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if key.isEmpty { return nil }
        if let exact = pool.first(where: { $0.id == key || $0.name == key }) {
            return exact
        }
        let slug = slugify(key)
        if !slug.isEmpty, let bySlug = pool.first(where: { $0.id == slug }) {
            return bySlug
        }
        let folded = key.lowercased()
        // Name only — never maker. "Apple Watch" contains "Apple", which would
        // otherwise resolve to the first Apple SKU (AirPods Pro).
        let nameHits = pool.filter { device in
            let name = device.name.lowercased()
            return name.contains(folded) || folded.contains(name)
        }
        if nameHits.isEmpty { return nil }
        let listedIDs = Set(listed(from: pool).map(\.id))
        return nameHits.max { a, b in
            let aListed = listedIDs.contains(a.id)
            let bListed = listedIDs.contains(b.id)
            if aListed != bListed { return !aListed && bListed }
            if a.generation != b.generation { return a.generation < b.generation }
            return a.id > b.id
        }
    }

    private static func isDuplicate(_ device: HealthDevice, of pool: [HealthDevice]) -> Bool {
        let name = device.name.lowercased()
        return pool.contains { existing in
            existing.id == device.id ||
            existing.name.lowercased() == name ||
            (existing.maker.caseInsensitiveCompare(device.maker) == .orderedSame &&
             (existing.name.lowercased().contains(name) || name.contains(existing.name.lowercased())))
        }
    }

    private static func shouldIgnoreHealthSource(_ name: String) -> Bool {
        let folded = name.lowercased()
        let skip = [
            "health", "health app", "forge", "iphone", "ipad", "ipod",
            "clock", "sleep", "shortcuts", "siri",
        ]
        if skip.contains(folded) { return true }
        if folded.hasPrefix("iphone") || folded.hasPrefix("ipad") { return true }
        if folded.contains("forge") { return true }
        return false
    }

    private static func inferredMaker(from name: String) -> String {
        let folded = name.lowercased()
        let known: [(String, String)] = [
            ("oura", "Oura"), ("garmin", "Garmin"), ("whoop", "WHOOP"),
            ("larq", "LARQ"), ("hidrate", "HidrateSpark"), ("withings", "Withings"),
            ("dexcom", "Dexcom"), ("polar", "Polar"), ("fitbit", "Fitbit"),
            ("eight", "Eight Sleep"), ("peloton", "Peloton"), ("strava", "Strava"),
            ("ultrahuman", "Ultrahuman"), ("amazfit", "Amazfit"), ("zepp", "Amazfit"),
            ("coros", "COROS"), ("abbott", "Abbott"), ("libre", "Abbott"),
            ("lingo", "Abbott"), ("pixel", "Google"), ("nike", "Nike"),
            ("apple", "Apple"), ("suunto", "Suunto"), ("ringconn", "RingConn"),
        ]
        for (needle, maker) in known where folded.contains(needle) {
            return maker
        }
        return name.split(separator: " ").first.map(String.init) ?? name
    }

    private static func inferredCategory(from name: String, maker: String) -> HealthDeviceCategory {
        let folded = (name + " " + maker).lowercased()
        if folded.contains("larq") || folded.contains("hidrate") || folded.contains("bottle") {
            return .hydration
        }
        if folded.contains("sleep") || folded.contains("eight") { return .sleep }
        if folded.contains("dexcom") || folded.contains("libre") || folded.contains("lingo") || folded.contains("glucose") {
            return .metabolic
        }
        if folded.contains("peloton") || folded.contains("strava") || folded.contains("nike") { return .training }
        if folded.contains("scale") || folded.contains("body") || folded.contains("bpm") { return .body }
        if folded.contains("apple") { return .apple }
        return .wearable
    }

    private static func slugify(_ raw: String) -> String {
        let allowed = raw.lowercased().map { ch -> Character in
            if ch.isLetter || ch.isNumber { return ch }
            return "-"
        }
        let collapsed = String(allowed)
            .split(separator: "-", omittingEmptySubsequences: true)
            .joined(separator: "-")
        return String(collapsed.prefix(40))
    }

    private final class OverlayBox: @unchecked Sendable {
        let lock = NSLock()
        var remote: [HealthDevice] = []
        var retire: [String] = []
        var discovered: [HealthDevice] = []

        func snapshot() -> (remote: [HealthDevice], retire: [String], discovered: [HealthDevice]) {
            lock.lock()
            defer { lock.unlock() }
            return (remote, retire, discovered)
        }
    }

    private static let overlays = OverlayBox()

    private static let apple: [HealthDevice] = [
        HealthDevice(
            id: "apple-watch",
            name: "Apple Watch Series 11",
            maker: "Apple",
            category: .apple,
            summary: "The native wrist. Heart, workouts, sleep, mobility and cycle data land in Health automatically.",
            metrics: ["Heart rate", "HRV", "Workouts", "Sleep", "Activity rings", "Blood oxygen"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Wear the Watch and keep Health sharing on. Forge already reads what it writes.",
            symbolName: "applewatch",
            line: "apple-watch-series",
            generation: 11,
            releasedYear: 2025
        ),
        HealthDevice(
            id: "apple-health",
            name: "Health",
            maker: "Apple",
            category: .apple,
            summary: "The ledger every other device on this list writes into. This is how Forge stays vendor-neutral.",
            metrics: ["All HealthKit types Forge is authorized for"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Tap Connect to re-request HealthKit. Nothing leaves the device except what you already allowed.",
            symbolName: "heart.text.square.fill",
            line: "apple-health",
            generation: 1,
            releasedYear: 2014
        ),
        HealthDevice(
            id: "airpods-pro",
            name: "AirPods Pro 3",
            maker: "Apple",
            category: .apple,
            summary: "Hearing health and conversation boost live in Health. Not a trainer — still an Apple Health source.",
            metrics: ["Hearing level", "Headphone audio exposure"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Pair AirPods in Settings. Hearing Test and Headphone Notifications write to Health.",
            symbolName: "airpodspro",
            line: "airpods-pro",
            generation: 3,
            releasedYear: 2025
        ),
        HealthDevice(
            id: "apple-watch-ultra",
            name: "Apple Watch Ultra 3",
            maker: "Apple",
            category: .apple,
            summary: "The expedition Watch. Same Health ledger as Series — GPS, diving, trail workouts and dual-frequency location.",
            metrics: ["Heart rate", "Workouts", "GPS", "Depth", "Sleep", "Activity rings"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Pair in the Watch app. Health sharing is on by default.",
            symbolName: "applewatch.side.right",
            line: "apple-watch-ultra",
            generation: 3,
            releasedYear: 2025
        ),
        HealthDevice(
            id: "apple-watch-se",
            name: "Apple Watch SE 3",
            maker: "Apple",
            category: .apple,
            summary: "The lighter Watch. Activity, heart and sleep still land in Health for Forge to read.",
            metrics: ["Heart rate", "Workouts", "Sleep", "Activity rings"],
            writesToAppleHealth: true,
            hasIOSApp: true,
            worksWithAppleWatch: true,
            appStoreURL: nil,
            setupHint: "Pair in the Watch app. Keep Health sharing on.",
            symbolName: "applewatch",
            line: "apple-watch-se",
            generation: 3,
            releasedYear: 2025
        ),
        // Past five Series cycles and no longer a Health writer we support.
        device("apple-watch-s6", "Apple Watch Series 6", "Apple", .apple,
               "Retired. Five Series cycles have shipped since this box. Forge no longer lists it.",
               ["Heart rate", "Workouts"],
               false, false, nil,
               "This model is past five product cycles and is no longer offered as a Health source.",
               "applewatch",
               line: "apple-watch-series", generation: 6, year: 2020, compatible: false),
    ]

    private static let wearables: [HealthDevice] = [
        device("oura-ring", "Oura Ring Gen3", "Oura", .wearable,
               "Sleep and recovery specialist. Stages, readiness, temperature and HRV sync to Health from the Oura iOS app.",
               ["Sleep stages", "Readiness", "HRV", "Resting HR", "Temperature", "Activity"],
               true, true, "https://apps.apple.com/app/oura/id1043837948",
               "In Oura → Settings → Data Sharing → Apple Health, turn on Sleep, Heart and Activity.",
               "circle.dashed.inset.filled",
               line: "oura-ring", generation: 3, year: 2021),
        device("oura-ring-4", "Oura Ring 4", "Oura", .wearable,
               "Titanium Oura Ring 4. Same Health path as Gen3 — sleep, readiness and temperature.",
               ["Sleep stages", "Readiness", "HRV", "Temperature", "Activity"],
               true, true, "https://apps.apple.com/app/oura/id1043837948",
               "Oura → Settings → Data Sharing → Apple Health.",
               "circle.dashed.inset.filled",
               line: "oura-ring", generation: 4, year: 2024),
        device("oura-ring-5", "Oura Ring 5", "Oura", .wearable,
               "The current Oura on the store. Sleep, activity and recovery write through the Oura iOS app.",
               ["Sleep stages", "Readiness", "HRV", "Temperature", "Activity"],
               true, true, "https://apps.apple.com/app/oura/id1043837948",
               "Oura → Settings → Data Sharing → Apple Health.",
               "circle.dashed.inset.filled",
               line: "oura-ring", generation: 5, year: 2026),
        device("oura-ring-heritage", "Oura Ring Heritage", "Oura", .wearable,
               "Retired. Five Oura cycles have shipped since this ring. Not listed.",
               ["Sleep"],
               false, false, nil,
               "Past five product cycles and no longer a Health source Forge offers.",
               "circle.dashed.inset.filled",
               line: "oura-ring", generation: 0, year: 2018, compatible: false),
        device("whoop", "WHOOP 4.0", "WHOOP", .wearable,
               "24/7 strain and recovery band. The iOS app can share heart, sleep and workouts with Apple Health.",
               ["Strain", "Recovery", "Sleep", "HRV", "Resting HR"],
               true, true, "https://apps.apple.com/app/whoop/id937847611",
               "Open WHOOP → More → App Settings → Apple Health and enable the types you want Forge to see.",
               "waveform.path.ecg",
               line: "whoop-band", generation: 4, year: 2021),
        device("whoop-5", "WHOOP 5.0", "WHOOP", .wearable,
               "The current WHOOP membership band. Strain, recovery and sleep share through the WHOOP iOS app.",
               ["Strain", "Recovery", "Sleep", "HRV", "Resting HR"],
               true, true, "https://apps.apple.com/app/whoop/id937847611",
               "WHOOP → More → App Settings → Apple Health.",
               "waveform.path.ecg",
               line: "whoop-band", generation: 5, year: 2025),
        device("whoop-mg", "WHOOP MG", "WHOOP", .wearable,
               "WHOOP Medical Grade. Same Health sharing path as 5.0.",
               ["Strain", "Recovery", "Sleep", "HRV", "Resting HR"],
               true, true, "https://apps.apple.com/app/whoop/id937847611",
               "WHOOP → More → App Settings → Apple Health.",
               "waveform.path.ecg",
               line: "whoop-band", generation: 5, year: 2025),
        device("garmin-forerunner", "Garmin Forerunner 970", "Garmin", .wearable,
               "Running and triathlon watch. Training status and daily suggested workouts live in Connect — Health gets the ledger.",
               ["Runs", "Heart rate", "Training load", "Sleep", "VO2 max"],
               true, true, "https://apps.apple.com/app/garmin-connect/id583446403",
               "Garmin Connect → Settings → Health Stats → Apple Health.",
               "figure.run",
               line: "garmin-forerunner", generation: 7, year: 2025),
        device("garmin-fenix", "Garmin fēnix 8", "Garmin", .wearable,
               "Multisport GPS smartwatch. Climb, ski, swim and trail sessions sync through Connect.",
               ["Workouts", "Heart rate", "GPS", "Sleep", "Pulse Ox"],
               true, true, "https://apps.apple.com/app/garmin-connect/id583446403",
               "Garmin Connect → Settings → Health Stats → Apple Health.",
               "applewatch.side.right",
               line: "garmin-fenix", generation: 8, year: 2024),
        device("garmin-venu", "Garmin Venu 4", "Garmin", .wearable,
               "AMOLED health and fitness GPS watch. Body Battery, naps and workouts write to Health via Connect.",
               ["Activity", "Sleep", "Heart rate", "Body Battery", "Workouts"],
               true, true, "https://apps.apple.com/app/garmin-connect/id583446403",
               "Garmin Connect → Settings → Health Stats → Apple Health.",
               "applewatch",
               line: "garmin-venu", generation: 4, year: 2025),
        device("garmin-edge", "Garmin Edge 1050", "Garmin", .wearable,
               "Cycling computer. Rides, power and heart rate land in Connect, then Health.",
               ["Rides", "Heart rate", "Power", "Cadence"],
               true, true, "https://apps.apple.com/app/garmin-connect/id583446403",
               "Garmin Connect → Settings → Health Stats → Apple Health → Activity.",
               "bicycle",
               line: "garmin-edge", generation: 10, year: 2024),
        device("ultrahuman-ring", "Ultrahuman Ring AIR", "Ultrahuman", .wearable,
               "Light smart ring. The iOS app shares sleep, movement and recovery into Apple Health.",
               ["Sleep", "Movement", "Recovery", "HRV", "Temperature"],
               true, true, "https://apps.apple.com/app/ultrahuman/id1564655521",
               "In Ultrahuman → Profile → Integrations → Apple Health, enable Sleep and Heart.",
               "circle.fill",
               line: "ultrahuman-ring", generation: 1, year: 2023),
        device("polar-h10", "Polar H10", "Polar", .wearable,
               "Chest strap. Flow or Beat writes heart rate to Health.",
               ["Heart rate", "HRV", "Workouts"],
               true, true, "https://apps.apple.com/app/polar-flow/id668016625",
               "Pair the H10 in Polar Beat or Flow, then enable Apple Health.",
               "heart.fill",
               line: "polar-h10", generation: 1, year: 2017),
        device("polar-vantage", "Polar Vantage V3", "Polar", .wearable,
               "Multisport watch with FuelWise and nightly recharge. Polar Flow writes to Health.",
               ["Workouts", "Heart rate", "Sleep", "Training load"],
               true, true, "https://apps.apple.com/app/polar-flow/id668016625",
               "Polar Flow → General Settings → Apple Health.",
               "applewatch",
               line: "polar-vantage", generation: 3, year: 2023),
        device("fitbit", "Fitbit Charge 6", "Fitbit", .wearable,
               "Fitness band. Activity, sleep and heart write to Health from the Fitbit iOS app.",
               ["Steps", "Sleep", "Heart rate", "Workouts", "SpO2"],
               true, true, "https://apps.apple.com/app/fitbit-health-fitness/id462638897",
               "Fitbit app → Today tab → profile → Health & Fitness → Apple Health.",
               "applewatch.and.arrow.forward",
               line: "fitbit-charge", generation: 6, year: 2023),
        device("pixel-watch", "Google Pixel Watch 5", "Google", .wearable,
               "Wear OS watch. Fitbit on the watch writes activity, sleep and heart to Health.",
               ["Steps", "Sleep", "Heart rate", "Workouts"],
               true, true, "https://apps.apple.com/app/fitbit-health-fitness/id462638897",
               "Fitbit app → Today tab → profile → Health & Fitness → Apple Health.",
               "applewatch",
               line: "pixel-watch", generation: 5, year: 2026),
        device("withings-scanwatch", "Withings ScanWatch 2", "Withings", .wearable,
               "Hybrid smartwatch. Health Mate writes ECG, SpO2, sleep and activity to Apple Health.",
               ["ECG", "SpO2", "Sleep", "Activity", "Heart rate"],
               true, true, "https://apps.apple.com/app/health-mate/id542701020",
               "Health Mate → Profile → Integrations → Apple Health. Approve each data type.",
               "watch.analog",
               line: "withings-scanwatch", generation: 2, year: 2023),
        device("coros", "COROS PACE 3", "COROS", .wearable,
               "GPS sport watch. The COROS app syncs training and heart data to Health.",
               ["Workouts", "Heart rate", "Training load"],
               true, true, "https://apps.apple.com/app/coros/id1280465736",
               "COROS app → Profile → Settings → Apple Health.",
               "applewatch",
               line: "coros-pace", generation: 3, year: 2023),
        device("amazfit", "Amazfit Balance", "Amazfit", .wearable,
               "Zepp OS watch. Zepp writes activity and sleep to Apple Health.",
               ["Activity", "Sleep", "Heart rate", "Workouts"],
               true, true, "https://apps.apple.com/app/zepp-formerly-amazfit/id1127269366",
               "Zepp → Profile → Add accounts → Apple Health.",
               "applewatch.radiowaves.left.and.right",
               line: "amazfit-watch", generation: 1, year: 2023),
        device("amazfit-helio", "Amazfit Helio Ring", "Amazfit", .wearable,
               "Zepp smart ring. Sleep and recovery share through the Zepp iOS app.",
               ["Sleep", "Recovery", "Heart rate", "Activity"],
               true, true, "https://apps.apple.com/app/zepp-formerly-amazfit/id1127269366",
               "Zepp → Profile → Add accounts → Apple Health.",
               "circle.dashed.inset.filled",
               line: "amazfit-ring", generation: 1, year: 2024),
    ]

    private static let sleep: [HealthDevice] = [
        device("eight-sleep", "Eight Sleep Pod 4", "Eight Sleep", .sleep,
               "Pod cover that heats, cools and tracks sleep. The iOS app writes stages, HR and HRV to Health.",
               ["Sleep stages", "Heart rate", "HRV", "Respiratory rate"],
               true, true, "https://apps.apple.com/app/eight-sleep/id1052275603",
               "Eight Sleep app → Settings → Integrations → Apple Health.",
               "bed.double.fill",
               line: "eight-sleep-pod", generation: 4, year: 2023),
        device("eight-sleep-pod5", "Eight Sleep Pod 5", "Eight Sleep", .sleep,
               "The current Pod on eightsleep.com. Same Health sleep write as Pod 4.",
               ["Sleep stages", "Heart rate", "HRV", "Temperature"],
               true, true, "https://apps.apple.com/app/eight-sleep/id1052275603",
               "Eight Sleep app → Settings → Integrations → Apple Health.",
               "bed.double.fill",
               line: "eight-sleep-pod", generation: 5, year: 2025),
        device("withings-sleep", "Withings Sleep Analyzer", "Withings", .sleep,
               "Under-mattress mat. Validated sleep tracking with nothing on your wrist. Writes to Health via Health Mate.",
               ["Sleep", "Heart rate", "Snoring", "Breathing"],
               true, true, "https://apps.apple.com/app/health-mate/id542701020",
               "Install Health Mate, add Sleep Analyzer, then enable Apple Health sharing.",
               "moon.zzz.fill",
               line: "withings-sleep", generation: 1, year: 2018),
    ]

    private static let hydration: [HealthDevice] = [
        device("larq-bottle", "LARQ Bottle PureVis 2", "LARQ", .hydration,
               "Self-cleaning UV bottle with an iOS app. Log sips there; if Health sharing is on, Forge already counts dietary water.",
               ["Water intake", "Bottle cycles"],
               true, true, "https://apps.apple.com/app/larq/id1461752670",
               "Pair the bottle in the LARQ app. Settings → Apple Health → turn on Dietary Water so Forge can see it.",
               "drop.circle.fill",
               line: "larq-bottle", generation: 2, year: 2023),
        device("larq-pitcher", "LARQ Pitcher PureVis", "LARQ", .hydration,
               "Countertop pitcher with PureVis UV-C. The iOS app can still log volume into Health.",
               ["Water intake"],
               true, true, "https://apps.apple.com/app/larq/id1461752670",
               "Add the pitcher in the LARQ app, then enable Apple Health water.",
               "cup.and.saucer.fill",
               line: "larq-pitcher", generation: 1, year: 2022),
        device("hidratespark", "HidrateSpark STEEL", "HidrateSpark", .hydration,
               "Smart bottle that lights up when you fall behind. The iOS app is a first-class Apple Health water writer.",
               ["Water intake", "Hydration reminders"],
               true, true, "https://apps.apple.com/app/hidratespark/id961078587",
               "HidrateSpark app → Profile → Apple Health → Water. Forge's hydration card will pick it up live.",
               "drop.fill",
               line: "hidratespark-steel", generation: 1, year: 2021),
        device("hidratespark-pro", "HidrateSpark PRO 2", "HidrateSpark", .hydration,
               "The current HidrateSpark bottle on Apple.com. Same Health water write as STEEL.",
               ["Water intake", "Hydration reminders"],
               true, true, "https://apps.apple.com/app/hidratespark/id961078587",
               "HidrateSpark app → Profile → Apple Health → Water.",
               "drop.fill",
               line: "hidratespark-pro", generation: 2, year: 2023),
    ]

    private static let metabolic: [HealthDevice] = [
        device("dexcom", "Dexcom G7", "Dexcom", .metabolic,
               "Continuous glucose. The Dexcom iOS app can share glucose into Apple Health for Forge to read.",
               ["Blood glucose"],
               true, true, "https://apps.apple.com/app/dexcom-g7/id1600516211",
               "In the Dexcom app, enable Apple Health sharing for Blood Glucose.",
               "waveform.path.ecg.rectangle",
               line: "dexcom-g", generation: 7, year: 2022),
        device("dexcom-stelo", "Dexcom Stelo", "Dexcom", .metabolic,
               "Over-the-counter CGM. Same Health glucose write as G7.",
               ["Blood glucose"],
               true, true, "https://apps.apple.com/app/stelo/id6476118636",
               "Stelo app → Profile → Apple Health → Blood Glucose.",
               "waveform.path.ecg.rectangle",
               line: "dexcom-stelo", generation: 1, year: 2024),
        device("abbott-lingo", "Lingo", "Abbott", .metabolic,
               "Abbott’s consumer CGM. The Lingo iOS app writes glucose to Health when sharing is on.",
               ["Blood glucose"],
               true, true, "https://apps.apple.com/app/lingo/id6445881821",
               "Lingo → Account → Connected Apps → Apple Health.",
               "cross.vial.fill",
               line: "abbott-lingo", generation: 1, year: 2024),
        device("abbott-libre", "FreeStyle Libre 3", "Abbott", .metabolic,
               "Clinical CGM. LibreLink writes glucose to Health when sharing is on.",
               ["Blood glucose"],
               true, true, "https://apps.apple.com/app/freestyle-librelink/id872652809",
               "LibreLink → Account → Connected Apps → Apple Health.",
               "cross.vial.fill",
               line: "abbott-libre", generation: 3, year: 2022),
    ]

    private static let training: [HealthDevice] = [
        device("peloton", "Peloton", "Peloton", .training,
               "The Peloton iOS app. Classes write workouts and heart rate to Health.",
               ["Workouts", "Heart rate", "Calories"],
               true, true, "https://apps.apple.com/app/peloton-fitness-workouts/id477996689",
               "Peloton → Profile → Health → connect Apple Health.",
               "figure.strengthtraining.traditional",
               line: "peloton-app", generation: 1, year: 2014),
        device("peloton-bike", "Peloton Bike+", "Peloton", .training,
               "The Bike+. Cadence, output and heart rate land in the Peloton app, then Health.",
               ["Cycling", "Heart rate", "Output", "Calories"],
               true, true, "https://apps.apple.com/app/peloton-fitness-workouts/id477996689",
               "Peloton → Profile → Health → Apple Health.",
               "bicycle",
               line: "peloton-bike", generation: 2, year: 2021),
        device("peloton-tread", "Peloton Tread", "Peloton", .training,
               "The tread. Runs and walks write through the same Peloton Health connection.",
               ["Runs", "Heart rate", "Calories"],
               true, true, "https://apps.apple.com/app/peloton-fitness-workouts/id477996689",
               "Peloton → Profile → Health → Apple Health.",
               "figure.run",
               line: "peloton-tread", generation: 1, year: 2021),
        device("strava", "Strava", "Strava", .training,
               "Social training log. Can both read and write workouts with Apple Health.",
               ["Workouts", "Routes", "Heart rate"],
               true, true, "https://apps.apple.com/app/strava-run-bike-hike/id426826309",
               "Strava → Settings → Applications, Devices and Integrations → Health.",
               "figure.run",
               line: "strava", generation: 1, year: 2012),
        device("nike-run-club", "Nike Run Club", "Nike", .training,
               "Guided runs on iPhone and Watch. Writes running workouts to Health.",
               ["Runs", "Heart rate"],
               true, true, "https://apps.apple.com/app/nike-run-club/id387771637",
               "NRC → Profile → Settings → Apple Health.",
               "figure.run",
               line: "nike-run-club", generation: 1, year: 2010),
    ]

    private static let body: [HealthDevice] = [
        device("withings-body", "Withings Body Comp", "Withings", .body,
               "Wi-Fi scale. Weight, BMI, muscle and fat write to Health from Health Mate.",
               ["Weight", "BMI", "Body fat", "Muscle mass"],
               true, true, "https://apps.apple.com/app/health-mate/id542701020",
               "Health Mate → Integrations → Apple Health → Body Measurements.",
               "scalemass.fill",
               line: "withings-scale", generation: 1, year: 2022),
        device("withings-bpm", "Withings BPM Connect", "Withings", .body,
               "Wi-Fi blood pressure cuff. Readings write to Health through Health Mate.",
               ["Blood pressure", "Heart rate"],
               true, true, "https://apps.apple.com/app/health-mate/id542701020",
               "Health Mate → Integrations → Apple Health → Heart.",
               "heart.text.clipboard",
               line: "withings-bpm", generation: 1, year: 2019),
        device("garmin-index", "Garmin Index S2", "Garmin", .body,
               "Garmin's scale. Composition syncs through Garmin Connect into Health.",
               ["Weight", "Body fat", "BMI"],
               true, true, "https://apps.apple.com/app/garmin-connect/id583446403",
               "Garmin Connect → Settings → Health Stats → Apple Health → Body.",
               "scalemass",
               line: "garmin-index", generation: 2, year: 2020),
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
        _ symbol: String,
        line: String,
        generation: Int,
        year: Int,
        compatible: Bool = true
    ) -> HealthDevice {
        HealthDevice(
            id: id,
            name: name,
            maker: maker,
            category: category,
            summary: summary,
            metrics: metrics,
            writesToAppleHealth: health,
            hasIOSApp: compatible,
            worksWithAppleWatch: watch,
            appStoreURL: url,
            setupHint: hint,
            symbolName: symbol,
            line: line,
            generation: generation,
            releasedYear: year,
            stillCompatible: compatible
        )
    }
}
