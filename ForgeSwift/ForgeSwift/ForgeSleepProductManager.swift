import Foundation
import UserNotifications
import AVFoundation
import HealthKit

// MARK: - Models

struct WakeProductSettings: Codable {
    var smartWakeEnabled: Bool = true
    var smartWakeWindow: Int = 30
    var sunriseEnabled: Bool = true
    var sunriseDuration: Int = 20
    var colorTemp: Double = 0.5
    var volumeRamp: String = VolumeRampCurve.gradual.rawValue
    var morningRoutine: [RoutineItem] = RoutineItem.defaults

    var rampCurve: VolumeRampCurve {
        get { VolumeRampCurve(rawValue: volumeRamp) ?? .gradual }
        set { volumeRamp = newValue.rawValue }
    }
}

struct PersistedSleepSound: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var volume: Double
}

// MARK: - Sleep Product Manager

@MainActor
final class ForgeSleepProductManager: ObservableObject {
    static let shared = ForgeSleepProductManager()

    @Published var alarms: [ForgeAlarm] = []
    @Published var wakeSettings = WakeProductSettings()
    @Published var activeSounds: [(sound: SleepSoundItem, volume: Double)] = []
    @Published var sleepTimerMinutes: Int = 0
    @Published var sleepTimerRemaining: Int = 0
    @Published var notificationPermissionGranted = false
    @Published var isPlayingSounds = false

    private let soundEngine = SleepSoundEngine()
    private var sleepTimerTask: Task<Void, Never>?
    private let notificationCenter = UNUserNotificationCenter.current()

    private init() {
        loadPersistedState()
    }

    // MARK: - Persistence

    func loadPersistedState() {
        if let saved = ForgePersistence.loadSleepAlarms() {
            alarms = saved
        } else {
            alarms = Self.defaultAlarms
        }
        if let savedWake = ForgePersistence.loadWakeSettings() {
            wakeSettings = savedWake
        }
        sleepTimerMinutes = ForgePersistence.loadSleepTimerMinutes()
        if let savedMix = ForgePersistence.loadSleepSoundMix() {
            activeSounds = savedMix.compactMap { persisted in
                guard let item = allSleepSounds.first(where: { $0.name == persisted.name }) else { return nil }
                return (sound: item, volume: persisted.volume)
            }
            if !activeSounds.isEmpty {
                soundEngine.play(mix: activeSounds)
                isPlayingSounds = true
            }
        }
    }

    func persistAlarms() {
        ForgePersistence.saveSleepAlarms(alarms)
        Task { await rescheduleAllNotifications(recentSleepScore: nil) }
    }

    func persistWakeSettings() {
        ForgePersistence.saveWakeSettings(wakeSettings)
        syncWakeSettingsToAlarms()
        Task { await rescheduleAllNotifications(recentSleepScore: nil) }
    }

    func persistSoundMix() {
        let payload = activeSounds.map { PersistedSleepSound(id: $0.sound.id, name: $0.sound.name, volume: $0.volume) }
        ForgePersistence.saveSleepSoundMix(payload)
    }

    func persistSleepTimer() {
        ForgePersistence.saveSleepTimerMinutes(sleepTimerMinutes)
    }

    // MARK: - Alarms

    func upsertAlarm(_ alarm: ForgeAlarm) {
        if let index = alarms.firstIndex(where: { $0.id == alarm.id }) {
            alarms[index] = alarm
        } else {
            alarms.append(alarm)
        }
        persistAlarms()
    }

    func deleteAlarms(at offsets: IndexSet) {
        alarms.remove(atOffsets: offsets)
        persistAlarms()
    }

    func setAlarmEnabled(_ alarmId: UUID, enabled: Bool) {
        guard let index = alarms.firstIndex(where: { $0.id == alarmId }) else { return }
        alarms[index].isEnabled = enabled
        persistAlarms()
    }

    private func syncWakeSettingsToAlarms() {
        for index in alarms.indices {
            alarms[index].isSmartWake = wakeSettings.smartWakeEnabled
            alarms[index].smartWakeWindow = wakeSettings.smartWakeWindow
        }
        ForgePersistence.saveSleepAlarms(alarms)
    }

