import SwiftUI

/// Iron Man 2 HUD energy — clean luminous ticks and a sweep, not 1940s
/// atom-split chrome. Shared by Home Today and Tomorrow's Readiness so the
/// two surfaces hand-in-hand.
///
/// Cheap by design: one-shot sweep, no TimelineView, no forever pulse.
/// Reduce Motion skips the fill and paints the finished ring.
enum HudChrome {
    static let tickCount = 36
    static let majorEvery = 6
    static let ringSize: CGFloat = 168
    static let compactRingSize: CGFloat = 92
    static let stroke: CGFloat = 8
    static let compactStroke: CGFloat = 6

    /// HUD cyan-steel. Brand ember stays the energy accent — this is the
    /// luminous plate the sweep rides on.
    static let plate = Color(hex: "7EC8FF")

    static func energy(for score: Int) -> Color {
        HomeReadiness.color(score)
    }

    static func sweep(from percent: Int) -> CGFloat {
        CGFloat(min(max(percent, 0), 100)) / 100
    }
}

/// Concentric HUD progress ring. Center content is the caller's score/vibe.
struct HudProgressRing<Center: View>: View {
    var progress: Int
    var energy: Color
    var size: CGFloat = HudChrome.ringSize
    var stroke: CGFloat = HudChrome.stroke
    var animate: Bool = true
    @ViewBuilder var center: () -> Center

    @State private var sweep: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let target = HudChrome.sweep(from: progress)
        ZStack {
            HudTickRing(size: size, energy: energy)
            Circle()
                .stroke(HudChrome.plate.opacity(0.14), style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .frame(width: size - 22, height: size - 22)
            Circle()
                .trim(from: 0, to: sweep)
                .stroke(
                    AngularGradient(
                        colors: [
                            energy.opacity(0.45),
                            energy,
                            HudChrome.plate.opacity(0.95),
                            energy
                        ],
                        center: .center,
                        startAngle: .degrees(-90),
                        endAngle: .degrees(270)
                    ),
                    style: StrokeStyle(lineWidth: stroke, lineCap: .round)
                )
                .frame(width: size - 22, height: size - 22)
                .rotationEffect(.degrees(-90))
                .shadow(color: energy.opacity(0.45), radius: 10)
            if sweep > 0.02 {
                Circle()
                    .fill(HudChrome.plate)
                    .frame(width: stroke * 0.7, height: stroke * 0.7)
                    .shadow(color: HudChrome.plate, radius: 5)
                    .offset(y: -(size - 22) / 2)
                    .rotationEffect(.degrees(-90 + Double(sweep) * 360))
            }
            center()
        }
        .frame(width: size, height: size)
        .onAppear {
            if reduceMotion || !animate {
                sweep = target
            } else {
                withAnimation(FDS.Spring.sweep.delay(0.12)) { sweep = target }
            }
        }
        .onChange(of: progress) { _, new in
            let next = HudChrome.sweep(from: new)
            withAnimation(reduceMotion ? .easeOut(duration: 0.12) : FDS.Spring.sweep) {
                sweep = next
            }
        }
    }
}

/// Outer HUD ticks — luminous hash marks, not rivets or atom petals.
struct HudTickRing: View {
    var size: CGFloat
    var energy: Color

    var body: some View {
        Canvas { context, canvas in
            let s = min(canvas.width, canvas.height)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let outer = s / 2 - 1
            for i in 0..<HudChrome.tickCount {
                let major = i.isMultiple(of: HudChrome.majorEvery)
                let angle = Double(i) / Double(HudChrome.tickCount) * .pi * 2 - .pi / 2
                let inner = outer - (major ? 9 : 5)
                var path = Path()
                path.move(to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * inner,
                    y: center.y + CGFloat(sin(angle)) * inner
                ))
                path.addLine(to: CGPoint(
                    x: center.x + CGFloat(cos(angle)) * outer,
                    y: center.y + CGFloat(sin(angle)) * outer
                ))
                context.stroke(
                    path,
                    with: .color(major ? energy.opacity(0.72) : HudChrome.plate.opacity(0.28)),
                    lineWidth: major ? 1.6 : 0.8
                )
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
                                colors: [energy.opacity(0.10), HudChrome.plate.opacity(0.04), .clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    RoundedRectangle(cornerRadius: HomeMetrics.hudRadius, style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    HudChrome.plate.opacity(0.38),
                                    energy.opacity(0.22),
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
                // Top leading
                path.move(to: CGPoint(x: 0, y: arm))
                path.addLine(to: CGPoint(x: 0, y: 0))
                path.addLine(to: CGPoint(x: arm, y: 0))
                // Top trailing
                path.move(to: CGPoint(x: w - arm, y: 0))
                path.addLine(to: CGPoint(x: w, y: 0))
                path.addLine(to: CGPoint(x: w, y: arm))
                // Bottom trailing
                path.move(to: CGPoint(x: w, y: h - arm))
                path.addLine(to: CGPoint(x: w, y: h))
                path.addLine(to: CGPoint(x: w - arm, y: h))
                // Bottom leading
                path.move(to: CGPoint(x: arm, y: h))
                path.addLine(to: CGPoint(x: 0, y: h))
                path.addLine(to: CGPoint(x: 0, y: h - arm))
            }
            .stroke(HudChrome.plate.opacity(0.55), lineWidth: 1.1)
            .shadow(color: energy.opacity(0.35), radius: 3)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension View {
    func hudPlate(energy: Color, compact: Bool = false) -> some View {
        modifier(HudPlate(energy: energy, compact: compact))
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
