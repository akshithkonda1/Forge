import SwiftUI
import ForgeCore

// MARK: - AuroraOrbWatch
//
// Home / data language only: Lex kinetic orange ring-field. Not the logo.
// Watch onboarding / brand face stays `AriaNestMarkWatch` (`AriaNestGeometry`).
// Compared to AuroraOrbComponents.swift on iOS this version:
//  - draws everything in ONE Canvas inside ONE TimelineView (the iOS orb
//    composites Ellipse views — fine on an A-series chip, wasteful on S9)
//  - hero (≥90pt) draws all five ellipses; Watch ≤32pt / size < 90 uses
//    compactRingIndices (two ≥0.70 + strongest support)
//  - ticks at 12 Hz; data rings spin at idleSpinHz 0.04 (speakingSpinHz 0.075
//    lives in the shared geometry)
//  - freezes at stillPoseAngleDeg 18 when Reduce Motion, Minimal Animation,
//    or always-on dimming is on
//
// Geometry is ForgeCore AriaRingFieldGeometry. Do not invent a second ring.
// No PNG / raster. ReadinessRing at Home is score chrome around this field.

struct AuroraOrbWatch: View {
    var accent: Color = ForgePalette.steel
    var size: CGFloat = 32
    /// 0...1 — kept for Home readiness call-site compatibility.
    var intensity: Double = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    private var frozen: Bool { reduceMotion || minimalAnimation || luminanceReduced }

    var body: some View {
        let _ = (accent, intensity)
        TimelineView(.animation(minimumInterval: 1.0 / 12.0, paused: frozen)) { timeline in
            let t = frozen
                ? AriaRingFieldGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            ringCanvas(time: t, frozen: frozen)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // decorative — the ring/score carry meaning
    }

    private func ringCanvas(time: Double, frozen: Bool) -> some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            guard s >= 2 else { return }
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let orange = Color(forgeHex: AriaRingFieldGeometry.forgeOrangeHex)
            let indices = AriaRingFieldGeometry.visibleRingIndices(size: size)

            for index in indices {
                let pose = AriaRingFieldGeometry.ellipse(
                    index: index,
                    time: time,
                    speaking: false,
                    reduceMotion: frozen
                )
                let width = CGFloat(pose.rx) * s
                let height = CGFloat(pose.ry) * s
                guard width >= 1, height >= 1 else { continue }
                let lineWidth = AriaRingFieldGeometry.strokeWidth(size: size, index: index)

                context.drawLayer { layer in
                    layer.translateBy(x: center.x, y: center.y)
                    layer.rotate(by: .radians(pose.rotation))
                    layer.stroke(
                        Path(ellipseIn: CGRect(
                            x: -width / 2,
                            y: -height / 2,
                            width: width,
                            height: height
                        )),
                        with: .color(orange.opacity(pose.opacity)),
                        lineWidth: lineWidth
                    )
                }
            }
        }
    }
}
