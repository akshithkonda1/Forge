import SwiftUI
import Combine
import Charts
import WidgetKit
import AVFoundation
import UIKit
import HealthKit
import WorkoutKit
import CoreLocation
import MapKit
import UserNotifications
import UIKit

// MARK: - Supporting Data Models (HealthKit types defined in HealthKitManager.swift)

// MARK: - WorkoutKit Manager

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

struct CustomWorkoutPlan: Identifiable, Codable {
    let id: UUID
    let name: String
    let duration: Int
    let exercises: [WorkoutExercise]
    let targetMuscles: [MuscleGroup]
    let difficulty: WorkoutDifficulty
    let caloriesBurn: Int
}

struct WorkoutExercise: Identifiable, Codable {
    var id = UUID()
    let name: String
    let sets: Int
    let reps: Int
    let restSeconds: Int
    let muscleGroup: MuscleGroup
}

enum FitnessGoal: String, CaseIterable {
    case strength = "Strength"
    case hypertrophy = "Hypertrophy"
    case endurance = "Endurance"
    case mobility = "Mobility"
    
    var primaryMuscles: [MuscleGroup] {
        switch self {
        case .strength: return [.chest, .back, .legs]
        case .hypertrophy: return [.chest, .back, .legs, .arms, .shoulders]
        case .endurance: return [.cardio, .fullBody]
        case .mobility: return [.fullBody]
        }
    }
}

enum Equipment: String, CaseIterable {
    case barbell = "Barbell"
    case dumbbells = "Dumbbells"
    case cables = "Cables"
    case machines = "Machines"
    case bodyweight = "Bodyweight"
    case bands = "Resistance Bands"
}

enum MuscleGroup: String, Codable {
    case chest, back, legs, arms, shoulders, core, cardio, fullBody
}

enum WorkoutDifficulty: String, Codable {
    case beginner, intermediate, advanced
}

struct AIWorkoutSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let reason: String
    let workout: CustomWorkoutPlan
}

// MARK: - Notification Manager

@MainActor
final class SmartNotificationManager: ObservableObject {
    static let shared = SmartNotificationManager()
    
    @Published var scheduledReminders: [SmartReminder] = []
    
    private init() {}
    
    func requestAuthorization() async throws {
        let center = UNUserNotificationCenter.current()
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }
    
    func scheduleHydrationReminder(every hours: Int) async {
        let content = UNMutableNotificationContent()
        content.title = "💧 Hydration Check"
        content.body = "Time to drink some water! You're doing great staying hydrated."
        content.sound = .default
        
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(hours * 3600), repeats: true)
        let request = UNNotificationRequest(identifier: "hydration-\(UUID())", content: content, trigger: trigger)
        
        try? await UNUserNotificationCenter.current().add(request)
    }
    
    func scheduleMealReminder(time: DateComponents, mealType: String) async {
        let content = UNMutableNotificationContent()
        content.title = "🍽️ \(mealType) Time"
        content.body = "Don't forget your \(mealType.lowercased())! Hit your protein goals today."
        content.sound = .default
        
        let trigger = UNCalendarNotificationTrigger(dateMatching: time, repeats: true)
        let request = UNNotificationRequest(identifier: "meal-\(mealType)-\(UUID())", content: content, trigger: trigger)
        
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
        let request = UNNotificationRequest(identifier: "sleep-\(UUID())", content: content, trigger: trigger)

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

struct SmartReminder: Identifiable {
    let id: String
    let type: ReminderType
    let time: DateComponents
    let enabled: Bool
}

enum ReminderType {
    case hydration, meal, sleep, workout, supplement
}

// MARK: - Widget Bridge (shared snapshot for the Home Screen widget)

/// Snapshot the Lifestyle Home Screen widget reads from the shared App Group.
/// Lives in the app target (so it compiles in CI); the widget extension — added
/// separately in Xcode — decodes the same struct from the same suite + key.
struct LifestyleWidgetSnapshot: Codable {
    var qol: Int
    var topTitle: String?
    var topCategory: String?
    var updatedAt: Date
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
    }
}

// MARK: - Domain Models

struct Restaurant: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let logo: String
    let items: [MenuItem]
    let category: RestaurantCategory

    init(id: UUID = UUID(), name: String, logo: String, items: [MenuItem], category: RestaurantCategory) {
        self.id = id; self.name = name; self.logo = logo; self.items = items; self.category = category
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: Restaurant, rhs: Restaurant) -> Bool { lhs.id == rhs.id }
}

struct MenuItem: Identifiable, Codable, Hashable {
    let id: UUID
    let name: String
    let calories: Int
    let protein: Int
    let carbs: Int
    let fat: Int
    let serving: String
    let isHealthy: Bool

    init(id: UUID = UUID(), name: String, calories: Int, protein: Int, carbs: Int, fat: Int, serving: String, isHealthy: Bool) {
        self.id = id; self.name = name; self.calories = calories; self.protein = protein
        self.carbs = carbs; self.fat = fat; self.serving = serving; self.isHealthy = isHealthy
    }

    /// Protein per 100 kcal — higher = better ratio
    var proteinEfficiency: Int {
        guard calories > 0 else { return 0 }
        return Int(Double(protein) / Double(calories) * 1000)
    }

    var nutritionalRating: NutritionRating {
        switch proteinEfficiency {
        case 150...: return .excellent
        case 100..<150: return .good
        case 50..<100: return .fair
        default: return .poor
        }
    }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    static func == (lhs: MenuItem, rhs: MenuItem) -> Bool { lhs.id == rhs.id }
}

enum NutritionRating {
    case excellent, good, fair, poor
    var color: Color {
        switch self {
        case .excellent: return .success
        case .good: return .steel
        case .fair: return .warning
        case .poor: return .danger
        }
    }
    var label: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        }
    }
}

enum RestaurantCategory: String, CaseIterable, Codable {
    case all = "All"
    case fastFood = "Fast Food"
    case chicken = "Chicken"
    case mexican = "Mexican"
    case burgers = "Burgers"
    case pizza = "Pizza"
    case healthy = "Healthy"
}

// MARK: - Lifestyle Domain Models

struct LifestyleMetrics: Codable {
    let sleepAverage: Double
    let sleepTarget: Double
    let nutritionQuality: Double
    let dailySteps: Int
    let stressLevel: StressLevel
    let qualityOfLifeScore: Int
    let physicalHealth: Int
    let mentalWellbeing: Int
    let energyLevels: Int
    let sleepQuality: Int
    let nutritionScore: Int

    static var `default`: LifestyleMetrics {
        LifestyleMetrics(
            sleepAverage: 7.2, sleepTarget: 8.0, nutritionQuality: 0.78,
            dailySteps: 8400, stressLevel: .medium, qualityOfLifeScore: 82,
            physicalHealth: 88, mentalWellbeing: 75, energyLevels: 82,
            sleepQuality: 79, nutritionScore: 85
        )
    }
}

enum StressLevel: String, Codable {
    case low = "Low", medium = "Medium", high = "High"
    var color: Color {
        switch self { case .low: return .success; case .medium: return .warning; case .high: return .danger }
    }
}

struct AIRecommendation: Identifiable, Codable {
    let id: UUID
    let title: String
    let description: String
    let impact: ImpactLevel
    let category: RecommendationCategory

    init(id: UUID = UUID(), title: String, description: String, impact: ImpactLevel, category: RecommendationCategory) {
        self.id = id; self.title = title; self.description = description
        self.impact = impact; self.category = category
    }

    static var sampleRecommendations: [AIRecommendation] {[
        AIRecommendation(title: "Increase protein by 30g", description: "Muscle recovery improves with 180g daily. You're averaging 150g — add a serving of Greek yogurt or chicken after training.", impact: .high, category: .nutrition),
        AIRecommendation(title: "Earlier bedtime (9:30 PM)", description: "Your deep sleep increases by 18% when asleep before 10 PM. Oura data across 47 nights confirms this pattern.", impact: .high, category: .sleep),
        AIRecommendation(title: "10 min morning sunlight", description: "Cortisol regulation and circadian rhythm improve with early light. Best before 9 AM.", impact: .medium, category: .wellbeing),
        AIRecommendation(title: "No caffeine after 2 PM", description: "Late caffeine correlates with 40 fewer minutes of deep sleep in your personal data.", impact: .medium, category: .sleep),
    ]}
}

enum ImpactLevel: String, Codable {
    case high = "High", medium = "Medium", low = "Low"
    var color: Color {
        switch self { case .high: return .ember; case .medium: return .warning; case .low: return .steel }
    }
}

enum RecommendationCategory: String, Codable {
    case nutrition = "Nutrition", sleep = "Sleep", wellbeing = "Wellbeing", fitness = "Fitness"
    var icon: String {
        switch self {
        case .nutrition: return "fork.knife"
        case .sleep:     return "moon.stars.fill"
        case .wellbeing: return "heart.fill"
        case .fitness:   return "dumbbell.fill"
        }
    }
}

enum LifestyleError: Error, LocalizedError {
    case networkError, dataParsingError, unauthorizedAccess, unknownError
    var errorDescription: String? {
        switch self {
        case .networkError:      return "Unable to connect. Check your internet connection."
        case .dataParsingError:  return "Unable to process data. Please try again."
        case .unauthorizedAccess: return "You don't have access to this data."
        case .unknownError:      return "An unexpected error occurred."
        }
    }
}

// MARK: - Location Services

private final class LocationProvider: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    func requestWhenInUseAuthorization() {
        manager.requestWhenInUseAuthorization()
    }

    func waitForAuthorization() async -> CLAuthorizationStatus {
        let status = manager.authorizationStatus
        guard status == .notDetermined else { return status }
        return await withCheckedContinuation { continuation in
            authContinuation = continuation
        }
    }

    func requestLocation() async throws -> CLLocation {
        try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            manager.requestLocation()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status != .notDetermined {
            authContinuation?.resume(returning: status)
            authContinuation = nil
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        locationContinuation?.resume(returning: location)
        locationContinuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        locationContinuation?.resume(throwing: error)
        locationContinuation = nil
    }
}

// MARK: - Location Meal Logger

@MainActor
final class LocationMealLogger: ObservableObject {
    @Published var isDetectingLocation = false
    @Published var detectedVenue: String?
    @Published var detectedItems: [MenuItem] = []
    @Published var showConfirmation = false
    @Published var errorMessage: String?

