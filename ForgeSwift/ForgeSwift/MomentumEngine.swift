import SwiftUI

/// Celebration choreography for chat momentum. The *numbers* live in `AppStore`
/// (so they persist across launches); this only owns the transient animation
/// state that shouldn't survive a relaunch.
@MainActor
final class MomentumEngine: ObservableObject {
    @Published var showXPBurst:    Bool   = false
    @Published var lastXPGain:     Int    = 0
    @Published var showLevelUp:    Bool   = false

    private weak var store: AppStore?
    private let xpPerLevel = 100
    private var burstResetTask:    Task<Void, Never>?
    private var levelUpResetTask:  Task<Void, Never>?

    func bind(to store: AppStore) { self.store = store }

    var xp:         Int    { store?.chatXP ?? 0 }
    var level:      Int    { store?.chatLevel ?? 1 }
    var xpProgress: Double { store?.chatXPProgress ?? 0 }
    var xpToNext:   Int    { store?.chatXPToNextLevel ?? xpPerLevel }

    func award(xp amount: Int) {
        guard let store else { return }
        lastXPGain = amount
        let leveledUp = store.awardChatXP(amount)

        withAnimation(FDS.Spring.hero) { showXPBurst = true }
        burstResetTask?.cancel()
        burstResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(FDS.Spring.standard) { self?.showXPBurst = false }
        }

        guard leveledUp else { return }
        choreographedHaptic(.milestone)
        withAnimation(FDS.Spring.hero) { showLevelUp = true }
        levelUpResetTask?.cancel()
        levelUpResetTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_800_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(FDS.Spring.standard) { self?.showLevelUp = false }
        }
    }

    /// Cancels pending celebration resets when chat leaves the screen.
    func cancelPendingAnimations() {
        burstResetTask?.cancel();   burstResetTask = nil
        levelUpResetTask?.cancel(); levelUpResetTask = nil
        showXPBurst = false
        showLevelUp = false
    }
}

struct XPBurstView: View {
    let amount: Int
    @State private var scale:   CGFloat = 0.5
    @State private var opacity: Double  = 0
    @State private var offset:  CGFloat = 0

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(Color(hex: "FFD700"))
            Text("+\(amount) XP")
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundColor(Color(hex: "FFD700"))
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(Color(hex: "FFD700").opacity(0.15))
        .cornerRadius(FDS.Radius.pill)
        .overlay(Capsule().stroke(Color(hex: "FFD700").opacity(0.4), lineWidth: 1))
        .shadow(color: Color(hex: "FFD700").opacity(0.45), radius: 12, y: 4)
        .scaleEffect(scale)
        .opacity(opacity)
        .offset(y: offset)
        .onAppear {
            withAnimation(FDS.Spring.hero) { scale = 1.1; opacity = 1 }
            withAnimation(FDS.Spring.snap.delay(0.18)) { scale = 1.0 }
            withAnimation(.easeIn(duration: 0.5).delay(0.9)) { opacity = 0; offset = -24 }
        }
    }
}

struct LevelUpBanner: View {
    let level: Int
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Color(hex: "FFD700"), Color(hex: "FFA500")],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 52, height: 52)
                            .shadow(color: Color(hex: "FFD700").opacity(0.6), radius: 16)
                        Image(systemName: "crown.fill")
                            .font(.system(size: 24))
                            .foregroundColor(.white)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text("LEVEL UP!")
                            .font(.system(size: 11, weight: .black))
                            .tracking(2.5)
                            .foregroundColor(Color(hex: "FFD700"))
                        Text("You reached Level \(level)")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.textPrimary)
                        Text("ARIA is unlocking new insights for you.")
                            .font(.system(size: 12))
                            .foregroundColor(.textSecondary)
                    }
                }
            }
            .padding(20)
            .background(ZStack {
                Color.surface.opacity(0.96)
                LinearGradient(colors: [Color(hex: "FFD700").opacity(0.07), .clear], startPoint: .top, endPoint: .bottom)
            })
            .cornerRadius(FDS.Radius.xl)
            .overlay(RoundedRectangle(cornerRadius: FDS.Radius.xl)
                .stroke(Color(hex: "FFD700").opacity(0.35), lineWidth: 1.5))
            .shadow(color: Color(hex: "FFD700").opacity(0.2), radius: 28, y: 10)
            .padding(.horizontal, 20).padding(.bottom, 120)
            .scaleEffect(appeared ? 1 : 0.82)
            .opacity(appeared ? 1 : 0)
            .onAppear { withAnimation(FDS.Spring.hero.delay(0.1)) { appeared = true } }
        }
    }
}

struct MicroConfettiBurst: View {
    let at: CGPoint
    @State private var particles: [BurstParticle] = []
    @State private var launched = false

    private struct BurstParticle: Identifiable {
        let id: Int; let color: Color; let angle: Double; let speed: CGFloat; let size: CGFloat
    }
    private let colors: [Color] = [.ember, Color(hex: "22C55E"), Color.steel,
                                    Color(hex: "FFD700"), Color(hex: "A855F7")]

    var body: some View {
        ZStack {
            ForEach(particles) { p in
                Circle()
                    .fill(p.color)
                    .frame(width: p.size, height: p.size)
                    .offset(
                        x: launched ? cos(p.angle) * p.speed : 0,
                        y: launched ? sin(p.angle) * p.speed : 0
                    )
                    .opacity(launched ? 0 : 1)
                    .animation(.easeOut(duration: 0.8), value: launched)
            }
        }
        .position(at)
        .onAppear {
            particles = (0..<16).map { i in
                BurstParticle(
                    id: i,
                    color: colors[i % colors.count],
                    angle: Double(i) / 16.0 * .pi * 2,
                    speed: CGFloat.random(in: 40...90),
                    size:  CGFloat.random(in: 4...9)
                )
            }
            withAnimation { launched = true }
        }
    }
}