    var nextEnabledAlarm: ForgeAlarm? {
        enabledAlarmsSortedByNextFire().first
    }

    // MARK: - Notifications

    func refreshNotificationPermission() async {
        let settings = await notificationCenter.notificationSettings()
        notificationPermissionGranted = settings.authorizationStatus == .authorized
    }

    func requestNotificationPermissionIfNeeded() async -> Bool {
        await refreshNotificationPermission()
        if notificationPermissionGranted { return true }

        do {
            let granted = try await notificationCenter.requestAuthorization(options: [.alert, .sound, .badge])
            notificationPermissionGranted = granted
            if granted {
                await rescheduleAllNotifications(recentSleepScore: nil)
            }
            return granted
        } catch {
            return false
        }
    }

    func rescheduleAllNotifications(recentSleepScore: Int?) async {
        await refreshNotificationPermission()
        guard notificationPermissionGranted else { return }

        let pending = await notificationCenter.pendingNotificationRequests()
        let forgeIDs = pending.map(\.identifier).filter { $0.hasPrefix("forge.sleep.") }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: forgeIDs)

        let adaptiveWindow = adaptiveSmartWakeWindow(recentSleepScore: recentSleepScore)
        for alarm in alarms where alarm.isEnabled {
            await scheduleNotifications(for: alarm, adaptiveWindow: adaptiveWindow)
        }
    }

    private func adaptiveSmartWakeWindow(recentSleepScore: Int?) -> Int {
        guard let score = recentSleepScore else { return wakeSettings.smartWakeWindow }
        if score < 70 { return min(45, wakeSettings.smartWakeWindow + 15) }
        if score >= 85 { return max(15, wakeSettings.smartWakeWindow - 10) }
        return wakeSettings.smartWakeWindow
    }

    private func scheduleNotifications(for alarm: ForgeAlarm, adaptiveWindow: Int) async {
        let calendar = Calendar.current
        let hour = calendar.component(.hour, from: alarm.time)
        let minute = calendar.component(.minute, from: alarm.time)
        let usesSmartWake = alarm.isSmartWake || wakeSettings.smartWakeEnabled
        let window = max(15, min(45, adaptiveWindow))

        for weekday in alarm.days {
            if usesSmartWake {
                let windowStart = shiftedMinutes(hour: hour, minute: minute, by: -window)
                await addNotification(
                    id: "forge.sleep.smart.\(alarm.id.uuidString).\(weekday)",
                    title: "Smart Wake — \(alarm.label)",
                    body: "Light-sleep window open. Rise gently when you feel ready.",
                    hour: windowStart.hour,
                    minute: windowStart.minute,
                    weekday: weekday,
                    sound: .default
                )
            }

            await addNotification(
                id: "forge.sleep.alarm.\(alarm.id.uuidString).\(weekday)",
                title: alarm.label,
                body: morningRoutineSummary(),
                hour: hour,
                minute: minute,
                weekday: weekday,
                sound: .default
            )

            if wakeSettings.sunriseEnabled {
                let sunriseStart = shiftedMinutes(hour: hour, minute: minute, by: -wakeSettings.sunriseDuration)
                await addNotification(
                    id: "forge.sleep.sunrise.\(alarm.id.uuidString).\(weekday)",
                    title: "Sunrise ramp started",
                    body: "Forge is gradually brightening your wake window.",
                    hour: sunriseStart.hour,
                    minute: sunriseStart.minute,
                    weekday: weekday,
                    sound: nil
                )
            }
        }
    }

    private func morningRoutineSummary() -> String {
        let enabled = wakeSettings.morningRoutine.filter(\.isEnabled)
        guard !enabled.isEmpty else { return "Time to wake up with Forge." }
        let names = enabled.prefix(3).map(\.name).joined(separator: " · ")
        return "Morning routine: \(names)"
    }

    private func shiftedMinutes(hour: Int, minute: Int, by offset: Int) -> (hour: Int, minute: Int) {
        var total = hour * 60 + minute + offset
        while total < 0 { total += 24 * 60 }
        total %= 24 * 60
        return (total / 60, total % 60)
    }

    private func addNotification(
        id: String,
        title: String,
        body: String,
        hour: Int,
        minute: Int,
        weekday: Int,
        sound: UNNotificationSound?
    ) async {
        var date = DateComponents()
        date.hour = hour
        date.minute = minute
        date.weekday = weekday

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = "FORGE_SLEEP_ALARM"
        if let sound { content.sound = sound }

        let trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: true)
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        try? await notificationCenter.add(request)
    }

    // MARK: - Adaptive wake refinement (foreground)

    func refineNextAlarmUsingHealthKit() async -> Date? {
        guard wakeSettings.smartWakeEnabled,
              let next = nextEnabledAlarm else { return nil }

        let windowMinutes = adaptiveSmartWakeWindow(recentSleepScore: nil)
        let calendar = Calendar.current
        let alarmComponents = calendar.dateComponents([.hour, .minute], from: next.time)
        guard let alarmHour = alarmComponents.hour, let alarmMinute = alarmComponents.minute else { return nil }

        var alarmDate = calendar.nextDate(
            after: Date(),
            matching: DateComponents(hour: alarmHour, minute: alarmMinute),
            matchingPolicy: .nextTime
        ) ?? Date()

        let windowStart = alarmDate.addingTimeInterval(TimeInterval(-windowMinutes * 60))
        guard let lightSleepMoment = await HealthKitSleepWindow.lightestMoment(
            between: windowStart,
            and: alarmDate
        ) else {
            return alarmDate
        }
        return lightSleepMoment
    }

    // MARK: - Sleep sounds

    func toggleSound(_ sound: SleepSoundItem) {
        if let index = activeSounds.firstIndex(where: { $0.sound.id == sound.id }) {
            activeSounds.remove(at: index)
        } else if activeSounds.count < 3 {
            activeSounds.append((sound: sound, volume: 0.75))
        } else {
            return
        }
        applySoundMix()
    }

    func updateSoundVolume(at index: Int, volume: Double) {
        guard activeSounds.indices.contains(index) else { return }
        activeSounds[index].volume = volume
        applySoundMix()
    }

    func stopAllSounds() {
        activeSounds.removeAll()
        soundEngine.stop()
        isPlayingSounds = false
        cancelSleepTimer()
        persistSoundMix()
    }

    func refreshSoundMixVolumes() {
        guard !activeSounds.isEmpty else { return }
        applySoundMix()
    }

    func setSleepTimer(minutes: Int) {
        sleepTimerMinutes = minutes
        persistSleepTimer()
        cancelSleepTimer()
        guard minutes > 0 else {
            sleepTimerRemaining = 0
            return
        }
        sleepTimerRemaining = minutes * 60
        sleepTimerTask = Task {
            while !Task.isCancelled, sleepTimerRemaining > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard !Task.isCancelled else { return }
                sleepTimerRemaining -= 1
                if sleepTimerRemaining == 0 {
                    stopAllSounds()
                }
            }
        }
    }

    private func applySoundMix() {
        if activeSounds.isEmpty {
            soundEngine.stop()
            isPlayingSounds = false
        } else {
            soundEngine.play(mix: activeSounds)
            isPlayingSounds = true
        }
        persistSoundMix()
    }

    private func cancelSleepTimer() {
        sleepTimerTask?.cancel()
        sleepTimerTask = nil
    }

    private static var defaultAlarms: [ForgeAlarm] {
        [
            ForgeAlarm(
                label: "Wake Up",
                time: Calendar.current.date(from: DateComponents(hour: 6, minute: 45)) ?? Date(),
                days: [2, 3, 4, 5, 6],
                isEnabled: true
            ),
            ForgeAlarm(
                label: "Weekend",
                time: Calendar.current.date(from: DateComponents(hour: 8, minute: 0)) ?? Date(),
                days: [1, 7],
                sound: .forestBirds,
                isEnabled: false
            ),
        ]
    }

    private func enabledAlarmsSortedByNextFire() -> [ForgeAlarm] {
        let calendar = Calendar.current
        let now = Date()
        return alarms
            .filter(\.isEnabled)
            .sorted { lhs, rhs in
                let left = calendar.nextDate(after: now, matching: calendar.dateComponents([.hour, .minute], from: lhs.time), matchingPolicy: .nextTime) ?? .distantFuture
                let right = calendar.nextDate(after: now, matching: calendar.dateComponents([.hour, .minute], from: rhs.time), matchingPolicy: .nextTime) ?? .distantFuture
                return left < right
            }
    }
}

