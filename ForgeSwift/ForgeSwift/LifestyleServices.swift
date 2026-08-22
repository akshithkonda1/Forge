import SwiftUI
import Combine
import WidgetKit
import CoreLocation
import MapKit
import UserNotifications
import ForgeCore

@MainActor
final class WorkoutPlanManager: ObservableObject {
    @Published var customWorkouts: [CustomWorkoutPlan] = []
    @Published var aiGeneratedWorkouts: [AIWorkoutSuggestion] = []
    @Published var aiGeneratedWorkoutsSuggested: [AIWorkoutSuggestion] = []
    @Published var isLoading: Bool = false
    @Published var isLoadingSuggested: Bool = false

    func generateAIWorkout(goals: [FitnessGoal], equipment: [Equipment], duration: Int) async -> CustomWorkoutPlan {
        // Simulate AI generation with workout patterns
        let exercises = selectExercises(for: goals, with: equipment)
        
        return CustomWorkoutPlan(
            id: UUID(),
            name: "\(goals.first?.rawValue ?? "Custom") Workout",
            duration: duration,
            exercises: exercises,
            targetMuscles: goals.compactMap { $0.primaryMuscles }.flatMap { $0 },
            difficulty: .intermediate,
            caloriesBurn: duration * 8
        )
    }
    
    private func selectExercises(for goals: [FitnessGoal], with equipment: [Equipment]) -> [WorkoutExercise] {
        var exercises: [WorkoutExercise] = []
        
        for goal in goals {
            switch goal {
            case .strength:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Bench Press", sets: 4, reps: 8, restSeconds: 90, muscleGroup: .chest),
                    WorkoutExercise(name: "Squats", sets: 4, reps: 10, restSeconds: 120, muscleGroup: .legs),
                    WorkoutExercise(name: "Deadlifts", sets: 3, reps: 6, restSeconds: 180, muscleGroup: .back)
                ])
            case .hypertrophy:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Incline DB Press", sets: 4, reps: 12, restSeconds: 60, muscleGroup: .chest),
                    WorkoutExercise(name: "Leg Press", sets: 4, reps: 15, restSeconds: 90, muscleGroup: .legs),
                    WorkoutExercise(name: "Pull-ups", sets: 3, reps: 10, restSeconds: 60, muscleGroup: .back)
                ])
            case .endurance:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Burpees", sets: 3, reps: 20, restSeconds: 45, muscleGroup: .fullBody),
                    WorkoutExercise(name: "Jump Rope", sets: 4, reps: 100, restSeconds: 30, muscleGroup: .cardio),
                    WorkoutExercise(name: "Mountain Climbers", sets: 3, reps: 30, restSeconds: 30, muscleGroup: .core)
                ])
            case .mobility:
                exercises.append(contentsOf: [
                    WorkoutExercise(name: "Hip Flexor Stretch", sets: 3, reps: 10, restSeconds: 30, muscleGroup: .legs),
                    WorkoutExercise(name: "Shoulder Dislocations", sets: 3, reps: 15, restSeconds: 20, muscleGroup: .shoulders),
                    WorkoutExercise(name: "Cat-Cow Stretch", sets: 3, reps: 12, restSeconds: 20, muscleGroup: .back)
                ])
            }
        }
        
        return exercises
    }
}

@MainActor
final class SmartNotificationManager: ObservableObject {
    static let shared = SmartNotificationManager()
    
    @Published var scheduledReminders: [SmartReminder] = []
    
