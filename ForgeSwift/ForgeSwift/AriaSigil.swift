import Foundation

/// Living 4-lobe ember. Lockstep with `src/lib/aria-mark.ts`.
enum AriaSigilGeometry: Sendable {

    static let stillPose: Double = 1.72
    static let idleBreathHz: Double = 0.42
    static let listeningBreathHz: Double = 0.55
    static let processingBreathHz: Double = 0.7
    static let speakingBreathHz: Double = 0.68
    static let maxGaze: Double = 0.14
    static let lobeCount: Int = 4

    private static let angles: [Double] = [0.62, 2.18, 3.92, 5.48]
    private static let dists: [Double] = [0.26, 0.24, 0.28, 0.23]
    private static let radii: [Double] = [0.44, 0.41, 0.43, 0.40]
    private static let phases: [Double] = [0.0, 1.1, 2.4, 3.6]

    static func breathHz(for state: AROrbState) -> Double {
        switch state {
        case .idle: return idleBreathHz
        case .listening: return listeningBreathHz
        case .processing: return processingBreathHz
        case .speaking: return speakingBreathHz
        }
    }

    static func clampGaze(_ value: Double) -> Double {
        min(maxGaze, max(-maxGaze, value))
    }

    static func gaze(time: Double, state: AROrbState, reduceMotion: Bool) -> (x: Double, y: Double) {
        if reduceMotion { return (0.02, -0.02) }
        let wander = state == .listening ? 0.55 : 0.32
        let x = sin(time * 0.19) * maxGaze * wander
        let y = cos(time * 0.15) * maxGaze * wander * 0.7
        let attend: Double = state == .listening ? 0.03 : state == .speaking ? -0.02 : 0
        return (clampGaze(x), clampGaze(y + attend))
    }

    static func lobe(index: Int, time: Double, state: AROrbState, reduceMotion: Bool) -> (x: Double, y: Double, r: Double) {
        let i = max(0, min(lobeCount - 1, index))
        let angle = angles[i]
        let dist = dists[i]
        let radius = radii[i]
        let phase = phases[i]
        if reduceMotion {
            return (cos(angle) * dist, sin(angle) * dist, radius)
        }
        let hz = breathHz(for: state)
        let wave = sin(time * hz * .pi * 2 + phase)
        let liveDist = dist + 0.045 * wave
        let liveAngle = angle + 0.09 * sin(time * 0.28 * .pi * 2 + phase)
        let liveR = radius * (0.93 + 0.09 * (0.5 + 0.5 * sin(time * hz * .pi * 2)))
        return (cos(liveAngle) * liveDist, sin(liveAngle) * liveDist, liveR)
    }

    static func coreRadius(time: Double, state: AROrbState, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.22 }
        let wave = 0.5 + 0.5 * sin(time * breathHz(for: state) * .pi * 2)
        let talk = state == .speaking ? 0.04 : 0
        return 0.18 + wave * 0.07 + talk
    }
}

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
