import SwiftUI
import ForgeCore

/// Calm Forge progress chrome — a solid sweep on a quiet track.
/// Not a HUD costume: no ticks, scanlines, brackets, or always-on glow.
///
/// Shared by Home Today, Tomorrow's Readiness, workouts, and Progress.
enum HudChrome {
    static let tickCount = HomeReadinessTokens.tickCount
    static let majorEvery = HomeReadinessTokens.majorEvery
    static let ringSize = CGFloat(HomeReadinessTokens.ringSize)
    static let compactRingSize = CGFloat(HomeReadinessTokens.compactRingSize)
    static let stroke = CGFloat(HomeReadinessTokens.stroke)
    static let compactStroke = CGFloat(HomeReadinessTokens.compactStroke)
    static let tickHz = HomeReadinessTokens.tickHz
    static let tickInterval = HomeReadinessTokens.tickInterval
    static let inArcMinimumScale = CGFloat(HomeReadinessTokens.inArcMinimumScale)
    static let glowRadius = CGFloat(HomeReadinessTokens.glowRadius)
    static let miss = Color(hex: HomeReadinessTokens.missHex)
    static let plate = Color(hex: HomeReadinessTokens.plateHex)
    static let emberSteel = Color(hex: HomeReadinessTokens.emberSteelHex)

    static func energy(for score: Int) -> Color {
        score > 0 ? HomeReadiness.color(score) : miss
    }

    static func sweep(from percent: Int) -> CGFloat {
        CGFloat(HomeReadinessTokens.sweep(from: percent))
    }

    static func isClockPaused(
        reduceMotion: Bool,
        sceneActive: Bool,
        onscreen: Bool,
        animate: Bool
    ) -> Bool {
        HomeReadinessTokens.isClockPaused(
            reduceMotion: reduceMotion,
            sceneActive: sceneActive,
            onscreen: onscreen,
            animate: animate
        )
    }
}

/// Concentric progress ring. Center content is the caller's score/vibe.
/// One solid band — the arc length is the data. No tick dial, no glow loop.
struct HudProgressRing<Center: View>: View {
    var progress: Int
    var energy: Color
    var size: CGFloat = HudChrome.ringSize
    var stroke: CGFloat = HudChrome.stroke
    var animate: Bool = true
    var almostThere: Bool = false
    /// Accepted for call-site compatibility. Glow is retired.
    var eventGlow: Bool = false
    @ViewBuilder var center: () -> Center

    @State private var sweep: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var target: CGFloat { HudChrome.sweep(from: progress) }

    var body: some View {
        let ring = size - 24
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 1))
                .frame(width: ring + 10, height: ring + 10)
            Circle()
                .stroke(HudChrome.plate.opacity(0.16), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: ring, height: ring)
            if almostThere && sweep < 0.999 {
                Circle()
                    .trim(from: sweep, to: 1)
                    .stroke(
                        HudChrome.plate.opacity(0.22),
                        style: StrokeStyle(lineWidth: stroke * 0.55, lineCap: .round)
                    )
                    .frame(width: ring, height: ring)
                    .rotationEffect(.degrees(-90))
            }
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(
                    energy,
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .frame(width: ring, height: ring)
                .rotationEffect(.degrees(-90))
            center()
        }
        .frame(width: size, height: size)
        .onAppear { applySweep(animated: !reduceMotion && animate) }
        .onChange(of: progress) { _, _ in
            applySweep(animated: !reduceMotion && animate)
        }
    }

    private func applySweep(animated: Bool) {
        let next = HomeReadinessTokens.ringSweep(
            percent: progress,
            reduceMotion: reduceMotion || !animated,
            animatedProgress: nil
        )
        if animated && !reduceMotion {
            withAnimation(ForgeMotion.sweep.delay(0.12)) { sweep = CGFloat(next) }
        } else {
            sweep = CGFloat(next)
        }
    }
}

/// Flat plate behind a card — one surface step and a hairline. No wash, no halo.
struct HudPlate: ViewModifier {
    var energy: Color
    var compact: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(compact ? 16 : HomeMetrics.cardPadding)
            .background {
                RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous)
                    .fill(Color.surface)
            }
            .overlay {
                RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous)
                    .strokeBorder(Color.borderHairline, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous))
    }
}

extension View {
    func hudPlate(energy: Color, compact: Bool = false) -> some View {
        modifier(HudPlate(energy: energy, compact: compact))
    }

    func hudInArcText() -> some View {
        minimumScaleFactor(HudChrome.inArcMinimumScale).lineLimit(1)
    }
}

struct HudVibeChip: View {
    var label: String
    var energy: Color

    var body: some View {
        Text(label.uppercased())
            .font(HomeType.micro)
            .foregroundStyle(energy)
            .tracking(1.4)
            .padding(.horizontal, FDS.Spacing.sm)
            .padding(.vertical, FDS.Spacing.xs)
            .background(energy.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(energy.opacity(0.28), lineWidth: 0.8))
    }
}