    private init() {}
    
    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    func scheduleHydrationReminder(every hours: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "💧 Hydration Check"
        content.body = "Time to drink some water! You're doing great staying hydrated."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600), repeats: true)
        let request = UNNotificationRequest(identifier: "hydration-repeating", content: content, trigger: trigger)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleMealReminder(time: DateComponents, mealType: String) async {
        let content = UNMutableNotificationContent()
        content.title = "🍽️ \(mealType) Time"
        content.body = "Don't forget your \(mealType.lowercased())! Hit your protein goals today."
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: "meal-\(mealType)", content: content, trigger: trigger)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleSleepReminder(bedtime: DateComponents) async {
        let content = UNMutableNotificationContent()
        content.title = "🌙 Wind Down Time"
        content.body = "Start your bedtime routine. Quality sleep = better gains!"
        content.sound = .default
        
        var earlyTime = bedtime
        earlyTime.hour = (earlyTime.hour ?? 22) - 1
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: earlyTime, repeats: true)
        let request = UNNotificationRequest(identifier: "sleep-wind-down", content: content, trigger: trigger)

        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Replaces any prior recommendation notifications with the current top
    /// high-impact picks. Non-repeating — each load reschedules from fresh data,
    /// so the user is never nudged about a recommendation that no longer applies.
    func scheduleRecommendationReminders(_ recommendations: [AIRecommendation]) async {
        let center = UNUserNotificationCenter.current()

        // Clear stale recommendation notifications so we never stack duplicates.
        let pending = await center.pendingNotificationRequests()
        let staleIDs = pending.map(\.identifier).filter { $0.hasPrefix("recommendation-") }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: staleIDs)
        }

        // Nudge the top high-impact recommendations, spaced a couple hours out.
        let picks = Array(recommendations.filter { $0.impact == .high }.prefix(2))
        for (i, rec) in picks.enumerated() {
            let content = UNMutableNotificationContent()
            content.title = "⚡️ \(rec.title)"
            content.body = rec.description
            content.sound = .default

            let delay = TimeInterval((i + 1) * 2 * 3600)  // 2h, then 4h
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            let request = UNNotificationRequest(
                identifier: "recommendation-\(rec.id.uuidString)",
                content: content,
                trigger: trigger
            )
            try? await center.add(request)
        }
    }
}

enum LifestyleWidgetBridge {
    /// Must match the App Group capability on BOTH the app and widget targets.
    static let appGroup = "group.com.forge.ForgeSwift"
    static let kind = "LifestyleWidget"
    static let snapshotKey = "lifestyle.widget.snapshot"

    /// Persists the latest QOL + top recommendation and pokes the widget to reload.
    /// Safe before the App Group is configured: writes fall back to a private
    /// domain and the reload is a no-op when no widget is installed.
    static func update(metrics: LifestyleMetrics, recommendations: [AIRecommendation]) {
        let top = recommendations.first
        let snapshot = LifestyleWidgetSnapshot(
            qol: metrics.qualityOfLifeScore,
            topTitle: top?.title,
            topCategory: top?.category.rawValue,
            updatedAt: Date()
        )
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: snapshotKey)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
        HomeWidgetSnapshotStore.update { snap in
            snap.qol = metrics.qualityOfLifeScore
            snap.topRecommendation = top?.title
        }
    }

    static func currentQOL() -> Int {
        loadSnapshot()?.qol ?? 0
    }

    static func currentRecommendation() -> String? {
        loadSnapshot()?.topTitle
    }

    private static func loadSnapshot() -> LifestyleWidgetSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let data = defaults.data(forKey: snapshotKey) else { return nil }
        return try? JSONDecoder().decode(LifestyleWidgetSnapshot.self, from: data)
    }
}

@MainActor
final class LocationMealLogger: ObservableObject {
    @Published var isDetectingLocation = false
    @Published var detectedVenue: String?
    @Published var detectedItems: [MenuItem] = []
    @Published var showConfirmation = false
    @Published var errorMessage: String?

