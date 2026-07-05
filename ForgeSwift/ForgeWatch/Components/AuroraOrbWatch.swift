import SwiftUI
import ForgeCore

// MARK: - AuroraOrbWatch
//
// The iOS Aurora Orb, distilled for the wrist. Compared to
// AuroraOrbComponents.swift on iOS this version:
//  - draws everything in ONE Canvas inside ONE TimelineView (the iOS orb
//    runs nine TimelineViews — fine on an A-series chip, wasteful on S9)
//  - runs at 30fps with 3 wave rings and no particles or blur
//  - freezes to a static, intentional composition when Reduce Motion is
//    on or the display is in always-on dimmed mode (battery + AOD craft)
//
// Epilepsy safety: wave wobble is slow (≤ 0.15 Hz per ring), low contrast,
// and there is no flashing or strobing anywhere.

struct AuroraOrbWatch: View {
    var accent: Color = ForgePalette.steel
    var size: CGFloat = 72
    /// 0...1 — how alive the orb feels (readiness confidence or session energy).
    var intensity: Double = 0.5

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation

    private var animated: Bool { !reduceMotion && !luminanceReduced && !minimalAnimation }

    var body: some View {
        Group {
            if animated {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
                    orbCanvas(time: timeline.date.timeIntervalSinceReferenceDate)
                }
            } else {
                // Static fallback: same composition, frozen at a pleasing phase.
                orbCanvas(time: 1.2, staticRendering: true)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true) // decorative — the ring/score carry meaning
    }

    private func orbCanvas(time: Double, staticRendering: Bool = false) -> some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let radius = min(canvasSize.width, canvasSize.height) / 2

            // Core: soft radial glow, dimmed further in AOD.
            let coreOpacity = staticRendering && luminanceReduced ? 0.25 : 0.45
            let core = Path(ellipseIn: CGRect(
                x: center.x - radius * 0.8, y: center.y - radius * 0.8,
                width: radius * 1.6, height: radius * 1.6
            ))
            context.fill(core, with: .radialGradient(
                Gradient(colors: [
                    accent.opacity(coreOpacity),
                    accent.opacity(0.08),
                    .clear,
                ]),
                center: center, startRadius: 0, endRadius: radius * 0.9
            ))

            // Three slow aurora rings (ported wave math from AuroraWaveCanvas).
            let configs: [(phase: Double, speed: Double, opacity: Double)] = [
                (0.0, 0.55, 0.20), (1.8, 0.75, 0.30), (3.4, 0.95, 0.40),
            ]
            for config in configs {
                let waveAmp = radius * 0.07 * (0.6 + intensity)
                var path = Path()
                let steps = 24
                for step in 0...steps {
                    let angle = Double(step) / Double(steps) * .pi * 2
                    let wobble = sin(angle * 3 + time * config.speed + config.phase) * waveAmp
                    let r = radius * 0.80 + wobble
                    let point = CGPoint(
                        x: center.x + CGFloat(cos(angle) * r),
                        y: center.y + CGFloat(sin(angle) * r)
                    )
                    if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                path.closeSubpath()
                let opacity = staticRendering ? config.opacity * 0.6 : config.opacity
                context.stroke(path, with: .color(accent.opacity(opacity)), lineWidth: 1.2)
            }
        }
    }
}
