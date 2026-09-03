import SwiftUI

struct ChatEmptyStateView: View {
    let mood: ARIAMood
    let onQuickActionTap: (String) -> Void
    var onVoiceTap: (() -> Void)? = nil
    @EnvironmentObject var store: AppStore
    @State private var appeared  = false
    @State private var orbPulse  = false
    @State private var orbGlow   = false

    // Greeting message varies by mood
    private var greeting: String {
        let first = store.userProfile.name.components(separatedBy: " ").first ?? ""
        let who = first.isEmpty ? "" : ", \(first)"
        switch mood {
        case .energized: return "The window's open\(who).\nWant to step through it?"
        case .focused:   return "I'm already listening\(who).\nYou don't have to know what to ask."
        case .calm:      return "Quiet has a shape tonight\(who).\nWe can stay inside it."
        case .pushed:    return "I felt that.\nWe don't have to name it yet."
        }
    }

    private var subtext: String {
        let life = AriaLifeRead.from(tags: AriaContextStore.shared.context.lifestyleTags)
        if let story = life.story, !story.isEmpty { return story }
        switch mood {
        case .energized: return "You've got a window. We can train if you want."
        case .focused:   return "I'll use last night and today's load — just talk."
        case .calm:      return "Recovery is part of training. We can keep it light."
        case .pushed:    return "We go at your pace. No pressure."
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 36)

            ZStack {
                ForEach(0..<3, id: \.self) { i in
                    let ringSize = CGFloat(168 + i * 52)
                    let ringAnimation = Animation.easeOut(duration: 3.6 + Double(i) * 0.8)
                        .repeatForever(autoreverses: false)
                        .delay(Double(i) * 0.9)

                    Circle()
                        .stroke(mood.accentColor.opacity(0.07 - Double(i) * 0.018), lineWidth: 0.6)
                        .frame(width: ringSize, height: ringSize)
                        .scaleEffect(orbPulse ? 1.22 : 1.0)
                        .opacity(orbPulse ? 0 : 0.85)
                        .animation(ringAnimation, value: orbPulse)
                }

                Circle()
                    .fill(RadialGradient(
                        colors: [
                            mood.accentColor.opacity(orbGlow ? 0.18 : 0.05),
                            Color(hex: "7B61FF").opacity(orbGlow ? 0.06 : 0.015),
                            .clear
                        ],
                        center: .center, startRadius: 8, endRadius: 110
                    ))
                    .frame(width: 220, height: 220).blur(radius: 36)

                AuroraOrbView(state: .idle, amplitude: 0.32, mood: mood, size: 128)
            }
            .scaleEffect(appeared ? 1 : 0.72)
            .opacity(appeared ? 1 : 0)
            .animation(FDS.Spring.fluid.delay(0.06), value: appeared)
            .padding(.bottom, 28)

            VStack(spacing: 10) {
                Text(greeting)
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.white, .white.opacity(0.7)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .minimumScaleFactor(0.85)

                Text(subtext)
                    .font(.system(size: 15, weight: .regular, design: .rounded))
                    .foregroundColor(.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .opacity(appeared ? 1 : 0)
            .offset(y: appeared ? 0 : 14)
            .animation(FDS.Spring.fluid.delay(0.18), value: appeared)
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, 16)

            if let onVoiceTap {
                Button(action: onVoiceTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .semibold))
                        Text("I'm listening")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        Capsule()
                            .fill(Color.white.opacity(0.06))
                            .overlay(
                                Capsule().stroke(
                                    LinearGradient(
                                        colors: [Color.ember.opacity(0.7), Color(hex: "7B61FF").opacity(0.35)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    ),
                                    lineWidth: 1
                                )
                            )
                    )
                    .shadow(color: Color.ember.opacity(0.28), radius: 14, y: 4)
                }
                .buttonStyle(ScaleButtonStyle())
                .accessibilityLabel("Talk to ARIA")
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 10)
                .animation(FDS.Spring.hero.delay(0.22), value: appeared)
                .padding(.bottom, 24)
            } else {
                Color.clear.frame(height: 16)
            }

            // Smart suggested prompts
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("OR BEGIN HERE")
                        .forgeSectionLabel()
                    Spacer()
                    Text(mood.displayName.lowercased())
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundColor(mood.accentColor.opacity(0.85))
                }
                .padding(.horizontal, 4)

                let prompts: [(String, String)] = [
                    ("Who are you?", "sparkles"),
                    ("How did I sleep?", "moon.fill"),
                    ("What should I train?", "figure.strengthtraining.traditional"),
                    ("How do I show up?", "heart.fill"),
                ]

                ForEach(Array(prompts.enumerated()), id: \.offset) { i, prompt in
                    Button { onQuickActionTap(prompt.0) } label: {
                        HStack(spacing: 14) {
                            ZStack {
                                Circle()
                                    .fill(
                                        LinearGradient(
                                            colors: [
                                                mood.accentColor.opacity(0.28),
                                                mood.accentColor.opacity(0.10)
                                            ],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )
                                    .frame(width: 34, height: 34)
                                Image(systemName: prompt.1)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(mood.accentColor)
                            }
                            Text(prompt.0)
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundColor(.textPrimary)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.textMuted)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .forgeInnerWell(cornerRadius: FDS.Radius.lg)
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
            withAnimation(.easeOut(duration: 3.4).repeatForever(autoreverses: false)) { orbPulse = true }
            withAnimation(.easeInOut(duration: 4.2).repeatForever(autoreverses: true)) { orbGlow = true }
        }
    }
}
