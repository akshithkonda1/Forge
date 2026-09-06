import Foundation

/// Living motion for ARIA's fluid ember mark.
/// Adaptive Recovery Interactive Assistant — friendly, warm, approachable.
/// Numbers lock to `shared/aria-mark.json`. Pure so tests can freeze
/// Reduce Motion without a TimelineView.
enum AriaSigilGeometry: Sendable {

    /// Frozen phase for Reduce Motion and snapshots.
    static let stillPose: Double = 1.72

    static let idleBreathHz: Double = 0.28
    static let listeningBreathHz: Double = 0.42
    static let processingBreathHz: Double = 0.52
    static let speakingBreathHz: Double = 0.38

    /// Soft iridescent wander. Stay well under carnival territory.
    static let maxHueDegrees: Double = 7
    /// Gentle lobe stretch — a breath, not a wobble.
    static let maxEdgeUndulation: Double = 0.016
    static let breathScale: Double = 0.028
    /// Orange-core brightness pulse.
    static let corePulseAmount: Double = 0.035

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
        case .speaking: boost = 0.22
        case .listening: boost = 0.12
        case .processing: boost = 0.10
        case .idle: boost = 0
        }
        return wave * corePulseAmount + boost * corePulseAmount
    }

    static func hueShiftDegrees(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0 }
        let wander = sin(time * 0.22 * .pi * 2)
        return wander * maxHueDegrees
    }

    static func edgeUndulation(time: Double, reduceMotion: Bool) -> (x: Double, y: Double) {
        if reduceMotion { return (0, 0) }
        let x = sin(time * 0.31 * .pi * 2) * maxEdgeUndulation
        let y = cos(time * 0.27 * .pi * 2) * maxEdgeUndulation
        return (x, y)
    }

    static func glowOpacity(state: AROrbState, breath: Double) -> Double {
        switch state {
        case .idle: return 0.34 + breath * 0.10
        case .listening: return 0.48 + breath * 0.12
        case .processing: return 0.40 + breath * 0.08
        case .speaking: return 0.58 + breath * 0.16
        }
    }
}

/// Metals and void. Mood tints the ambient wash; the ember core stays warm.
enum AriaSigilPalette: Sendable {
    static let voidDeepHex = "030207"
    static let voidMidHex = "0B0812"
    static let ivoryHex = "F3EBDD"
    static let goldHex = "C9A36A"
    static let goldHotHex = "E8C48A"
    static let steelHex = "6B7CFF"
    static let frostHex = "9FD6FF"
    static let bloodHex = "4A1018"
    static let limbHex = "000000"
    static let emberHex = "FF6A1A"
    static let tealHex = "3EC8C8"

    static func photonPrimary(for mood: ARIAMood) -> String {
        switch mood {
        case .energized: return goldHotHex
        case .focused: return steelHex
        case .calm: return "8B6CFF"
        case .pushed: return goldHex
        }
    }

    static func photonSecondary(for mood: ARIAMood) -> String {
        switch mood {
        case .energized: return goldHex
        case .focused: return frostHex
        case .calm: return goldHex
        case .pushed: return "E07A6A"
        }
    }
}
