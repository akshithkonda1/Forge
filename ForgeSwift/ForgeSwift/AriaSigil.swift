import Foundation
import SwiftUI

/// Kinetic orange ring-field. Numbers copied from Lex `#270` head
/// `fab0a402097050dfec528f014e902591314204ca` (`shared/aria-mark.json`).
/// That PR is mergeable but not on `main` yet — do not invent a second geometry.
/// Soft spin while alive; Reduce Motion / `forgeMinimalAnimation` freeze at
/// `stillPoseAngleDeg`.
enum AriaSigilGeometry: Sendable {

    static let kind = "ring-field"
    static let assetName = "AriaMark"
    static let ringCount: Int = 5
    static let ellipseCount: Int = ringCount
    static let forgeOrangeHex = "FF4D00"
    static let brandHueLightHex = "FF6B2B"

    /// Frozen TimelineView clock only. Angle lock is `stillPoseAngleDeg` (Lex).
    static let stillPose: Double = 1.72
    static let stillPoseAngleDeg: Double = 18
    static let heroMinimumSize: CGFloat = 90
    static let compactRecommend: CGFloat = 28

    static let idleSpinHz: Double = 0.04
    static let speakingSpinHz: Double = 0.075

    static let strokeWidthCompact: CGFloat = 1.5
    static let strokeWidthHero: CGFloat = 1.85
    static let contrastFloor: Double = 0.70

    static let radii: [Double] = [0.38, 0.48, 0.58, 0.68, 0.78]
    static let eccentricity: [Double] = [0.1, 0.14, 0.08, 0.16, 0.11]
    static let tiltDeg: [Double] = [14, -22, 28, -10, 18]
    static let phaseOffsets: [Double] = [0, 0.18, 0.41, 0.63, 0.88]
    static let ringOpacities: [Double] = [0.40, 0.72, 0.78, 0.45, 0.55]

    struct EllipsePose: Equatable, Sendable {
        var rx: Double
        var ry: Double
        var rotation: Double
        var opacity: Double
    }

    static var contrastRingIndices: [Int] {
        ringOpacities.enumerated().compactMap { $0.element >= contrastFloor ? $0.offset : nil }
    }

    /// Compact 3-ring: the two ≥ 0.70 rings plus the strongest support ring.
    /// Watch later / tab / avatar slots. Not Home readiness chrome.
    static var compactRingIndices: [Int] {
        let support = ringOpacities.enumerated()
            .filter { $0.element < contrastFloor }
            .max { $0.element < $1.element }?
            .offset
        return (contrastRingIndices + [support].compactMap { $0 }).sorted()
    }

    static func visibleRingIndices(size: CGFloat) -> [Int] {
        size < heroMinimumSize ? compactRingIndices : Array(0..<ellipseCount)
    }

    static func spinHz(for state: AROrbState) -> Double {
        switch state {
        case .idle, .listening: return idleSpinHz
        case .processing, .speaking: return speakingSpinHz
        }
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

    static func strokeWidth(size: CGFloat, index: Int = 0) -> CGFloat {
        _ = index
        let raw = size < heroMinimumSize ? strokeWidthCompact : strokeWidthHero
        return max(strokeWidthCompact, raw)
    }
}

enum AriaSigilPalette: Sendable {
    static let forgeOrangeHex = AriaSigilGeometry.forgeOrangeHex
    /// Brand lock. Was `FF6A1A` (gooey hearth); the mark is Forge orange now.
    static let emberHex = forgeOrangeHex
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
/// freezes the ring-field at `AriaSigilGeometry.stillPoseAngleDeg`. Default is off;
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
