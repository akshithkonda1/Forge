import SwiftUI
import ForgeCore

/// Compact ARIA mark for avatars, tabs, and cards.
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
                    .fill(Color(hex: AriaSigilPalette.forgeOrangeHex).opacity(0.9))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Procedural B+E nest: soft-hex nest + metal sun, `#FF4D00` accent.
/// One TimelineView. Soft orbit/wave. Reduce Motion / `forgeMinimalAnimation`
/// freeze at `AriaNestGeometry.stillPose`. Tick ≤ 12 Hz. No PNG. No fire splash.
struct AuroraOrbView: View {
    let state: AROrbState
    let amplitude: Float
    var mood: ARIAMood = .focused
    var size: CGFloat = 140
    var followPresence: Bool = false

    private let presence = AriaPresence.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.forgeMinimalAnimation) private var minimalAnimation
    @Environment(\.scenePhase) private var scenePhase

    private var resolvedState: AROrbState {
        followPresence && presence.orbState != .idle ? presence.orbState : state
    }

    private var frozen: Bool {
        reduceMotion
            || minimalAnimation
            || scenePhase != .active
            || !AriaNestGeometry.shouldOrbit(size: Double(size), reduceMotion: false)
    }

    private var tick: Double {
        frozen ? 1 : AriaNestGeometry.tickInterval
    }

    var body: some View {
        let _ = mood
        TimelineView(.animation(minimumInterval: tick, paused: frozen)) { timeline in
            let t = frozen
                ? AriaNestGeometry.stillPose
                : timeline.date.timeIntervalSinceReferenceDate
            AriaNestFieldView(
                time: t,
                presence: AriaNestGeometry.presence(from: resolvedState),
                amplitude: amplitude,
                size: size,
                reduceMotion: frozen
            )
            .scaleEffect(
                AriaSigilLife.breathScale(
                    time: t,
                    hero: size >= AriaSigilGeometry.heroMinimumSize,
                    reduceMotion: frozen
                )
            )
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            resolvedState == .speaking ? "ARIA speaking"
                : resolvedState == .listening ? "ARIA listening"
                : "ARIA"
        )
        .accessibilityAddTraits(resolvedState == .idle ? [] : .updatesFrequently)
        .onAppear {
            presence.playWelcomeChimeIfNeeded(size: size, reduceMotion: reduceMotion)
        }
    }
}

/// Soft-hex nest + metal sun. Single Canvas — one live paint path.
private struct AriaNestFieldView: View {
    let time: TimeInterval
    let presence: AriaNestGeometry.Presence
    let amplitude: Float
    let size: CGFloat
    let reduceMotion: Bool

    private var energy: Double { max(0, min(1, Double(amplitude))) }

