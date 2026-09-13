import SwiftUI

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
                    .fill(Color(hex: AriaSigilPalette.emberHex).opacity(0.9))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Procedural 4-lobe gooey ember. No ping rings, no PNG stretch.
/// Presence (speech / listen) drives energy. Reduce Motion freezes the pose.
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

    private var tick: Double {
        if reduceMotion { return 1 }
        return 1.0 / 24.0
    }

    /// Simulator uses a static radial stand-in (see EmberCanvas) — don't burn a
    /// 24 Hz TimelineView just to redraw the same circles.
    private var pauseTimeline: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        reduceMotion || scenePhase != .active
        #endif
    }

    var body: some View {
        TimelineView(.animation(
            minimumInterval: tick,
            paused: pauseTimeline
        )) { timeline in
            let frozen = pauseTimeline
            let t = frozen ? AriaSigilGeometry.stillPose : timeline.date.timeIntervalSinceReferenceDate
            EmberCanvas(
                time: t,
                state: resolvedState,
                mood: mood,
                amplitude: amplitude,
                size: size,
                reduceMotion: frozen
            )
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            resolvedState == .speaking ? "ARIA speaking"
                : resolvedState == .listening ? "ARIA listening"
                : "ARIA"
        )
        .accessibilityAddTraits(resolvedState == .idle ? AccessibilityTraits() : .updatesFrequently)
        .onAppear {
            presence.playWelcomeChimeIfNeeded(size: size, reduceMotion: reduceMotion)
        }
    }
}

private struct EmberCanvas: View {
    let time: TimeInterval
    let state: AROrbState
    let mood: ARIAMood
    let amplitude: Float
    let size: CGFloat
    let reduceMotion: Bool

    var body: some View {
        // Zero-size Canvas on Simulator (iOS 26/27 betas especially) creates a
        // CAMetalLayer with drawableSize 0×0, then MSAA resolve asserts and
        // kills the process under Metal API Validation. Skip the pass entirely.
        // On Simulator, prefer a static radial stand-in: TimelineView+Canvas with
        // `.plusLighter` still hits the same MSAA path even at non-zero size.
        Group {
            if size < 2 {
                Color.clear
            } else if Self.useStaticSimulatorStandIn {
                simulatorStandIn
            } else {
                liveCanvas
            }
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
    }

    /// Simulator Metal validation + SwiftUI Canvas MSAA has been killing the
    /// process on iOS 27 betas (`MTLStoreActionMultisampleResolve` with a nil
    /// resolve texture after a 0×0 drawable). Device keeps the live ember.
    private static var useStaticSimulatorStandIn: Bool {
        #if targetEnvironment(simulator)
        true
        #else
        false
        #endif
    }

    private var simulatorStandIn: some View {
        let ember = Color(hex: AriaSigilPalette.emberHex)
        let teal = Color(hex: AriaSigilPalette.tealHex)
        let hot = Color(hex: "FFE28A")
        let accent = Color(hex: AriaSigilPalette.photonPrimary(for: mood))
        return ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [hot.opacity(0.9), ember.opacity(0.75), accent.opacity(0.35), teal.opacity(0.2), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: size * 0.5
                    )
                )
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(state == .speaking ? 0.85 : 0.55), ember.opacity(0.4), .clear],
                        center: UnitPoint(x: 0.42, y: 0.38),
                        startRadius: 0,
                        endRadius: size * 0.28
                    )
                )
                .frame(width: size * 0.55, height: size * 0.55)
        }
    }

    private var liveCanvas: some View {
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
            guard s >= 2 else { return }
            let center = CGPoint(x: canvasSize.width / 2, y: canvasSize.height / 2)
            let gaze = AriaSigilGeometry.gaze(time: time, state: state, reduceMotion: reduceMotion)
            let ember = Color(hex: AriaSigilPalette.emberHex)
            let teal = Color(hex: AriaSigilPalette.tealHex)
            let hot = Color(hex: "FFE28A")
            let accent = Color(hex: AriaSigilPalette.photonPrimary(for: mood))

            context.blendMode = .plusLighter

            for index in 0..<AriaSigilGeometry.lobeCount {
                let lobe = AriaSigilGeometry.lobe(index: index, time: time, state: state, reduceMotion: reduceMotion)
                let lx = center.x + CGFloat(lobe.x + gaze.x) * s * 0.5
                let ly = center.y + CGFloat(lobe.y + gaze.y) * s * 0.5
                let rad = CGFloat(lobe.r) * s * 0.5
                guard rad >= 0.5 else { continue }
                let rect = CGRect(x: lx - rad, y: ly - rad, width: rad * 2, height: rad * 2)
                context.fill(
                    Path(ellipseIn: rect),
                    with: .radialGradient(
                        Gradient(colors: [
                            hot.opacity(0.95),
                            ember.opacity(0.82),
                            accent.opacity(0.42),
                            teal.opacity(0.28),
                            .clear
                        ]),
                        center: CGPoint(x: lx, y: ly),
                        startRadius: 0,
                        endRadius: rad
                    )
                )
            }

            let extra = CGFloat(max(0, min(1, Double(amplitude)))) * 0.04
            let coreR = (CGFloat(AriaSigilGeometry.coreRadius(time: time, state: state, reduceMotion: reduceMotion)) + extra) * s
            guard coreR >= 0.5 else { return }
            let coreCenter = CGPoint(
                x: center.x + CGFloat(gaze.x) * s * 0.35,
                y: center.y + CGFloat(gaze.y) * s * 0.35
            )
            context.fill(
                Path(ellipseIn: CGRect(x: coreCenter.x - coreR, y: coreCenter.y - coreR, width: coreR * 2, height: coreR * 2)),
                with: .radialGradient(
                    Gradient(colors: [
                        (state == .speaking ? Color.white.opacity(0.9) : hot.opacity(0.85)),
                        ember.opacity(0.5),
                        .clear
                    ]),
                    center: coreCenter,
                    startRadius: 0,
                    endRadius: coreR
                )
            )

            let spec = CGPoint(
                x: center.x + CGFloat(gaze.x) * s * 0.2 - s * 0.08,
                y: center.y + CGFloat(gaze.y) * s * 0.2 - s * 0.1
            )
            let specR = s * 0.08
            guard specR >= 0.5 else { return }
            context.fill(
                Path(ellipseIn: CGRect(x: spec.x - specR, y: spec.y - specR, width: specR * 2, height: specR * 2)),
                with: .radialGradient(
                    Gradient(colors: [Color.white.opacity(0.55), .clear]),
                    center: spec,
                    startRadius: 0,
                    endRadius: specR
                )
            )
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
