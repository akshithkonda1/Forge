import SwiftUI

// ============================================================
// MARK: - Readiness band
// ============================================================

/// Mirrors `readinessColor(_:)` in HomeView.swift exactly (85 / 70 / 50 cuts),
/// but as a value type so the background can key its cross-fade on the *band*
/// rather than the raw score. `store.readiness.overall` changes on every refresh;
/// the band changes roughly once a day. Keying on the band removes almost all of
/// the background's transition churn.
enum HomeReadinessBand: Int, Hashable {
    case low, fair, good, peak

    init(score: Int) {
        switch score {
        case 85...:   self = .peak
        case 70..<85: self = .good
        case 50..<70: self = .fair
        default:      self = .low
        }
    }

    var tint: Color {
        switch self {
        case .peak: return Color(hex: "22C55E")
        case .good: return .ember
        case .fair: return .steel
        case .low:  return Color(hex: "EF4444")
        }
    }

    /// Perceptual-luminance normalisation, folded together with product intent.
    ///
    /// `22C55E` carries ~1.33x the relative luminance of `FF4D00` per unit alpha,
    /// so peak readiness is scaled down to keep the header contrast constant.
    /// `.low` is *also* scaled down (and its cool layers boosted) so a poor
    /// readiness day reads calm and restful rather than alarming.
    var tintScale: Double {
        switch self {
        case .peak: return 0.75
        case .good: return 1.00
        case .fair: return 0.95
        case .low:  return 0.70
        }
    }

    /// Boosts the violet/steel shells. At `.good` the readiness tint *is* ember,
    /// so the cool side is lifted to keep chromatic contrast in the field.
    var coolScale: Double {
        switch self {
        case .peak: return 1.00
        case .good: return 1.30
        case .fair: return 1.10
        case .low:  return 1.50
        }
    }

    /// "Motion serves state" — inherited from the old particle overlay's
    /// variable particle count, at three layers instead of a 24 Hz Canvas.
    var moteCount: Int {
        switch self {
        case .peak: return 3
        case .good: return 2
        default:    return 0
        }
    }
}

// ============================================================
// MARK: - Layer specification
// ============================================================

private struct AuroraLayerSpec: Identifiable {
    enum Role { case ember, readiness, cool, mote }

    let id: Int
    let role: Role
    /// `nil` means "use the readiness tint".
    let color: Color?
    /// Resting centre, as a fraction of the container.
    let center: UnitPoint
    /// Radius as a fraction of the derived base dimension.
    let radius: CGFloat
    /// Static elongation. Applied as a constant `scaleEffect`, never animated.
    let stretch: CGSize
    /// Peak alpha at presence 1.0, already at its band-maximum.
    let alpha: Double
    /// +1 / -1 picks the rotation sense of the drift tangent, so neighbouring
    /// shells counter-rotate and shear against each other.
    let swirl: CGFloat
    /// Drift excursion as a fraction of the base dimension.
    let driftAmount: CGFloat
    /// All periods below are distinct primes. Every driver autoreverses, so the
    /// full-configuration recurrence is 2x the product of eighteen distinct
    /// primes — the field never visibly repeats.
    let driftPeriod: Double
    let shimmerDepth: Double
    let shimmerPeriod: Double
    /// Staggers phase, and doubles as entrance choreography.
    let startDelay: Double

    /// Maximum value `HomeReadinessBand.coolScale` can take. Cool alphas are
    /// stored pre-multiplied by this so the runtime multiplier is always <= 1
    /// and never gets clamped by `.opacity`.
    static let maxCoolScale: Double = 1.5

