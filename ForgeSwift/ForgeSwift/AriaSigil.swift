import Foundation
import SwiftUI

/// Kinetic orange ring-field. Five overlapping ellipses, Forge orange `#FF4D00`.
/// Soft spin while alive; Reduce Motion / `forgeMinimalAnimation` freeze at `stillPose`.
///
/// Lex owns `shared/aria-mark.json` / Frontend. The tree copy is still the
/// 4-lobe ember contract (`lobeCount: 4`, breath Hz, `maxGaze`). Phone ships
/// this craft until that JSON lands — do not treat the ember file as the mark.
enum AriaSigilGeometry: Sendable {

    static let stillPose: Double = 1.72
    static let ellipseCount: Int = 5
    static let forgeOrangeHex = "FF4D00"

    /// Soft field spin. Idle is slower than speaking. All well under a flicker bar.
    static let idleSpinHz: Double = 0.08
    static let listeningSpinHz: Double = 0.11
    static let processingSpinHz: Double = 0.13
    static let speakingSpinHz: Double = 0.16

    struct EllipsePose: Equatable, Sendable {
        var rx: Double
        var ry: Double
        var rotation: Double
        var opacity: Double
    }

    /// Aspect + counter-spin. Tilts are `index * 2π / 5` so the five rings overlap
    /// as a field, not a stacked nest.
    private static let rings: [(rx: Double, ry: Double, spinSign: Double, opacity: Double)] = [
        (0.94, 0.62, 1.00, 0.92),
        (0.90, 0.54, -0.92, 0.76),
        (0.86, 0.58, 1.08, 0.84),
        (0.92, 0.50, -1.04, 0.70),
        (0.88, 0.66, 0.96, 0.86),
    ]

    static func spinHz(for state: AROrbState) -> Double {
        switch state {
        case .idle: return idleSpinHz
        case .listening: return listeningSpinHz
        case .processing: return processingSpinHz
        case .speaking: return speakingSpinHz
        }
    }

    static func ellipse(
        index: Int,
        time: Double,
        state: AROrbState,
        reduceMotion: Bool
    ) -> EllipsePose {
        let i = max(0, min(ellipseCount - 1, index))
        let ring = rings[i]
        let tilt = Double(i) * (.pi * 2 / Double(ellipseCount))
        // Still-pose is one composition: freeze the clock and the idle rate
        // so speaking / listening cannot drift the reduced frame.
        let hz = reduceMotion ? idleSpinHz : spinHz(for: state)
        let clock = reduceMotion ? stillPose : time
        let rotation = tilt + ring.spinSign * clock * hz * .pi * 2
        let talk = (!reduceMotion && state == .speaking) ? 0.03 : 0
        return EllipsePose(
            rx: ring.rx + talk,
            ry: ring.ry + talk * 0.5,
            rotation: rotation,
            opacity: ring.opacity
        )
    }

    static func strokeWidth(size: CGFloat, index: Int) -> CGFloat {
        let i = max(0, min(ellipseCount - 1, index))
        let weights: [CGFloat] = [1.12, 0.92, 1.04, 0.86, 1.00]
        return max(1.15, size * 0.022) * weights[i]
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
/// freezes the ring-field at `AriaSigilGeometry.stillPose`. Default is off;
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
