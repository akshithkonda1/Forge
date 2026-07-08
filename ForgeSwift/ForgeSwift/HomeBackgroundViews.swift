import SwiftUI

// ============================================================
// MARK: - Cinematic Home Background
// ============================================================

struct CinematicHomeBackground: View {
    let readinessScore: Int
    @State private var phase:     Bool    = false
    @State private var meshPhase: Double  = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var primaryColor: Color {
        switch readinessScore {
        case 85...:  return Color.success
        case 70..<85: return Color.ember
        case 50..<70: return Color.steel
        default:      return Color(hex: "4B5563")
        }
    }

    var body: some View {
        ZStack {
            Color(hex: "080808")
            cinematicBackgroundLayer
            vignetteLayer
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 14).repeatForever(autoreverses: true)) { phase = true }
        }
        .animation(.easeInOut(duration: 1.8), value: readinessScore)
    }

    @ViewBuilder
    private var cinematicBackgroundLayer: some View {
        if reduceMotion {
            primaryColor.opacity(0.06).ignoresSafeArea()
        } else {
            breathingGradient
            blobMeshLayer
            auroraLayer
        }
    }

    private var breathingGradient: some View {
        LinearGradient(
            colors: [
                Color(hex: "080808"),
                primaryColor.opacity(phase ? 0.09 : 0.04),
                Color(hex: "080808"),
                Color.ember.opacity(phase ? 0.03 : 0.01),
            ],
            startPoint: phase ? .topLeading : .bottomLeading,
            endPoint: phase ? .bottomTrailing : .topTrailing
        )
        .opacity(0.9)
    }

    private var blobMeshLayer: some View {
        CinematicBlobMeshLayer(primaryColor: primaryColor)
    }

    private var auroraLayer: some View {
        CinematicAuroraLayer(primaryColor: primaryColor)
    }

    private var vignetteLayer: some View {
        RadialGradient(
            colors: [.clear, Color.black.opacity(0.5)],
            center: .center, startRadius: 80, endRadius: 380
        )
    }
}

private struct CinematicBlobMeshLayer: View {
    let primaryColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { timeline in
            Canvas { context, size in
                HomeBackgroundDrawing.drawBlobs(
                    in: &context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    accent: primaryColor
                )
            }
        }
        .blur(radius: 50)
    }
}

private struct CinematicAuroraLayer: View {
    let primaryColor: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
            Canvas { context, size in
                HomeBackgroundDrawing.drawAurora(
                    in: &context,
                    size: size,
                    time: timeline.date.timeIntervalSinceReferenceDate,
                    accent: primaryColor
                )
            }
        }
        .blendMode(.screen)
        .opacity(0.5)
    }
}

private enum HomeBackgroundDrawing {
    static func drawBlobs(in context: inout GraphicsContext, size: CGSize, time: Double, accent: Color) {
        let w = size.width
        let h = size.height
        let blobs: [(CGPoint, Color, CGFloat, Double)] = [
            (CGPoint(x: w * (0.15 + 0.10 * sin(time * 0.17)), y: h * (0.20 + 0.08 * cos(time * 0.13))), accent, 280, 0.26),
            (CGPoint(x: w * (0.80 + 0.09 * cos(time * 0.15)), y: h * (0.15 + 0.12 * sin(time * 0.11))), Color.steel, 240, 0.18),
            (CGPoint(x: w * (0.50 + 0.14 * sin(time * 0.12 + 1.0)), y: h * (0.70 + 0.07 * cos(time * 0.19))), accent, 200, 0.16),
            (CGPoint(x: w * (0.10 + 0.08 * cos(time * 0.24)), y: h * (0.80 + 0.06 * sin(time * 0.14))), Color.steel, 180, 0.14),
        ]

        for (center, color, radius, opacity) in blobs {
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            context.fill(
                Path(ellipseIn: rect),
                with: .radialGradient(
                    Gradient(colors: [color.opacity(opacity), color.opacity(0)]),
                    center: center,
                    startRadius: 0,
                    endRadius: radius
                )
            )
        }
    }