    private var knownVenues: [String: [MenuItem]] {
        var venues: [String: [MenuItem]] = [:]
        for restaurant in popularRestaurants {
            venues[restaurant.name] = restaurant.items
        }
        venues["Wingstop"] = [
            MenuItem(name: "Classic Wings (6 pc)", calories: 480, protein: 42, carbs: 8, fat: 32, serving: "6 pieces", isHealthy: false),
            MenuItem(name: "Boneless Wings (8 pc)", calories: 520, protein: 38, carbs: 32, fat: 28, serving: "8 pieces", isHealthy: false),
            MenuItem(name: "Lemon Pepper Wings (6 pc)", calories: 500, protein: 40, carbs: 10, fat: 34, serving: "6 pieces", isHealthy: false),
        ]
        venues["In-N-Out Burger"] = [
            MenuItem(name: "Protein Style Burger", calories: 330, protein: 18, carbs: 11, fat: 25, serving: "1 burger", isHealthy: true),
            MenuItem(name: "Grilled Cheese", calories: 380, protein: 15, carbs: 39, fat: 19, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Double-Double", calories: 670, protein: 37, carbs: 39, fat: 41, serving: "1 burger", isHealthy: false),
        ]
        venues["Starbucks"] = [
            MenuItem(name: "Egg White & Roasted Red Pepper Egg Bites", calories: 170, protein: 12, carbs: 11, fat: 8, serving: "2 bites", isHealthy: true),
            MenuItem(name: "Spinach Feta Wrap", calories: 290, protein: 19, carbs: 34, fat: 10, serving: "1 wrap", isHealthy: true),
            MenuItem(name: "Grande Latte (2% milk)", calories: 190, protein: 12, carbs: 18, fat: 7, serving: "16 oz", isHealthy: true),
        ]
        venues["Cava"] = [
            MenuItem(name: "Grilled Chicken Bowl", calories: 610, protein: 42, carbs: 52, fat: 24, serving: "1 bowl", isHealthy: true),
            MenuItem(name: "Greens + Grains Bowl", calories: 520, protein: 18, carbs: 68, fat: 18, serving: "1 bowl", isHealthy: true),
        ]
        venues["Shake Shack"] = [
            MenuItem(name: "ShackBurger (Single)", calories: 530, protein: 28, carbs: 27, fat: 34, serving: "1 burger", isHealthy: false),
            MenuItem(name: "Chicken Shack", calories: 550, protein: 33, carbs: 36, fat: 31, serving: "1 sandwich", isHealthy: false),
            MenuItem(name: "Lettuce Wrap ShackBurger", calories: 320, protein: 25, carbs: 6, fat: 22, serving: "1 burger", isHealthy: true),
        ]
        return venues
    }

    private let venueAliases: [String: String] = [
        "raising canes": "Raising Cane's",
        "canes": "Raising Cane's",
        "chick fil a": "Chick-fil-A",
        "chickfila": "Chick-fil-A",
        "in n out": "In-N-Out Burger",
        "innout": "In-N-Out Burger",
        "shake shack": "Shake Shack",
        "what a burger": "Whataburger",
        "wing stop": "Wingstop",
        "mcdonald": "McDonald's",
        "taco bell": "Taco Bell",
        "panera": "Panera Bread",
        "sub way": "Subway",
    ]

    func lookupMenu(for venueName: String) -> [MenuItem] {
        catalogMenu(for: venueName) ?? [
            MenuItem(name: "Grilled Chicken Plate", calories: 420, protein: 38, carbs: 22, fat: 18, serving: "1 plate", isHealthy: true),
            MenuItem(name: "Mixed Greens Salad", calories: 180, protein: 8, carbs: 14, fat: 10, serving: "1 salad", isHealthy: true),
            MenuItem(name: "Brown Rice Bowl", calories: 360, protein: 14, carbs: 58, fat: 8, serving: "1 bowl", isHealthy: true),
        ]
    }

    /// Real catalog match only — nil when Apple Maps found a kitchen we don't have a menu for.
    func catalogMenu(for venueName: String) -> [MenuItem]? {
        if let items = knownVenues[venueName] { return items }
        if let matched = matchVenueName(venueName), let items = knownVenues[matched] { return items }
        return nil
    }

    func detectCurrentLocationAndLog() async {
        isDetectingLocation = true
        errorMessage = nil
        defer { isDetectingLocation = false }

        let locator = LifestyleLocationStore.shared
        if locator.canAsk || !locator.isAuthorized {
            let status = await locator.requestAccess()
            guard status == .authorizedWhenInUse || status == .authorizedAlways else {
                errorMessage = "Location access is required to detect nearby restaurants."
                return
            }
        }
        locator.startTracking()

        guard let location = await locator.latestLocation() else {
            errorMessage = "Couldn't get a GPS fix. Try again in the open, or log from Places."
            return
        }
        do {
            let venue = try await resolveVenue(near: location)
            detectedVenue = venue
            detectedItems = lookupMenu(for: venue)
            showConfirmation = true
        } catch {
            errorMessage = "Couldn't match a restaurant. Open Places and pick one on the map."
        }
    }

    private func resolveVenue(near location: CLLocation) async throws -> String {
        if let already = LifestyleLocationStore.shared.nearby.first,
           already.distanceMeters < 80 {
            return matchVenueName(already.name) ?? already.name
        }
        if let mapMatch = try? await searchNearbyRestaurant(at: location.coordinate) {
            return matchVenueName(mapMatch) ?? mapMatch
        }

        let geocoder = CLGeocoder()
        let placemarks = try await geocoder.reverseGeocodeLocation(location)
        for placemark in placemarks {
            for candidate in [placemark.name, placemark.areasOfInterest?.first, placemark.thoroughfare].compactMap({ $0 }) {
                if let matched = matchVenueName(candidate) { return matched }
            }
        }

        return "Local Restaurant"
    }

    private func searchNearbyRestaurant(at coordinate: CLLocationCoordinate2D) async throws -> String? {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = "restaurant"
        request.resultTypes = .pointOfInterest
        request.region = MKCoordinateRegion(center: coordinate, latitudinalMeters: 400, longitudinalMeters: 400)
        let response = try await MKLocalSearch(request: request).start()
        return response.mapItems
            .sorted { lhs, rhs in
                let lhsDistance = lhs.placemark.location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? .greatestFiniteMagnitude
                let rhsDistance = rhs.placemark.location?.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) ?? .greatestFiniteMagnitude
                return lhsDistance < rhsDistance
            }
            .compactMap { $0.name }
            .first
    }

