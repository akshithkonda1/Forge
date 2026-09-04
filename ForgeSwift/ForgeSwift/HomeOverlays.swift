import SwiftUI

struct CelebrationOverlay: View {
    let key: Int
    let onDismiss: () -> Void
    @State private var particles: [ConfettiParticle] = []
    @State private var bannerScale: CGFloat = 0.6
    @State private var revealed = false

    private struct ConfettiParticle: Identifiable {
        let id = UUID()
        var x: CGFloat
        var y: CGFloat
        var color: Color
        var rotation: Double
        var size: CGFloat
    }

    var body: some View {
        ZStack {
            Color.black.opacity(revealed ? 0.35 : 0).ignoresSafeArea()
            TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { tl in
                let t = tl.date.timeIntervalSinceReferenceDate
                Canvas { ctx, size in
                    for p in particles {
                        var tctx = ctx
                        tctx.opacity = 0.9
                        tctx.translateBy(x: p.x, y: p.y + CGFloat((t * 40).truncatingRemainder(dividingBy: Double(size.height))))
                        tctx.rotate(by: .degrees(p.rotation + t * 40))
                        tctx.fill(
                            Path(CGRect(x: -p.size / 2, y: -p.size / 2, width: p.size, height: p.size * 0.6)),
                            with: .color(p.color)
                        )
                    }
                }
            }

            VStack(spacing: 10) {
                Text("Peak readiness")
                    .font(.system(size: 28, weight: .black))
                    .foregroundColor(.white)
                Text("You're in the window. Use it well.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
            }
            .scaleEffect(bannerScale)
            .padding(28)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: FDS.Radius.xl, style: .continuous))
        }
        .onAppear {
            let colors: [Color] = [.ember, Color.vitality, .steel, Color.warning]
            let w = UIScreen.main.bounds.width
            particles = (0..<40).map { _ in
                ConfettiParticle(
                    x: .random(in: 0...w),
                    y: .random(in: -40...120),
                    color: colors.randomElement()!,
                    rotation: .random(in: 0...360),
                    size: .random(in: 6...12)
                )
            }
            withAnimation(FDS.Spring.hero) {
                revealed = true
                bannerScale = 1
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.8) { onDismiss() }
        }
        .id(key)
    }
}

struct VoiceQuickLaunchOrb: View {
    @EnvironmentObject var store: AppStore
    @State private var pulse = false
    @State private var outerPulse = false
    @State private var pressed = false
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button {
            FDS.haptic(.heavy)
            store.openChat(with: "Voice check-in — what should I do next?", voice: true)
        } label: {
            ZStack {
                if !reduceMotion {
                    Circle()
                        .fill(Color.ember.opacity(0.16))
                        .frame(width: 56, height: 56)
                        .scaleEffect(outerPulse ? 1.22 : 1.0)
                        .opacity(outerPulse ? 0 : 0.7)
                    Circle()
                        .fill(Color.ember.opacity(0.22))
                        .frame(width: 44, height: 44)
                        .blur(radius: 8)
                        .scaleEffect(pulse ? 1.08 : 0.96)
                }

                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.ember, Color.emberDark],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 44, height: 44)
                    .overlay(Circle().stroke(Color.white.opacity(0.16), lineWidth: 1))
                    .shadow(color: Color.ember.opacity(0.4), radius: 10, y: 5)

                Image(systemName: "mic.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
            }
            .scaleEffect(pressed ? 0.92 : (appeared ? 1.0 : 0.6))
            .opacity(appeared ? 1 : 0)
            .animation(FDS.Spring.snap, value: pressed)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Talk to ARIA")
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
        .onAppear {
            withAnimation(FDS.Spring.floaty.delay(0.7)) { appeared = true }
            guard !reduceMotion else { return }
            withAnimation(.easeOut(duration: 2.2).repeatForever(autoreverses: false)) { outerPulse = true }
            withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { pulse = true }
        }
    }
}
