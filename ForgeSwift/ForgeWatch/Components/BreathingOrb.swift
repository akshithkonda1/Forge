import SwiftUI
import ForgeCore

// MARK: - BreathingOrb
//
// The heart of a mindfulness session. One TimelineView + one Canvas at
// 30fps (comfortably smooth for breath-speed motion at a fraction of the
// battery of 60fps; ProMotion isn't the bottleneck — breath is).
//
// The orb's scale follows the breathing pattern exactly: it grows on
// inhale, holds, and releases on exhale, easing with a sine curve so
// turnarounds feel organic. Haptics are scheduled by
// MindfulnessSessionManager — the orb is pure rendering, so the eyes-free
// experience works even with the wrist down.
//
// Reduce Motion: scaling is replaced by a slow opacity swell on a fixed
// circle plus the phase label — guidance intact, motion minimal.
// Epilepsy safety: the fastest luminance change tracks the breath itself
// (≥ 1.5s per phase, << 3 Hz), no flashes.

struct BreathingOrb: View {
    let pattern: BreathingPattern
    var accent: Color = ForgePalette.teal
    /// Maps a frame timestamp to seconds elapsed in the session (the
    /// session manager owns pause/resume bookkeeping).
    var elapsed: (Date) -> TimeInterval
    var isPaused: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: isPaused || luminanceReduced)) { timeline in
            let t = elapsed(timeline.date)
            let (phase, progress) = pattern.phase(at: t)

            ZStack {
                Canvas { context, size in
                    draw(context: context, size: size, phase: phase, progress: progress, time: t)
                }

                Text(phase.kind.instruction)
                    .font(ForgeType.caption(13))
                    .foregroundStyle(ForgePalette.textSecondary)
                    .offset(y: 58)
                    .animation(.easeInOut(duration: 0.3), value: phase.kind)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Breathing guide")
        .accessibilityValue(isPaused ? "Paused" : "In progress. Follow the taps on your wrist.")
        .accessibilityHint("The wrist taps mark each breath: rising taps to breathe in, falling taps to breathe out.")
    }

    // MARK: Rendering

    /// Sine-eased breath fraction: 0 = fully released, 1 = fully drawn in.
    private func breathFraction(phase: BreathPhase, progress: Double) -> Double {
        let eased = 0.5 - 0.5 * cos(progress * .pi)
        switch phase.kind {
        case .inhale:      return eased
        case .quickInhale: return 0.85 + eased * 0.15  // small top-up sip
        case .holdIn:      return 1.0
        case .exhale:      return 1.0 - eased
        case .holdOut:     return 0.0
        case .rest:        return 0.15 + 0.05 * sin(progress * .pi) // barely-there sway
        }
    }

    private func draw(context: GraphicsContext, size: CGSize, phase: BreathPhase, progress: Double, time: Double) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let maxRadius = min(size.width, size.height) / 2 - 6
        let fraction = breathFraction(phase: phase, progress: progress)

        if reduceMotion {
            // Fixed-size circle; only opacity breathes.
            let radius = maxRadius * 0.66
            let circle = Path(ellipseIn: CGRect(
                x: center.x - radius, y: center.y - radius,
                width: radius * 2, height: radius * 2
            ))
            context.fill(circle, with: .radialGradient(
                Gradient(colors: [accent.opacity(0.25 + fraction * 0.4), accent.opacity(0.05)]),
                center: center, startRadius: 0, endRadius: radius
            ))
            context.stroke(circle, with: .color(accent.opacity(0.5 + fraction * 0.4)), lineWidth: 2)
            return
        }

        // Breathing disc.
        let radius = maxRadius * (0.42 + 0.40 * fraction)
        let disc = Path(ellipseIn: CGRect(
            x: center.x - radius, y: center.y - radius,
            width: radius * 2, height: radius * 2
        ))
        context.fill(disc, with: .radialGradient(
            Gradient(colors: [
                accent.opacity(0.55),
                accent.opacity(0.22),
                accent.opacity(0.04),
            ]),
            center: center, startRadius: radius * 0.1, endRadius: radius
        ))
        context.stroke(disc, with: .color(accent.opacity(0.85)), lineWidth: 1.5)

        // Two gentle aurora rings drift just outside the disc.
        for (index, speed) in [0.45, 0.7].enumerated() {
            let ringAmp = maxRadius * 0.05
            var path = Path()
            let steps = 24
            for step in 0...steps {
                let angle = Double(step) / Double(steps) * .pi * 2
                let wobble = sin(angle * 3 + time * speed + Double(index) * 2.1) * ringAmp
                let r = radius + 7 + wobble
                let point = CGPoint(
                    x: center.x + CGFloat(cos(angle) * r),
                    y: center.y + CGFloat(sin(angle) * r)
                )
                if step == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            context.stroke(path, with: .color(accent.opacity(0.18 + Double(index) * 0.1)), lineWidth: 1)
        }

        // Phase progress tick ring — a thin arc completing over the phase,
        // helpful once users learn to pace holds by it.
        var arc = Path()
        arc.addArc(
            center: center, radius: maxRadius,
            startAngle: .degrees(-90),
            endAngle: .degrees(-90 + 360 * progress),
            clockwise: false
        )
        context.stroke(arc, with: .color(accent.opacity(0.35)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
    }
}
