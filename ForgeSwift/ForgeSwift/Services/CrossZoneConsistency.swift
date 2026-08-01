import Foundation

/// Keeps sleep ↔ readiness ↔ training ↔ chat context *tight* so ARIA never
/// coaches as if the athlete is primed when biometrics say recover (or the reverse).
/// Pure rules — no network, deterministic, safe for offline + SimRunner parity.
enum CrossZoneConsistency {

    struct Snapshot: Equatable {
        var readiness: Int
        var recoveryScore: Int
        var sleepScore: Int?
        var sleepHours: Double?
        var hoursSinceLastWorkout: Double?
        var lastWorkoutIntensity: Double?
        var isCurrentlyBleeding: Bool
        var cycleRecoveryBias: Bool
        var quietMode: Bool
    }

    enum Band: String {
        case recover
        case steady
        case ready
        case primed
    }

    /// Single-band truth for coaching tone across every surface.
    static func readinessBand(_ readiness: Int) -> Band {
        switch readiness {
        case ..<50: return .recover
        case 50..<70: return .steady
        case 70..<85: return .ready
        default: return .primed
        }
    }

    /// Hard safety: never prescribe high intensity when recovery signals dominate.
    static func blocksHighIntensity(_ snap: Snapshot) -> Bool {
        if snap.readiness < 55 { return true }
        if snap.recoveryScore < 50 { return true }
        if let sleep = snap.sleepScore, sleep < 55 { return true }
        if let hours = snap.sleepHours, hours < 5.5 { return true }
        if snap.cycleRecoveryBias || snap.isCurrentlyBleeding { return true }
        if let hrs = snap.hoursSinceLastWorkout, hrs < 12,
           let intensity = snap.lastWorkoutIntensity, intensity >= 8 {
            return true
        }
        return false
    }

    /// Constraint strings injected into ARIA context so remote + local paths share truth.
    static func coachingConstraints(for snap: Snapshot) -> [String] {
        var out: [String] = []
        let band = readinessBand(snap.readiness)
        out.append("cross_zone:readiness_band:\(band.rawValue)")
        out.append("cross_zone:readiness:\(snap.readiness)")

        if blocksHighIntensity(snap) {
            out.append("cross_zone:safety:block_high_intensity")
            out.append(
                "cross_zone:directive:Do not prescribe HIIT, max-effort, or PR attempts. Prefer recovery, mobility, Zone 2, or rest. Naming high intensity is a safety failure."
            )
        } else if band == .primed {
            out.append("cross_zone:directive:Athlete is primed — quality intensity is appropriate if they want it; still hedge if sleep is thin.")
        } else if band == .ready {
            out.append("cross_zone:directive:Solid day — progressive work OK; avoid stacking all-out sessions back-to-back.")
        } else {
            out.append("cross_zone:directive:Steady day — keep volume honest; emphasize form and recovery between efforts.")
        }

        if let sleep = snap.sleepScore {
            out.append("cross_zone:sleep_score:\(sleep)")
            if sleep < 60, snap.readiness >= 75 {
                out.append(
                    "cross_zone:tension:readiness_high_sleep_low — acknowledge thin sleep before pushing load; readiness alone is not permission."
                )
            }
            if sleep >= 85, snap.readiness < 55 {
                out.append(
                    "cross_zone:tension:sleep_good_readiness_low — good night did not erase accumulated load; still recover-first."
                )
            }
        }
        if let hours = snap.sleepHours {
            out.append("cross_zone:sleep_hours:\(String(format: "%.1f", hours))")
        }
        if let hrs = snap.hoursSinceLastWorkout {
            out.append("cross_zone:hours_since_workout:\(Int(hrs))")
        }
        if snap.cycleRecoveryBias {
            out.append("cross_zone:cycle:recovery_bias")
        }
        if snap.isCurrentlyBleeding {
            out.append("cross_zone:cycle:bleeding")
        }
        if snap.quietMode {
            out.append("cross_zone:quiet_mode")
        }
        return out
    }

    /// Compact memory-anchor line for token-efficient prompt packing.
    static func memoryAnchorLine(for snap: Snapshot) -> String {
        var parts: [String] = [
            "Readiness \(snap.readiness)/100 (\(readinessBand(snap.readiness).rawValue))",
            "recovery \(snap.recoveryScore)",
        ]
        if let s = snap.sleepScore { parts.append("sleep \(s)") }
        if let h = snap.sleepHours { parts.append(String(format: "%.1fh sleep", h)) }
        if blocksHighIntensity(snap) {
            parts.append("SAFETY: no high intensity")
        }
        return "Live biometrics: " + parts.joined(separator: " · ")
    }

    @MainActor
    static func snapshot(from store: AppStore) -> Snapshot {
        let cycle = MenstrualHealthStore.shared
        // Capture MainActor-isolated cycle state into locals first.
        // Never read `cycle.snapshot` (or other isolated properties) inside `&&` —
        // the RHS is a nonisolated autoclosure and will fail isolation checks.
        let cycleEnabled = cycle.settings.enabled
        let cycleSnap = cycle.snapshot
        let isCurrentlyBleeding = cycleEnabled && cycleSnap.isCurrentlyBleeding
        let cycleRecoveryBias = cycleEnabled && cycleSnap.recommendRecoveryBias
        let lastWorkout = store.workoutHistory.first
        let hoursSince: Double? = {
            guard let lastWorkout,
                  let date = ISO8601DateFormatter().date(from: lastWorkout.date) else { return nil }
            return Date().timeIntervalSince(date) / 3600
        }()
        let intensity: Double? = lastWorkout.map { w in
            switch w.intensity {
            case .low: return 3
            case .moderate: return 6
            case .high: return 8
            case .max: return 10
            }
        }
        return Snapshot(
            readiness: store.readiness.overall,
            recoveryScore: store.readiness.recoveryScore,
            sleepScore: store.sleepData.first?.score,
            sleepHours: store.sleepData.first?.totalHours,
            hoursSinceLastWorkout: hoursSince,
            lastWorkoutIntensity: intensity,
            isCurrentlyBleeding: isCurrentlyBleeding,
            cycleRecoveryBias: cycleRecoveryBias,
            quietMode: store.quietMode
        )
    }
}
