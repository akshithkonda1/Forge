import SwiftUI

/// Compact ARIA mark for avatars, tabs, and cards.
/// The halo is part of the identity — do not clip it.
struct ARIAIdentityMark: View {
    var state: AROrbState = .idle
    var mood: ARIAMood = .focused
    var size: CGFloat = 40
    var amplitude: Float = 0.22
    var showsPresence: Bool = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            AuroraOrbView(
                state: state,
                amplitude: amplitude,
                mood: mood,
                size: size,
                followPresence: true
            )
            if showsPresence {
                Circle()
                    .stroke(Color(hex: AriaSigilPalette.goldHex), lineWidth: max(1.0, size * 0.045))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
                    .opacity(0.85)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// ARIA's face. An onyx lens with a photon ring and a mind in the void —
/// valuable, a little dangerous, still something you can trust.
struct AuroraOrbView: View {
    let state: AROrbState
    let amplitude: Float
    var mood: ARIAMood = .focused
    var size: CGFloat = 140
    var followPresence: Bool = false

    private let presence = AriaPresence.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var resolvedState: AROrbState {
        followPresence && presence.orbState != .idle ? presence.orbState : state
    }

    private var resolvedAmplitude: Float {
        if followPresence, presence.isSpeaking { return max(amplitude, 0.72) }
        if followPresence, presence.isListening { return max(amplitude, max(presence.amplitude, 0.42)) }
        return amplitude
    }

    private var tick: Double {
        if reduceMotion { return 1 }
        if size < 36 { return 1.0 / 16.0 }
        if size < 80 { return 1.0 / 20.0 }
        return 1.0 / 24.0
    }

    private var gold: Color { Color(hex: AriaSigilPalette.goldHex) }
    private var goldHot: Color { Color(hex: AriaSigilPalette.goldHotHex) }
    private var ivory: Color { Color(hex: AriaSigilPalette.ivoryHex) }
    private var frost: Color { Color(hex: AriaSigilPalette.frostHex) }
    private var blood: Color { Color(hex: AriaSigilPalette.bloodHex) }
    private var photonA: Color { Color(hex: AriaSigilPalette.photonPrimary(for: mood)) }
    private var photonB: Color { Color(hex: AriaSigilPalette.photonSecondary(for: mood)) }

    private func scaled(_ ratio: Double) -> CGFloat { size * CGFloat(ratio) }

    var body: some View {
        TimelineView(.animation(
            minimumInterval: tick,
            paused: reduceMotion || scenePhase != .active
        )) { timeline in
            let t = reduceMotion
                ? AriaSigilGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            sigil(at: t)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            resolvedState == .speaking ? "ARIA speaking"
                : resolvedState == .listening ? "ARIA listening"
                : "ARIA"
        )
        .accessibilityAddTraits(resolvedState == .idle ? AccessibilityTraits() : .updatesFrequently)
    }

    private func sigil(at t: TimeInterval) -> some View {
        let live = resolvedState
        let amp = Double(resolvedAmplitude)
        let breath = AriaSigilGeometry.breath(time: t, state: live, reduceMotion: reduceMotion)
        let spin = AriaSigilGeometry.photonSpinDegrees(time: t, state: live, reduceMotion: reduceMotion)
        let inner = AriaSigilGeometry.innerSpinDegrees(time: t, state: live, reduceMotion: reduceMotion)
        let gaze = AriaSigilGeometry.gaze(time: t, state: live, reduceMotion: reduceMotion)
        let glow = AriaSigilGeometry.mindGlow(amplitude: amp, state: live, breath: breath)
        let halo = AriaSigilGeometry.haloOpacity(state: live, breath: breath)
        let compact = size < 48
        let floatY: CGFloat = (!reduceMotion && size >= 90) ? CGFloat(sin(t * 0.55)) * size * 0.012 : 0
        let scale: CGFloat = 1 + CGFloat(breath) * (size >= 90 ? 0.018 : 0.012)

        return ZStack {
            gravityWell(halo: halo, live: live, glow: glow)
            voidSphere
            if !compact {
                AriaSigilField(
                    size: size,
                    time: t,
                    breath: breath,
                    innerSpin: inner,
                    gaze: gaze,
                    gold: gold,
                    photonA: photonA,
                    photonB: photonB,
                    frost: frost,
                    blood: blood,
                    live: live
                )
            }
            eventHorizon
            mind(glow: glow, gaze: gaze, live: live)
            photonRing(spin: spin, breath: breath, live: live)
            if live == .listening && !reduceMotion {
                listenLimb
            }
            specular
            eclipseLimb
        }
        .frame(width: size, height: size)
        .scaleEffect(scale)
        .offset(y: floatY)
    }

    /// Almost no color. A well, not a glow stick.
    private func gravityWell(halo: Double, live: AROrbState, glow: Double) -> some View {
        let cold = live == .listening
        return Circle()
            .fill(
                RadialGradient(
                    colors: [
                        (cold ? frost : gold).opacity(0.16 * halo + glow * 0.08),
                        blood.opacity(0.14 * halo),
                        Color.clear
                    ],
                    center: .center,
                    startRadius: size * 0.18,
                    endRadius: size * 0.82
                )
            )
            .frame(width: size * 1.72, height: size * 1.72)
            .blur(radius: max(6, size * 0.16))
            .opacity(reduceMotion ? 0.45 : 0.9)
    }

    private var voidSphere: some View {
        Circle()
            .fill(
                RadialGradient(
                    colors: [
                        Color(hex: AriaSigilPalette.voidMidHex),
                        Color(hex: AriaSigilPalette.voidDeepHex),
                        blood.opacity(0.55),
                        Color(hex: AriaSigilPalette.voidDeepHex)
                    ],
                    center: UnitPoint(x: 0.38, y: 0.32),
                    startRadius: 0,
                    endRadius: size * 0.56
                )
            )
            .frame(
                width: scaled(AriaSigilGeometry.voidRatio),
                height: scaled(AriaSigilGeometry.voidRatio)
            )
            .overlay {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                ivory.opacity(0.14),
                                Color.clear
                            ],
                            center: UnitPoint(x: 0.34, y: 0.28),
                            startRadius: 0,
                            endRadius: size * 0.28
                        )
                    )
                    .blendMode(.screen)
            }
    }

    private var eventHorizon: some View {
        Circle()
            .stroke(
                AngularGradient(
                    colors: [
                        gold.opacity(0.22),
                        Color.clear,
                        gold.opacity(0.08),
                        frost.opacity(0.10),
                        gold.opacity(0.22)
                    ],
                    center: .center
                ),
                lineWidth: max(0.6, size * 0.012)
            )
            .frame(
                width: scaled(AriaSigilGeometry.horizonRatio),
                height: scaled(AriaSigilGeometry.horizonRatio)
            )
            .opacity(0.85)
    }

    private func mind(glow: Double, gaze: (x: Double, y: Double), live: AROrbState) -> some View {
        let r = scaled(AriaSigilGeometry.mindRatio) * (0.92 + CGFloat(glow) * 0.28)
        let spark = live == .speaking ? ivory : goldHot
        return ZStack {
            Circle()
                .fill(spark.opacity(0.28 + glow * 0.35))
                .frame(width: r * 2.8, height: r * 2.8)
                .blur(radius: r * 0.9)
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            ivory.opacity(0.95),
                            spark.opacity(0.9),
                            Color(hex: AriaSigilPalette.bloodHex).opacity(0.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: r * 0.72
                    )
                )
                .frame(width: r, height: r)
        }
        .offset(x: scaled(gaze.x), y: scaled(gaze.y))
        .blendMode(.screen)
        .opacity(0.72 + glow * 0.28)
    }

    private func photonRing(spin: Double, breath: Double, live: AROrbState) -> some View {
        let width = max(1.0, scaled(AriaSigilGeometry.photonWidthRatio))
            * (live == .idle ? 1.0 : 1.15)
        return Circle()
            .trim(
                from: CGFloat(AriaSigilGeometry.photonTrimStart),
                to: CGFloat(AriaSigilGeometry.photonTrimEnd)
            )
            .stroke(
                AngularGradient(
                    colors: [
                        photonA.opacity(0.92),
                        ivory.opacity(0.35),
                        photonB.opacity(0.18),
                        Color.clear,
                        photonB.opacity(0.55),
                        photonA.opacity(0.92)
                    ],
                    center: .center
                ),
                style: StrokeStyle(lineWidth: width, lineCap: .round)
            )
            .frame(
                width: scaled(AriaSigilGeometry.photonRatio),
                height: scaled(AriaSigilGeometry.photonRatio)
            )
            .rotationEffect(.degrees(spin))
            .opacity(0.72 + breath * 0.22)
            .shadow(color: photonA.opacity(live == .speaking ? 0.45 : 0.18), radius: max(2, size * 0.04))
    }

    private var listenLimb: some View {
        Circle()
            .stroke(frost.opacity(0.28), lineWidth: max(0.7, size * 0.012))
            .frame(width: size * 0.96, height: size * 0.96)
            .opacity(0.7)
    }

    /// A real object has a highlight. Without this she looks like a UI blob.
    private var specular: some View {
        let r = scaled(AriaSigilGeometry.specularRatio)
        return Ellipse()
            .fill(
                RadialGradient(
                    colors: [ivory.opacity(0.72), ivory.opacity(0.0)],
                    center: .center,
                    startRadius: 0,
                    endRadius: r
                )
            )
            .frame(width: r * 1.6, height: r)
            .rotationEffect(.degrees(-28))
            .offset(x: -size * 0.16, y: -size * 0.20)
            .blendMode(.screen)
            .opacity(0.7)
    }

    /// Terminator — the edge that makes her a stone, not a gradient.
    private var eclipseLimb: some View {
        Circle()
            .stroke(
                LinearGradient(
                    colors: [
                        ivory.opacity(0.16),
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.85)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: max(0.8, size * 0.018)
            )
            .frame(
                width: scaled(AriaSigilGeometry.voidRatio),
                height: scaled(AriaSigilGeometry.voidRatio)
            )
    }
}

