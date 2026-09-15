import CoreGraphics
import Foundation

/// Kinetic orange ring-field numbers + ellipse pose.
/// Copied from Lex `#270` / `shared/aria-mark.json` and the phone
/// `AriaSigilGeometry` contract. Phone wraps this type; Watch draws it.
/// No `AROrbState`, no phone UI, no PNG.
public enum AriaRingFieldGeometry: Sendable {

    public static let kind = "ring-field"
    public static let assetName = "AriaMark"
    public static let ringCount: Int = 5
    public static let ellipseCount: Int = ringCount
    public static let forgeOrangeHex = "FF4D00"
    public static let brandHueLightHex = "FF6B2B"

    /// Frozen TimelineView clock only. Angle lock is `stillPoseAngleDeg` (Lex).
    public static let stillPose: Double = 1.72
    public static let stillPoseAngleDeg: Double = 18
    public static let heroMinimumSize: CGFloat = 90
    public static let compactRecommend: CGFloat = 28

    public static let idleSpinHz: Double = 0.04
    public static let speakingSpinHz: Double = 0.075

    public static let strokeWidthCompact: CGFloat = 1.5
    public static let strokeWidthHero: CGFloat = 1.85
    public static let contrastFloor: Double = 0.70

    public static let radii: [Double] = [0.38, 0.48, 0.58, 0.68, 0.78]
    public static let eccentricity: [Double] = [0.1, 0.14, 0.08, 0.16, 0.11]
    public static let tiltDeg: [Double] = [14, -22, 28, -10, 18]
    public static let phaseOffsets: [Double] = [0, 0.18, 0.41, 0.63, 0.88]
    public static let ringOpacities: [Double] = [0.40, 0.72, 0.78, 0.45, 0.55]

    public struct EllipsePose: Equatable, Sendable {
        public var rx: Double
        public var ry: Double
        public var rotation: Double
        public var opacity: Double

        public init(rx: Double, ry: Double, rotation: Double, opacity: Double) {
            self.rx = rx
            self.ry = ry
            self.rotation = rotation
            self.opacity = opacity
        }
    }

    public static var contrastRingIndices: [Int] {
        ringOpacities.enumerated().compactMap { $0.element >= contrastFloor ? $0.offset : nil }
    }

    /// Compact 3-ring: the two ≥ 0.70 rings plus the strongest support ring.
    /// Watch ≤32pt / size < `heroMinimumSize`. Not Home readiness chrome.
    public static var compactRingIndices: [Int] {
        let support = ringOpacities.enumerated()
            .filter { $0.element < contrastFloor }
            .max { $0.element < $1.element }?
            .offset
        return (contrastRingIndices + [support].compactMap { $0 }).sorted()
    }

    public static func visibleRingIndices(size: CGFloat) -> [Int] {
        size < heroMinimumSize ? compactRingIndices : Array(0..<ellipseCount)
    }

    public static func spinHz(speaking: Bool) -> Double {
        speaking ? speakingSpinHz : idleSpinHz
    }

    public static func ellipse(
        index: Int,
        time: Double,
        speaking: Bool,
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
            spin = time * spinHz(speaking: speaking) * .pi * 2
        }
        return EllipsePose(
            rx: radius * (1 + ecc),
            ry: radius * (1 - ecc),
            rotation: tilt + phase + spin,
            opacity: ringOpacities[i]
        )
    }

    public static func strokeWidth(size: CGFloat, index: Int = 0) -> CGFloat {
        _ = index
        let raw = size < heroMinimumSize ? strokeWidthCompact : strokeWidthHero
        return max(strokeWidthCompact, raw)
    }
}
