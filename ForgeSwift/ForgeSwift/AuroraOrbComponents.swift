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

/// Stroked ellipses only. Identity is orange — mood does not recolor the field.
/// Drawn with SwiftUI shapes (not Canvas + `.plusLighter`) so Simulator never
/// hits the Metal MSAA 0×0 resolve crash the retired gooey ember used.
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
                            orange.opacity(0.16 + energy * 0.06),
                            orange.opacity(0.04),
                            .clear
                        ],
                        center: .center,
                        startRadius: size * 0.04,
                        endRadius: size * 0.48
                    )
                )
            ForEach(0..<AriaSigilGeometry.ellipseCount, id: \.self) { index in
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
        }
        .frame(width: size, height: size)
        .shadow(color: orange.opacity(0.28 + energy * 0.12), radius: max(4, size * 0.08))
        .allowsHitTesting(false)
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
            .environment(\.accessibilityReduceMotion, true)
    }
    .preferredColorScheme(.dark)
}
