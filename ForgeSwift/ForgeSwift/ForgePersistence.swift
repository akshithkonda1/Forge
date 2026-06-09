import Foundation

enum ForgePersistence {
    private static let onboardedKey = "forge.isOnboarded"
    private static let idTokenKey = "forge.auth.idToken"
    private static let accessTokenKey = "forge.auth.accessToken"
    private static let refreshTokenKey = "forge.auth.refreshToken"
    private static let sleepAlarmsKey = "forge.sleep.alarms"
    private static let wakeSettingsKey = "forge.sleep.wakeSettings"
    private static let sleepSoundMixKey = "forge.sleep.soundMix"
    private static let sleepTimerKey = "forge.sleep.timerMinutes"
    private static let chatGamificationKey = "forge.chat.gamification"

    static var isOnboarded: Bool {
        UserDefaults.standard.bool(forKey: onboardedKey)
    }

    static func setOnboarded(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: onboardedKey)
    }

    static func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: onboardedKey)
    }

    static func saveAuthTokens(idToken: String?, accessToken: String?, refreshToken: String?) {
        let defaults = UserDefaults.standard
        if let idToken { defaults.set(idToken, forKey: idTokenKey) } else { defaults.removeObject(forKey: idTokenKey) }
        if let accessToken { defaults.set(accessToken, forKey: accessTokenKey) } else { defaults.removeObject(forKey: accessTokenKey) }
        if let refreshToken { defaults.set(refreshToken, forKey: refreshTokenKey) } else { defaults.removeObject(forKey: refreshTokenKey) }
    }

    static func loadAuthTokens() -> (id: String?, access: String?, refresh: String?) {
        let defaults = UserDefaults.standard
        return (
            defaults.string(forKey: idTokenKey),
            defaults.string(forKey: accessTokenKey),
            defaults.string(forKey: refreshTokenKey)
        )
    }

    static func clearAuthTokens() {
        saveAuthTokens(idToken: nil, accessToken: nil, refreshToken: nil)
    }

    // MARK: - Sleep

    static func saveSleepAlarms(_ alarms: [ForgeAlarm]) {
        guard let data = try? JSONEncoder().encode(alarms) else { return }
        UserDefaults.standard.set(data, forKey: sleepAlarmsKey)
    }

    static func loadSleepAlarms() -> [ForgeAlarm]? {
        guard let data = UserDefaults.standard.data(forKey: sleepAlarmsKey),
              let alarms = try? JSONDecoder().decode([ForgeAlarm].self, from: data) else {
            return nil
        }
        return alarms
    }

    static func saveWakeSettings(_ settings: WakeProductSettings) {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        UserDefaults.standard.set(data, forKey: wakeSettingsKey)
    }

    static func loadWakeSettings() -> WakeProductSettings? {
        guard let data = UserDefaults.standard.data(forKey: wakeSettingsKey),
              let settings = try? JSONDecoder().decode(WakeProductSettings.self, from: data) else {
            return nil
        }
        return settings
    }

    static func saveSleepSoundMix(_ mix: [PersistedSleepSound]) {
        guard let data = try? JSONEncoder().encode(mix) else { return }
        UserDefaults.standard.set(data, forKey: sleepSoundMixKey)
    }

    static func loadSleepSoundMix() -> [PersistedSleepSound]? {
        guard let data = UserDefaults.standard.data(forKey: sleepSoundMixKey),
              let mix = try? JSONDecoder().decode([PersistedSleepSound].self, from: data) else {
            return nil
        }
        return mix
    }

    static func saveSleepTimerMinutes(_ minutes: Int) {
        UserDefaults.standard.set(minutes, forKey: sleepTimerKey)
    }

    static func loadSleepTimerMinutes() -> Int {
        UserDefaults.standard.integer(forKey: sleepTimerKey)
    }

    // MARK: - Chat gamification

    static func saveChatGamification(_ state: ChatGamificationState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        UserDefaults.standard.set(data, forKey: chatGamificationKey)
    }

    static func loadChatGamification() -> ChatGamificationState? {
        guard let data = UserDefaults.standard.data(forKey: chatGamificationKey),
              let state = try? JSONDecoder().decode(ChatGamificationState.self, from: data) else {
            return nil
        }
        return state
    }
}