    static func drawAurora(in context: inout GraphicsContext, size: CGSize, time: Double, accent: Color) {
        let w = size.width
        let h = size.height
        let bands: [(CGFloat, Color, CGFloat)] = [
            (h * (0.28 + 0.05 * sin(time * 0.09)), accent, h * 0.16),
            (h * (0.55 + 0.07 * cos(time * 0.07)), Color.steel, h * 0.12),
        ]

        for (y, color, bandHeight) in bands {
            let rect = CGRect(x: 0, y: y - bandHeight / 2, width: w, height: bandHeight)
            context.fill(
                Path(rect),
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0), color.opacity(0.14), color.opacity(0)]),
                    startPoint: CGPoint(x: 0, y: y - bandHeight / 2),
                    endPoint: CGPoint(x: 0, y: y + bandHeight / 2)
                )
            )
        }
    }
}

// ============================================================
// MARK: - Particle Overlay (readiness-reactive)
// ============================================================

private struct Particle: Identifiable {
    let id:           Int
    var x:            CGFloat
    var y:            CGFloat
    let size:         CGFloat
    let speed:        Double
    let opacity:      Double
    let color:        Bool      // true = accent, false = neutral
    let phaseOffset:  Double
}

struct ReadinessParticleOverlay: View {
    let readinessScore: Int
    @State private var particles: [Particle] = []
    @State private var globalT: Double = 0

    private var particleCount: Int {
        switch readinessScore {
        case 85...:  return 28
        case 70..<85: return 16
        case 50..<70: return 8
        default:      return 4
        }
    }

    private var accentColor: Color {
        switch readinessScore {
        case 85...:  return Color.success
        case 70..<85: return Color.ember
        default:      return Color.steel
        }
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for p in particles {
                        let drift = CGFloat(sin(t * p.speed + p.phaseOffset) * 18)
                        let rise  = CGFloat(t * p.speed * 22).truncatingRemainder(dividingBy: size.height + 40)
                        let px    = p.x + drift
                        let py    = size.height - rise - p.y
                        let fade  = min(1.0, min(py / 60, (size.height - py) / 60))
                        let color = p.color ? accentColor : Color.white
                        let rect  = CGRect(x: px - p.size/2, y: py - p.size/2, width: p.size, height: p.size)
                        ctx.fill(
                            Path(ellipseIn: rect),
                            with: .color(color.opacity(p.opacity * fade * 0.6))
                        )
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height)
            }
            .onAppear {
                particles = (0..<particleCount).map { i in
                    Particle(
                        id: i,
                        x: .random(in: 0...geo.size.width),
                        y: .random(in: 0...geo.size.height),
                        size: .random(in: 1.2...3.8),
                        speed: .random(in: 0.18...0.42),
                        opacity: .random(in: 0.25...0.7),
                        color: i % 3 == 0,
                        phaseOffset: .random(in: 0...(.pi * 2))
                    )
                }
            }
        }
    }
}

// ============================================================
// MARK: - Celebration Confetti
// ============================================================

struct CelebrationOverlay: View {
    let key:       Int
    let onDismiss: () -> Void
    @State private var particles: [ConfettiParticle] = []
    @State private var revealed = false
    @State private var bannerScale: CGFloat = 0.6

    private struct ConfettiParticle: Identifiable {
        let id: Int
        let x: CGFloat; let size: CGFloat
        let color: Color; let rotation: Double
        let speed: Double; let drift: Double
    }

    private let confettiColors: [Color] = [
        .ember, Color.success, Color.steel,
        Color.amber, Color.violet, .white
    ]