    private let locationProvider = LocationProvider()

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
        if let items = knownVenues[venueName] { return items }
        return [
            MenuItem(name: "Grilled Chicken Plate", calories: 420, protein: 38, carbs: 22, fat: 18, serving: "1 plate", isHealthy: true),
            MenuItem(name: "Mixed Greens Salad", calories: 180, protein: 8, carbs: 14, fat: 10, serving: "1 salad", isHealthy: true),
            MenuItem(name: "Brown Rice Bowl", calories: 360, protein: 14, carbs: 58, fat: 8, serving: "1 bowl", isHealthy: true),
        ]
    }

    func detectCurrentLocationAndLog() async {
        isDetectingLocation = true
        errorMessage = nil
        defer { isDetectingLocation = false }

        if locationProvider.authorizationStatus == .notDetermined {
            locationProvider.requestWhenInUseAuthorization()
        }

        let status = await locationProvider.waitForAuthorization()
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            errorMessage = "Location access is required to detect nearby restaurants."
            return
        }

        do {
            let location = try await locationProvider.requestLocation()
            let venue = try await resolveVenue(near: location)
            detectedVenue = venue
            detectedItems = lookupMenu(for: venue)
            showConfirmation = true
        } catch {
            errorMessage = "Couldn't detect your location. Try again or log manually."
        }
    }

    private func resolveVenue(near location: CLLocation) async throws -> String {
        if let mapMatch = try? await searchNearbyRestaurant(at: location.coordinate),
           let matched = matchVenueName(mapMatch) {
            return matched
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

// MARK: - Wellbeing Persistence

struct DailyHabit: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var done: Bool
}

struct QOLDay: Identifiable, Codable {
    var id = UUID()
    let date: Date
    let score: Int
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

// MARK: - ViewModel (integrated with HealthKit + AI)

@MainActor
final class LifestyleViewModel: ObservableObject {
    @Published private(set) var metrics: LifestyleMetrics = .default
    @Published private(set) var recommendations: [AIRecommendation] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: LifestyleError?
    
    // Real-time health data
    @Published var healthStats: DailyHealthStats?
    @Published var weeklyTrends: [WeeklyHealthTrend] = []
    @Published var mindfulTrend: [MindfulDay] = []
    @Published var qolHistory: [QOLDay] = []
    @Published var aiWorkouts: [AIWorkoutSuggestion] = []
    @Published var loggedMeals: [MealLog] = []
    @Published var mindfulMinutesToday: Int = 0
    @Published var mindfulMinutesWeek: Int = 0

    // Live ARIA insights — overlay real Claude/Bedrock reasoning onto the cards.
    // When nil, the cards render their existing local heuristic content (fallback).
    @Published var aiLifeAnalysis: String?
    @Published var aiNutritionInsight: String?
    @Published var aiBestPicksNote: String?
    @Published var aiMealNote: String?
    @Published var aiInsightsLive = false      // true when the last refresh came from the remote engine
    @Published var aiInsightsLoading = false

    private let healthManager = HealthKitManager.shared
    private let workoutManager = WorkoutPlanManager()
    private let notificationManager = SmartNotificationManager.shared
    
    init() {}

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await healthManager.requestAuthorization()
            try await notificationManager.requestAuthorization()

            await healthManager.fetchTodayStats()
            await healthManager.fetchWeeklyTrends()
            await healthManager.fetchMindfulTrend()
            healthStats = healthManager.todayStats
            weeklyTrends = healthManager.weeklyTrends
            mindfulTrend = healthManager.mindfulTrend
            loggedMeals = healthManager.loggedMeals

            let now = Date()
            let startOfDay = Calendar.current.startOfDay(for: now)
            let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? startOfDay
            async let mindfulToday = healthManager.fetchMindfulMinutes(from: startOfDay, to: now)
            async let mindfulWeek = healthManager.fetchMindfulMinutes(from: weekAgo, to: now)
            async let m = fetchMetrics()
            async let r = fetchRecommendations()
            async let ai = generateAIWorkouts(from: healthStats)

            metrics = try await m
            recommendations = try await r
            aiWorkouts = await ai
            mindfulMinutesToday = Int(await mindfulToday)
            mindfulMinutesWeek = Int(await mindfulWeek)
            qolHistory = LifestyleWellbeingStore.recordQOL(metrics.qualityOfLifeScore)

            await scheduleSmartReminders()
            await notificationManager.scheduleRecommendationReminders(recommendations)
            syncAriaContext()
            error = nil
        } catch {
            self.error = error as? LifestyleError ?? .unknownError
        }
    }

    func refresh() async { await load() }

    func syncAriaContext() {
        AriaContextStore.shared.syncLifestyleSignals(
            metrics: metrics,
            stats: healthStats,
            recommendations: recommendations,
            loggedMeals: loggedMeals
        )
        LifestyleWidgetBridge.update(metrics: metrics, recommendations: recommendations)
    }

    /// Overlays live Claude/Bedrock reasoning onto the heuristic cards. Best-effort:
    /// on any failure the published fields stay nil and the cards keep rendering their
    /// existing local content. Safe to call after `load()` / `refresh()`.
    func refreshAIInsights(store: AppStore) async {
        guard !aiInsightsLoading else { return }
        aiInsightsLoading = true
        defer { aiInsightsLoading = false }

        // Make sure ARIA reasons over the latest lifestyle signals.
        syncAriaContext()

        let analysisResp = await store.ariaInsight(prompt: lifestyleAnalysisPrompt())
        let nutritionResp = await store.ariaInsight(prompt: nutritionCoachPrompt())

        aiLifeAnalysis = analysisResp.map { $0.proseSummary ?? $0.message }
        aiNutritionInsight = nutritionResp.map { $0.proseSummary ?? $0.message }
        // Remote engine answered (not the on-device fallback path).
        aiInsightsLive = !AriaService.shared.isLocalFallback
            && (analysisResp != nil || nutritionResp != nil)
    }

    private func lifestyleAnalysisPrompt() -> String {
        let s = healthStats
        return """
        Analyze my lifestyle today in 2-3 sentences. QOL \(metrics.qualityOfLifeScore)/100, \
        sleep \(String(format: "%.1f", metrics.sleepAverage))h, \(metrics.dailySteps) steps, \
        stress \(metrics.stressLevel.rawValue), protein \(Int(s?.protein ?? 0))g, HRV \(Int(s?.hrv ?? 0))ms. \
        What is the single highest-impact change I should make right now?
        """
    }

    private func nutritionCoachPrompt() -> String {
        let s = healthStats
        return """
        Coach my nutrition in 2-3 sentences. Today: \(Int(s?.protein ?? 0))g protein (target 180), \
        \(s?.totalCalories ?? 0) kcal (target 2600), \(Int(s?.water ?? 0)) of 8 glasses water. \
        Give one specific, actionable tip for my next meal.
        """
    }

    /// Lazy ARIA coaching note for the restaurant "Best Picks" — fired only when the
    /// Restaurants tab appears. Leaves the note nil (heuristic-only) on failure.
    func refreshBestPicksNote(store: AppStore) async {
        let gap = max(0, Int(180 - (healthStats?.protein ?? 0)))
        let kcalLeft = max(0, 2600 - (healthStats?.totalCalories ?? 0))
        let prompt = """
        I'm picking a restaurant meal. I have about \(gap)g protein and \(kcalLeft) kcal left today. \
        In 1-2 sentences, what should I prioritize ordering to close my protein gap without \
        overshooting calories?
        """
        let resp = await store.ariaInsight(prompt: prompt)
        aiBestPicksNote = resp.map { $0.proseSummary ?? $0.message }
    }

    /// Lazy ARIA dish suggestion for the Nutrition tab's meal-suggestions card.
    /// Distinct from the macro coach tip; nil → heuristic rows only.
    func refreshMealNote(store: AppStore) async {
        let gap = max(0, Int(180 - (healthStats?.protein ?? 0)))
        let kcalLeft = max(0, 2600 - (healthStats?.totalCalories ?? 0))
        let prompt = """
        Suggest one specific dish or meal to eat next, in a single sentence, to help me close \
        a \(gap)g protein gap within \(kcalLeft) kcal remaining today.
        """
        let resp = await store.ariaInsight(prompt: prompt)
        aiMealNote = resp.map { $0.proseSummary ?? $0.message }
    }

    func logMeal(name: String, calories: Double, protein: Double, carbs: Double, fat: Double) async {
        let meal = MealLog(name: name, calories: calories, protein: protein, carbs: carbs, fat: fat)
        try? await healthManager.logMeal(meal)
        await refresh()
    }
    
    func logWater(glasses: Int) async {
        try? await healthManager.logWater(ounces: Double(glasses * 8))
        await refresh()
    }
    
    func logMindfulSession(minutes: Int) async {
        try? await healthManager.logMindfulSession(minutes: Double(minutes))
        await refresh()
    }

    private func generateAIWorkouts(from stats: DailyHealthStats?) async -> [AIWorkoutSuggestion] {
        var suggestions: [AIWorkoutSuggestion] = []
        
        if let hrv = stats?.hrv, hrv < 30 {
            let recoveryWorkout = await workoutManager.generateAIWorkout(
                goals: [.mobility],
                equipment: [.bodyweight, .bands],
                duration: 30
            )
            suggestions.append(AIWorkoutSuggestion(
                title: "Active Recovery",
                reason: "HRV is low (\(Int(hrv))ms) — prioritize mobility and light movement",
                workout: recoveryWorkout
            ))
        } else {
            let strengthWorkout = await workoutManager.generateAIWorkout(
                goals: [.strength, .hypertrophy],
                equipment: [.barbell, .dumbbells],
                duration: 60
            )
            suggestions.append(AIWorkoutSuggestion(
                title: "Strength Focus",
                reason: "Recovery metrics are solid — time to push hard",
                workout: strengthWorkout
            ))
        }
        
        if let stats, stats.steps < 6000 {
            let cardioWorkout = await workoutManager.generateAIWorkout(
                goals: [.endurance],
                equipment: [.bodyweight],
                duration: 30
            )
            suggestions.append(AIWorkoutSuggestion(
                title: "HIIT Cardio",
                reason: "Only \(stats.steps) steps today — let's boost activity",
                workout: cardioWorkout
            ))
        }
        
        return suggestions
    }
    
    private func scheduleSmartReminders() async {
        // Hydration reminder every 2 hours
        await notificationManager.scheduleHydrationReminder(every: 2)
        
        // Meal reminders
        var lunch = DateComponents()
        lunch.hour = 12
        lunch.minute = 0
        await notificationManager.scheduleMealReminder(time: lunch, mealType: "Lunch")
        
        var dinner = DateComponents()
        dinner.hour = 18
        dinner.minute = 30
        await notificationManager.scheduleMealReminder(time: dinner, mealType: "Dinner")
        
        // Sleep reminder
        var bedtime = DateComponents()
        bedtime.hour = 22
        bedtime.minute = 0
        await notificationManager.scheduleSleepReminder(bedtime: bedtime)
    }

    private func fetchMetrics() async throws -> LifestyleMetrics {
        guard let stats = healthStats else {
            return .default
        }
        
        let sleepQuality = Int((stats.sleepHours / 8.0) * 100)
        let nutritionScore = calculateNutritionScore(stats: stats)
        let physicalHealth = calculatePhysicalHealth(stats: stats)
        let mentalWellbeing = calculateMentalWellbeing(stats: stats)
        let energyLevels = calculateEnergyLevels(stats: stats)
        
        let qol = (sleepQuality + nutritionScore + physicalHealth + mentalWellbeing + energyLevels) / 5
        
        return LifestyleMetrics(
            sleepAverage: stats.sleepHours,
            sleepTarget: 8.0,
            nutritionQuality: Double(nutritionScore) / 100.0,
            dailySteps: stats.steps,
            stressLevel: stats.hrv < 30 ? .high : stats.hrv < 50 ? .medium : .low,
            qualityOfLifeScore: qol,
            physicalHealth: physicalHealth,
            mentalWellbeing: mentalWellbeing,
            energyLevels: energyLevels,
            sleepQuality: sleepQuality,
            nutritionScore: nutritionScore
        )
    }
    
    private func calculateNutritionScore(stats: DailyHealthStats) -> Int {
        var score = 0
        
        // Protein (target 180g)
        let proteinScore = min(Int((stats.protein / 180.0) * 100), 100)
        score += proteinScore
        
        // Calorie balance (target 2600)
        let calorieScore = stats.totalCalories > 0 ? min(Int((Double(stats.totalCalories) / 2600.0) * 100), 100) : 50
        score += calorieScore
        
        // Hydration (target 8 glasses)
        let hydrationScore = min(Int((stats.water / 8.0) * 100), 100)
        score += hydrationScore
        
        return score / 3
    }
    
    private func calculatePhysicalHealth(stats: DailyHealthStats) -> Int {
        var score = 0
        
        // Steps (target 10000)
        let stepScore = min(Int((Double(stats.steps) / 10000.0) * 100), 100)
        score += stepScore
        
        // Active calories (target 600)
        let calorieScore = min(Int((Double(stats.activeCalories) / 600.0) * 100), 100)
        score += calorieScore
        
        // Resting HR (lower is better, 60 is optimal)
        let hrScore = stats.restingHeartRate > 0 ? max(100 - Int((stats.restingHeartRate - 60) * 2), 0) : 70
        score += hrScore
        
        return score / 3
    }
    
    private func calculateMentalWellbeing(stats: DailyHealthStats) -> Int {
        var score = 70 // Base score
        
        // HRV (higher is better, 50+ is good)
        if stats.hrv > 0 {
            score = min(Int(stats.hrv * 1.5), 100)
        }
        
        // Sleep quality bonus
        if stats.sleepHours >= 7.5 {
            score = min(score + 10, 100)
        }
        
        return score
    }
    
    private func calculateEnergyLevels(stats: DailyHealthStats) -> Int {
        var score = 0
        
        // Sleep impact (40% weight)
        let sleepScore = Int((stats.sleepHours / 8.0) * 100)
        score += Int(Double(sleepScore) * 0.4)
        
        // Nutrition impact (30% weight)
        let nutritionScore = calculateNutritionScore(stats: stats)
        score += Int(Double(nutritionScore) * 0.3)
        
        // Activity impact (30% weight)
        let activityScore = min(Int((Double(stats.steps) / 10000.0) * 100), 100)
        score += Int(Double(activityScore) * 0.3)
        
        return min(score, 100)
    }

    private func fetchRecommendations() async throws -> [AIRecommendation] {
        var recommendations: [AIRecommendation] = []
        
        // Generate personalized recommendations based on real data
        if let stats = healthStats {
            // Protein recommendation
            if stats.protein < 150 {
                let deficit = Int(180 - stats.protein)
                recommendations.append(AIRecommendation(
                    title: "Increase protein by \(deficit)g",
                    description: "You've consumed \(Int(stats.protein))g today. Add \(deficit)g to hit your 180g target — try Greek yogurt or chicken.",
                    impact: .high,
                    category: .nutrition
                ))
            }
            
            // Sleep recommendation
            if stats.sleepHours < 7.5 {
                let deficit = 8.0 - stats.sleepHours
                recommendations.append(AIRecommendation(
                    title: "Add \(String(format: "%.1f", deficit)) hours of sleep",
                    description: "Last night: \(String(format: "%.1f", stats.sleepHours))h. Deep sleep improves by 18% when you hit 8 hours.",
                    impact: .high,
                    category: .sleep
                ))
            }
            
            // HRV/Recovery recommendation
            if stats.hrv < 40 {
                recommendations.append(AIRecommendation(
                    title: "Priority: Recovery",
                    description: "HRV is \(Int(stats.hrv))ms (low). Consider mobility work, meditation, or a rest day.",
                    impact: .high,
                    category: .wellbeing
                ))
            }
            
            // Steps recommendation
            if stats.steps < 8000 {
                let deficit = 10000 - stats.steps
                recommendations.append(AIRecommendation(
                    title: "Boost movement by \(deficit.formatted()) steps",
                    description: "Currently at \(stats.steps.formatted()) steps. A 15-min walk adds ~2,000 steps.",
                    impact: .medium,
                    category: .fitness
                ))
            }
        }
        
        // Add baseline recommendations if none generated
        if recommendations.isEmpty {
            return AIRecommendation.sampleRecommendations
        }
        
        return recommendations
    }
}

