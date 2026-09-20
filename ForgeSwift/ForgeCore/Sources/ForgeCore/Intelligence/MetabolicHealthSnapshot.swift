import Foundation

/// One blood-glucose reading, already converted to mg/dL.
///
/// Lifestyle comparison only — never a glycemic diagnosis.
public struct GlucosePoint: Sendable, Equatable {
    public var date: Date
    public var mgdl: Double
    public var sourceName: String

    public init(date: Date, mgdl: Double, sourceName: String = "") {
        self.date = date
        self.mgdl = mgdl
        self.sourceName = sourceName
    }
}

/// A logged meal used to pair carbs with the glucose that followed.
public struct MetabolicMealEvent: Sendable, Equatable {
    public var name: String
    public var date: Date
    public var calories: Double
    public var carbs: Double
    public var protein: Double
    public var fat: Double

    public init(
        name: String,
        date: Date,
        calories: Double,
        carbs: Double,
        protein: Double = 0,
        fat: Double = 0
    ) {
        self.name = name
        self.date = date
        self.calories = calories
        self.carbs = carbs
        self.protein = protein
        self.fat = fat
    }
}

/// One meal and the glucose that showed up after it.
public struct MealGlucosePair: Sendable, Equatable {
    public var mealName: String
    public var mealDate: Date
    public var carbs: Double
    public var calories: Double
    public var peakMgdl: Double?
    public var deltaMgdl: Double?
    public var line: String

    public init(
        mealName: String,
        mealDate: Date,
        carbs: Double,
        calories: Double,
        peakMgdl: Double?,
        deltaMgdl: Double?,
        line: String
    ) {
        self.mealName = mealName
        self.mealDate = mealDate
        self.carbs = carbs
        self.calories = calories
        self.peakMgdl = peakMgdl
        self.deltaMgdl = deltaMgdl
        self.line = line
    }
}

/// Meals + macros + glucose as one story.
///
/// Oura's metabolic wedge is meals, a nutritional breakdown, and glucose
/// from a CGM sold separately. Forge already logs meals; this is the
/// missing meal ↔ glucose sentence — lifestyle copy, never a diagnosis.
public struct MetabolicHealthSnapshot: Sendable, Equatable {
    public var latestMgdl: Double?
    public var latestDate: Date?
    public var latestSource: String?
    public var mealCount: Int
    public var carbsGrams: Double
    public var proteinGrams: Double
    public var fatGrams: Double
    public var calories: Double
    public var storyLine: String
    public var accessoryLine: String
    public var pairs: [MealGlucosePair]
    public var bullets: [String]

    public var hasGlucose: Bool { latestMgdl != nil }

    public static let empty = MetabolicHealthSnapshot(
        latestMgdl: nil,
        latestDate: nil,
        latestSource: nil,
        mealCount: 0,
        carbsGrams: 0,
        proteinGrams: 0,
        fatGrams: 0,
        calories: 0,
        storyLine: "",
        accessoryLine: TranslationCatalog.metabolicAccessoryNote,
        pairs: [],
        bullets: TranslationCatalog.metabolic.bullets
    )

    public static var soldSeparatelyLine: String { TranslationCatalog.metabolicAccessoryNote }

    public static func evaluate(
        meals: [MetabolicMealEvent],
        glucose: [GlucosePoint],
        dayCarbs: Double? = nil,
        dayProtein: Double? = nil,
        dayFat: Double? = nil,
        dayCalories: Double? = nil,
        connectedDeviceIDs: [String] = [],
        now: Date = Date()
    ) -> MetabolicHealthSnapshot {
        let dayStart = Calendar.current.startOfDay(for: now)
        let todayMeals = meals
            .filter { $0.date >= dayStart && $0.date <= now }
            .sorted { $0.date > $1.date }
        let readings = glucose
            .filter { $0.mgdl >= 40 && $0.mgdl <= 400 }
            .sorted { $0.date > $1.date }

        let latest = readings.first
        let carbs = dayCarbs ?? todayMeals.reduce(0) { $0 + $1.carbs }
        let protein = dayProtein ?? todayMeals.reduce(0) { $0 + $1.protein }
        let fat = dayFat ?? todayMeals.reduce(0) { $0 + $1.fat }
        let calories = dayCalories ?? todayMeals.reduce(0) { $0 + $1.calories }
        let pairs = pairMeals(todayMeals, glucose: readings)
        let accessory = accessoryLine(
            connectedDeviceIDs: connectedDeviceIDs,
            latestSource: latest?.sourceName
        )
        let story = buildStoryLine(
            latest: latest,
            meals: todayMeals,
            pairs: pairs,
            accessory: accessory
        )

        return MetabolicHealthSnapshot(
            latestMgdl: latest.map { ($0.mgdl * 10).rounded() / 10 },
            latestDate: latest?.date,
            latestSource: cleanedSource(latest?.sourceName),
            mealCount: todayMeals.count,
            carbsGrams: (carbs * 10).rounded() / 10,
            proteinGrams: (protein * 10).rounded() / 10,
            fatGrams: (fat * 10).rounded() / 10,
            calories: calories.rounded(),
            storyLine: story,
            accessoryLine: accessory,
            pairs: pairs,
            bullets: TranslationCatalog.metabolic.bullets
        )
    }

