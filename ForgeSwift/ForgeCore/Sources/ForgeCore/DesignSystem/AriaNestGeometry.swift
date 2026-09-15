import Foundation

/// B+E nest mix — brand mark.
/// Soft-hex nest + metal sun. Forge orange `#FF4D00` accent. Consumer-friendly.
///
/// Numbers lockstep with open iOS nest drafts `#274` / `#275`
/// (`soft-hex-field`, three rings, planetary orbits, still-pose 18°).
/// `shared/aria-mark.json` on `main` is still `ring-field` (Lex/Cove). That
/// JSON is Home/data language only — do not invent a second nest once Lex
/// lands nest fields; map these constants to it.
///
/// Not a flower. Not an industrial F. Not splash fire. Ring-field stays
/// on `AriaSigilGeometry` for Home readiness language.
public enum AriaNestGeometry: Sendable {

    public static let kind = "soft-hex-field"
    public static let assetName = "AriaMark"
    public static let mixLock = "B+E"
    public static let ringCount = 3
    public static let hexCount = ringCount
    public static let forgeOrangeHex = "FF4D00"
    public static let brandHueLightHex = "FF6B2B"
    public static let pearlHex = "F7F4F0"
    public static let pearlHotHex = "FFFFFF"
    public static let metalCoolHex = "E8EEF4"
    public static let metalMidHex = "C9D2DC"

    /// Frozen TimelineView clock only. Angle lock is `stillPoseAngleDeg`.
    public static let stillPose: Double = 1.72
    public static let stillPoseAngleDeg: Double = 18
    public static let heroMinimumSize: Double = 90
    public static let compactRecommend: Double = 28

    /// Shared spin floor (legacy). Prefer per-ring orbit Hz.
    public static let idleSpinHz: Double = 0.05
    public static let speakingSpinHz: Double = 0.09
    /// Soft nest weave — well under flash. Restrained vs `#275` 2.35 / 3.1 Hz.
    public static let waveformHz: Double = 0.55
    public static let metalRippleHz: Double = 0.45
    public static let liquidWaveHz: Double = 0.28
    /// Watch-safe ceiling. Phone TimelineView must not exceed this.
    public static let tickHz: Double = 12
    public static let tickInterval: Double = 1.0 / 12.0
    /// Spatial wobble ceiling (Watch epilepsy bar).
    public static let maxWobbleHz: Double = 0.15

    public static let strokeWidthCompact: Double = 1.35
    public static let strokeWidthHero: Double = 1.6
    public static let contrastFloor: Double = 0.70
    /// Corner softness — higher is more ellipse-like. Soft nest, not sharp hex.
    public static let cornerRoundness: Double = 0.34
    /// Sun — ~1/3 of nest diameter in the idle lock.
    public static let orbDiameterIdle: Double = 0.22
    public static let orbDiameterSpeaking: Double = 0.245
    /// 6-fold hex bias. Kept low so the nest does not read as a flower.
    public static let hexBiasAmount: Double = 0.06
    /// Path sample count — enough for a rounded hex, cheap on Watch.
    public static let pathSamples = 48

    /// Tight nest around the sun — `#274` / `#275` radii.
    public static let radii: [Double] = [0.46, 0.52, 0.58]
    public static let eccentricity: [Double] = [0.07, 0.05, 0.06]
    public static let tiltDeg: [Double] = [-18, 24, -12]
    public static let phaseOffsets: [Double] = [0.0, 0.33, 0.66]
    public static let ringOpacities: [Double] = [0.88, 0.78, 0.62]
    /// Sign = direction (inner/outer prograde, middle retrograde).
    public static let idleOrbitHz: [Double] = [0.065, -0.042, 0.028]
    public static let speakingOrbitHz: [Double] = [0.11, -0.075, 0.048]

    public struct HexPose: Equatable, Sendable {
        public var rx: Double
        public var ry: Double
        public var rotation: Double
        public var opacity: Double
        public var wavePhase: Double
        public var waveAmp: Double
    }

    public struct OrbCorePose: Equatable, Sendable {
        public var sx: Double
        public var sy: Double
        public var glow: Double
        public var highlight: Double
        public var ripple: Double
        public var sheenAngle: Double
        public var metalWarp: Double
        public var diameter: Double
    }