// MARK: - Lifestyle Segments

enum LifestyleSegment: Int, CaseIterable {
    case aiOptimization, restaurants, nutrition, wellbeing
    var title: String {
        switch self {
        case .aiOptimization: return "AI Optimize"
        case .restaurants:    return "Restaurants"
        case .nutrition:      return "Nutrition"
        case .wellbeing:      return "Wellbeing"
        }
    }
    var icon: String {
        switch self {
        case .aiOptimization: return "sparkles"
        case .restaurants:    return "fork.knife"
        case .nutrition:      return "chart.pie.fill"
        case .wellbeing:      return "heart.fill"
        }
    }
}

// MARK: - Root View

struct LifestyleView: View {
    @EnvironmentObject var store: AppStore
    @StateObject private var vm = LifestyleViewModel()
    @StateObject private var locationLogger = LocationMealLogger()
    @State private var selectedSegment: LifestyleSegment = .aiOptimization
    @State private var showInsights = false
    @Namespace private var segmentNS

    var body: some View {
        ZStack {
            // Background — subtle radial haze tuned to selected segment
            LifestyleBackground(segment: selectedSegment)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                LifestyleHeaderView(showInsights: $showInsights, metrics: vm.metrics)
                    .padding(.horizontal, 20)
                    .padding(.top, 60)
                    .padding(.bottom, 16)

                SegmentedPillControl(selected: $selectedSegment, namespace: segmentNS)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)

                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        segmentContent
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 110)
                }
                .refreshable {
                    await vm.refresh()
                    await vm.refreshAIInsights(store: store)
                }
            }

            if showInsights {
                AIInsightsModal(
                    isPresented: $showInsights,
                    recommendations: vm.recommendations,
                    metrics: vm.metrics,
                    stats: vm.healthStats,
                    summary: vm.aiLifeAnalysis,
                    isLive: vm.aiInsightsLive
                )
                    .zIndex(10)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if locationLogger.showConfirmation, let venue = locationLogger.detectedVenue {
                LocationMealConfirmationSheet(
                    venue: venue,
                    items: locationLogger.detectedItems,
                    onLog: { item in locationLogger.logSelectedMeal(item, to: vm) },
                    onDismiss: { locationLogger.showConfirmation = false }
                )
                .zIndex(11)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showInsights)
        // Single load point — fixes double-call bug
        .task {
            await vm.load()
            await vm.refreshAIInsights(store: store)
        }
        .onChange(of: vm.metrics.qualityOfLifeScore) { _, _ in vm.syncAriaContext() }
        .onChange(of: vm.recommendations.count) { _, _ in vm.syncAriaContext() }
        .alert("Error", isPresented: .constant(vm.error != nil), presenting: vm.error) { _ in
            Button("OK") {}
        } message: { err in Text(err.localizedDescription) }
    }

    @ViewBuilder
    private var segmentContent: some View {
        switch selectedSegment {
        case .aiOptimization: AIOptimizationContent(vm: vm, locationLogger: locationLogger)
        case .restaurants:    NutritionDatabaseView(vm: vm)
        case .nutrition:      DailyNutritionView(vm: vm)
        case .wellbeing:      WellbeingView(vm: vm)
        }
    }
}

// MARK: - Dynamic Background

struct LifestyleBackground: View {
    let segment: LifestyleSegment
    @State private var phase = false

    private var accentColor: Color {
        switch segment {
        case .aiOptimization: return .ember
        case .restaurants:    return .steel
        case .nutrition:      return Color.amberLight
        case .wellbeing:      return .success
        }
    }

    var body: some View {
        ZStack {
            Color.background
            LinearGradient(
                colors: [accentColor.opacity(phase ? 0.06 : 0.03), .clear],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 4).repeatForever(autoreverses: true)) { phase = true }
        }
        .animation(.easeInOut(duration: 0.8), value: segment)
    }
}

// MARK: - Header