    // ---- Ember + cool shells. Stable identity across band changes, so their
    //      drift animations are never restarted.
    static let constant: [AuroraLayerSpec] = [
        AuroraLayerSpec(
            id: 0, role: .ember, color: .ember,
            center: UnitPoint(x: 0.16, y: 0.78), radius: 0.78,
            stretch: CGSize(width: 1.30, height: 0.92), alpha: 0.150,
            swirl: 1, driftAmount: 0.070, driftPeriod: 37,
            shimmerDepth: 0.20, shimmerPeriod: 61, startDelay: 0.00
        ),
        AuroraLayerSpec(
            id: 1, role: .ember, color: .emberLight,
            center: UnitPoint(x: 0.88, y: 0.14), radius: 0.52,
            stretch: CGSize(width: 1.10, height: 0.85), alpha: 0.065,
            swirl: -1, driftAmount: 0.085, driftPeriod: 29,
            shimmerDepth: 0.28, shimmerPeriod: 47, startDelay: 0.22
        ),
        AuroraLayerSpec(
            id: 4, role: .cool, color: .aurora,
            center: UnitPoint(x: 0.52, y: 0.66), radius: 0.82,
            stretch: CGSize(width: 1.45, height: 0.80), alpha: 0.090,
            swirl: -1, driftAmount: 0.060, driftPeriod: 19,
            shimmerDepth: 0.45, shimmerPeriod: 59, startDelay: 0.44
        ),
        AuroraLayerSpec(
            id: 5, role: .cool, color: .steel,
            center: UnitPoint(x: 0.90, y: 0.86), radius: 0.50,
            stretch: CGSize(width: 1.15, height: 0.90), alpha: 0.0825,
            swirl: 1, driftAmount: 0.080, driftPeriod: 43,
            shimmerDepth: 0.45, shimmerPeriod: 67, startDelay: 0.66
        )
    ]

    // ---- Readiness shells. New identity per band -> SwiftUI cross-fades them.
    static let readiness: [AuroraLayerSpec] = [
        AuroraLayerSpec(
            id: 2, role: .readiness, color: nil,
            center: UnitPoint(x: 0.74, y: 0.36), radius: 0.70,
            stretch: CGSize(width: 1.20, height: 1.00), alpha: 0.145,
            swirl: -1, driftAmount: 0.075, driftPeriod: 23,
            shimmerDepth: 0.22, shimmerPeriod: 53, startDelay: 0.11
        ),
        AuroraLayerSpec(
            id: 3, role: .readiness, color: nil,
            center: UnitPoint(x: 0.22, y: 0.42), radius: 0.55,
            stretch: CGSize(width: 0.95, height: 1.25), alpha: 0.075,
            swirl: 1, driftAmount: 0.090, driftPeriod: 31,
            shimmerDepth: 0.30, shimmerPeriod: 41, startDelay: 0.33
        )
    ]

    /// Big, heavily-feathered motes. Same rendering model as the shells, so they
    /// cost three transforms rather than a full-screen Canvas — and unlike the
    /// old particles they reflow, because they are sized from the container.
    private static let allMotes: [AuroraLayerSpec] = [
        AuroraLayerSpec(
            id: 10, role: .mote, color: .emberLight,
            center: UnitPoint(x: 0.30, y: 0.30), radius: 0.075,
            stretch: CGSize(width: 1, height: 1), alpha: 0.080,
            swirl: -1, driftAmount: 0.26, driftPeriod: 71,
            shimmerDepth: 0.55, shimmerPeriod: 83, startDelay: 0.90
        ),
        AuroraLayerSpec(
            id: 11, role: .mote, color: nil,
            center: UnitPoint(x: 0.68, y: 0.58), radius: 0.060,
            stretch: CGSize(width: 1, height: 1), alpha: 0.080,
            swirl: 1, driftAmount: 0.30, driftPeriod: 79,
            shimmerDepth: 0.55, shimmerPeriod: 89, startDelay: 1.30
        ),
        AuroraLayerSpec(
            id: 12, role: .mote, color: .emberLight,
            center: UnitPoint(x: 0.46, y: 0.20), radius: 0.055,
            stretch: CGSize(width: 1, height: 1), alpha: 0.070,
            swirl: -1, driftAmount: 0.24, driftPeriod: 73,
            shimmerDepth: 0.60, shimmerPeriod: 97, startDelay: 1.70
        )
    ]

    static func motes(for band: HomeReadinessBand) -> [AuroraLayerSpec] {
        Array(allMotes.prefix(band.moteCount))
    }
}

// ============================================================
// MARK: - Session gate for the first-launch bloom
// ============================================================

/// `MainTabView` rebuilds `HomeView` on every tab switch (`.id(store.activeTab)`),
/// so `@State` cannot remember whether we have already bloomed. This survives the
/// rebuild and resets on process launch, which is exactly the semantics we want.
///
/// Only ever touched from `onAppear`, i.e. the main thread. `@unchecked Sendable`
/// keeps this clean under both Swift 5 and Swift 6 language modes.
private final class HomeAuroraSession: @unchecked Sendable {
    static let shared = HomeAuroraSession()
    var hasBloomed = false
    private init() {}
}