    var body: some View {
        Canvas { context, canvasSize in
            AriaNestCanvas.paint(
                context: &context,
                canvasSize: canvasSize,
                time: time,
                presence: presence,
                amplitude: energy,
                reduceMotion: reduceMotion
            )
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }
}

/// Shared nest painter (phone Canvas). Watch uses the same geometry.
enum AriaNestCanvas {
    static func paint(
        context: inout GraphicsContext,
        canvasSize: CGSize,
        time: Double,
        presence: AriaNestGeometry.Presence,
        amplitude: Double,
        reduceMotion: Bool
    ) {
        let s = min(canvasSize.width, canvasSize.height)
        guard s >= 2 else { return }
        let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
        let drive = AriaNestGeometry.waveformDrive(presence: presence, amplitude: amplitude)
        let orange = Color(hex: AriaNestGeometry.forgeOrangeHex)
        let pearl = Color(hex: AriaNestGeometry.pearlHex)
        let pearlHot = Color(hex: AriaNestGeometry.pearlHotHex)
        let metalCool = Color(hex: AriaNestGeometry.metalCoolHex)
        let metalMid = Color(hex: AriaNestGeometry.metalMidHex)
        let hearth = Color(hex: AriaNestGeometry.hearthGlowHex)

        // Decorative hearth wash only — specular under 0.55, never a fire splash.
        let washR = s * 0.46
        let wash = min(AriaNestGeometry.hearthSpecularMax, 0.18 + drive * 0.10)
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - washR, y: center.y - washR,
                width: washR * 2, height: washR * 2
            )),
            with: .radialGradient(
                Gradient(colors: [
                    pearlHot.opacity(0.12 + drive * 0.06),
                    hearth.opacity(wash * 0.35),
                    orange.opacity(min(AriaNestGeometry.hearthSpecularMax, 0.05 + amplitude * 0.04)),
                    .clear
                ]),
                center: center,
                startRadius: s * 0.02,
                endRadius: washR
            )
        )

        for index in AriaNestGeometry.visibleRingIndices(size: Double(s)).reversed() {
            let pose = AriaNestGeometry.livingHex(
                index: index,
                time: time,
                presence: presence,
                amplitude: amplitude,
                reduceMotion: reduceMotion
            )
            let stroke = Color(hex: AriaNestGeometry.ringHex(at: index))
            let line = CGFloat(AriaNestGeometry.strokeWidth(size: Double(s), index: index))
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
                with: .color(stroke.opacity(pose.opacity * 0.28)),
                lineWidth: max(1.4, line * 1.8)
            )
            context.stroke(
                path,
                with: .color(stroke.opacity(min(1, pose.opacity + 0.06))),
                lineWidth: line
            )
        }

        paintSun(
            context: &context,
            center: center,
            size: s,
            time: time,
            presence: presence,
            amplitude: amplitude,
            reduceMotion: reduceMotion,
            pearl: pearl,
            pearlHot: pearlHot,
            metalCool: metalCool,
            metalMid: metalMid,
            orange: orange
        )
    }

    private static func nestPath(
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
            let rx = x * cosR - y * sinR
            let ry = x * sinR + y * cosR
            let mapped = CGPoint(x: center.x + rx, y: center.y + ry)
            if i == 0 {
                path.move(to: mapped)
            } else {
                path.addLine(to: mapped)
            }
        }
        path.closeSubpath()
        return path
    }

    private static func paintSun(
        context: inout GraphicsContext,
        center: CGPoint,
        size: CGFloat,
        time: Double,
        presence: AriaNestGeometry.Presence,
        amplitude: Double,
        reduceMotion: Bool,
        pearl: Color,
        pearlHot: Color,
        metalCool: Color,
        metalMid: Color,
        orange: Color
    ) {
        let core = AriaNestGeometry.orbCore(
            time: time,
            presence: presence,
            amplitude: amplitude,
            reduceMotion: reduceMotion
        )
        let diameter = size * core.diameter
        let glowR = diameter * 1.15
        context.fill(
            Path(ellipseIn: CGRect(
                x: center.x - glowR, y: center.y - glowR,
                width: glowR * 2, height: glowR * 2
            )),
            with: .radialGradient(
                Gradient(colors: [
                    pearlHot.opacity(0.36 + core.glow * 0.22),
                    metalCool.opacity(0.12),
                    orange.opacity(0.04),
                    .clear
                ]),
                center: center,
                startRadius: diameter * 0.08,
                endRadius: glowR
            )
        )

        let bodyW = diameter * core.sx
        let bodyH = diameter * core.sy
        let body = CGRect(
            x: center.x - bodyW / 2,
            y: center.y - bodyH / 2,
            width: bodyW,
            height: bodyH
        )
        context.fill(
            Path(ellipseIn: body),
            with: .radialGradient(
                Gradient(colors: [
                    pearlHot.opacity(0.98),
                    metalCool.opacity(0.92),
                    pearl.opacity(0.78),
                    metalMid.opacity(0.42)
                ]),
                center: CGPoint(
                    x: center.x - bodyW * 0.16,
                    y: center.y - bodyH * 0.18
                ),
                startRadius: 0,
                endRadius: diameter * 0.58
            )
        )

        let highlight = CGRect(
            x: center.x - diameter * 0.28,
            y: center.y - diameter * 0.28,
            width: diameter * 0.30,
            height: diameter * 0.18
        )
        context.fill(
            Path(ellipseIn: highlight),
            with: .radialGradient(
                Gradient(colors: [
                    pearlHot.opacity(0.85 * core.highlight),
                    .clear
                ]),
                center: CGPoint(x: highlight.midX, y: highlight.midY),
                startRadius: 0,
                endRadius: diameter * 0.16
            )
        )
    }
}

// MARK: - Retired gooey hearth (unused — do not ship as the brand mark)

/// Legacy 4-lobe additive ember. Kept so a future cleanup can delete it in one
/// place. Not referenced by `AuroraOrbView` / `ARIAIdentityMark`.
enum AriaSigilEmberLegacy: Sendable {
    static let lobeCount: Int = 4
    static let hearthHex = "FF6A1A"
}

#Preview("ARIA idle") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.28, size: 220)
    }
    .environment(AriaPresence.shared)
    .preferredColorScheme(.dark)
}

#Preview("ARIA speaking") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        AuroraOrbView(state: .speaking, amplitude: 0.85, size: 220, followPresence: false)
    }
    .preferredColorScheme(.dark)
}

#Preview("ARIA compact") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        HStack(spacing: 24) {
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 22, followPresence: false)
            AuroraOrbView(state: .idle, amplitude: 0.2, size: 44, followPresence: false)
            AuroraOrbView(state: .listening, amplitude: 0.5, size: 58, followPresence: false)
        }
    }
    .preferredColorScheme(.dark)
}

#Preview("ARIA still-pose") {
    ZStack {
        Color(hex: "000000").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 220, followPresence: false)
            .environment(\.forgeMinimalAnimation, true)
    }
    .preferredColorScheme(.dark)
}