struct LifestyleHeaderView: View {
    @Binding var showInsights: Bool
    let metrics: LifestyleMetrics
    @State private var appeared = false

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 5) {
                Text("LIFESTYLE")
                    .font(.forgeDynamic(size: 11, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(3)
                Text("Optimization")
                    .font(.forgeDynamic(size: 34, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            Spacer()

            // QOL score chip + AI button
            HStack(spacing: 12) {
                VStack(spacing: 2) {
                    Text("\(metrics.qualityOfLifeScore)")
                        .font(.forgeDynamic(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("QOL")
                        .font(.forgeDynamic(size: 9, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1.5)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.surface)
                .cornerRadius(14)
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.ember.opacity(0.3), lineWidth: 1))
                .shadow(color: .black.opacity(0.05), radius: 6, y: 3)

                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { showInsights = true }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    ZStack {
                        Circle().fill(Color.ember.opacity(0.15)).frame(width: 46, height: 46)
                        Image(systemName: "sparkles")
                            .font(.forgeDynamic(size: 18, weight: .semibold))
                            .foregroundColor(.ember)
                    }
                }
                .shadow(color: Color.ember.opacity(0.2), radius: 8, y: 4)
            }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : -12)
        .onAppear { withAnimation(.spring(response: 0.55, dampingFraction: 0.78).delay(0.05)) { appeared = true } }
    }
}

// MARK: - Segmented Control with matchedGeometryEffect

struct SegmentedPillControl: View {
    @Binding var selected: LifestyleSegment
    let namespace: Namespace.ID

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LifestyleSegment.allCases, id: \.self) { seg in
                    Button {
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.75)) { selected = seg }
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: seg.icon)
                                .font(.forgeDynamic(size: 12, weight: .semibold))
                            Text(seg.title)
                                .font(.forgeDynamic(size: 13, weight: .semibold))
                        }
                        .foregroundColor(selected == seg ? .white : .textTertiary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background {
                            if selected == seg {
                                Capsule()
                                    .fill(Color.ember)
                                    .matchedGeometryEffect(id: "pill", in: namespace)
                                    .shadow(color: Color.ember.opacity(0.45), radius: 10, y: 4)
                            } else {
                                Capsule().fill(Color.surface.opacity(0.6))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(seg.title)
                    .accessibilityAddTraits(selected == seg ? [.isButton, .isSelected] : .isButton)
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - AI Optimization Content

struct AIOptimizationContent: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var vm: LifestyleViewModel
    @ObservedObject var locationLogger: LocationMealLogger

    var body: some View {
        LazyVStack(spacing: 20) {
            LocationQuickLogCard(locationLogger: locationLogger, vm: vm)
            TodaysFocusCard(vm: vm)
            
            // NEW: Real-time HealthKit Dashboard
            if let stats = vm.healthStats {
                LiveHealthDashboard(stats: stats, trends: vm.weeklyTrends)
            }
            
            // NEW: AI Workout Suggestions
            if !vm.aiWorkouts.isEmpty {
                AIWorkoutSuggestionsCard(workouts: vm.aiWorkouts)
            }
            
            MultiArcQOLCard(metrics: vm.metrics)
            QOLTrendCard(history: vm.qolHistory)
            AILifeAnalysisCard(metrics: vm.metrics, analysis: vm.aiLifeAnalysis, isLive: vm.aiInsightsLive)
            AIRecommendationsCard(recommendations: vm.recommendations, store: store)
            OptimizationGoalsCard(vm: vm)
            
            // NEW: Recovery & Performance
            if let stats = vm.healthStats {
                RecoveryMetricsCard(stats: stats)
            }
        }
    }
}

// MARK: - Location Quick Log

struct LocationQuickLogCard: View {
    @ObservedObject var locationLogger: LocationMealLogger
    @ObservedObject var vm: LifestyleViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "location.fill")
                    .font(.forgeDynamic(size: 18))
                    .foregroundColor(.ember)
                Text("Quick Location Log")
                    .font(.forgeDynamic(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
            }

            Text("Detect nearby restaurants and log meals in one tap. Uses your location and Apple Maps POI data.")
                .font(.forgeDynamic(size: 14))
                .foregroundColor(.textSecondary)
                .lineSpacing(4)

            Button {
                Task { await locationLogger.detectCurrentLocationAndLog() }
            } label: {
                HStack {
                    if locationLogger.isDetectingLocation {
                        ProgressView().tint(.white)
                        Text("Detecting location...")
                    } else {
                        Image(systemName: "location.circle.fill")
                        Text("Detect Current Location & Log Meal")
                    }
                }
                .font(.forgeDynamic(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(LinearGradient.emberGradient)
                .cornerRadius(14)
            }
            .disabled(locationLogger.isDetectingLocation)

            if let error = locationLogger.errorMessage {
                Text(error)
                    .font(.forgeDynamic(size: 13))
                    .foregroundColor(.danger)
            }
        }
        .padding(20)
        .background(Color.surface)
        .cornerRadius(20)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
    }
}

struct LocationMealConfirmationSheet: View {
    let venue: String
    let items: [MenuItem]
    let onLog: (MenuItem) -> Void
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture(perform: onDismiss)

            VStack(spacing: 0) {
                Spacer()
                VStack(alignment: .leading, spacing: 18) {
                    Capsule()
                        .fill(Color.textTertiary.opacity(0.4))
                        .frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Nearby Match")
                                .font(.forgeDynamic(size: 11, weight: .black))
                                .foregroundColor(.textTertiary)
                                .tracking(1.5)
                            Text(venue)
                                .font(.forgeDynamic(size: 24, weight: .bold))
                                .foregroundColor(.textPrimary)
                        }
                        Spacer()
                        Button(action: onDismiss) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.forgeDynamic(size: 26))
                                .foregroundColor(.textTertiary)
                                .accessibilityLabel("Close")
                        }
                    }

                    Text("Select what you ate to log macros to HealthKit.")
                        .font(.forgeDynamic(size: 13))
                        .foregroundColor(.textSecondary)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            ForEach(items) { item in
                                Button { onLog(item) } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(item.name)
                                                .font(.forgeDynamic(size: 14, weight: .semibold))
                                                .foregroundColor(.textPrimary)
                                            Text("\(item.calories) cal · \(item.protein)g protein")
                                                .font(.forgeDynamic(size: 12))
                                                .foregroundColor(.textTertiary)
                                        }
                                        Spacer()
                                        Image(systemName: "plus.circle.fill")
                                            .foregroundColor(.ember)
                                    }
                                    .padding(14)
                                    .background(Color.surfaceElevated)
                                    .cornerRadius(12)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .frame(maxHeight: 280)
                }
                .padding(22)
                .background(Color.surface)
                .cornerRadius(28, corners: [.topLeft, .topRight])
            }
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

// MARK: - Today's Focus Card (Award-Winning Feature)

