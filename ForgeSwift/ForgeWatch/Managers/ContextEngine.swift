import Foundation
import CoreMotion
import Observation
import ForgeCore

// MARK: - ContextEngine
//
// Tracks what part of their day the user is in:
//   - manual modes (always available, always authoritative)
//   - motion hints (stationary vs moving) — suggestions only
//   - known-place detection (Phase 4): one foreground location fix per
//     evaluation compared against user-labeled places (gym/home/office),
//     cross-checked with recent heart rate ("elevated HR at the gym place
//     → probably training"). Suggestions, never silent switches.
//   - evening wind-down timing driven by the WindDownPredictor's plan
//     when available (falls back to 21:00)
//
// Privacy-first: motion classification and place coordinates stay
// on-device (App Group only); nothing location-shaped ever enters
// WatchARIAContext or a network payload.

@MainActor
@Observable
final class ContextEngine {

    private(set) var currentMode: LifestyleMode?
    private(set) var modeStartedAt: Date?
    /// A gentle auto-detected hint ("looks like a desk block?") the UI can
    /// offer as a one-tap confirm. Never auto-applied.
    private(set) var suggestedMode: LifestyleMode?
    /// Bumped whenever context changes meaningfully — views observe this
    /// to re-ask ARIA for a fresh greeting + recommendation.
    private(set) var revision = 0

    var profile: LifestyleProfile {
        didSet { defaults?.set(profile.rawValue, forKey: Keys.profile) }
    }

    var minutesInCurrentMode: Double? {
        modeStartedAt.map { Date().timeIntervalSince($0) / 60 }
    }

    /// A sustained desk/focus stretch — used to tune tonight's plan copy.
    var isHighCognitiveLoadDay: Bool {
        guard let mode = currentMode, mode == .deskCoding || mode == .deepFocus else { return false }
        return (minutesInCurrentMode ?? 0) >= 180
    }

    let knownPlaces = KnownPlacesStore()
    private let placeDetector = PlaceDetector()
    /// Today's one-tap sleep factors (reset when the day changes).
    private(set) var todaySleepFactors: [SleepFactor] = []

    private let defaults = UserDefaults(suiteName: WatchSnapshotStore.appGroupID)
    private let motionManager = CMMotionActivityManager()
    private var evaluationTask: Task<Void, Never>?
    /// Set true once the 90-minute desk nudge fired for the current block,
    /// so we nudge once per block, not once per evaluation tick.
    private var deskNudgeFiredForCurrentBlock = false

    private enum Keys {
        static let mode = "forge.watch.context.mode"
        static let modeStart = "forge.watch.context.modeStart"
        static let profile = "forge.watch.context.profile"
        static let sleepFactors = "forge.watch.context.sleepFactors"
        static let sleepFactorsDay = "forge.watch.context.sleepFactorsDay"
    }

    init() {
        profile = defaults?.string(forKey: Keys.profile).flatMap(LifestyleProfile.init(rawValue:)) ?? .general
        if let raw = defaults?.string(forKey: Keys.mode), let mode = LifestyleMode(rawValue: raw) {
            currentMode = mode
            modeStartedAt = defaults?.object(forKey: Keys.modeStart) as? Date ?? Date()
        }
        restoreSleepFactors()
        startEvaluationLoop()
    }

    // MARK: Sleep factors (one-tap, per-day)

    func toggleSleepFactor(_ factor: SleepFactor) {
        if let index = todaySleepFactors.firstIndex(of: factor) {
            todaySleepFactors.remove(at: index)
        } else {
            todaySleepFactors.append(factor)
        }
        persistSleepFactors()
        revision += 1
    }

    private func restoreSleepFactors() {
        let today = Calendar.current.startOfDay(for: Date())
        guard
            let day = defaults?.object(forKey: Keys.sleepFactorsDay) as? Date,
            Calendar.current.isDate(day, inSameDayAs: today),
            let data = defaults?.data(forKey: Keys.sleepFactors),
            let factors = try? JSONDecoder().decode([SleepFactor].self, from: data)
        else { return }
        todaySleepFactors = factors
    }

    private func persistSleepFactors() {
        defaults?.set(Calendar.current.startOfDay(for: Date()), forKey: Keys.sleepFactorsDay)
        if let data = try? JSONEncoder().encode(todaySleepFactors) {
            defaults?.set(data, forKey: Keys.sleepFactors)
        }
    }

    // MARK: Manual control

