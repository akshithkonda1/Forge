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

/// Procedural nest: thin soft-hex lines + a flat `#FF4D00` core. No glow.
/// One TimelineView. Soft orbit/wave. Reduce Motion / `forgeMinimalAnimation`
/// freeze at `AriaNestGeometry.stillPose`. Idle ticks 4–6 Hz; Chat/voice
/// may use the 12 Hz ceiling. No PNG. No fire splash.
struct AuroraOrbView: View {
    let state: AROrbState
    let amplitude: Float
    var mood: ARIAMood = .focused
    var size: CGFloat = 140
    var followPresence: Bool = false

    /// Idle nest clock. Brand geometry stays `AriaNestGeometry` — only the
    /// TimelineView interval drops while nobody is talking.
    static let idleTickHz: Double = 5
    static let idleTickInterval: Double = 1.0 / 5.0

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
        if frozen { return 1 }
        if resolvedState == .idle { return Self.idleTickInterval }
        return AriaNestGeometry.tickInterval
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
        let orange = Color(hex: AriaNestGeometry.forgeOrangeHex)
        let pearl = Color(hex: AriaNestGeometry.pearlHex)
        let pearlHot = Color(hex: AriaNestGeometry.pearlHotHex)
        let metalCool = Color(hex: AriaNestGeometry.metalCoolHex)
        let metalMid = Color(hex: AriaNestGeometry.metalMidHex)
        // Premium refresh: no hearth wash, no halo. The mark is crisp nested
        // lines around a solid core — ARIA reads as a quiet signature, not an orb.

        for index in AriaNestGeometry.visibleRingIndices(size: Double(s)).reversed() {
            let pose = AriaNestGeometry.livingHex(
                index: index,
                time: time,
                presence: presence,
                amplitude: amplitude,
                reduceMotion: reduceMotion
            )
            // Monochrome lines; the core carries the single accent.
            let stroke = pearl
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
        let bodyW = diameter * core.sx
        let bodyH = diameter * core.sy
        let body = CGRect(
            x: center.x - bodyW / 2,
            y: center.y - bodyH / 2,
            width: bodyW,
            height: bodyH
        )
        // One flat accent core. No specular, no glow radius.
        context.fill(Path(ellipseIn: body), with: .color(orange))
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
        HStack(spacing: FDS.Spacing.xl) {
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

