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
                    .fill(Color(hex: AriaSigilPalette.forgeOrangeHex).opacity(0.9))
                    .frame(width: max(7, size * 0.18), height: max(7, size * 0.18))
                    .offset(x: 1, y: 1)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Procedural kinetic orange ring-field. Five overlapping ellipses, `#FF4D00`.
/// Soft spin. No PNG, no gooey hearth, no Home readiness chrome.
/// Presence (speech / listen) raises spin rate. Reduce Motion and
/// `forgeMinimalAnimation` freeze at `AriaSigilGeometry.stillPose`.
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
        reduceMotion || minimalAnimation || scenePhase != .active
    }

    private var tick: Double {
        frozen ? 1 : 1.0 / 12.0
    }

    var body: some View {
        // Mood stays on the call-site API. Identity does not recolor — the field is `#FF4D00`.
        let _ = mood
        TimelineView(.animation(
            minimumInterval: tick,
            paused: frozen
        )) { timeline in
            let t = frozen ? AriaSigilGeometry.stillPose : timeline.date.timeIntervalSinceReferenceDate
            AriaRingFieldView(
                time: t,
                state: resolvedState,
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

/// Kinetic orange ring-field around a white intelligence orb.
/// Hero (≥90pt) draws all five ellipses. Compact slots draw the Cove 3-ring.
private struct AriaRingFieldView: View {
    let time: TimeInterval
    let state: AROrbState
    let amplitude: Float
    let size: CGFloat
    let reduceMotion: Bool

    private var orange: Color { Color(hex: AriaSigilPalette.forgeOrangeHex) }
    private var energy: Double { max(0, min(1, Double(amplitude))) }

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            orange.opacity(0.10 + energy * 0.05),
                            orange.opacity(0.03),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.04,
                        endRadius: size * 0.48
                    )
                )
            ForEach(AriaSigilGeometry.visibleRingIndices(size: size), id: \.self) { index in
                let pose = AriaSigilGeometry.ellipse(
                    index: index,
                    time: time,
                    state: state,
                    reduceMotion: reduceMotion
                )
                Ellipse()
                    .stroke(
                        orange.opacity(pose.opacity),
                        lineWidth: AriaSigilGeometry.strokeWidth(size: size, index: index)
                    )
                    .frame(width: size * pose.rx, height: size * pose.ry)
                    .rotationEffect(.radians(pose.rotation))
            }
            AriaIntelligenceOrb(size: size, energy: energy)
        }
        .frame(width: size, height: size)
        .shadow(color: orange.opacity(0.22 + energy * 0.10), radius: max(4, size * 0.08))
        .allowsHitTesting(false)
    }
}

/// White volumetric core. The rings orbit this — not a frame, not readiness chrome.
private struct AriaIntelligenceOrb: View {
    let size: CGFloat
    let energy: Double

    var body: some View {
        let r = AriaSigilGeometry.orbCoreRadius(size: size)
        let bloom = r * 2.2
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.38 * energy),
                            Color(hex: AriaSigilPalette.ivoryHex).opacity(0.12 * energy),
                            Color(hex: AriaSigilGeometry.forgeOrangeHex).opacity(0.10 * energy),
                            .clear
                        ],
                        center: .center,
                        startRadius: r * 0.18,
                        endRadius: bloom
                    )
                )
                .frame(width: bloom * 2, height: bloom * 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color.white.opacity(0.98),
                            Color.white.opacity(0.86),
                            Color(hex: AriaSigilGeometry.orbSoftHex).opacity(0.70),
                            Color(hex: AriaSigilGeometry.brandHueLightHex).opacity(0.16),
                            Color(hex: AriaSigilGeometry.forgeOrangeHex).opacity(0)
                        ],
                        center: UnitPoint(x: 0.34, y: 0.30),
                        startRadius: 0,
                        endRadius: r
                    )
                )
                .frame(width: r * 2, height: r * 2)

            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.white.opacity(0.95), Color.white.opacity(0)],
                        center: .center,
                        startRadius: 0,
                        endRadius: r * 0.42
                    )
                )
                .frame(width: r * 0.72, height: r * 0.72)
                .offset(x: -r * 0.28, y: -r * 0.32)
        }
        .frame(width: size, height: size)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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

#Preview("ARIA still-pose") {
    ZStack {
        Color(hex: "07060A").ignoresSafeArea()
        AuroraOrbView(state: .idle, amplitude: 0.3, size: 168, followPresence: false)
            .environment(\.forgeMinimalAnimation, true)
    }
    .preferredColorScheme(.dark)
}
