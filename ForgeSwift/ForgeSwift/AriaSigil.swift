import Foundation
import ForgeCore
import SwiftUI

/// Kinetic orange ring-field. Thin wrapper over ForgeCore `AriaRingFieldGeometry`
/// so phone and Watch stay lockstep. Watch cannot import this file (`AROrbState`).
/// Soft spin while alive; Reduce Motion / `forgeMinimalAnimation` freeze at
/// `stillPoseAngleDeg`.
enum AriaSigilGeometry: Sendable {

    typealias EllipsePose = AriaRingFieldGeometry.EllipsePose

    static let kind = AriaRingFieldGeometry.kind
    static let assetName = AriaRingFieldGeometry.assetName
    static let ringCount = AriaRingFieldGeometry.ringCount
    static let ellipseCount = AriaRingFieldGeometry.ellipseCount
    static let forgeOrangeHex = AriaRingFieldGeometry.forgeOrangeHex
    static let brandHueLightHex = AriaRingFieldGeometry.brandHueLightHex

    /// Frozen TimelineView clock only. Angle lock is `stillPoseAngleDeg` (Lex).
    static let stillPose = AriaRingFieldGeometry.stillPose
    static let stillPoseAngleDeg = AriaRingFieldGeometry.stillPoseAngleDeg
    static let heroMinimumSize = AriaRingFieldGeometry.heroMinimumSize
    static let compactRecommend = AriaRingFieldGeometry.compactRecommend

    static let idleSpinHz = AriaRingFieldGeometry.idleSpinHz
    static let speakingSpinHz = AriaRingFieldGeometry.speakingSpinHz

    static let strokeWidthCompact = AriaRingFieldGeometry.strokeWidthCompact
    static let strokeWidthHero = AriaRingFieldGeometry.strokeWidthHero
    static let contrastFloor = AriaRingFieldGeometry.contrastFloor

    static let radii = AriaRingFieldGeometry.radii
    static let eccentricity = AriaRingFieldGeometry.eccentricity
    static let tiltDeg = AriaRingFieldGeometry.tiltDeg
    static let phaseOffsets = AriaRingFieldGeometry.phaseOffsets
    static let ringOpacities = AriaRingFieldGeometry.ringOpacities

    static var contrastRingIndices: [Int] { AriaRingFieldGeometry.contrastRingIndices }

    /// Compact 3-ring: the two ≥ 0.70 rings plus the strongest support ring.
    /// Watch later / tab / avatar slots. Not Home readiness chrome.
    static var compactRingIndices: [Int] { AriaRingFieldGeometry.compactRingIndices }

    static func visibleRingIndices(size: CGFloat) -> [Int] {
        AriaRingFieldGeometry.visibleRingIndices(size: size)
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
        AriaRingFieldGeometry.ellipse(
            index: index,
            time: time,
            speaking: state == .processing || state == .speaking,
            reduceMotion: reduceMotion
        )
    }

    static func strokeWidth(size: CGFloat, index: Int = 0) -> CGFloat {
        AriaRingFieldGeometry.strokeWidth(size: size, index: index)
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