    var body: some View {
        ZStack {
            // Confetti canvas
            GeometryReader { geo in
                TimelineView(.animation(minimumInterval: 1.0/60.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        for p in particles {
                            let elapsed = t.truncatingRemainder(dividingBy: 4.0)
                            let progress = elapsed / 4.0
                            let y = -30 + (size.height + 60) * CGFloat(progress) * CGFloat(p.speed)
                            let x = p.x + CGFloat(sin(t * p.drift + Double(p.id)) * 28)
                            let rot = t * p.rotation
                            let fade = min(1.0, min(progress * 4, (1.0 - progress) * 4))

                            ctx.translateBy(x: x, y: y)
                            ctx.rotate(by: .radians(rot))
                            let rect = CGRect(x: -p.size/2, y: -p.size/2, width: p.size, height: p.size)
                            ctx.fill(Path(rect), with: .color(p.color.opacity(fade * 0.9)))
                            ctx.rotate(by: .radians(-rot))
                            ctx.translateBy(x: -x, y: -y)
                        }
                    }
                }
                .onAppear {
                    particles = (0..<60).map { i in
                        ConfettiParticle(
                            id: i,
                            x: .random(in: 0...geo.size.width),
                            size: .random(in: 5...12),
                            color: confettiColors[i % confettiColors.count],
                            rotation: .random(in: 1.5...4.0),
                            speed: .random(in: 0.5...1.0),
                            drift: .random(in: 0.5...2.0)
                        )
                    }
                }
            }

            // Peak Performance Banner
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 18) {
                    ZStack {
                        Circle()
                            .fill(Color.success.opacity(0.2))
                            .frame(width: 90, height: 90)
                            .blur(radius: 20)
                        Image(systemName: "crown.fill")
                            .font(.forgeDynamic(size: 44))
                            .foregroundStyle(LinearGradient(
                                colors: [Color.gold, Color(hex: "FFA500")],
                                startPoint: .top, endPoint: .bottom
                            ))
                            .shadow(color: Color.gold.opacity(0.6), radius: 20)
                    }

                    VStack(spacing: 8) {
                        Text("PEAK PERFORMANCE")
                            .font(.forgeDynamic(size: 13, weight: .black))
                            .tracking(3.5)
                            .foregroundColor(Color.success)

                        Text("Readiness Score \(store_readiness_placeholder)")
                            .font(.forgeDynamic(size: 32, weight: .black, design: .rounded))
                            .foregroundStyle(LinearGradient(
                                colors: [.white, Color.success],
                                startPoint: .top, endPoint: .bottom
                            ))

                        Text("You're in the zone. Go crush it.")
                            .font(.forgeDynamic(size: 15, weight: .medium))
                            .foregroundColor(.textSecondary)
                    }

                    Button(action: onDismiss) {
                        Text("Let's Go →")
                            .font(.forgeDynamic(size: 15, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 14)
                            .background(FDS.Gradient.ember)
                            .cornerRadius(FDS.Radius.pill)
                            .shadow(color: Color.ember.opacity(0.45), radius: 14, y: 6)
                    }
                }
                .padding(32)
                .background(
                    ZStack {
                        Color.surface.opacity(0.95)
                        LinearGradient(
                            colors: [Color.success.opacity(0.08), .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    }
                )
                .cornerRadius(FDS.Radius.xl)
                .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl)
                    .stroke(Color.success.opacity(0.3), lineWidth: 1.5))
                .shadow(color: .black.opacity(0.3), radius: 40, y: 20)
                .padding(.horizontal, 24)
                .scaleEffect(bannerScale)
                .opacity(revealed ? 1 : 0)

                Spacer()
            }
        }
        .background(Color.black.opacity(revealed ? 0.55 : 0).ignoresSafeArea())
        .onAppear {
            withAnimation(FDS.Spring.hero.delay(0.2)) {
                revealed = true
                bannerScale = 1.0
            }
        }
        .onTapGesture { onDismiss() }
        .id(key)
    }

    // Placeholder — real implementation reads from store via EnvironmentObject
    private var store_readiness_placeholder: Int { 87 }
}