/// Iris filaments and a slow inner orbit. Large marks only — at 22pt the
/// photon ring and mind are the whole logo.
private struct AriaSigilField: View {
    let size: CGFloat
    let time: Double
    let breath: Double
    let innerSpin: Double
    let gaze: (x: Double, y: Double)
    let gold: Color
    let photonA: Color
    let photonB: Color
    let frost: Color
    let blood: Color
    let live: AROrbState

    var body: some View {
        Canvas { context, canvasSize in
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            drawIris(context: &context, center: center, canvas: canvasSize)
            drawFilaments(context: &context, center: center, canvas: canvasSize)
            drawDust(context: &context, center: center, canvas: canvasSize)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    private func drawIris(context: inout GraphicsContext, center: CGPoint, canvas: CGSize) {
        let radii: [CGFloat] = [0.22, 0.28, 0.33]
        for (i, ratio) in radii.enumerated() {
            let r = canvas.width * ratio
            var path = Path()
            path.addArc(
                center: CGPoint(
                    x: center.x + CGFloat(gaze.x) * canvas.width * 0.35,
                    y: center.y + CGFloat(gaze.y) * canvas.height * 0.35
                ),
                radius: r,
                startAngle: .degrees(18 + Double(i) * 22 + innerSpin * 0.4),
                endAngle: .degrees(262 + Double(i) * 14 + innerSpin * 0.4),
                clockwise: false
            )
            let color = i == 1 ? frost.opacity(0.16 + breath * 0.08) : gold.opacity(0.20 - Double(i) * 0.04)
            context.stroke(path, with: .color(color), lineWidth: max(0.6, canvas.width * 0.008))
        }
    }

    private func drawFilaments(context: inout GraphicsContext, center: CGPoint, canvas: CGSize) {
        let count = live == .idle ? 2 : 3
        for i in 0..<count {
            let rot = innerSpin * .pi / 180 + Double(i) * 0.9
            let rx = canvas.width * AriaSigilGeometry.filamentRatio * (0.92 + Double(i) * 0.06)
            let ry = rx * (0.42 + Double(i) * 0.08)
            var path = Path()
            let steps = 48
            for step in 0...steps {
                let a = Double(step) / Double(steps) * .pi * 2
                let x = cos(a) * rx
                let y = sin(a) * ry
                let xr = x * cos(rot) - y * sin(rot)
                let yr = x * sin(rot) + y * cos(rot)
                let p = CGPoint(x: center.x + xr, y: center.y + yr)
                if step == 0 { path.move(to: p) }
                else { path.addLine(to: p) }
            }
            let color = i == 1 ? photonB.opacity(0.18) : gold.opacity(0.16 + breath * 0.08)
            context.stroke(path, with: .color(color), lineWidth: max(0.5, canvas.width * 0.006))
        }
    }

    /// A few grains of metal, not a sparkle party.
    private func drawDust(context: inout GraphicsContext, center: CGPoint, canvas: CGSize) {
        let n = live == .idle ? 4 : 6
        for i in 0..<n {
            let phase = Double(i) * 1.31 + time * 0.11
            let orbit = canvas.width * (0.20 + Double(i % 3) * 0.06)
            let x = center.x + CGFloat(cos(phase) * orbit)
            let y = center.y + CGFloat(sin(phase * 0.86) * orbit * 0.62)
            let r = max(0.6, canvas.width * 0.007)
            let fade = 0.18 + 0.22 * (0.5 + 0.5 * sin(time * 0.4 + Double(i)))
            let rect = CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)
            context.fill(Path(ellipseIn: rect), with: .color(gold.opacity(fade)))
        }
    }
}

#Preview("ARIA idle") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 168)
    }
    .environment(AriaPresence.shared)
    .preferredColorScheme(.dark)
}

#Preview("ARIA speaking") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .speaking, amplitude: 0.8, size: 168, followPresence: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("ARIA compact") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        HStack(spacing: 24) {
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 22, followPresence: false)
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 44, followPresence: false)
            AuroraOrbView(state: .listening, amplitude: 0.5, size: 58, followPresence: false)
        }
    }
    .preferredColorScheme(.dark)
}
