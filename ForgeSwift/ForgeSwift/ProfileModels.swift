import SwiftUI
import ForgeCore

struct AppNotificationSettings: Codable, Equatable {
    var workoutReminders: Bool = true
    var recoveryAlerts: Bool = true
    var weeklySummary: Bool = true
    var lifestyleReminders: Bool = true
}

struct BriefNotificationSettings: Codable, Equatable {
    var morningHour: Int = 6
    var morningMinute: Int = 0
    var eveningHour: Int = 18
    var eveningMinute: Int = 0
}

struct ProgressSummary: Equatable {
    var workoutsCompleted: Int
    var newPRCount: Int
    var recoveryDelta: Double
    var summary: String
}

struct TrainingInsight: Equatable {
    var title: String
    var observation: String
    var recommendation: String
}

enum DataLoadState: Equatable {
    case idle
    case loading
    case loaded
    case failed
}

enum ForgeDates {
    private static let isoFormatter = ISO8601DateFormatter()

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = .current
        formatter.locale = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let displayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    static func parse(_ value: String) -> Date? {
        isoFormatter.date(from: value) ?? dayFormatter.date(from: value)
    }

    static func yyyyMMdd(from date: Date) -> String {
        dayFormatter.string(from: date)
    }

    static func displayDate(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        return displayFormatter.string(from: date)
    }

    static func displayWeekdayDate(_ value: String) -> String {
        guard let date = parse(value) else { return value }
        return weekdayFormatter.string(from: date)
    }

    static func monthYearTitle(for date: Date) -> String {
        monthFormatter.string(from: date)
    }

    static func mondayBasedStartOffset(for date: Date, calendar: Calendar = .current) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        return (weekday + 5) % 7
    }
}

enum ForgePersistence {
    private static let notificationSettingsKey = "forge.notificationSettings"
    private static let briefNotificationSettingsKey = "forge.briefNotificationSettings"
    private static let briefNotificationsEnabledKey = "forge.briefNotificationsEnabled"
    private static let nutritionPreferencesKey = "forge.nutritionPreferences"

    static func loadNotificationSettings() -> AppNotificationSettings {
        load(AppNotificationSettings.self, forKey: notificationSettingsKey) ?? AppNotificationSettings()
    }

    static func saveNotificationSettings(_ settings: AppNotificationSettings) {
        save(settings, forKey: notificationSettingsKey)
    }

    static func loadBriefNotificationSettings() -> BriefNotificationSettings {
        var settings = load(BriefNotificationSettings.self, forKey: briefNotificationSettingsKey)
            ?? BriefNotificationSettings()
        // One-time move off the old 8:00 / 20:00 factory defaults that the
        // broken stepper UI also displayed as stacked digits.
        let migratedKey = "forge.brief.defaults.6am6pm"
        if !UserDefaults.standard.bool(forKey: migratedKey) {
            if settings.morningHour == 8, settings.morningMinute == 0,
               settings.eveningHour == 20, settings.eveningMinute == 0 {
                settings.morningHour = 6
                settings.eveningHour = 18
            }
            UserDefaults.standard.set(true, forKey: migratedKey)
            saveBriefNotificationSettings(settings)
        }
        return settings
    }

    static func saveBriefNotificationSettings(_ settings: BriefNotificationSettings) {
        save(settings, forKey: briefNotificationSettingsKey)
    }

    static func loadBriefNotificationsEnabled() -> Bool {
        guard UserDefaults.standard.object(forKey: briefNotificationsEnabledKey) != nil else { return true }
        return UserDefaults.standard.bool(forKey: briefNotificationsEnabledKey)
    }

    static func saveBriefNotificationsEnabled(_ isEnabled: Bool) {
        UserDefaults.standard.set(isEnabled, forKey: briefNotificationsEnabledKey)
    }

    static func loadNutritionPreferences() -> NutritionPreferences {
        load(NutritionPreferences.self, forKey: nutritionPreferencesKey) ?? NutritionPreferences()
    }

    static func saveNutritionPreferences(_ preferences: NutritionPreferences) {
        save(preferences, forKey: nutritionPreferencesKey)
    }

    private static func load<T: Decodable>(_ type: T.Type, forKey key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func save<T: Encodable>(_ value: T, forKey key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