struct TodaysFocusCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false
    
    private var focusArea: (title: String, icon: String, priority: String, action: String, color: Color, gradient: [Color]) {
        guard let stats = vm.healthStats else {
            return ("Start Your Day", "sun.max.fill", "Morning Routine", "Log your first meal", .ember, [.ember, .ember.opacity(0.7)])
        }
        
        // AI decision tree for daily focus
        if stats.hrv < 30 {
            return ("Recovery Focus", "heart.circle.fill", "Critical", "Take an active recovery day", .danger, [.danger, Color(hex: "FF6B6B")])
        }
        
        if stats.sleepHours < 6.5 {
            return ("Sleep Priority", "moon.zzz.fill", "High", "Aim for 8+ hours tonight", Color.violet, [Color.violet, Color(hex: "C77DFF")])
        }
        
        if stats.protein < 120 {
            let remaining = Int(180 - stats.protein)
            return ("Protein Deficit", "fork.knife.circle.fill", "High", "Add \(remaining)g protein today", .ember, [.ember, Color.amberLight])
        }
        
        if stats.steps < 5000 {
            return ("Movement Goal", "figure.walk.circle.fill", "Medium", "Hit 10K steps today", .steel, [.steel, .success])
        }
        
        if stats.water < 6 {
            return ("Hydration Check", "drop.circle.fill", "Medium", "Drink more water", Color(hex: "4A9EFF"), [Color(hex: "4A9EFF"), Color(hex: "00D4FF")])
        }
        
        return ("Peak Performance", "bolt.circle.fill", "Ready", "Crush your workout", .success, [.success, Color(hex: "00FF88")])
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Animated gradient header
            ZStack(alignment: .topLeading) {
                // Background gradient
                LinearGradient(
                    colors: focusArea.gradient + [focusArea.gradient.first!.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    LinearGradient(
                        colors: [.white.opacity(0.15), .clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                
                // Animated particles
                TimelineView(.animation(minimumInterval: 2)) { timeline in
                    Canvas { context, size in
                        let now = timeline.date.timeIntervalSinceReferenceDate
                        for i in 0..<8 {
                            let x = (CGFloat(i) / 8.0) * size.width + CGFloat(sin(now * 0.5 + Double(i))) * 30
                            let y = (CGFloat(i % 3) / 3.0) * size.height + CGFloat(cos(now * 0.3 + Double(i))) * 20
                            let opacity = 0.1 + abs(sin(now + Double(i))) * 0.2
                            
                            context.opacity = opacity
                            context.fill(
                                Circle().path(in: CGRect(x: x, y: y, width: 4, height: 4)),
                                with: .color(.white)
                            )
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 16) {
                    // Priority badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.white.opacity(0.9))
                            .frame(width: 6, height: 6)
                            .shadow(color: .white.opacity(0.6), radius: 4)
                        Text(focusArea.priority.uppercased())
                            .font(.forgeDynamic(size: 10, weight: .black))
                            .foregroundColor(.white)
                            .tracking(1.5)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.white.opacity(0.2))
                    .cornerRadius(20)
                    .overlay(
                        Capsule()
                            .stroke(.white.opacity(0.3), lineWidth: 1)
                    )
                    
                    // Main content
                    HStack(spacing: 16) {
                        ZStack {
                            Circle()
                                .fill(.white.opacity(0.2))
                                .frame(width: 70, height: 70)
                            Circle()
                                .fill(.white.opacity(0.1))
                                .frame(width: 70, height: 70)
                                .blur(radius: 8)
                            
                            Image(systemName: focusArea.icon)
                                .font(.forgeDynamic(size: 32, weight: .semibold))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                        }
                        .scaleEffect(appeared ? 1 : 0.7)
                        .animation(.spring(response: 0.6, dampingFraction: 0.65).delay(0.1), value: appeared)
                        
                        VStack(alignment: .leading, spacing: 6) {
                            Text("TODAY'S FOCUS")
                                .font(.forgeDynamic(size: 11, weight: .black))
                                .foregroundColor(.white.opacity(0.8))
                                .tracking(2)
                            
                            Text(focusArea.title)
                                .font(.forgeDynamic(size: 24, weight: .black))
                                .foregroundColor(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                            
                            Text(focusArea.action)
                                .font(.forgeDynamic(size: 14, weight: .semibold))
                                .foregroundColor(.white.opacity(0.9))
                        }
                    }
                }
                .padding(24)
            }
            .frame(height: 180)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            
            // Quick action button
            Button {
                // Navigate to relevant section
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.right.circle.fill")
                        .font(.forgeDynamic(size: 18, weight: .bold))
                    Text("Take Action")
                        .font(.forgeDynamic(size: 16, weight: .bold))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.forgeDynamic(size: 14, weight: .semibold))
                }
                .foregroundColor(focusArea.color)
                .padding(18)
                .background(focusArea.color.opacity(0.1))
                .cornerRadius(16)
            }
            .padding(16)
            .background(Color.surface)
        }
        .background(Color.surface)
        .cornerRadius(24)
        .shadow(color: focusArea.color.opacity(0.2), radius: 20, y: 10)
        .onAppear { appeared = true }
    }
}

// MARK: - Live Health Dashboard (HealthKit Integration)

struct LiveHealthDashboard: View {
    let stats: DailyHealthStats
    let trends: [WeeklyHealthTrend]
    @State private var appeared = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with live indicator
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color.success.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "heart.text.square.fill")
                        .font(.forgeDynamic(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient(colors: [.success, .ember], startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text("Live Health Data")
                            .font(.forgeDynamic(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        // Pulsing live indicator
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.success)
                                .frame(width: 6, height: 6)
                                .overlay(
                                    Circle()
                                        .stroke(Color.success.opacity(0.3), lineWidth: 2)
                                        .scaleEffect(appeared ? 1.5 : 1)
                                        .opacity(appeared ? 0 : 1)
                                        .animation(.easeOut(duration: 1.2).repeatForever(autoreverses: false), value: appeared)
                                )
                            Text("LIVE")
                                .font(.forgeDynamic(size: 10, weight: .black))
                                .foregroundColor(.success)
                                .tracking(1)
                        }
                    }
                    Text("Powered by HealthKit")
                        .font(.forgeDynamic(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 4)
            
            // Today's Key Metrics
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                HealthMetricTile(
                    icon: "figure.walk",
                    label: "Steps",
                    value: "\(stats.steps.formatted())",
                    target: "10,000",
                    progress: Double(stats.steps) / 10000.0,
                    color: .steel,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "flame.fill",
                    label: "Active Cal",
                    value: "\(stats.activeCalories)",
                    target: "600",
                    progress: Double(stats.activeCalories) / 600.0,
                    color: .ember,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "moon.zzz.fill",
                    label: "Sleep",
                    value: String(format: "%.1fh", stats.sleepHours),
                    target: "8h",
                    progress: stats.sleepHours / 8.0,
                    color: Color.violet,
                    appeared: appeared
                )
                
                HealthMetricTile(
                    icon: "waveform.path.ecg",
                    label: "HRV",
                    value: "\(Int(stats.hrv))",
                    target: "50+",
                    progress: stats.hrv / 50.0,
                    color: .success,
                    appeared: appeared
                )

                // Cardio fitness — surfaced from HealthKit, previously unused
                if stats.vo2Max > 0 {
                    HealthMetricTile(
                        icon: "lungs.fill",
                        label: "VO₂ Max",
                        value: String(format: "%.0f", stats.vo2Max),
                        target: "50",
                        progress: stats.vo2Max / 50.0,
                        color: Color(hex: "FF6B9D"),
                        appeared: appeared
                    )
                }

                if stats.exerciseMinutes > 0 {
                    HealthMetricTile(
                        icon: "figure.run",
                        label: "Exercise",
                        value: "\(Int(stats.exerciseMinutes))m",
                        target: "30m",
                        progress: stats.exerciseMinutes / 30.0,
                        color: Color.amberLight,
                        appeared: appeared
                    )
                }
            }

            // Weekly Trend Chart (Swift Charts — interactive, multi-metric)
            if !trends.isEmpty {
                WeeklyTrendChart(trends: trends)
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .stroke(LinearGradient(
                    colors: [Color.success.opacity(0.3), Color.ember.opacity(0.2)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.08), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

// MARK: - Weekly Trend Chart (Swift Charts)

private enum TrendMetric: String, CaseIterable, Identifiable {
    case steps = "Steps"
    case activeCalories = "Active"
    case sleep = "Sleep"
    case hrv = "HRV"
    var id: String { rawValue }

    var color: Color {
        switch self {
        case .steps:          return .steel
        case .activeCalories: return .ember
        case .sleep:          return Color.violet
        case .hrv:            return .success
        }
    }

    func value(_ t: WeeklyHealthTrend) -> Double {
        switch self {
        case .steps:          return Double(t.steps)
        case .activeCalories: return Double(t.activeCalories)
        case .sleep:          return t.sleepHours
        case .hrv:            return t.avgHRV
        }
    }

    func format(_ v: Double) -> String {
        switch self {
        case .steps:          return Int(v).formatted()
        case .activeCalories: return "\(Int(v)) cal"
        case .sleep:          return String(format: "%.1f h", v)
        case .hrv:            return "\(Int(v)) ms"
        }
    }
}

/// Interactive 7-day chart replacing the old steps-only sparkline. Toggles between
/// Steps / Active Cal / Sleep / HRV and supports tap-to-read on any day.
struct WeeklyTrendChart: View {
    let trends: [WeeklyHealthTrend]
    @State private var metric: TrendMetric = .steps
    @State private var selectedDate: Date?

    private var selectedTrend: WeeklyHealthTrend? {
        guard let selectedDate else { return nil }
        return trends.min {
            abs($0.date.timeIntervalSince(selectedDate)) < abs($1.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("7-Day Trends")
                    .font(.forgeDynamic(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                if let t = selectedTrend {
                    Text("\(t.date.formatted(.dateTime.weekday(.abbreviated))) · \(metric.format(metric.value(t)))")
                        .font(.forgeDynamic(size: 11, weight: .bold))
                        .foregroundColor(metric.color)
                        .transition(.opacity)
                }
            }

            Picker("Metric", selection: $metric) {
                ForEach(TrendMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Chart(trends) { t in
                BarMark(
                    x: .value("Day", t.date, unit: .day),
                    y: .value(metric.rawValue, metric.value(t))
                )
                .foregroundStyle(metric.color.gradient)
                .cornerRadius(5)
                .opacity(selectedTrend == nil || selectedTrend?.id == t.id ? 1 : 0.35)
            }
            .chartXSelection(value: $selectedDate)
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                        .font(.forgeDynamic(size: 9))
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine()
                    AxisValueLabel().font(.forgeDynamic(size: 9))
                }
            }
            .frame(height: 150)
            .animation(.easeInOut(duration: 0.25), value: metric)
        }
        .padding(.top, 8)
    }
}

struct HealthMetricTile: View {
    let icon: String
    let label: String
    let value: String
    let target: String
    let progress: Double
    let color: Color
    let appeared: Bool
    
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.forgeDynamic(size: 16))
                    .foregroundColor(color)
                Text(label)
                    .font(.forgeDynamic(size: 11, weight: .semibold))
                    .foregroundColor(.textSecondary)
                Spacer()
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.forgeDynamic(size: 24, weight: .black, design: .rounded))
                    .foregroundColor(.textPrimary)
                Text("/ \(target)")
                    .font(.forgeDynamic(size: 11, weight: .medium))
                    .foregroundColor(.textTertiary)
                Spacer()
            }
            
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.borderColor.opacity(0.3))
                    Capsule()
                        .fill(color)
                        .frame(width: appeared ? geo.size.width * CGFloat(min(progress, 1.0)) : 0)
                        .animation(.spring(response: 1.0, dampingFraction: 0.7).delay(0.2), value: appeared)
                }
            }
            .frame(height: 4)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

// MARK: - AI Workout Suggestions Card

struct AIWorkoutSuggestionsCard: View {
    let workouts: [AIWorkoutSuggestion]
    @State private var appeared = false
    @State private var selectedWorkout: CustomWorkoutPlan?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "figure.strengthtraining.traditional")
                    .font(.forgeDynamic(size: 18, weight: .semibold))
                    .foregroundColor(.ember)
                Text("AI Workout Suggestions")
                    .font(.forgeDynamic(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(workouts.count) ready")
                    .font(.forgeDynamic(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }
            
            VStack(spacing: 12) {
                ForEach(Array(workouts.enumerated()), id: \.element.id) { i, suggestion in
                    AIWorkoutCard(suggestion: suggestion)
                        .opacity(appeared ? 1 : 0)
                        .offset(y: appeared ? 0 : 20)
                        .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(Double(i) * 0.1), value: appeared)
                        .onTapGesture {
                            selectedWorkout = suggestion.workout
                        }
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
        .sheet(item: $selectedWorkout) { workout in
            WorkoutDetailSheet(workout: workout)
        }
    }
}

struct AIWorkoutCard: View {
    let suggestion: AIWorkoutSuggestion
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.ember.opacity(0.12))
                        .frame(width: 50, height: 50)
                    Image(systemName: "dumbbell.fill")
                        .font(.forgeDynamic(size: 22))
                        .foregroundStyle(LinearGradient.emberGradient)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(suggestion.title)
                        .font(.forgeDynamic(size: 16, weight: .bold))
                        .foregroundColor(.textPrimary)
                    HStack(spacing: 8) {
                        Label("\(suggestion.workout.duration) min", systemImage: "clock.fill")
                        Label("\(suggestion.workout.exercises.count) exercises", systemImage: "list.bullet")
                    }
                    .font(.forgeDynamic(size: 11, weight: .medium))
                    .foregroundColor(.textSecondary)
                }
                
                Spacer()
                
                Image(systemName: "arrow.right.circle.fill")
                    .font(.forgeDynamic(size: 24))
                    .foregroundColor(.ember)
            }
            
            Divider().background(Color.borderColor.opacity(0.4))
            
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.forgeDynamic(size: 11))
                    .foregroundColor(.ember)
                Text(suggestion.reason)
                    .font(.forgeDynamic(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                    .lineLimit(2)
            }
        }
        .padding(16)
        .background(Color.surfaceElevated)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.ember.opacity(0.2), lineWidth: 1)
        )
    }
}

// MARK: - Recovery Metrics Card

struct RecoveryMetricsCard: View {
    let stats: DailyHealthStats
    @State private var appeared = false
    
    var recoveryScore: Int {
        var score = 0
        
        // HRV component (40% weight)
        let hrvScore = min(Int(stats.hrv * 1.5), 100)
        score += Int(Double(hrvScore) * 0.4)
        
        // Resting HR component (30% weight)
        let hrScore = stats.restingHeartRate > 0 ? max(100 - Int((stats.restingHeartRate - 60) * 2), 0) : 70
        score += Int(Double(hrScore) * 0.3)
        
        // Sleep component (30% weight)
        let sleepScore = Int((stats.sleepHours / 8.0) * 100)
        score += Int(Double(sleepScore) * 0.3)
        
        return min(score, 100)
    }
    
    var recoveryStatus: (label: String, color: Color) {
        switch recoveryScore {
        case 80...: return ("Excellent", .success)
        case 60..<80: return ("Good", .steel)
        case 40..<60: return ("Moderate", .warning)
        default: return ("Low", .danger)
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(recoveryStatus.color.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "bolt.heart.fill")
                        .font(.forgeDynamic(size: 20, weight: .medium))
                        .foregroundColor(recoveryStatus.color)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("Recovery Status")
                        .font(.forgeDynamic(size: 18, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryStatus.label)
                        .font(.forgeDynamic(size: 13, weight: .semibold))
                        .foregroundColor(recoveryStatus.color)
                }
                Spacer()
                
                // Recovery score ring
                ZStack {
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), lineWidth: 8)
                        .frame(width: 60, height: 60)
                    
                    Circle()
                        .trim(from: 0, to: appeared ? CGFloat(recoveryScore) / 100 : 0)
                        .stroke(recoveryStatus.color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                        .frame(width: 60, height: 60)
                        .rotationEffect(.degrees(-90))
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.2), value: appeared)
                    