    private func matchVenueName(_ raw: String) -> String? {
        let normalized = raw.lowercased()
        for restaurant in popularRestaurants where normalized.contains(restaurant.name.lowercased()) {
            return restaurant.name
        }
        for (alias, canonical) in venueAliases where normalized.contains(alias) {
            return canonical
        }
        for key in knownVenues.keys where normalized.contains(key.lowercased()) {
            return key
        }
        return nil
    }

    func logSelectedMeal(_ item: MenuItem, to vm: LifestyleViewModel) {
        Task {
            await vm.logMeal(
                name: "\(detectedVenue ?? "Restaurant") - \(item.name)",
                calories: Double(item.calories),
                protein: Double(item.protein),
                carbs: Double(item.carbs),
                fat: Double(item.fat)
            )
            showConfirmation = false
            detectedVenue = nil
            detectedItems = []
        }
    }
}

@MainActor
enum LifestyleWellbeingStore {
    private static let habitsKey = "lifestyle.dailyHabits"
    private static let streakKey = "lifestyle.habitStreak"
    private static let stressKey = "lifestyle.stressLevel"
    private static let habitsDateKey = "lifestyle.habitsDate"
    private static let qolHistoryKey = "lifestyle.qolHistory"

    static let defaultHabits: [DailyHabit] = [
        DailyHabit(id: UUID(), name: "Morning sunlight (10 min)", done: false),
        DailyHabit(id: UUID(), name: "Meditation (5 min)", done: false),
        DailyHabit(id: UUID(), name: "Read (20 min)", done: false),
        DailyHabit(id: UUID(), name: "Mobility work (10 min)", done: false),
        DailyHabit(id: UUID(), name: "Cold shower", done: false),
        DailyHabit(id: UUID(), name: "Journaling", done: false),
    ]

