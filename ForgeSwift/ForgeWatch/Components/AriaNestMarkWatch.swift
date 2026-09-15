import SwiftUI
import ForgeCore

// MARK: - AriaNestMarkWatch
//
// Wrist identity mark — B+E nest (soft-hex + metal sun). One Canvas inside
// one TimelineView at ≤12 Hz. Home readiness glow stays `AuroraOrbWatch` +
// `ReadinessRing` (data language). This view is the brand mark.
//
// Geometry is `AriaNestGeometry` in ForgeCore. Do not invent a second nest.

struct AriaNestMarkWatch: View {
    var presence: AriaNestGeometry.Presence = .idle
    var size: CGFloat = 64
    var amplitude: Double = 0.28

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation

    private var frozen: Bool {
        reduceMotion
            || minimalAnimation
            || luminanceReduced
            || !AriaNestGeometry.shouldOrbit(size: Double(size), reduceMotion: false)
    }

    var body: some View {
        TimelineView(.animation(
            minimumInterval: frozen ? 1 : AriaNestGeometry.tickInterval,
            paused: frozen
        )) { timeline in
            let t = frozen
                ? AriaNestGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            Canvas { context, canvasSize in
                paint(context: &context, canvasSize: canvasSize, time: t)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private func paint(context: inout GraphicsContext, canvasSize: CGSize, time: Double) {
        let s = min(canvasSize.width, canvasSize.height)
        guard s >= 2 else { return }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let orange = Color(forgeHex: AriaNestGeometry.forgeOrangeHex)
        let pearl = Color(forgeHex: AriaNestGeometry.pearlHex)
        let pearlHot = Color(forgeHex: AriaNestGeometry.pearlHotHex)
        let metalCool = Color(forgeHex: AriaNestGeometry.metalCoolHex)

        let washR = s * 0.42
        context.fill(
            Path(ellipseIn: CGRect(x: center.x - washR, y: center.y - washR, width: washR * 2, height: washR * 2)),
            with: .radialGradient(
                Gradient(colors: [
                    pearlHot.opacity(0.16),
                    orange.opacity(0.06),
                    .clear
                ]),
                center: center,
                startRadius: 1,
                endRadius: washR
            )
        )

        for index in AriaNestGeometry.visibleRingIndices(size: Double(s)).reversed() {
            let pose = AriaNestGeometry.livingHex(
                index: index,
                time: time,
                presence: presence,
                amplitude: amplitude,
                reduceMotion: frozen
            )
            let stroke = Color(forgeHex: AriaNestGeometry.ringHex(at: index))
            let path = nestPath(
                center: center,
                width: s * pose.rx,
                height: s * pose.ry,
                rotation: pose.rotation,
                wavePhase: pose.wavePhase,
                waveAmp: pose.waveAmp
            )
            context.stroke(
                path,
                with: .color(stroke.opacity(min(1, pose.opacity))),
                lineWidth: CGFloat(AriaNestGeometry.strokeWidth(size: Double(s), index: index))
            )
        }

        let core = AriaNestGeometry.orbCore(
            time: time,
            presence: presence,
            amplitude: amplitude,
            reduceMotion: frozen
        )
        let diameter = s * core.diameter
        let body = CGRect(
            x: center.x - diameter * core.sx / 2,
            y: center.y - diameter * core.sy / 2,
            width: diameter * core.sx,
            height: diameter * core.sy
        )
        context.fill(
            Path(ellipseIn: body),
            with: .radialGradient(
                Gradient(colors: [
                    pearlHot.opacity(0.96),
                    metalCool.opacity(0.88),
                    pearl.opacity(0.7)
                ]),
                center: CGPoint(x: center.x - diameter * 0.12, y: center.y - diameter * 0.14),
                startRadius: 0,
                endRadius: diameter * 0.55
            )
        )
    }

    private func nestPath(
        center: CGPoint,
        width: CGFloat,
        height: CGFloat,
        rotation: Double,
        wavePhase: Double,
        waveAmp: Double
    ) -> Path {
        let points = AriaNestGeometry.nestRingPoints(
            roundness: AriaNestGeometry.cornerRoundness,
            wavePhase: wavePhase,
            waveAmp: waveAmp
        )
        let cosR = cos(rotation)
        let sinR = sin(rotation)
        var path = Path()
        for (i, point) in points.enumerated() {
            let x = CGFloat(point.x) * width * 0.5
            let y = CGFloat(point.y) * height * 0.5
            let mapped = CGPoint(
                x: center.x + x * cosR - y * sinR,
                y: center.y + x * sinR + y * cosR
            )
            if i == 0 { path.move(to: mapped) } else { path.addLine(to: mapped) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview("Watch nest idle") {
    ZStack {
        Color.black.ignoresSafeArea()
        AriaNestMarkWatch(presence: .idle, size: 72)
    }
}

#Preview("Watch nest still") {
    ZStack {
        Color.black.ignoresSafeArea()
        AriaNestMarkWatch(presence: .idle, size: 72)
            .environment(\.forgeMinimalAnimation, true)
    }
}
