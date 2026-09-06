import Foundation

/// Geometry and motion for ARIA's mark. Pure so tests can lock the still
/// pose, the gaze clamp, and the slow idle — the thing that makes her feel
/// like a mind instead of a spinner.
enum AriaSigilGeometry: Sendable {

    /// Frozen pose for Reduce Motion and snapshots. Photon-ring gap sits
    /// near 1 o'clock; specular reads as a lens, not a sticker.
    static let stillPose: Double = 1.72

    /// Sphere fills most of the mark. Halo lives outside this.
    static let voidRatio: Double = 0.92
    /// The mind — a pupil of light. Small enough to feel like a thought.
    static let mindRatio: Double = 0.118
    /// Photon ring just inside the limb.
    static let photonRatio: Double = 0.84
    static let photonWidthRatio: Double = 0.038
    /// Incomplete ring. The gap is the mystery.
    static let photonTrimStart: Double = 0.045
    static let photonTrimEnd: Double = 0.88
    /// How far the mind may wander. Any more and she looks unwell.
    static let maxGazeRatio: Double = 0.046
    static let specularRatio: Double = 0.068
    static let filamentRatio: Double = 0.58
    /// Inner event-horizon line.
    static let horizonRatio: Double = 0.36

    static func breath(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.42 }
        let hz: Double
        switch state {
        case .idle: hz = 0.26
        case .listening: hz = 0.52
        case .processing: hz = 0.88
        case .speaking: hz = 0.46
        }
        return 0.5 + 0.5 * sin(time * hz * .pi * 2)
    }

    static func photonSpinDegrees(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return 28 }
        let dps: Double
        switch state {
        case .idle: dps = 4.2
        case .listening: dps = 10.5
        case .processing: dps = 20
        case .speaking: dps = 13
        }
        return time * dps
    }

    static func innerSpinDegrees(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return -18 }
        let dps: Double
        switch state {
        case .idle: dps = -7
        case .listening: dps = -14
        case .processing: dps = -28
        case .speaking: dps = -16
        }
        return time * dps
    }

    /// A living gaze, clamped. Idle barely moves. Listening looks toward you.
    static func gaze(time: Double, state: AROrbState, reduceMotion: Bool) -> (x: Double, y: Double) {
        if reduceMotion { return (0.012, -0.018) }
        let wander: Double
        switch state {
        case .idle: wander = 0.32
        case .listening: wander = 0.55
        case .processing: wander = 0.22
        case .speaking: wander = 0.40
        }
        let x = sin(time * 0.17) * maxGazeRatio * wander
        let y = cos(time * 0.13) * maxGazeRatio * wander * 0.68
        let attend: Double
        switch state {
        case .listening: attend = 0.014
        case .speaking: attend = -0.006
        default: attend = 0
        }
        return (clampGaze(x), clampGaze(y + attend))
    }

    static func clampGaze(_ value: Double) -> Double {
        min(maxGazeRatio, max(-maxGazeRatio, value))
    }

    static func mindGlow(amplitude: Double, state: AROrbState, breath: Double) -> Double {
        let base: Double
        switch state {
        case .idle: base = 0.42
        case .listening: base = 0.62
        case .processing: base = 0.55
        case .speaking: base = 0.78
        }
        return min(1.0, base + amplitude * 0.22 + breath * 0.12)
    }

    static func haloOpacity(state: AROrbState, breath: Double) -> Double {
        switch state {
        case .idle: return 0.34 + breath * 0.10
        case .listening: return 0.48 + breath * 0.12
        case .processing: return 0.40 + breath * 0.08
        case .speaking: return 0.58 + breath * 0.16
        }
    }
}

/// Metals and void. Mood tints the photon ring; the blood-shadow and ivory
/// specular never change — that's the gray area: valuable, a little dangerous.
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