// ============================================================
// MARK: - Public view
// ============================================================

/// Ambient Home background: a slow living aurora.
///
/// Design contract:
///  - Nothing in the steady state animates anything but `.offset` and `.opacity`.
///    Those are pure CALayer properties; gradients rasterise once and are then
///    only re-composited. No Canvas, no blur, no offscreen pass, no drawingGroup.
///  - Gradient *contents* are never animated. `Gradient` is not `Animatable`, so
///    animating stop colours snaps rather than interpolating. Colour changes are
///    expressed as identity changes plus an opacity transition instead.
///  - Everything is sized from `GeometryReader`, never `UIScreen.main.bounds`,
///    so it reflows on rotation, split view, Slide Over and Stage Manager.
struct HomeAuroraBackground: View {
    let readinessScore: Int

    /// Off by default. A full-screen `Canvas` needs a backing bitmap (~12 MB at
    /// @3x), which is a lot to pay for a hypothetical. Turn on only if gradient
    /// banding is visible on device (most likely on OLED at these low alphas).
    var showsGrain: Bool = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var presence: Double = 0
    @State private var bloomScale: CGFloat = 0.88

    /// Steady-state ceiling. All spec alphas are authored as bloom peaks; the
    /// field settles to 85% of them, which puts the brightest pixel at
    /// L ~= 0.0067 — the same luminance as the previous implementation's
    /// brightest pixel, but positioned in a card gutter rather than under the
    /// header, and spread over several times the area.
    private static let steadyPresence: Double = 0.85
    /// The still fallback spends its "aliveness" budget on luminance instead of
    /// motion, so it settles slightly brighter.
    private static let stillPresence: Double = 0.95

    private var band: HomeReadinessBand { HomeReadinessBand(score: readinessScore) }