                    Text("\(recoveryScore)")
                        .font(.forgeDynamic(size: 20, weight: .black))
                        .foregroundColor(.textPrimary)
                }
            }
            .padding(.bottom, 20)
            
            // Recovery metrics grid
            VStack(spacing: 12) {
                RecoveryMetricRow(
                    icon: "waveform.path.ecg",
                    label: "Heart Rate Variability",
                    value: "\(Int(stats.hrv)) ms",
                    status: stats.hrv > 50 ? "Optimal" : stats.hrv > 30 ? "Good" : "Low",
                    color: stats.hrv > 50 ? .success : stats.hrv > 30 ? .warning : .danger
                )
                
                RecoveryMetricRow(
                    icon: "heart.fill",
                    label: "Resting Heart Rate",
                    value: "\(Int(stats.restingHeartRate)) bpm",
                    status: stats.restingHeartRate < 60 ? "Excellent" : stats.restingHeartRate < 70 ? "Good" : "Elevated",
                    color: stats.restingHeartRate < 60 ? .success : stats.restingHeartRate < 70 ? .steel : .warning
                )
                
                RecoveryMetricRow(
                    icon: "bed.double.fill",
                    label: "Sleep Duration",
                    value: String(format: "%.1f hours", stats.sleepHours),
                    status: stats.sleepHours >= 8 ? "Optimal" : stats.sleepHours >= 7 ? "Good" : "Low",
                    color: stats.sleepHours >= 8 ? .success : stats.sleepHours >= 7 ? .steel : .warning
                )
            }
            
            Divider().background(Color.borderColor.opacity(0.4)).padding(.vertical, 16)
            
            // Training readiness
            HStack(spacing: 12) {
                Image(systemName: recoveryScore > 70 ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.forgeDynamic(size: 18))
                    .foregroundColor(recoveryScore > 70 ? .success : .warning)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(recoveryScore > 70 ? "Ready to Train" : "Consider Active Recovery")
                        .font(.forgeDynamic(size: 14, weight: .bold))
                        .foregroundColor(.textPrimary)
                    Text(recoveryScore > 70 
                         ? "Your body is primed for a hard session"
                         : "Focus on mobility, stretching, or light cardio")
                        .font(.forgeDynamic(size: 12))
                        .foregroundColor(.textSecondary)
                        .lineSpacing(3)
                }
            }
            .padding(14)
            .background(recoveryStatus.color.opacity(0.08))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(recoveryStatus.color.opacity(0.2), lineWidth: 1)
            )
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct RecoveryMetricRow: View {
    let icon: String
    let label: String
    let value: String
    let status: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(color.opacity(0.12)).frame(width: 38, height: 38)
                Image(systemName: icon)
                    .font(.forgeDynamic(size: 16))
                    .foregroundColor(color)
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.forgeDynamic(size: 13, weight: .medium))
                    .foregroundColor(.textSecondary)
                Text(value)
                    .font(.forgeDynamic(size: 15, weight: .bold))
                    .foregroundColor(.textPrimary)
            }
            
            Spacer()
            
            Text(status)
                .font(.forgeDynamic(size: 12, weight: .semibold))
                .foregroundColor(color)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(color.opacity(0.12))
                .cornerRadius(8)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
    }
}

// MARK: - Workout Detail Sheet

struct WorkoutDetailSheet: View {
    let workout: CustomWorkoutPlan
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    // Header stats
                    VStack(alignment: .leading, spacing: 12) {
                        Text(workout.name)
                            .font(.forgeDynamic(size: 28, weight: .bold))
                            .foregroundColor(.textPrimary)
                        
                        HStack(spacing: 16) {
                            StatPill(icon: "clock.fill", value: "\(workout.duration) min", color: .steel)
                            StatPill(icon: "flame.fill", value: "~\(workout.caloriesBurn) cal", color: .ember)
                            StatPill(icon: "list.bullet", value: "\(workout.exercises.count) exercises", color: .success)
                        }
                    }
                    .padding(.horizontal, 20)
                    
                    // Exercise list
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Exercises")
                            .font(.forgeDynamic(size: 20, weight: .bold))
                            .foregroundColor(.textPrimary)
                            .padding(.horizontal, 20)
                        
                        ForEach(Array(workout.exercises.enumerated()), id: \.element.id) { i, exercise in
                            ExerciseRow(index: i + 1, exercise: exercise)
                                .padding(.horizontal, 20)
                        }
                    }
                    
                    // Start workout button
                    Button {
                        // Integration with WorkoutKit would go here
                        dismiss()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "play.fill")
                                .font(.forgeDynamic(size: 16, weight: .bold))
                            Text("Start Workout")
                                .font(.forgeDynamic(size: 17, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.emberGradient)
                        .cornerRadius(16)
                        .shadow(color: Color.ember.opacity(0.4), radius: 12, y: 6)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .padding(.vertical, 24)
            }
            .background(Color.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundColor(.ember)
                        .fontWeight(.semibold)
                }
            }
        }
    }
}

struct StatPill: View {
    let icon: String
    let value: String
    let color: Color
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.forgeDynamic(size: 12))
            Text(value)
                .font(.forgeDynamic(size: 13, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(color.opacity(0.12))
        .cornerRadius(10)
    }
}

struct ExerciseRow: View {
    let index: Int
    let exercise: WorkoutExercise
    
    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.ember.opacity(0.12)).frame(width: 40, height: 40)
                Text("\(index)")
                    .font(.forgeDynamic(size: 16, weight: .bold))
                    .foregroundColor(.ember)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.forgeDynamic(size: 15, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 8) {
                    Text("\(exercise.sets) sets")
                    Text("·")
                    Text("\(exercise.reps) reps")
                    Text("·")
                    Text("\(exercise.restSeconds)s rest")
                }
                .font(.forgeDynamic(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            }
            
            Spacer()
            
            Text(exercise.muscleGroup.rawValue.capitalized)
                .font(.forgeDynamic(size: 11, weight: .semibold))
                .foregroundColor(.textTertiary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.surfaceElevated)
                .cornerRadius(6)
        }
        .padding(14)
        .background(Color.surface)
        .cornerRadius(14)
    }
}

// MARK: - Multi-Arc QOL Card (flagship visual)

struct MultiArcQOLCard: View {
    let metrics: LifestyleMetrics
    @State private var appeared = false

    private let arcs: [(label: String, kp: KeyPath<LifestyleMetrics, Int>, color: Color, radius: CGFloat)] = [
        ("Physical",  \.physicalHealth,  .success,                  96),
        ("Mental",    \.mentalWellbeing, .steel,                    78),
        ("Energy",    \.energyLevels,    .ember,                    60),
        ("Sleep",     \.sleepQuality,    Color.violet,      42),
        ("Nutrition", \.nutritionScore,  Color.amberLight,      24),
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Section label
            HStack {
                Text("QUALITY OF LIFE")
                    .font(.forgeDynamic(size: 10, weight: .black))
                    .foregroundColor(.textTertiary)
                    .tracking(2.5)
                Spacer()
                Text("All dimensions")
                    .font(.forgeDynamic(size: 11, weight: .medium))
                    .foregroundColor(.textMuted)
            }
            .padding(.bottom, 28)

            // Arc visualisation
            ZStack {
                // Background arcs (tracks) -- decorative; the legend grid
                // below already states each dimension's name + number in
                // text, so these unlabeled rings would otherwise present
                // to VoiceOver as 5 indistinguishable stops with no way
                // to tell which is "Sleep" vs "Energy".
                ForEach(Array(arcs.enumerated()), id: \.offset) { i, arc in
                    Circle()
                        .stroke(Color.borderColor.opacity(0.3), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                }
                .accessibilityHidden(true)

                // Progress arcs
                ForEach(Array(arcs.enumerated()), id: \.offset) { i, arc in
                    let value = metrics[keyPath: arc.kp]
                    let progress = appeared ? CGFloat(value) / 100 : 0

                    // Glow
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color.opacity(0.3), style: StrokeStyle(lineWidth: 14, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .blur(radius: 6)

                    // Main arc
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(arc.color, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                        .frame(width: arc.radius * 2, height: arc.radius * 2)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: arc.color.opacity(0.4), radius: 6)
                        .animation(.spring(response: 1.4, dampingFraction: 0.68).delay(0.3 + Double(i) * 0.12), value: appeared)
                }
                .accessibilityHidden(true)

                // Center score
                VStack(spacing: 3) {
                    Text("\(metrics.qualityOfLifeScore)")
                        .font(.forgeDynamic(size: 36, weight: .black, design: .rounded))
                        .foregroundColor(.textPrimary)
                    Text("QOL Score")
                        .font(.forgeDynamic(size: 10, weight: .bold))
                        .foregroundColor(.textTertiary)
                        .tracking(1)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Quality of life score")
                .accessibilityValue("\(metrics.qualityOfLifeScore) out of 100")
            }
            .frame(height: 220)
            .frame(maxWidth: .infinity)
            .padding(.bottom, 28)

            // Legend grid
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(Array(arcs.enumerated()), id: \.offset) { _, arc in
                    let val = metrics[keyPath: arc.kp]
                    ArcLegendItem(label: arc.label, value: val, color: arc.color)
                }
            }
        }
        .padding(24)
        .background(Color.surface)
        .cornerRadius(24)
        .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.borderColor.opacity(0.5), lineWidth: 1))
        .shadow(color: .black.opacity(0.07), radius: 20, y: 8)
        .onAppear { appeared = true }
    }
}

struct ArcLegendItem: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(color).frame(width: 8, height: 8)
                .shadow(color: color.opacity(0.5), radius: 3)
            Text(label)
                .font(.forgeDynamic(size: 12, weight: .medium))
                .foregroundColor(.textSecondary)
            Spacer()
            Text("\(value)")
                .font(.forgeDynamic(size: 13, weight: .bold))
                .foregroundColor(.textPrimary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue("\(value)")
    }
}

// MARK: - AI Life Analysis Card

struct AILifeAnalysisCard: View {
    let metrics: LifestyleMetrics
    var analysis: String? = nil
    var isLive: Bool = false
    @State private var appeared = false
    @State private var expanded = false