// MARK: - Procedural sleep audio

private final class SleepSoundEngine {
    private let engine = AVAudioEngine()
    private var sourceNodes: [AVAudioSourceNode] = []
    private var isConfigured = false

    func play(mix: [(sound: SleepSoundItem, volume: Double)]) {
        stop()
        configureSession()
        let format = engine.outputNode.inputFormat(forBus: 0)
        let sampleRate = format.sampleRate

        for item in mix {
            let profile = SleepSoundProfile(name: item.sound.name)
            var phase = profile.seed
            let node = AVAudioSourceNode { _, _, frameCount, audioBufferList -> OSStatus in
                let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
                for frame in 0..<Int(frameCount) {
                    let sample = profile.sample(phase: &phase, sampleRate: sampleRate) * Float(item.volume)
                    for buffer in abl {
                        let ptr = buffer.mData?.assumingMemoryBound(to: Float.self)
                        ptr?[frame] = sample
                    }
                }
                return noErr
            }
            sourceNodes.append(node)
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: format)
        }

        do {
            try engine.start()
        } catch {
            stop()
        }
    }

    func stop() {
        sourceNodes.forEach { engine.detach($0) }
        sourceNodes.removeAll()
        engine.stop()
    }

    private func configureSession() {
        guard !isConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        isConfigured = true
    }
}

