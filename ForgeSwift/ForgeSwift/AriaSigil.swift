import Foundation
import SwiftUI

/// Kinetic orange/pearl ellipse nest + smart-metal pearl core (iOS Aria logo).
/// Three stroked ellipses — same wirefield language as the Watch Home readiness
/// nest (tilted eccentric rings) — around a white orb. Soft spin while alive;
/// Reduce Motion / `forgeMinimalAnimation` freeze at `stillPoseAngleDeg`.
/// Speaking adds a liquid-metal waveform on the orb and a soft breathe on the rings.
enum AriaSigilGeometry: Sendable {

    static let kind = "ring-field"
    static let assetName = "AriaMark"
    static let ringCount: Int = 3
    /// Legacy aliases — mark is the Watch-style ellipse nest (not hexagons).
    static let hexCount: Int = ringCount
    static let ellipseCount: Int = ringCount
    static let forgeOrangeHex = "FF4D00"
    static let brandHueLightHex = "FF6B2B"
    /// Soft pearl core — glows; never readiness chrome.
    static let pearlHex = "F7F4F0"
    static let pearlHotHex = "FFFFFF"

    /// Frozen TimelineView clock only. Angle lock is `stillPoseAngleDeg`.
    static let stillPose: Double = 1.72
    static let stillPoseAngleDeg: Double = 18
    static let heroMinimumSize: CGFloat = 90
    static let compactRecommend: CGFloat = 28

    static let idleSpinHz: Double = 0.04
    static let speakingSpinHz: Double = 0.075
    /// Soft liquid breathe while talking — well under flash rates.
    static let waveformHz: Double = 2.35
    /// Faster surface shimmer for the smart-metal orb (spatial, not a strobe).
    static let metalRippleHz: Double = 3.1

    static let strokeWidthCompact: CGFloat = 1.5
    static let strokeWidthHero: CGFloat = 1.85
    static let contrastFloor: Double = 0.70

    /// Watch Home nest compact subset (indices 1, 2, 4 of the 5-ring field).
    /// High eccentricity + strong tilts = the kinetic wirefield look.
    static let radii: [Double] = [0.48, 0.58, 0.78]
    static let eccentricity: [Double] = [0.14, 0.08, 0.11]
    static let tiltDeg: [Double] = [-22, 28, 18]
    static let phaseOffsets: [Double] = [0.18, 0.41, 0.88]
    static let ringOpacities: [Double] = [0.72, 0.78, 0.55]

    struct EllipsePose: Equatable, Sendable {
        var rx: Double
        var ry: Double
        var rotation: Double
        var opacity: Double
    }

    /// Legacy name kept for call-site continuity.
    typealias HexPose = EllipsePose

    struct OrbCorePose: Equatable, Sendable {
        var sx: Double
        var sy: Double
        var glow: Double
        var highlight: Double
        /// Smart-metal surface ripples (0…1). Idle is a whisper; speaking is a voice.
        var ripple: Double
        var sheenAngle: Double
        var metalWarp: Double
    }

    static var contrastRingIndices: [Int] {
        ringOpacities.enumerated().compactMap { $0.element >= contrastFloor ? $0.offset : nil }
    }

    /// Always the three rings — compact and hero share the same nest.
    static var compactRingIndices: [Int] { Array(0..<ellipseCount) }

    static func visibleRingIndices(size: CGFloat) -> [Int] {
        _ = size
        return Array(0..<ellipseCount)
    }

    /// Watch nest hue rhythm: ring 0 pearl, ring 1 orange-light, ring 2 orange.
    static func ringIsPearl(_ index: Int) -> Bool {
        index == 0
    }

    static func spinHz(for state: AROrbState) -> Double {
        switch state {
        case .idle, .listening: return idleSpinHz
        case .processing, .speaking: return speakingSpinHz
        }
    }

    /// How hard the liquid waveform drives — speaking is full, idle is a whisper.
    static func waveformDrive(state: AROrbState, amplitude: Double) -> Double {
        let energy = max(0, min(1, amplitude))
        let boost: Double
        switch state {
        case .speaking: boost = 1.0
        case .listening: boost = 0.38
        case .processing: boost = 0.48
        case .idle: boost = 0.14
        }
        return energy * boost
    }

    static func ellipse(
        index: Int,
        time: Double,
        state: AROrbState,
        reduceMotion: Bool
    ) -> EllipsePose {
        let i = max(0, min(ellipseCount - 1, index))
        let radius = radii[i]
        let ecc = eccentricity[i]
        let tilt = tiltDeg[i] * .pi / 180
        let phase = phaseOffsets[i] * .pi * 2
        let still = stillPoseAngleDeg * .pi / 180
        let spin: Double
        if reduceMotion {
            spin = still
        } else {
            spin = time * spinHz(for: state) * .pi * 2
        }
        return EllipsePose(
            rx: radius * (1 + ecc),
            ry: radius * (1 - ecc),
            rotation: tilt + phase + spin,
            opacity: ringOpacities[i]
        )
    }