    public struct RingPoint: Equatable, Sendable {
        public var x: Double
        public var y: Double
    }

    public enum Presence: Equatable, Sendable {
        case idle
        case listening
        case processing
        case speaking
    }

    public static var contrastRingIndices: [Int] {
        ringOpacities.enumerated().compactMap { $0.element >= contrastFloor ? $0.offset : nil }
    }

    /// Compact and hero share the same three-ring nest.
    public static var compactRingIndices: [Int] { Array(0..<ringCount) }

    public static func visibleRingIndices(size: Double) -> [Int] {
        _ = size
        return Array(0..<ringCount)
    }

    /// Inner ring is pearl/metal; outer is Forge orange accent.
    public static func ringIsPearl(_ index: Int) -> Bool {
        index == 0
    }

    public static func ringIsOrangeAccent(_ index: Int) -> Bool {
        index == ringCount - 1
    }

    public static func spinHz(for presence: Presence) -> Double {
        switch presence {
        case .idle, .listening: return idleSpinHz
        case .processing, .speaking: return speakingSpinHz
        }
    }

    public static func orbitHz(index: Int, presence: Presence) -> Double {
        let i = clampedIndex(index)
        switch presence {
        case .speaking, .processing: return speakingOrbitHz[i]
        case .idle, .listening: return idleOrbitHz[i]
        }
    }

    /// Speaking is fuller; idle keeps a living floor so the mark breathes.
    public static func waveformDrive(presence: Presence, amplitude: Double) -> Double {
        let energy = clamp01(amplitude)
        let boost: Double
        let floor: Double
        switch presence {
        case .speaking:
            boost = 1.0
            floor = 0.22
        case .processing:
            boost = 0.48
            floor = 0.14
        case .listening:
            boost = 0.36
            floor = 0.10
        case .idle:
            boost = 0.16
            floor = 0.12
        }
        return max(floor, energy * boost)
    }

    public static func hex(
        index: Int,
        time: Double,
        presence: Presence,
        reduceMotion: Bool
    ) -> HexPose {
        let i = clampedIndex(index)
        let radius = radii[i]
        let ecc = eccentricity[i]
        let tilt = tiltDeg[i] * .pi / 180
        let phase = phaseOffsets[i] * .pi * 2
        let still = stillPoseAngleDeg * .pi / 180 + phase
        let orbit: Double
        let wavePhase: Double
        let waveAmp: Double
        if reduceMotion {
            orbit = still
            wavePhase = phase
            waveAmp = 0.012
        } else {
            orbit = phase + time * orbitHz(index: i, presence: presence) * .pi * 2
            wavePhase = time * liquidWaveHz * .pi * 2 + phase
            let base: Double
            switch presence {
            case .idle: base = 0.016
            case .listening: base = 0.020
            case .processing: base = 0.024
            case .speaking: base = 0.032
            }
            waveAmp = base + Double(i) * 0.003
        }
        return HexPose(
            rx: radius * (1 + ecc),
            ry: radius * (1 - ecc),
            rotation: tilt + orbit,
            opacity: ringOpacities[i],
            wavePhase: wavePhase,
            waveAmp: waveAmp
        )
    }

    /// Soft orbit plus a restrained nest weave. Reduce Motion returns still.
    public static func livingHex(
        index: Int,
        time: Double,
        presence: Presence,
        amplitude: Double,
        reduceMotion: Bool
    ) -> HexPose {
        var pose = hex(index: index, time: time, presence: presence, reduceMotion: reduceMotion)
        guard !reduceMotion else { return pose }
        let drive = waveformDrive(presence: presence, amplitude: amplitude)
        let i = clampedIndex(index)
        let phase = time * waveformHz * .pi * 2 + phaseOffsets[i] * .pi * 2
        let wave = sin(phase)
        let wave2 = cos(phase * 1.18 + Double(i) * 0.4)
        pose.rx *= 1.0 + wave * 0.012 * drive
        pose.ry *= 1.0 + wave2 * 0.014 * drive
        pose.rotation += wave * 0.008 * drive
        pose.opacity = min(1.0, pose.opacity + drive * 0.06 * (0.55 + 0.45 * wave))
        pose.waveAmp *= 1.0 + 0.35 * drive
        pose.wavePhase += wave * 0.18 * drive
        return pose
    }