private struct SleepSoundProfile {
    let name: String
    let seed: Double

    init(name: String) {
        self.name = name
        self.seed = Double(name.hashValue % 10_000) / 10_000.0
    }

    func sample(phase: inout Double, sampleRate: Double) -> Float {
        phase += 1.0 / sampleRate
        switch name {
        case "White Noise":
            return Float.random(in: -0.25...0.25)
        case "Brown Noise":
            let step = Double.random(in: -0.04...0.04)
            phase = min(max(phase + step, -0.35), 0.35)
            return Float(phase)
        case "Pink Noise":
            return Float.random(in: -0.2...0.2) * Float(1.0 / (1.0 + phase.truncatingRemainder(dividingBy: 0.5)))
        case "Rain", "Thunder":
            let burst = sin(phase * 9.0) * 0.08
            return Float.random(in: -0.18...0.18) + Float(burst)
        case "Ocean":
            return Float(sin(phase * 0.6) * 0.12 + Double.random(in: -0.08...0.08))
        case "Fan":
            return Float.random(in: -0.1...0.1) * 0.9
        case "Forest", "Wind Chimes":
            return Float(sin(phase * 3.5) * 0.05 + Double.random(in: -0.06...0.06))
        case "Lo-Fi", "Soft Piano", "432 Hz":
            return Float(sin(phase * 2.2) * 0.08)
        case "Binaural", "Deep Focus":
            return Float(sin(phase * 12.0) * 0.06)
        default:
            return Float.random(in: -0.12...0.12)
        }
    }
}

private enum HealthKitSleepWindow {
    static func lightestMoment(between start: Date, and end: Date) async -> Date? {
        guard HKHealthStore.isHealthDataAvailable(),
              let sleepType = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return nil
        }

        let store = HKHealthStore()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return await withCheckedContinuation { continuation in
            let query = HKSampleQuery(
                sampleType: sleepType,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let asleep = (samples as? [HKCategorySample])?
                    .filter { $0.value == HKCategoryValueSleepAnalysis.asleepUnspecified.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue
                        || $0.value == HKCategoryValueSleepAnalysis.asleepREM.rawValue }
                    .sorted { $0.startDate < $1.startDate }

                guard let asleep, !asleep.isEmpty else {
                    continuation.resume(returning: nil)
                    return
                }

                let coreSegments = asleep.filter { $0.value == HKCategoryValueSleepAnalysis.asleepCore.rawValue }
                let candidate = coreSegments.first ?? asleep.first
                continuation.resume(returning: candidate?.startDate.addingTimeInterval(60))
            }
            store.execute(query)
        }
    }
}