    public static func accessoryLine(
        connectedDeviceIDs: [String],
        latestSource: String?
    ) -> String {
        if let source = cleanedSource(latestSource), isCGMSource(source) {
            return "Glucose is coming from \(source) through Apple Health."
        }
        if let named = connectedMetabolicName(connectedDeviceIDs) {
            return "\(named) is selected. Open its app and share Blood Glucose with Apple Health. The sensor is sold separately."
        }
        return soldSeparatelyLine
    }
}

// MARK: - Pairing

private func pairMeals(
    _ meals: [MetabolicMealEvent],
    glucose: [GlucosePoint]
) -> [MealGlucosePair] {
    meals.compactMap { meal in
        let preWindow = glucose.filter {
            $0.date >= meal.date.addingTimeInterval(-45 * 60)
                && $0.date <= meal.date.addingTimeInterval(5 * 60)
        }
        let postWindow = glucose.filter {
            $0.date >= meal.date.addingTimeInterval(20 * 60)
                && $0.date <= meal.date.addingTimeInterval(150 * 60)
        }
        guard !postWindow.isEmpty else { return nil }

        let peak = postWindow.map(\.mgdl).max()
        let baseline = preWindow.sorted { $0.date > $1.date }.first?.mgdl
        let delta = zipOptional(peak, baseline).map { $0 - $1 }
        return MealGlucosePair(
            mealName: meal.name,
            mealDate: meal.date,
            carbs: meal.carbs,
            calories: meal.calories,
            peakMgdl: peak.map { $0.rounded() },
            deltaMgdl: delta.map { $0.rounded() },
            line: pairLine(name: meal.name, carbs: meal.carbs, peak: peak, delta: delta)
        )
    }
}

private func pairLine(name: String, carbs: Double, peak: Double?, delta: Double?) -> String {
    let meal = name.trimmingCharacters(in: .whitespacesAndNewlines)
    let title = meal.isEmpty ? "Meal" : meal
    let carbBit = carbs > 0 ? " · \(Int(carbs.rounded()))g carbs" : ""
    if let peak, let delta {
        let change = Int(abs(delta).rounded())
        if delta >= 8 {
            return "\(title)\(carbBit) · glucose rose \(change) mg/dL after."
        }
        if delta <= -8 {
            return "\(title)\(carbBit) · glucose eased \(change) mg/dL after."
        }
        return "\(title)\(carbBit) · glucose held near \(Int(peak.rounded())) mg/dL after."
    }
    if let peak {
        return "\(title)\(carbBit) · \(Int(peak.rounded())) mg/dL after the meal."
    }
    return "\(title)\(carbBit)."
}

// Named `buildStoryLine`, not `storyLine` — `MetabolicHealthSnapshot` itself
// declares an instance property called `storyLine`, and an unqualified call
// from `evaluate()` (a static method of that same type) resolves to the
// property before this file-scope function, which doesn't typecheck as a
// call at all.
private func buildStoryLine(
    latest: GlucosePoint?,
    meals: [MetabolicMealEvent],
    pairs: [MealGlucosePair],
    accessory: String
) -> String {
    if let pair = pairs.first {
        return pair.line
    }
    if let latest {
        let value = Int(latest.mgdl.rounded())
        if meals.isEmpty {
            return "Latest glucose \(value) mg/dL. Log a meal to see how food lands."
        }
        let noun = meals.count == 1 ? "meal" : "meals"
        return "Latest glucose \(value) mg/dL. \(meals.count) \(noun) today — waiting on a post-meal reading."
    }
    if !meals.isEmpty {
        let noun = meals.count == 1 ? "meal" : "meals"
        return "\(meals.count) \(noun) logged. \(accessory)"
    }
    return "Log a meal. A glucose sensor, sold separately, turns that into a meal ↔ glucose story."
}

private func connectedMetabolicName(_ ids: [String]) -> String? {
    let migrated = HealthDeviceCatalog.migrateStoredIDs(ids)
    let devices = migrated.compactMap { HealthDeviceCatalog.device(matching: $0) }
    return devices.first(where: { $0.category == .metabolic })?.name
}

private func isCGMSource(_ name: String) -> Bool {
    let folded = name.lowercased()
    return ["dexcom", "stelo", "libre", "librelink", "lingo", "abbott", "glucose"]
        .contains { folded.contains($0) }
}

private func cleanedSource(_ raw: String?) -> String? {
    let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
}

private func zipOptional<A, B>(_ a: A?, _ b: B?) -> (A, B)? {
    guard let a, let b else { return nil }
    return (a, b)
}