    /// Metal sun. Idle is a quiet pearl; speaking is a soft voice, not mercury.
    public static func orbCore(
        time: Double,
        presence: Presence,
        amplitude: Double,
        reduceMotion: Bool
    ) -> OrbCorePose {
        let diameter: Double
        switch presence {
        case .speaking, .processing: diameter = orbDiameterSpeaking
        case .idle, .listening: diameter = orbDiameterIdle
        }
        if reduceMotion {
            return OrbCorePose(
                sx: 1, sy: 1, glow: 0.48, highlight: 0.66,
                ripple: 0.08, sheenAngle: 0.55, metalWarp: 0,
                diameter: orbDiameterIdle
            )
        }
        let drive = waveformDrive(presence: presence, amplitude: amplitude)
        let phase = time * waveformHz * .pi * 2
        let metalPhase = time * metalRippleHz * .pi * 2
        let wave = sin(phase)
        let wave2 = cos(phase * 1.22 + 0.25)
        let ripple = sin(metalPhase) * 0.55 + sin(metalPhase * 1.35 + 0.7) * 0.45
        let warp = sin(metalPhase * 1.6 + 0.3) * cos(phase * 0.7)
        let breath = 0.008 * sin(time * 0.42 * .pi * 2)
        return OrbCorePose(
            sx: 1.0 + breath + wave * 0.04 * drive + warp * 0.016 * drive,
            sy: 1.0 + breath * 0.85 + wave2 * 0.05 * drive - warp * 0.018 * drive,
            glow: 0.44 + 0.22 * drive + 0.05 * wave * drive,
            highlight: 0.66 + 0.16 * drive,
            ripple: 0.08 + 0.36 * drive * (0.55 + 0.45 * abs(ripple)),
            sheenAngle: metalPhase,
            metalWarp: warp * drive * 0.55,
            diameter: diameter * (1.0 + 0.02 * drive * wave)
        )
    }

    public static func strokeWidth(size: Double, index: Int = 0) -> Double {
        _ = index
        let scaled = max(strokeWidthCompact, size * 0.018)
        let tier = size < heroMinimumSize ? strokeWidthCompact : strokeWidthHero
        return max(scaled, tier)
    }

    /// Unit-circle nest ring. 2-fold weave + a quiet 6-fold hex — not petals.
    public static func nestRingPoints(
        roundness: Double,
        wavePhase: Double,
        waveAmp: Double
    ) -> [RingPoint] {
        let soft = min(0.42, max(0.12, roundness))
        let amp = min(0.05, max(0, waveAmp))
        var points: [RingPoint] = []
        points.reserveCapacity(pathSamples)
        for i in 0..<pathSamples {
            let t = Double(i) / Double(pathSamples)
            let angle = t * .pi * 2
            let hexBias = 1.0 + (1.0 - soft) * hexBiasAmount * cos(6 * angle)
            let weave =
                0.72 * sin(2 * angle + wavePhase)
                + 0.28 * sin(6 * angle - wavePhase * 0.45)
            let liquid = 1.0 + amp * weave
            let r = hexBias * liquid
            points.append(RingPoint(x: r * cos(angle), y: r * sin(angle)))
        }
        return points
    }

    public static func nestRingPoint(
        angle: Double,
        roundness: Double,
        wavePhase: Double,
        waveAmp: Double
    ) -> RingPoint {
        let soft = min(0.42, max(0.12, roundness))
        let amp = min(0.05, max(0, waveAmp))
        let hexBias = 1.0 + (1.0 - soft) * hexBiasAmount * cos(6 * angle)
        let weave =
            0.72 * sin(2 * angle + wavePhase)
            + 0.28 * sin(6 * angle - wavePhase * 0.45)
        let r = hexBias * (1.0 + amp * weave)
        return RingPoint(x: r * cos(angle), y: r * sin(angle))
    }

    private static func clampedIndex(_ index: Int) -> Int {
        max(0, min(ringCount - 1, index))
    }

    private static func clamp01(_ value: Double) -> Double {
        min(1, max(0, value))
    }
}
