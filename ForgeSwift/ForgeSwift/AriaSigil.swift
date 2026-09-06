import Foundation

/// Living motion for ARIA's fluid ember mark.
/// Uniform scale only — never stretch. Numbers lock to `shared/aria-mark.json`.
enum AriaSigilGeometry: Sendable {

    /// Frozen phase for Reduce Motion and snapshots.
    static let stillPose: Double = 1.72

    static let idleBreathHz: Double = 0.45
    static let listeningBreathHz: Double = 0.58
    static let processingBreathHz: Double = 0.7
    static let speakingBreathHz: Double = 0.62

    static let maxHueDegrees: Double = 12
    /// Always 0 — nonuniform lobe stretch is what made the mark look melted.
    static let maxEdgeUndulation: Double = 0
    /// 1.0 ↔ 1.04 uniform breath.
    static let breathScale: Double = 0.04
    static let corePulseAmount: Double = 0.1

    static func breathHz(for state: AROrbState) -> Double {
        switch state {
        case .idle: return idleBreathHz
        case .listening: return listeningBreathHz
        case .processing: return processingBreathHz
        case .speaking: return speakingBreathHz
        }
    }

    static func breath(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.42 }
        return 0.5 + 0.5 * sin(time * breathHz(for: state) * .pi * 2)
    }

    static func corePulse(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.18 }
        let wave = 0.5 + 0.5 * sin(time * breathHz(for: state) * 1.15 * .pi * 2)
        let boost: Double
        switch state {
        case .speaking: boost = 0.35
        case .listening: boost = 0.18
        case .processing: boost = 0.14
        case .idle: boost = 0
        }
        return wave * corePulseAmount + boost * corePulseAmount
    }

    static func hueShiftDegrees(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        return sin(time * 0.35 * .pi * 2) * maxHueDegrees
    }

    static func uniformScale(breath: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 1 }
        return 1 + breath * breathScale
    }

    static func glowOpacity(state: AROrbState, breath: Double) -> Double {
        switch state {
        case .idle: return 0.42 + breath * 0.22
        case .listening: return 0.55 + breath * 0.2
        case .processing: return 0.48 + breath * 0.16
        case .speaking: return 0.66 + breath * 0.24
        }
    }
}
