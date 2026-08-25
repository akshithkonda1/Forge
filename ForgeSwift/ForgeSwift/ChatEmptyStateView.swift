import SwiftUI

struct ChatEmptyStateView: View {
    let mood: ARIAMood
    let onQuickActionTap: (String) -> Void
    @EnvironmentObject var store: AppStore
    @State private var appeared  = false
    @State private var orbPulse  = false
    @State private var orbGlow   = false
    @State private var wavePhase: Double = 0

    // Greeting message varies by mood
    private var greeting: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        switch mood {
        case .energized: return "You look ready today\(first.isEmpty ? "" : ", \(first)").\nWant a session that uses that?"
        case .focused:   return "I’m here\(first.isEmpty ? "" : ", \(first)").\nWhat’s on your mind?"
        case .calm:      return "Easy does it\(first.isEmpty ? "" : ", \(first)").\nHow are you feeling?"
        case .pushed:    return "Rough day? That’s okay.\nI’m here for whatever you need."
        }
    }

    private var subtext: String {
        switch mood {
        case .energized: return "Readiness is high — we can train if you want."
        case .focused:   return "I’ll use last night’s sleep and today’s load."
        case .calm:      return "Recovery is part of training. We can keep it light."
        case .pushed:    return "We go at your pace. No pressure."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            // Animated ARIA orb
            ZStack {
                // Outer breathing rings
                ForEach(0..<3, id: \.self) { i in
                    let ringOpacity = 0.05 - Double(i) * 0.015
                    let ringSize = CGFloat(170 + i * 48)
                    let ringAnimation = Animation.easeOut(duration: 2.2 + Double(i) * 0.4)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.55)

                    Circle()
                        .fill(mood.accentColor.opacity(ringOpacity))
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(orbPulse ? 1.15 : 1.0)
                        .opacity(orbPulse ? 0 : 0.8)
                        .animation(ringAnimation, value: orbPulse)
                }

                // Bloom
                Circle()
                    .fill(RadialGradient(
                        colors: [mood.accentColor.opacity(orbGlow ? 0.28 : 0.12), .clear],
                        center: .center, startRadius: 0, endRadius: 75
                    ))
                    .frame(width: 150, height: 150).blur(radius: 22)

                // Core orb
                Circle()
                    .fill(LinearGradient(
                        colors: [mood.accentColor.opacity(0.24), mood.accentColor.opacity(0.08)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ))
                    .frame(width: 96, height: 96)
                    .overlay(Circle().stroke(
                        LinearGradient(colors: [mood.accentColor.opacity(0.55), mood.accentColor.opacity(0.1)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5
                    ))
                    .shadow(color: mood.accentColor.opacity(orbGlow ? 0.55 : 0.2), radius: orbGlow ? 28 : 12)

                // Screen-blend bloom
                Circle()
                    .fill(RadialGradient(
                        colors: [Color.white.opacity(orbGlow ? 0.12 : 0.04), .clear],
                        center: .center, startRadius: 0, endRadius: 48
                    ))
                    .frame(width: 96, height: 96).blendMode(.screen)

                // Waveform inside orb
                TimelineView(.animation(minimumInterval: 1.0/30.0)) { tl in
                    let t = tl.date.timeIntervalSinceReferenceDate
                    Canvas { ctx, size in
                        let mid = size.height / 2
                        var path = Path()
                        for xi in 0...Int(size.width) {
                            let x = CGFloat(xi)
                            let y = mid + 14 * CGFloat(sin(Double(x/size.width) * .pi * 4 + t * 1.8))
                            if xi == 0 { path.move(to: CGPoint(x: x, y: y)) }
                            else { path.addLine(to: CGPoint(x: x, y: y)) }
                        }
                        ctx.stroke(path, with: .color(Color.white.opacity(0.35)), lineWidth: 1.5)
                    }
                }
                .frame(width: 60, height: 30)
                .clipShape(Circle().scale(0.58))

                Image(systemName: "brain.head.profile")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(LinearGradient(
                        colors: [mood.accentColor, mood.accentColor.opacity(0.7)],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .shadow(color: mood.accentColor.opacity(0.5), radius: 10)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(FDS.Spring.floaty.delay(0.08), value: appeared)
            .padding(.bottom, 28)

            // Greeting
            VStack(spacing: 8) {
                Text(greeting)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundColor(.textPrimary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)

                Text(subtext)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(FDS.Spring.hero.delay(0.18), value: appeared)
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, 32)

            // Smart suggested prompts
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("ARIA SUGGESTS")
                        .font(.system(size: 9, weight: .black))
                        .tracking(2.8)
                        .foregroundColor(.textMuted)
                    Spacer()
                    Text("based on \(mood.displayName.lowercased()) mode")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(mood.accentColor.opacity(0.7))
                }
                .padding(.horizontal, 4)

                let prompts: [(String, String)] = [
                    mood == .energized ? ("Let's go heavy today", "bolt.fill") : ("What's right for today?", "sparkles"),
                    ("How'd I sleep?", "moon.fill"),
                    ("Am I making progress?", "chart.line.uptrend.xyaxis"),
                ]

                ForEach(Array(prompts.enumerated()), id: \.offset) { i, prompt in
                    Button { onQuickActionTap(prompt.0) } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(mood.accentColor.opacity(0.14))
                                    .frame(width: 32, height: 32)
                                Image(systemName: prompt.1)
                                    .font(.system(size: 13))
                                    .foregroundColor(mood.accentColor)
                            }
                            Text(prompt.0)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.horizontal, 16).padding(.vertical, 14)
                        .background(Color.surfaceElevated)
                        .cornerRadius(FDS.Radius.md)
                        .overlay(RoundedRectangle(cornerRadius: FDS.Radius.md)
                            .stroke(Color.borderColor.opacity(0.5), lineWidth: 0.5))
                    }
                    .buttonStyle(ScaleButtonStyle())
                    .opacity(appeared ? 1 : 0)
                    .offset(y: appeared ? 0 : 18)
                    .animation(FDS.Spring.hero.delay(0.28 + Double(i) * 0.07), value: appeared)
                }
            }
            .padding(.horizontal, FDS.Spacing.lg)

            Spacer(minLength: 36)
        }
        .onAppear {
            appeared = true
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) { orbPulse = true }
            withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { orbGlow = true }
        }
    }
}