    private var rows: [(icon: String, label: String, current: String, optimal: String, status: InsightStatus)] {[
        ("moon.zzz.fill", "Sleep", String(format: "%.1fh avg", metrics.sleepAverage), String(format: "%.0fh target", metrics.sleepTarget), metrics.sleepAverage >= metrics.sleepTarget ? .excellent : metrics.sleepAverage >= metrics.sleepTarget * 0.9 ? .good : .warning),
        ("fork.knife", "Nutrition", "\(Int(metrics.nutritionQuality * 100))% whole foods", "85%+", metrics.nutritionQuality >= 0.85 ? .excellent : metrics.nutritionQuality >= 0.75 ? .good : .warning),
        ("figure.walk", "Movement", "\(metrics.dailySteps.formatted()) steps", "10,000 steps", metrics.dailySteps >= 10000 ? .excellent : metrics.dailySteps >= 8000 ? .good : .warning),
        ("brain.fill", "Stress", metrics.stressLevel.rawValue, "Low", metrics.stressLevel == .low ? .excellent : metrics.stressLevel == .medium ? .warning : .poor),
    ]}

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Color.ember.opacity(0.15)).frame(width: 46, height: 46)
                    Image(systemName: "brain.head.profile")
                        .font(.forgeDynamic(size: 20, weight: .medium))
                        .foregroundStyle(LinearGradient.ember)
                }
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("AI Life Analysis")
                            .font(.forgeDynamic(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        if analysis != nil { liveBadge }
                    }
                    Text("Behavioral pattern analysis")
                        .font(.forgeDynamic(size: 12))
                        .foregroundColor(.textTertiary)
                }
                Spacer()
            }
            .padding(.bottom, 20)

            // Insight rows with left accent bar
            VStack(spacing: 12) {
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    AnalysisInsightRow(
                        icon: row.icon, label: row.label,
                        current: row.current, optimal: row.optimal, status: row.status
                    )
                    .opacity(appeared ? 1 : 0)
                    .offset(x: appeared ? 0 : -20)
                    .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.1 + Double(i) * 0.07), value: appeared)
                }
            }
            .padding(.bottom, 20)

            // Full analysis CTA
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { expanded.toggle() }
            } label: {
                HStack {
                    Image(systemName: "arrow.right.circle.fill").font(.forgeDynamic(size: 14))
                    Text(expanded ? "Hide Full Analysis" : "View Full Analysis").font(.forgeDynamic(size: 14, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.down")
                        .font(.forgeDynamic(size: 12, weight: .semibold))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundColor(.ember)
                .padding(.vertical, 12)
                .padding(.horizontal, 16)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(12)
            }

            if expanded {
                fullAnalysisSection
                    .padding(.top, 14)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }

    private var liveBadge: some View {
        Text(isLive ? "LIVE" : "ARIA")
            .font(.forgeDynamic(size: 8, weight: .black))
            .tracking(0.5)
            .foregroundColor(.ember)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(Color.ember.opacity(0.12))
            .cornerRadius(5)
    }

    @ViewBuilder
    private var fullAnalysisSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles").font(.forgeDynamic(size: 13)).foregroundColor(.ember)
                Text(isLive ? "ARIA's analysis" : "Summary")
                    .font(.forgeDynamic(size: 13, weight: .semibold))
                    .foregroundColor(.textPrimary)
            }
            if let analysis {
                Text(analysis)
                    .font(.forgeDynamic(size: 13))
                    .foregroundColor(.textSecondary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Connect ARIA to unlock a personalized breakdown of how your sleep, nutrition, movement, and stress are interacting today.")
                    .font(.forgeDynamic(size: 13))
                    .foregroundColor(.textTertiary)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

enum InsightStatus {
    case excellent, good, warning, poor
    var color: Color {
        switch self { case .excellent: return .success; case .good: return .steel; case .warning: return .warning; case .poor: return .danger }
    }
}

struct AnalysisInsightRow: View {
    let icon: String
    let label: String
    let current: String
    let optimal: String
    let status: InsightStatus

    var body: some View {
        HStack(spacing: 14) {
            // Colored left accent + icon
            HStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 2)
                    .fill(status.color)
                    .frame(width: 3, height: 40)
                    .padding(.trailing, 10)

                ZStack {
                    Circle().fill(status.color.opacity(0.12)).frame(width: 38, height: 38)
                    Image(systemName: icon)
                        .font(.forgeDynamic(size: 16))
                        .foregroundColor(status.color)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.forgeDynamic(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                HStack(spacing: 5) {
                    Text(current)
                        .font(.forgeDynamic(size: 12, weight: .medium))
                        .foregroundColor(.textSecondary)
                    Image(systemName: "arrow.right")
                        .font(.forgeDynamic(size: 9))
                        .foregroundColor(.textMuted)
                    Text(optimal)
                        .font(.forgeDynamic(size: 12, weight: .medium))
                        .foregroundColor(.textTertiary)
                }
            }

            Spacer()

            // Status dot with glow
            Circle()
                .fill(status.color)
                .frame(width: 10, height: 10)
                .shadow(color: status.color.opacity(0.6), radius: 5)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
    }
}

// MARK: - AI Recommendations Card (glowing accent borders)

struct AIRecommendationsCard: View {
    let recommendations: [AIRecommendation]
    @ObservedObject var store: AppStore
    @State private var appeared = false

    private var ariaPrompt: String {
        if let top = recommendations.first {
            return "Based on my lifestyle data, help me act on this: \(top.title). \(top.description)"
        }
        return "Review my lifestyle optimization metrics and suggest one high-impact change for today."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "lightbulb.fill")
                    .font(.forgeDynamic(size: 18))
                    .foregroundColor(.ember)
                Text("AI Recommendations")
                    .font(.forgeDynamic(size: 18, weight: .bold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(recommendations.count) active")
                    .font(.forgeDynamic(size: 11, weight: .semibold))
                    .foregroundColor(.ember)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Color.ember.opacity(0.12))
                    .cornerRadius(8)
            }

            Button {
                store.openChat(with: ariaPrompt)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                    Text("Ask ARIA to optimize")
                        .font(.forgeDynamic(size: 13, weight: .semibold))
                }
                .foregroundColor(.ember)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.ember.opacity(0.1))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)

            if recommendations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.forgeDynamic(size: 44)).foregroundColor(.success.opacity(0.6))
                    Text("You're doing great! No new recommendations.")
                        .font(.forgeDynamic(size: 14)).foregroundColor(.textSecondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 24)
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(recommendations.enumerated()), id: \.element.id) { i, rec in
                        RecommendationCard(recommendation: rec)
                            .opacity(appeared ? 1 : 0)
                            .offset(y: appeared ? 0 : 16)
                            .animation(.spring(response: 0.5, dampingFraction: 0.76).delay(0.05 + Double(i) * 0.08), value: appeared)
                    }
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct RecommendationCard: View {
    let recommendation: AIRecommendation
    @State private var expanded = false

    var body: some View {
        HStack(spacing: 0) {
            // Glowing left border — the signature visual
            RoundedRectangle(cornerRadius: 3)
                .fill(recommendation.impact.color)
                .frame(width: 4)
                .shadow(color: recommendation.impact.color.opacity(0.7), radius: 6)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 0) {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) { expanded.toggle() }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            HStack(spacing: 6) {
                                Image(systemName: recommendation.category.icon)
                                    .font(.forgeDynamic(size: 11))
                                    .foregroundColor(recommendation.impact.color)
                                Text(recommendation.category.rawValue.uppercased())
                                    .font(.forgeDynamic(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                    .tracking(1.5)
                            }
                            Spacer()
                            HStack(spacing: 4) {
                                Text(recommendation.impact.rawValue)
                                    .font(.forgeDynamic(size: 10, weight: .bold))
                                    .foregroundColor(recommendation.impact.color)
                                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                                    .font(.forgeDynamic(size: 10, weight: .semibold))
                                    .foregroundColor(.textMuted)
                            }
                        }

                        Text(recommendation.title)
                            .font(.forgeDynamic(size: 14, weight: .semibold))
                            .foregroundColor(.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if expanded {
                            Text(recommendation.description)
                                .font(.forgeDynamic(size: 13))
                                .foregroundColor(.textSecondary)
                                .lineSpacing(4)
                                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                        }
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
            }
        }
        .background(recommendation.impact.color.opacity(0.05))
        .cornerRadius(14)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(recommendation.impact.color.opacity(0.18), lineWidth: 1)
        )
    }
}

// MARK: - Optimization Goals Card (fixed animate-on-appear)

struct OptimizationGoalsCard: View {
    @ObservedObject var vm: LifestyleViewModel
    @State private var appeared = false

    // Derived from live HealthKit data (was a hardcoded array).
    private var goals: [(title: String, progress: Double, current: String, target: String, color: Color)] {
        let m = vm.metrics
        let protein = Int(vm.healthStats?.protein ?? 0)
        let mindfulWeek = vm.mindfulMinutesWeek
        let stressProgress: Double = {
            switch m.stressLevel {
            case .low: return 1.0
            case .medium: return 0.6
            case .high: return 0.3
            }
        }()
        return [
            ("Sleep → 8h", min(m.sleepAverage / 8.0, 1.0),
             String(format: "%.1fh avg", m.sleepAverage), "8h", Color.violet),
            ("Lower stress", stressProgress,
             m.stressLevel.rawValue, "Low", .warning),
            ("Daily protein 180g", min(Double(protein) / 180.0, 1.0),
             "\(protein)g", "180g", .ember),
            ("Mindfulness 70 min/wk", min(Double(mindfulWeek) / 70.0, 1.0),
             "\(mindfulWeek) min", "70 min", .steel),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Optimization Goals")
                .font(.forgeDynamic(size: 18, weight: .bold))
                .foregroundColor(.textPrimary)

            VStack(spacing: 12) {
                ForEach(Array(goals.enumerated()), id: \.offset) { i, goal in
                    GoalProgressItem(
                        title: goal.title, progress: goal.progress,
                        current: goal.current, target: goal.target,
                        color: goal.color, appeared: appeared, index: i
                    )
                }
            }
        }
        .padding(22)
        .background(Color.surface)
        .cornerRadius(22)
        .shadow(color: .black.opacity(0.06), radius: 16, y: 6)
        .onAppear { appeared = true }
    }
}

struct GoalProgressItem: View {
    let title: String
    let progress: Double
    let current: String
    let target: String
    let color: Color
    let appeared: Bool
    let index: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(title)
                    .font(.forgeDynamic(size: 14, weight: .semibold))
                    .foregroundColor(.textPrimary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.forgeDynamic(size: 13, weight: .bold))
                    .foregroundColor(color)
            }
            HStack(spacing: 6) {
                Text(current)
                    .font(.forgeDynamic(size: 12, weight: .medium))
                    .foregroundColor(.textSecondary)
                Image(systemName: "arrow.right")
                    .font(.forgeDynamic(size: 10)).foregroundColor(.textMuted)
                Text(target)
                    .font(.forgeDynamic(size: 12, weight: .semibold))
                    .foregroundColor(color)
            }
            // Responsive animated progress bar (fixed hardcoded-points bug)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.borderColor.opacity(0.3))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(LinearGradient(
                            colors: [color, color.opacity(0.7)],
                            startPoint: .leading, endPoint: .trailing
                        ))
                        .frame(width: appeared ? geo.size.width * CGFloat(progress) : 0)
                        .animation(.spring(response: 1.2, dampingFraction: 0.7).delay(0.4 + Double(index) * 0.1), value: appeared)
                }
            }
            .frame(height: 6)
        }
        .padding(14)
        .background(Color.surfaceElevated)
        .cornerRadius(14)
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(color.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Helpers

// Note: cornerRadius(_:corners:) extension is defined earlier in the file

// MARK: - Restaurant Data

let popularRestaurants: [Restaurant] = [
    Restaurant(name: "Raising Cane's", logo: "🍗", items: [
        MenuItem(name: "Box Combo (4 tenders)",    calories: 1220, protein: 56, carbs: 120, fat: 55, serving: "1 combo",   isHealthy: false),
        MenuItem(name: "Chicken Finger (1 piece)", calories: 130,  protein: 10, carbs: 8,   fat: 6,  serving: "1 tender",  isHealthy: true),
        MenuItem(name: "Crinkle Fries",            calories: 390,  protein: 5,  carbs: 50,  fat: 18, serving: "1 order",   isHealthy: false),
        MenuItem(name: "Coleslaw",                 calories: 170,  protein: 2,  carbs: 14,  fat: 13, serving: "1 order",   isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "McDonald's", logo: "🍔", items: [
        MenuItem(name: "Egg McMuffin",             calories: 310, protein: 17, carbs: 30, fat: 13, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Grilled Chicken Sandwich", calories: 380, protein: 37, carbs: 44, fat: 7,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Big Mac",                  calories: 550, protein: 25, carbs: 45, fat: 30, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "Medium Fries",             calories: 320, protein: 4,  carbs: 43, fat: 15, serving: "1 order",    isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Chick-fil-A", logo: "🐔", items: [
        MenuItem(name: "Grilled Nuggets (8-count)",    calories: 130, protein: 25, carbs: 1,  fat: 3,  serving: "8 pieces",  isHealthy: true),
        MenuItem(name: "Grilled Chicken Sandwich",     calories: 320, protein: 30, carbs: 42, fat: 6,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Cobb Salad (Grilled)",         calories: 390, protein: 40, carbs: 28, fat: 14, serving: "1 salad",    isHealthy: true),
        MenuItem(name: "Chicken Sandwich (fried)",     calories: 440, protein: 28, carbs: 41, fat: 19, serving: "1 sandwich", isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "Chipotle", logo: "🌯", items: [
        MenuItem(name: "Chicken Bowl (no rice)",  calories: 320,  protein: 42, carbs: 21,  fat: 8,  serving: "1 bowl",    isHealthy: true),
        MenuItem(name: "Chicken Salad",           calories: 500,  protein: 44, carbs: 36,  fat: 21, serving: "1 salad",   isHealthy: true),
        MenuItem(name: "Chicken Burrito",         calories: 1025, protein: 65, carbs: 123, fat: 30, serving: "1 burrito", isHealthy: false),
        MenuItem(name: "Veggie Bowl",             calories: 430,  protein: 16, carbs: 68,  fat: 12, serving: "1 bowl",    isHealthy: true),
    ], category: .mexican),

    Restaurant(name: "Subway", logo: "🥖", items: [
        MenuItem(name: "6\" Turkey Breast",  calories: 280, protein: 18, carbs: 46, fat: 4,  serving: "6 inch", isHealthy: true),
        MenuItem(name: "Grilled Chicken Salad", calories: 130, protein: 19, carbs: 10, fat: 3, serving: "1 salad", isHealthy: true),
        MenuItem(name: "6\" Veggie Delite",  calories: 230, protein: 9,  carbs: 44, fat: 3,  serving: "6 inch", isHealthy: true),
        MenuItem(name: "6\" Spicy Italian",  calories: 480, protein: 21, carbs: 46, fat: 24, serving: "6 inch", isHealthy: false),
    ], category: .healthy),

    Restaurant(name: "Panera Bread", logo: "🥗", items: [
        MenuItem(name: "Green Goddess Cobb Salad", calories: 550, protein: 42, carbs: 23, fat: 33, serving: "1 salad", isHealthy: true),
        MenuItem(name: "Chicken Noodle Soup",      calories: 90,  protein: 7,  carbs: 10, fat: 3,  serving: "1 cup",  isHealthy: true),
        MenuItem(name: "Mediterranean Grain Bowl", calories: 430, protein: 16, carbs: 48, fat: 21, serving: "1 bowl", isHealthy: true),
        MenuItem(name: "Turkey Bravo Sandwich",    calories: 830, protein: 44, carbs: 76, fat: 37, serving: "1 item", isHealthy: false),
    ], category: .healthy),

    Restaurant(name: "Taco Bell", logo: "🌮", items: [
        MenuItem(name: "Chicken Power Bowl",  calories: 470, protein: 26, carbs: 50, fat: 19, serving: "1 bowl",  isHealthy: true),
        MenuItem(name: "Fresco Crunchy Taco", calories: 140, protein: 7,  carbs: 13, fat: 7,  serving: "1 taco",  isHealthy: true),
        MenuItem(name: "Crunchwrap Supreme",  calories: 530, protein: 16, carbs: 71, fat: 21, serving: "1 item",  isHealthy: false),
        MenuItem(name: "Black Beans",         calories: 80,  protein: 5,  carbs: 14, fat: 0,  serving: "1 side",  isHealthy: true),
    ], category: .mexican),

    Restaurant(name: "Wendy's", logo: "🍔", items: [
        MenuItem(name: "Grilled Chicken Sandwich",       calories: 350, protein: 35, carbs: 37, fat: 8,  serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Southwest Avocado Salad",        calories: 540, protein: 43, carbs: 32, fat: 27, serving: "1 salad",    isHealthy: true),
        MenuItem(name: "Dave's Single",                  calories: 590, protein: 30, carbs: 39, fat: 34, serving: "1 burger",   isHealthy: false),
        MenuItem(name: "10 Piece Chicken Nuggets",       calories: 450, protein: 23, carbs: 31, fat: 27, serving: "10 pieces",  isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Whataburger", logo: "🍔", items: [
        MenuItem(name: "Whataburger (Single)", calories: 590, protein: 29, carbs: 62, fat: 27, serving: "1 burger", isHealthy: false),
        MenuItem(name: "Grilled Chicken Sandwich", calories: 430, protein: 32, carbs: 48, fat: 12, serving: "1 sandwich", isHealthy: true),
        MenuItem(name: "Apple & Cranberry Chicken Salad", calories: 390, protein: 34, carbs: 28, fat: 14, serving: "1 salad", isHealthy: true),
    ], category: .burgers),

    Restaurant(name: "Sweetgreen", logo: "🥗", items: [
        MenuItem(name: "Harvest Bowl", calories: 685, protein: 31, carbs: 71, fat: 32, serving: "1 bowl", isHealthy: true),
        MenuItem(name: "Kale Caesar", calories: 430, protein: 18, carbs: 24, fat: 30, serving: "1 salad", isHealthy: true),
        MenuItem(name: "Chicken Pesto Parm", calories: 525, protein: 36, carbs: 42, fat: 24, serving: "1 bowl", isHealthy: true),
    ], category: .healthy),

    Restaurant(name: "Wingstop", logo: "🍗", items: [
        MenuItem(name: "Classic Wings (6 pc)", calories: 480, protein: 42, carbs: 8, fat: 32, serving: "6 pieces", isHealthy: false),
        MenuItem(name: "Boneless Wings (8 pc)", calories: 520, protein: 38, carbs: 32, fat: 28, serving: "8 pieces", isHealthy: false),
        MenuItem(name: "Lemon Pepper Wings (6 pc)", calories: 500, protein: 40, carbs: 10, fat: 34, serving: "6 pieces", isHealthy: false),
    ], category: .chicken),

    Restaurant(name: "In-N-Out Burger", logo: "🍔", items: [
        MenuItem(name: "Protein Style Burger", calories: 330, protein: 18, carbs: 11, fat: 25, serving: "1 burger", isHealthy: true),
        MenuItem(name: "Grilled Cheese", calories: 380, protein: 15, carbs: 39, fat: 19, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "Double-Double", calories: 670, protein: 37, carbs: 39, fat: 41, serving: "1 burger", isHealthy: false),
    ], category: .burgers),

    Restaurant(name: "Starbucks", logo: "☕️", items: [
        MenuItem(name: "Egg White & Roasted Red Pepper Egg Bites", calories: 170, protein: 12, carbs: 11, fat: 8, serving: "2 bites", isHealthy: true),
        MenuItem(name: "Spinach Feta Wrap", calories: 290, protein: 19, carbs: 34, fat: 10, serving: "1 wrap", isHealthy: true),
        MenuItem(name: "Grande Latte (2% milk)", calories: 190, protein: 12, carbs: 18, fat: 7, serving: "16 oz", isHealthy: true),
    ], category: .healthy),

    Restaurant(name: "Cava", logo: "🥙", items: [
        MenuItem(name: "Grilled Chicken Bowl", calories: 610, protein: 42, carbs: 52, fat: 24, serving: "1 bowl", isHealthy: true),
        MenuItem(name: "Greens + Grains Bowl", calories: 520, protein: 18, carbs: 68, fat: 18, serving: "1 bowl", isHealthy: true),
    ], category: .healthy),

    Restaurant(name: "Shake Shack", logo: "🍔", items: [
        MenuItem(name: "Lettuce Wrap ShackBurger", calories: 320, protein: 25, carbs: 6, fat: 22, serving: "1 burger", isHealthy: true),
        MenuItem(name: "Chicken Shack", calories: 550, protein: 33, carbs: 36, fat: 31, serving: "1 sandwich", isHealthy: false),
        MenuItem(name: "ShackBurger (Single)", calories: 530, protein: 28, carbs: 27, fat: 34, serving: "1 burger", isHealthy: false),
    ], category: .burgers),
]

// MARK: - Preview

#Preview {
    LifestyleView()
        .environmentObject(AppStore())
}