    /// Legacy alias — callers that still say `hex`.
    static func hex(
        index: Int,
        time: Double,
        state: AROrbState,
        reduceMotion: Bool
    ) -> EllipsePose {
        ellipse(index: index, time: time, state: state, reduceMotion: reduceMotion)
    }

    /// Ellipse pose plus liquid breathe when alive. Reduce Motion returns still.
    static func liquidEllipse(
        index: Int,
        time: Double,
        state: AROrbState,
        amplitude: Double,
        reduceMotion: Bool
    ) -> EllipsePose {
        var pose = ellipse(index: index, time: time, state: state, reduceMotion: reduceMotion)
        guard !reduceMotion else { return pose }
        let drive = waveformDrive(state: state, amplitude: amplitude)
        guard drive > 0.01 else { return pose }

        let i = max(0, min(ellipseCount - 1, index))
        let phase = time * waveformHz * .pi * 2 + phaseOffsets[i] * .pi * 2
        let wave = sin(phase)
        let wave2 = cos(phase * 1.27 + Double(i) * 0.55)
        pose.rx *= 1.0 + wave * 0.045 * drive
        pose.ry *= 1.0 + wave2 * 0.055 * drive
        pose.rotation += wave * 0.03 * drive
        pose.opacity = min(1.0, pose.opacity + drive * 0.12 * (0.55 + 0.45 * wave))
        return pose
    }

    /// Legacy alias.
    static func liquidHex(
        index: Int,
        time: Double,
        state: AROrbState,
        amplitude: Double,
        reduceMotion: Bool
    ) -> EllipsePose {
        liquidEllipse(index: index, time: time, state: state, amplitude: amplitude, reduceMotion: reduceMotion)
    }

    /// White smart-metal orb: idle = soft pearl; speaking = vibrating liquid metal.
    static func orbCore(
        time: Double,
        state: AROrbState,
        amplitude: Double,
        reduceMotion: Bool
    ) -> OrbCorePose {
        if reduceMotion {
            return OrbCorePose(
                sx: 1, sy: 1, glow: 0.55, highlight: 0.7,
                ripple: 0.12, sheenAngle: 0.55, metalWarp: 0
            )
        }
        let drive = waveformDrive(state: state, amplitude: amplitude)
        let phase = time * waveformHz * .pi * 2
        let metalPhase = time * metalRippleHz * .pi * 2
        let wave = sin(phase)
        let wave2 = cos(phase * 1.4 + 0.3)
        let ripple = sin(metalPhase) * 0.55 + sin(metalPhase * 1.7 + 0.9) * 0.45
        let warp = sin(metalPhase * 2.1 + 0.4) * cos(phase * 0.85)
        return OrbCorePose(
            sx: 1.0 + wave * 0.10 * drive + warp * 0.035 * drive,
            sy: 1.0 + wave2 * 0.14 * drive - warp * 0.04 * drive,
            glow: 0.52 + 0.38 * drive + 0.1 * wave * drive,
            highlight: 0.68 + 0.28 * drive,
            ripple: 0.14 + 0.72 * drive * (0.55 + 0.45 * abs(ripple)),
            sheenAngle: metalPhase,
            metalWarp: warp * drive
        )
    }

    static func strokeWidth(size: CGFloat, index: Int = 0) -> CGFloat {
        _ = index
        // Match Watch: scale lightly with size, never below Cove compact floor.
        let scaled = max(strokeWidthCompact, size * 0.018)
        let tier = size < heroMinimumSize ? strokeWidthCompact : strokeWidthHero
        return max(scaled, tier)
    }
}

enum AriaSigilPalette: Sendable {
    static let forgeOrangeHex = AriaSigilGeometry.forgeOrangeHex
    /// Brand lock. Was `FF6A1A` (gooey hearth); the mark is Forge orange now.
    static let emberHex = forgeOrangeHex
    static let pearlHex = AriaSigilGeometry.pearlHex
    static let pearlHotHex = AriaSigilGeometry.pearlHotHex
    static let voidDeepHex = "030207"
    static let voidMidHex = "0B0812"
    static let ivoryHex = "F3EBDD"
    static let goldHex = "C9A36A"
    static let goldHotHex = "E8C48A"
    static let steelHex = "6B7CFF"
    static let frostHex = "9FD6FF"
    static let bloodHex = "4A1018"
    static let limbHex = "000000"
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

// MARK: - Minimal animation (phone)

/// Mirrors the Watch `forgeMinimalAnimation` key. Either this or Reduce Motion
/// freezes the ring nest at `AriaSigilGeometry.stillPoseAngleDeg`. Default is off;
/// iOS has no separate Settings toggle yet.
private struct ForgeMinimalAnimationKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var forgeMinimalAnimation: Bool {
        get { self[ForgeMinimalAnimationKey.self] }
        set { self[ForgeMinimalAnimationKey.self] = newValue }
    }
}