    static func loadHabits() -> [DailyHabit] {
        let calendar = Calendar.current
        let savedDay = UserDefaults.standard.object(forKey: habitsDateKey) as? Date
        if let savedDay, calendar.isDateInToday(savedDay),
           let data = UserDefaults.standard.data(forKey: habitsKey),
           let habits = try? JSONDecoder().decode([DailyHabit].self, from: data) {
            return habits
        }
        return defaultHabits
    }

    static func saveHabits(_ habits: [DailyHabit]) {
        UserDefaults.standard.set(Date(), forKey: habitsDateKey)
        if let data = try? JSONEncoder().encode(habits) {
            UserDefaults.standard.set(data, forKey: habitsKey)
        }
        updateStreakIfNeeded(habits)
    }

    static func habitStreak() -> Int {
        max(UserDefaults.standard.integer(forKey: streakKey), 1)
    }

    /// Records today's QOL score (one entry per day; last 30 days kept) and
    /// returns the updated history, oldest first.
    @discardableResult
    static func recordQOL(_ score: Int) -> [QOLDay] {
        let today = Calendar.current.startOfDay(for: Date())
        var history = loadQOLHistory().filter { !Calendar.current.isDate($0.date, inSameDayAs: today) }
        history.append(QOLDay(date: today, score: score))
        history.sort { $0.date < $1.date }
        if history.count > 30 { history = Array(history.suffix(30)) }
        if let data = try? JSONEncoder().encode(history) {
            UserDefaults.standard.set(data, forKey: qolHistoryKey)
        }
        return history
    }

    static func loadQOLHistory() -> [QOLDay] {
        guard let data = UserDefaults.standard.data(forKey: qolHistoryKey),
              let history = try? JSONDecoder().decode([QOLDay].self, from: data) else { return [] }
        return history
    }

    private static func updateStreakIfNeeded(_ habits: [DailyHabit]) {
        let completed = habits.filter(\.done).count
        let total = habits.count
        guard total > 0 else { return }
        if Double(completed) / Double(total) >= 0.6 {
            let current = UserDefaults.standard.integer(forKey: streakKey)
            UserDefaults.standard.set(max(current, 1), forKey: streakKey)
        }
    }

    static func loadStressLevel() -> Int {
        let value = UserDefaults.standard.integer(forKey: stressKey)
        return (0...2).contains(value) ? value : 1
    }

    static func saveStressLevel(_ level: Int) {
        UserDefaults.standard.set(level, forKey: stressKey)
    }
}

/// Nutrition lookup backed by the free Open Food Facts API (no key required).
enum FoodLookup {
    struct Result: Identifiable {
        let id = UUID()
        let found: Bool
        let name: String
        let calories: Double
        let protein: Double
        let carbs: Double
        let fat: Double
    }

    static func lookup(barcode: String) async -> Result {
        guard let url = URL(string: "https://world.openfoodfacts.org/api/v2/product/\(barcode).json?fields=product_name,nutriments"),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["status"] as? Int) == 1,
              let product = json["product"] as? [String: Any]
        else {
            return Result(found: false, name: "", calories: 0, protein: 0, carbs: 0, fat: 0)
        }

        let nutriments = (product["nutriments"] as? [String: Any]) ?? [:]
        func number(_ keys: [String]) -> Double {
            for key in keys {
                if let v = nutriments[key] as? Double { return v }
                if let v = nutriments[key] as? Int { return Double(v) }
                if let s = nutriments[key] as? String, let v = Double(s) { return v }
            }
            return 0
        }

        let name = (product["product_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Scanned item"
        // Prefer per-serving values; fall back to per-100g.
        return Result(
            found: true,
            name: name,
            calories: number(["energy-kcal_serving", "energy-kcal_100g", "energy-kcal"]),
            protein: number(["proteins_serving", "proteins_100g", "proteins"]),
            carbs: number(["carbohydrates_serving", "carbohydrates_100g", "carbohydrates"]),
            fat: number(["fat_serving", "fat_100g", "fat"])
        )
    }
}
