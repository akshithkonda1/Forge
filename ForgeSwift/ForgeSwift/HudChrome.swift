import SwiftUI
import ForgeCore

/// Iron Man 2 HUD energy — thin luminous ticks and a sweep, not the
/// kinetic atom-orbit ring-field and not the Nest brand mark.
///
/// Shared by Home Today and Tomorrow's Readiness so the two plates
/// hand-in-hand. Tokens come from `shared/readiness.json` /
/// `HomeReadinessTokens`. Cheap by design: one-shot sweep plus a lean
/// ≤6 Hz glow that pauses when Reduce Motion, backgrounded, or offscreen.
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

    /// HUD cyan-steel plate. Brand ember stays the energy accent — this is
    /// the luminous plate the sweep rides on.
    static let plate = Color(hex: HomeReadinessTokens.plateHex)
    static let emberSteel = Color(hex: HomeReadinessTokens.emberSteelHex)

    static func energy(for score: Int) -> Color {
        HomeReadiness.color(score)
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

/// Concentric HUD progress ring. Center content is the caller's score/vibe.
/// Outer ticks + sweep are Home chrome — never `AriaNestGeometry`.
struct HudProgressRing<Center: View>: View {
    var progress: Int
    var energy: Color
    var size: CGFloat = HudChrome.ringSize
    var stroke: CGFloat = HudChrome.stroke
    var animate: Bool = true
    @ViewBuilder var center: () -> Center

    @State private var sweep: CGFloat = 0
    @State private var isOnscreen = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var target: CGFloat { HudChrome.sweep(from: progress) }
    private var paused: Bool {
        HudChrome.isClockPaused(
            reduceMotion: reduceMotion,
            sceneActive: scenePhase == .active,
            onscreen: isOnscreen,
            animate: animate
        )
    }

    var body: some View {
        let ring = size - 24
        ZStack {
            TimelineView(.animation(minimumInterval: HudChrome.tickInterval, paused: paused)) { timeline in
                let glow = HomeReadinessTokens.headGlow(
                    time: paused
                        ? 0
                        : timeline.date.timeIntervalSinceReferenceDate,
                    paused: paused
                )
                ZStack {
                    HudTickRing(size: size, energy: energy, sweep: sweep)
                    Circle()
                        .stroke(HudChrome.plate.opacity(0.10), style: StrokeStyle(lineWidth: 1))
                        .frame(width: ring + 10, height: ring + 10)
                    Circle()
                        .stroke(HudChrome.plate.opacity(0.16), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                        .frame(width: ring, height: ring)
                    Circle()
                        .trim(from: 0, to: sweep)
                        .stroke(
                            AngularGradient(
                                colors: [
                                    energy.opacity(0.35),
                                    energy,
                                    HudChrome.emberSteel.opacity(0.95),
                                    HudChrome.plate,
                                    energy
                                ],
                                center: .center,
                                startAngle: .degrees(-90),
                                endAngle: .degrees(270)
                            ),
                            style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                        )
                        .frame(width: ring, height: ring)
                        .rotationEffect(.degrees(-90))
                        .shadow(color: energy.opacity(0.28 + 0.22 * glow), radius: 8)
                    if sweep > 0.02 {
                        Circle()
                            .fill(HudChrome.plate)
                            .frame(width: stroke * 0.85, height: stroke * 0.85)
                            .shadow(color: HudChrome.plate.opacity(0.55 + 0.45 * glow), radius: 5)
                            .offset(y: -ring / 2)
                            .rotationEffect(.degrees(-90 + Double(sweep) * 360))
                    }
                }
            }
            center()
        }
        .frame(width: size, height: size)
        .onAppear {
            isOnscreen = true
            applySweep(animated: !paused)
        }
        .onDisappear { isOnscreen = false }
        .onScrollVisibilityChange { isOnscreen = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                sweep = target
            }
        }
        .onChange(of: progress) { _, _ in
            applySweep(animated: !paused)
        }
    }

    private func applySweep(animated: Bool) {
        let next = HomeReadinessTokens.ringSweep(
            percent: progress,
            reduceMotion: reduceMotion || !animated,
            animatedProgress: nil
        )
        if animated && !reduceMotion {
            withAnimation(FDS.Spring.sweep.delay(0.12)) { sweep = CGFloat(next) }
        } else {
            sweep = CGFloat(next)
        }
    }
}

/// Outer HUD ticks — luminous hash marks that arm along the sweep.
/// Not rivets, atom petals, or Nest hexes.
struct HudTickRing: View {
    var size: CGFloat
    var energy: Color
    var sweep: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let outer = s / 2 - 1
            for i in 0..<HudChrome.tickCount {
                let major = i.isMultiple(of: HudChrome.majorEvery)
                let armed = HomeReadinessTokens.tickArmed(index: i, sweep: Double(sweep))
                let angle = Double(i) / Double(HudChrome.tickCount) * .pi * 2 - .pi / 2
                let inner = outer - (major ? 10 : 5)
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * inner,
                    y: center.y + CGFloat(sin(angle)) * inner
                ))
                path.addLine(to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * outer,
                    y: center.y + CGFloat(sin(angle)) * outer
                ))
                let opacity = HomeReadinessTokens.paintedTickOpacity(
                    major: major, armed: armed, glow: 0
                )
                let color: Color
                if major && armed {
                    color = energy.opacity(opacity)
                } else if armed {
                    color = HudChrome.plate.opacity(opacity)
                } else if major {
                    color = HudChrome.emberSteel.opacity(opacity)
                } else {
                    color = HudChrome.plate.opacity(opacity)
                }
                context.stroke(path, with: .color(color), lineWidth: major ? 1.5 : 0.7)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Hairline HUD plate behind a card — brackets, not clunky chrome.
struct HudPlate: ViewModifier {
    var energy: Color
    var compact: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(compact ? 16 : HomeMetrics.cardPadding)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous)
                        .fill(Color.surfaceElevated.opacity(0.94))
                    RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [energy.opacity(0.10), HudChrome.plate.opacity(0.05), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    HudChrome.plate.opacity(0.42),
                                    HudChrome.emberSteel.opacity(0.28),
                                    energy.opacity(0.20),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                    HudCornerBrackets(energy: energy)
                        .padding(8)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous))
            .forgeCardShadow(glow: energy)
    }
}

private struct HudCornerBrackets: View {
    var energy: Color

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let arm: CGFloat = 14
            Path { path in
                path.move(to: CGPoint(x: 0, y: arm))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: arm, y: 0))
                path.move(to: CGPoint(x: w - arm, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: arm))
                path.move(to: CGPoint(x: w, y: h - arm))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w - arm, y: h))
                path.move(to: CGPoint(x: arm, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h - arm))
            }
            .stroke(HudChrome.plate.opacity(0.58), lineWidth: 1.1)
            .shadow(color: energy.opacity(0.32), radius: 3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func hudPlate(energy: Color, compact: Bool = false) -> some View {
        modifier(HudPlate(energy: energy, compact: compact))
    }

    /// Constrained HUD type — same floor as the in-arc score.
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
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(energy.opacity(0.12))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(energy.opacity(0.28), lineWidth: 0.8))
    }
}