    func setMode(_ mode: LifestyleMode?) {
        guard mode != currentMode else { return }
        currentMode = mode
        modeStartedAt = mode == nil ? nil : Date()
        deskNudgeFiredForCurrentBlock = false
        suggestedMode = nil
        defaults?.set(mode?.rawValue, forKey: Keys.mode)
        defaults?.set(modeStartedAt, forKey: Keys.modeStart)
        WatchSnapshotStore.update { $0.lifestyleMode = mode }
        revision += 1
    }

    func acceptSuggestedMode() {
        guard let suggestion = suggestedMode else { return }
        setMode(suggestion)
    }

    /// Labels the user's current location (one foreground fix). Returns
    /// false when no fix is available (permission pending/denied).
    func saveCurrentLocation(as label: PlaceLabel) async -> Bool {
        guard let coordinate = await placeDetector.currentCoordinate() else { return false }
        knownPlaces.save(label: label, coordinate: coordinate)
        return true
    }

    func dismissSuggestedMode() {
        suggestedMode = nil
    }

    // MARK: Evaluation loop
    //
    // A slow heartbeat (every 5 minutes while the app is alive) — cheap,
    // and complications don't depend on it because snapshot updates also
    // happen on every foreground/refresh.

    private func startEvaluationLoop() {
        evaluationTask?.cancel()
        evaluationTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.evaluate()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    func evaluate(recentHeartRate: Double? = nil) async {
        // 1. Long-desk-block nudge: the flagship proactive trigger.
        if let mode = currentMode,
           mode == .deskCoding || mode == .deepFocus,
           let minutes = minutesInCurrentMode,
           minutes >= 90,
           !deskNudgeFiredForCurrentBlock {
            deskNudgeFiredForCurrentBlock = true
            revision += 1 // ARIA re-suggests; complication flips to Focus Reset
        }

        // 2. Evening wind-down hint — timed by the predictor when it has
        //    learned the user's rhythm, 21:00 otherwise.
        let windDownAt = WatchSnapshotStore.load()?.tonightWindDown
        let eveningReached: Bool
        if let windDownAt {
            eveningReached = Date() >= windDownAt
        } else {
            eveningReached = Calendar.current.component(.hour, from: Date()) >= 21
        }
        if eveningReached, currentMode != .windDown, suggestedMode != .windDown {
            suggestedMode = .windDown
            revision += 1
        }

        // 3. Known-place detection + HR cross-signal (foreground fix only;
        //    coordinates never leave the device).
        await refineWithPlace(recentHeartRate: recentHeartRate)

        // 4. Motion cross-check (guarded — simulator/denied users skip this).
        await refineWithMotion()
    }

    private func refineWithPlace(recentHeartRate: Double?) async {
        guard !knownPlaces.places.isEmpty,
              suggestedMode == nil,
              let coordinate = await placeDetector.currentCoordinate(),
              let place = knownPlaces.nearest(to: coordinate) else { return }

        let candidate = place.suggestedMode
        guard candidate != currentMode else { return }

        // Gym needs corroboration: being near the gym at resting HR is
        // probably just the car park. Elevated HR there means training.
        if place.label == .gym {
            guard let bpm = recentHeartRate, bpm >= 100 else { return }
        }
        suggestedMode = candidate
        revision += 1
    }

    private func refineWithMotion() async {
        guard CMMotionActivityManager.isActivityAvailable() else { return }
        let activities: [CMMotionActivity] = await withCheckedContinuation { continuation in
            let start = Date().addingTimeInterval(-30 * 60)
            motionManager.queryActivityStarting(from: start, to: Date(), to: .main) { activities, _ in
                continuation.resume(returning: activities ?? [])
            }
        }
        guard !activities.isEmpty else { return }

        let stationaryShare = Double(activities.filter(\.stationary).count) / Double(activities.count)
        let hour = Calendar.current.component(.hour, from: Date())

        // Mostly still during working hours with no mode set → probably a
        // desk block. Offer, don't assume.
        if currentMode == nil, suggestedMode == nil,
           stationaryShare > 0.8, (9..<19).contains(hour) {
            suggestedMode = .deskCoding
            revision += 1
        }

        // Sustained movement while in a desk mode → the block is over;
        // clear the nudge armed state so the next block can nudge again.
        if let mode = currentMode, mode == .deskCoding || mode == .deepFocus,
           stationaryShare < 0.2 {
            deskNudgeFiredForCurrentBlock = false
        }
    }
}