    var body: some View {
        GeometryReader { geo in
            content(size: geo.size)
                .frame(width: geo.size.width, height: geo.size.height)
                .onAppear { runEntrance() }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func content(size: CGSize) -> some View {
        ZStack {
            Color.background

            if reduceMotion {
                // Still, but composed: the same four hues at their resting
                // positions. A single static blur guarantees no banding and
                // costs one rasterisation, because nothing ever moves.
                AuroraField(size: size, band: band, animated: false)
                    .blur(radius: 22)
                    .clipped()
                    .opacity(presence)
            } else {
                AuroraField(size: size, band: band, animated: true)
                    .scaleEffect(bloomScale)   // one-shot bloom only, never in steady state
                    .clipped()                 // rectangular -> masksToBounds, free
                    .opacity(presence)
            }

            if showsGrain {
                AuroraGrain(size: size)
            }

            AuroraScrims()
        }
    }

    private func runEntrance() {
        let isFirstAppearance = !HomeAuroraSession.shared.hasBloomed
        HomeAuroraSession.shared.hasBloomed = true

        guard !reduceMotion else {
            // A cross-fade is the substitution Reduce Motion itself uses, so a
            // fade-in is permitted where a bloom is not.
            presence = 0
            bloomScale = 1
            withAnimation(.easeOut(duration: 0.9)) { presence = Self.stillPresence }
            return
        }

        if isFirstAppearance {
            // Welcome: the field blooms outward from the centre, overshoots to
            // full presence, then settles. Content fades in on top during the
            // overshoot, so the transient brightness is never behind text.
            presence = 0
            bloomScale = 0.88
            withAnimation(.easeOut(duration: 1.05)) { presence = 1.0 }
            withAnimation(.spring(response: 1.25, dampingFraction: 0.74)) { bloomScale = 1.0 }
            withAnimation(.easeInOut(duration: 2.2).delay(1.05)) { presence = Self.steadyPresence }
        } else {
            // Returning to the tab: a short settle, no overshoot.
            presence = 0
            bloomScale = 0.975
            withAnimation(.easeOut(duration: 0.55)) { presence = Self.steadyPresence }
            withAnimation(.spring(response: 0.70, dampingFraction: 0.85)) { bloomScale = 1.0 }
        }
    }
}

// ============================================================
// MARK: - The field
// ============================================================

private struct AuroraField: View {
    let size: CGSize
    let band: HomeReadinessBand
    let animated: Bool

    var body: some View {
        ZStack {
            // Ember + cool shells keep a stable identity across band changes, so
            // their drift animations are never interrupted. Ember warmth is
            // constant underneath by construction: its alpha never depends on
            // readiness.
            ForEach(AuroraLayerSpec.constant) { spec in
                AuroraBlob(
                    spec: spec,
                    size: size,
                    color: spec.color ?? band.tint,
                    alpha: spec.alpha,
                    level: level(for: spec),
                    animated: animated
                )
            }

            // Readiness shells + motes. `.id(band)` gives them a new identity per
            // band, so SwiftUI removes the old set and inserts the new one with
            // an opacity transition — a real cross-fade, and the outgoing views
            // are torn down automatically.
            ZStack {
                ForEach(AuroraLayerSpec.readiness) { spec in
                    AuroraBlob(
                        spec: spec,
                        size: size,
                        color: band.tint,
                        alpha: spec.alpha * band.tintScale,
                        level: 1.0,
                        animated: animated
                    )
                }
                ForEach(AuroraLayerSpec.motes(for: band)) { spec in
                    AuroraBlob(
                        spec: spec,
                        size: size,
                        color: spec.color ?? band.tint,
                        alpha: spec.alpha * (spec.color == nil ? band.tintScale : 1.0),
                        level: 1.0,
                        animated: animated
                    )
                }
            }
            .id(band)
            .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .animation(.easeInOut(duration: 1.8), value: band)
    }

    /// Band-dependent multiplier, applied as a view-level opacity (reliably
    /// animatable) rather than baked into the gradient (which would snap).
    /// Cool alphas are stored pre-multiplied by `maxCoolScale`, so this is
    /// always <= 1 and never clamped.
    private func level(for spec: AuroraLayerSpec) -> Double {
        switch spec.role {
        case .cool: return band.coolScale / AuroraLayerSpec.maxCoolScale
        default:    return 1.0
        }
    }
}

// ============================================================
// MARK: - One blob
// ============================================================

private struct AuroraBlob: View {
    let spec: AuroraLayerSpec
    let size: CGSize
    let color: Color
    let alpha: Double
    let level: Double
    let animated: Bool

    @State private var drift: CGFloat = 0
    @State private var shimmer: Double = 0

    var body: some View {
        blob.onAppear(perform: start)
    }

    private var blob: some View {
        let base = Self.baseDimension(for: size)
        let diameter = spec.radius * base * 2
        let restX = (spec.center.x - 0.5) * size.width
        let restY = (spec.center.y - 0.5) * size.height
        let direction = Self.driftDirection(for: spec)
        let amplitude = spec.driftAmount * base

        // A `Circle` in a *square* frame with `endRadius == diameter / 2` means
        // the gradient reaches zero alpha exactly at the shape boundary — no
        // clipped hard edge. Elongation is a constant `scaleEffect`, applied
        // once at layout, so nothing re-rasterises.
        return Circle()
            .fill(
                RadialGradient(
                    stops: Self.stops(color: color, alpha: alpha),
                    center: .center,
                    startRadius: 0,
                    endRadius: diameter / 2
                )
            )
            .frame(width: diameter, height: diameter)
            .scaleEffect(x: spec.stretch.width, y: spec.stretch.height, anchor: .center)
            .offset(x: restX, y: restY)
            .offset(x: drift * amplitude * direction.dx,
                    y: drift * amplitude * direction.dy)
            // Two separate `.opacity` modifiers, deliberately. They compose
            // multiplicatively but animate independently, so a band change
            // retargeting `level` does not kill the running shimmer loop.
            .opacity(1.0 - shimmer * spec.shimmerDepth)
            .opacity(level)
            // NOTE: do NOT add `.drawingGroup()` here or on any ancestor. The
            // children move, so it would force a Metal offscreen re-render every
            // frame — the exact cost this design exists to avoid.
    }

    private func start() {
        guard animated else { return }

        withAnimation(
            .easeInOut(duration: spec.driftPeriod)
                .repeatForever(autoreverses: true)
                .delay(spec.startDelay)
        ) {
            drift = 1
        }

        withAnimation(
            .easeInOut(duration: spec.shimmerPeriod)
                .repeatForever(autoreverses: true)
                .delay(spec.startDelay * 0.5)
        ) {
            shimmer = 1
        }
    }

    /// Hand-eased falloff approximating a Gaussian. Six stops rather than two,
    /// which both looks softer and suppresses mach banding on OLED.
    private static func stops(color: Color, alpha: Double) -> [Gradient.Stop] {
        [
            Gradient.Stop(color: color.opacity(alpha),        location: 0.00),
            Gradient.Stop(color: color.opacity(alpha * 0.72), location: 0.24),
            Gradient.Stop(color: color.opacity(alpha * 0.38), location: 0.46),
            Gradient.Stop(color: color.opacity(alpha * 0.14), location: 0.68),
            Gradient.Stop(color: color.opacity(alpha * 0.03), location: 0.86),
            Gradient.Stop(color: color.opacity(0.0),          location: 1.00)
        ]
    }

    /// Drift runs tangent to the container centre. `swirl` picks the sense, so
    /// neighbouring shells counter-rotate — that shear is what reads as an
    /// aurora curtain rather than a drifting blob.
    private static func driftDirection(for spec: AuroraLayerSpec) -> CGVector {
        let dx = spec.center.x - 0.5
        let dy = spec.center.y - 0.5
        let length = max((dx * dx + dy * dy).squareRoot(), 0.0001)
        return CGVector(dx: (-dy / length) * spec.swirl,
                        dy: ( dx / length) * spec.swirl)
    }

    /// Blob scale is driven off the container, never the screen. Weighted toward
    /// the short edge, with a mild widening term so a wide iPad canvas does not
    /// end up with a strip of untouched black down each side.
    private static func baseDimension(for size: CGSize) -> CGFloat {
        let shortSide = min(size.width, size.height)
        let longSide  = max(size.width, size.height)
        guard shortSide > 0 else { return 1 }
        let aspect = longSide / shortSide
        let widen = min(max(aspect - 1, 0), 1.4)
        return shortSide * (1.0 + 0.28 * widen)
    }
}

// ============================================================
// MARK: - Scrims
// ============================================================

/// Static, so they rasterise once.
///
/// The top scrim is the legibility mechanism. `HomeHeaderView` is the only text
/// on the Home tab that renders directly on the background; everything else sits
/// on `Color.surface.opacity(0.92)`, which attenuates the background to 8%.
/// Holding the top third near-black keeps `.textTertiary` at 4.21:1 — identical
/// to pure black — while leaving the body free to glow.
///
/// Scrim stops fade to `Color.background.opacity(0)` rather than `.clear`, so
/// premultiplied interpolation never introduces a hue shift.
private struct AuroraScrims: View {
    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.background.opacity(0.95), location: 0.00),
                    Gradient.Stop(color: Color.background.opacity(0.72), location: 0.09),
                    Gradient.Stop(color: Color.background.opacity(0.34), location: 0.20),
                    Gradient.Stop(color: Color.background.opacity(0.08), location: 0.28),
                    Gradient.Stop(color: Color.background.opacity(0.00), location: 0.34)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                stops: [
                    Gradient.Stop(color: Color.background.opacity(0.00), location: 0.56),
                    Gradient.Stop(color: Color.background.opacity(0.28), location: 0.78),
                    Gradient.Stop(color: Color.background.opacity(0.62), location: 0.92),
                    Gradient.Stop(color: Color.background.opacity(0.78), location: 1.00)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .allowsHitTesting(false)
    }
}

// ============================================================
// MARK: - Optional grain
// ============================================================

/// Off by default. Draws once per layout — it is a plain `Canvas`, NOT wrapped in
/// a `TimelineView`, so it never re-renders on a clock. Deterministic LCG so the
/// pattern does not re-randomise on every layout pass.
private struct AuroraGrain: View {
    let size: CGSize

    var body: some View {
        Canvas { context, canvasSize in
            var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
            func next() -> Double {
                seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                return Double((seed >> 33) & 0xFF_FFFF) / Double(0xFF_FFFF)
            }
            for _ in 0..<1400 {
                let x = next() * canvasSize.width
                let y = next() * canvasSize.height
                let a = 0.014 + next() * 0.020
                context.fill(
                    Path(CGRect(x: x, y: y, width: 1, height: 1)),
                    with: .color(.white.opacity(a))
                )
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }
}
