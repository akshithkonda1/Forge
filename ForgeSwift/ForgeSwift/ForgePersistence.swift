import Foundation

enum ForgePersistence {
    private static let onboardedKey = "forge.isOnboarded"

    static var isOnboarded: Bool {
        UserDefaults.standard.bool(forKey: onboardedKey)
    }

    static func setOnboarded(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: onboardedKey)
    }

    static func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: onboardedKey)
    }
}