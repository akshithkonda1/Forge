import SwiftUI
import ForgeCore

// MARK: - AuroraOrbWatch
//
// Wrist-small living ember: warm hearth + cooler rim as one body.
// Compared to AuroraOrbComponents.swift on iOS this version:
//  - draws everything in ONE Canvas inside ONE TimelineView (the iOS orb
//    runs nine TimelineViews — fine on an A-series chip, wasteful on S9)
//  - uses two filled layers only (Watch is ≤32pt / wrist-small — four
//    lobes would read as noise, a stroked ring would read as a halo)
//  - ticks at 12 Hz with ≤0.15 Hz spatial wobble (epilepsy bar)
//  - freezes to a still pose when Reduce Motion, Minimal Animation, or
//    always-on dimming is on; Reduce Motion keeps an opacity swell only
//    (same contract as BreathingOrb)
//
// Geometry numbers lockstep with AriaSigilGeometry (iOS target — Watch
// cannot see that file without pulling AROrbState into ForgeCore). Do
// not invent a ring. No PNG / raster.

struct AuroraOrbWatch: View {
    var accent: Color = ForgePalette.steel
    var size: CGFloat = 32
    /// 0...1 — how alive the ember feels (readiness confidence or session energy).
    var intensity: Double = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation

    private var staticRendering: Bool { reduceMotion || minimalAnimation }

    var body: some View {
        TimelineView(.animation(minimumInterval: WatchEmberGeometry.tickInterval, paused: luminanceReduced)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            emberCanvas(time: t, staticRendering: staticRendering || luminanceReduced)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // decorative — the ring/score carry meaning
    }

    private func emberCanvas(time: Double, staticRendering: Bool) -> some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            guard s >= 2 else { return }
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)

            let pose = staticRendering ? WatchEmberGeometry.stillPose : time
            let gaze = WatchEmberGeometry.gaze(time: pose, reduceMotion: staticRendering)
            let hearthR = WatchEmberGeometry.hearthRadius(time: pose, intensity: intensity, reduceMotion: staticRendering)
            let rimR = WatchEmberGeometry.rimRadius(time: pose, intensity: intensity, reduceMotion: staticRendering)

            // AOD / still: dim only. Reduce Motion: opacity swell, no spatial travel.
            let pulse: Double
            if luminanceReduced {
                pulse = 0.55
            } else if staticRendering {
                pulse = 0.72 + 0.18 * WatchEmberGeometry.breath(time: time)
            } else {
                pulse = 0.85 + 0.15 * intensity
            }

            let hearthCenter = CGPoint(
                x: center.x + CGFloat(gaze.x) * s * 0.35,
                y: center.y + CGFloat(gaze.y) * s * 0.35
            )
            let rimCenter = CGPoint(
                x: center.x + CGFloat(gaze.x) * s * 0.5,
                y: center.y + CGFloat(gaze.y) * s * 0.5
            )

            let rimPx = CGFloat(rimR) * s
            let hearthPx = CGFloat(hearthR) * s
            guard rimPx >= 0.5, hearthPx >= 0.5 else { return }

            // Layer 1 — cooler rim. Filled body, not a stroked circle.
            context.fill(
                Path(ellipseIn: CGRect(
                    x: rimCenter.x - rimPx, y: rimCenter.y - rimPx,
                    width: rimPx * 2, height: rimPx * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(forgeHex: WatchEmberGeometry.emberHex).opacity(0.38 * pulse),
                        accent.opacity(0.22 * pulse),
                        Color(forgeHex: WatchEmberGeometry.coolHex).opacity(0.16 * pulse),
                        .clear
                    ]),
                    center: rimCenter,
                    startRadius: 0,
                    endRadius: rimPx
                )
            )

            // Layer 2 — warm hearth. Same one-body silhouette, hotter core.
            context.fill(
                Path(ellipseIn: CGRect(
                    x: hearthCenter.x - hearthPx, y: hearthCenter.y - hearthPx,
                    width: hearthPx * 2, height: hearthPx * 2
                )),
                with: .radialGradient(
                    Gradient(colors: [
                        Color(forgeHex: WatchEmberGeometry.hotHex).opacity(0.78 * pulse),
                        Color(forgeHex: WatchEmberGeometry.emberHex).opacity(0.52 * pulse),
                        .clear
                    ]),
                    center: hearthCenter,
                    startRadius: 0,
                    endRadius: hearthPx
                )
            )
        }
    }
}

// MARK: - WatchEmberGeometry
//
// Spatial lockstep with AriaSigilGeometry / src/lib/aria-mark.ts.
// Temporal rate is the Watch epilepsy bar (≤0.15 Hz), not iOS breath Hz
// (idle 0.42 / speaking 0.68 would exceed the wobble ceiling).

private enum WatchEmberGeometry {
    static let stillPose: Double = 1.72
    static let maxGaze: Double = 0.14
    static let wobbleHz: Double = 0.15
    /// TimelineView interval — 12 Hz ceiling (1/12 s).
    static let tickInterval: Double = 1.0 / 12.0

    /// AriaSigilPalette / EmberCanvas stops — warm-dominant, not neon.
    static let emberHex = "FF6A1A"
    static let hotHex = "FFE28A"
    static let coolHex = "3EC8C8"

    // Four-lobe envelope collapsed to one rim (mean dist + mean r).
    private static let meanDist: Double = (0.26 + 0.24 + 0.28 + 0.23) / 4
    private static let meanRadius: Double = (0.44 + 0.41 + 0.43 + 0.40) / 4

    static func breath(time: Double) -> Double {
        0.5 + 0.5 * sin(time * wobbleHz * .pi * 2)
    }

    static func gaze(time: Double, reduceMotion: Bool) -> (x: Double, y: Double) {
        if reduceMotion { return (0.02, -0.02) }
        let wander = 0.32
        let x = sin(time * wobbleHz * .pi * 2) * maxGaze * wander
        let y = cos(time * wobbleHz * .pi * 2) * maxGaze * wander * 0.7
        return (
            min(maxGaze, max(-maxGaze, x)),
            min(maxGaze, max(-maxGaze, y))
        )
    }

    /// AriaSigilGeometry.coreRadius — idle numbers, Watch-safe Hz.
    static func hearthRadius(time: Double, intensity: Double, reduceMotion: Bool) -> Double {
        if reduceMotion { return 0.22 }
        let wave = breath(time: time)
        return 0.18 + wave * 0.07 * (0.65 + 0.35 * intensity)
    }

    /// Single outer body from the 4-lobe envelope. iOS draws each lobe at
    /// `r * s * 0.5` offset by `dist * s * 0.5`; the collapsed rim is that
    /// extent as one filled disc, not four blobs and not a ring stroke.
    static func rimRadius(time: Double, intensity: Double, reduceMotion: Bool) -> Double {
        let envelope = (meanDist + meanRadius) * 0.5
        if reduceMotion { return envelope }
        let wave = 0.5 + 0.5 * sin(time * wobbleHz * .pi * 2 + 1.1)
        return envelope * (0.93 + 0.09 * wave) * (0.88 + 0.12 * intensity)
    }
}
