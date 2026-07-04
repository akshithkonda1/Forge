import Foundation
import CoreMotion
import Observation
import ForgeCore

// MARK: - ContextEngine
//
// Tracks what part of their day the user is in. Phase 2 scope:
//   - manual modes (always available, always authoritative)
//   - basic automatic hints from CoreMotion (stationary vs moving) and
//     time of day — surfaced as *suggestions*, never silently applied
// Phase 4 adds CLLocationManager geofences (gym/home/office) and calendar
// density. The public surface is already shaped for that.
//
// Privacy-first: motion classification stays on-device; nothing is stored
// beyond the current mode + timestamps in the shared App Group.

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
    }

    init() {
        profile = defaults?.string(forKey: Keys.profile).flatMap(LifestyleProfile.init(rawValue:)) ?? .general
        if let raw = defaults?.string(forKey: Keys.mode), let mode = LifestyleMode(rawValue: raw) {
            currentMode = mode
            modeStartedAt = defaults?.object(forKey: Keys.modeStart) as? Date ?? Date()
        }
        startEvaluationLoop()
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

    func evaluate() async {
        // 1. Long-desk-block nudge: the flagship proactive trigger.
        if let mode = currentMode,
           mode == .deskCoding || mode == .deepFocus,
           let minutes = minutesInCurrentMode,
           minutes >= 90,
           !deskNudgeFiredForCurrentBlock {
            deskNudgeFiredForCurrentBlock = true
            revision += 1 // ARIA re-suggests; complication flips to Focus Reset
        }

        // 2. Evening wind-down hint.
        let hour = Calendar.current.component(.hour, from: Date())
        if hour >= 21, currentMode != .windDown, suggestedMode != .windDown {
            suggestedMode = .windDown
            revision += 1
        }

        // 3. Motion cross-check (guarded — simulator/denied users skip this).
        await refineWithMotion()
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
