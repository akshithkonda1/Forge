import SwiftUI
import ForgeCore

/// Solid Forge chrome — crisp ticks, a sweep, restrained glow.
/// Same tokens as Phase B (`shared/readiness.json`), evolved: not a HUD
/// costume, not scanlines, not fake telemetry.
///
/// Shared by Home Today and Tomorrow's Readiness so the two plates
/// hand-in-hand. Cheap by design: one-shot sweep plus an event-only glow
/// that pauses when Reduce Motion, backgrounded, offscreen, or idle.
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

    /// Plate steel. Brand ember stays the energy accent — this is the
    /// luminous edge the sweep rides on.
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

/// Concentric progress ring. Center content is the caller's score/vibe.
/// Outer ticks + sweep are Home chrome — never `AriaNestGeometry`.
/// Glow runs only for a close/log pulse (`eventGlow`).
struct HudProgressRing<Center: View>: View {
    var progress: Int
    var energy: Color
    var size: CGFloat = HudChrome.ringSize
    var stroke: CGFloat = HudChrome.stroke
    var animate: Bool = true
    var almostThere: Bool = false
    var eventGlow: Bool = false
    @ViewBuilder var center: () -> Center

    @State private var sweep: CGFloat = 0
    @State private var isOnscreen = true
    @State private var pulsing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    private var target: CGFloat { HudChrome.sweep(from: progress) }
    private var glowActive: Bool {
        HomeReadinessTokens.shouldRunClock(
            reduceMotion: reduceMotion,
            sceneActive: scenePhase == .active,
            onscreen: isOnscreen,
            eventGlow: eventGlow || pulsing
        )
    }
    private var paused: Bool { !glowActive }

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
                    HudTickRing(
                        size: size,
                        energy: energy,
                        sweep: sweep,
                        almostThere: almostThere
                    )
                    Circle()
                        .stroke(HudChrome.plate.opacity(0.08), style: StrokeStyle(lineWidth: 1))
                        .frame(width: ring + 10, height: ring + 10)
                    Circle()
                        .stroke(HudChrome.plate.opacity(0.14), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
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
                            AngularGradient(
                                colors: [
                                    energy.opacity(0.40),
                                    energy,
                                    HudChrome.emberSteel.opacity(0.92),
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
                        .shadow(color: energy.opacity(0.18 + 0.16 * glow), radius: HudChrome.glowRadius)
                    if sweep > 0.02 {
                        Circle()
                            .fill(HudChrome.plate)
                            .frame(width: stroke * 0.72, height: stroke * 0.72)
                            .shadow(color: HudChrome.plate.opacity(0.36 + 0.28 * glow), radius: 3)
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
            applySweep(animated: !reduceMotion && animate)
        }
        .onDisappear { isOnscreen = false }
        .onScrollVisibilityChange { isOnscreen = $0 }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                sweep = target
            }
        }
        .onChange(of: progress) { _, _ in
            applySweep(animated: !reduceMotion && animate)
        }
        .onChange(of: eventGlow) { _, on in
            guard on, !reduceMotion else { return }
            pulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.35) {
                pulsing = false
            }
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

/// Outer ticks — precise hash marks that arm along the sweep.
/// Not rivets, atom petals, Nest hexes, or costume brackets.
struct HudTickRing: View {
    var size: CGFloat
    var energy: Color
    var sweep: CGFloat
    var almostThere: Bool = false

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let outer = s / 2 - 1
            for i in 0..<HudChrome.tickCount {
                let major = i.isMultiple(of: HudChrome.majorEvery)
                let armed = HomeReadinessTokens.tickArmed(index: i, sweep: Double(sweep))
                let closing = almostThere && !armed && HomeReadinessTokens.tickArmed(
                    index: i,
                    sweep: 1
                )
                let angle = Double(i) / Double(HudChrome.tickCount) * .pi * 2 - .pi / 2
                let inner = outer - (major ? 9 : 4)
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
                } else if closing && major {
                    color = HudChrome.plate.opacity(0.38)
                } else if closing {
                    color = HudChrome.plate.opacity(0.22)
                } else if major {
                    color = HudChrome.emberSteel.opacity(opacity)
                } else {
                    color = HudChrome.plate.opacity(opacity)
                }
                context.stroke(
                    path,
                    with: .color(color),
                    lineWidth: CGFloat(
                        major
                            ? HomeReadinessTokens.tickMajorWidth
                            : HomeReadinessTokens.tickMinorWidth
                    )
                )
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// Hairline plate behind a card — depth and a thin edge, not costume chrome.
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
                                colors: [energy.opacity(0.08), HudChrome.plate.opacity(0.04), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    HudChrome.plate.opacity(0.32),
                                    HudChrome.emberSteel.opacity(0.20),
                                    energy.opacity(0.16),
                                    Color.white.opacity(0.06)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous))
            .forgeCardShadow(glow: energy)
    }
}

extension View {
    func hudPlate(energy: Color, compact: Bool = false) -> some View {
        modifier(HudPlate(energy: energy, compact: compact))
    }

    /// Constrained in-arc type — same floor as the score.
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
