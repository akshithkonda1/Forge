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

    var body: some View {
        TimelineView(.animation(
            minimumInterval: tick,
            paused: reduceMotion || scenePhase != .active
        )) { timeline in
            let t = reduceMotion ? AriaSigilGeometry.stillPose : timeline.date.timeIntervalSinceReferenceDate
            EmberCanvas(
                time: t,
                state: resolvedState,
                mood: mood,
                amplitude: amplitude,
                size: size,
                reduceMotion: reduceMotion
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
        Canvas { context, canvasSize in
            let s = min(canvasSize.width, canvasSize.height)
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
        .frame(width: size, height: size)
        .allowsHitTesting(false)
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
