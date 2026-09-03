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
        case .energized: return "You look ready today\(who).\nWant a session that uses that?"
        case .focused:   return "I’m here\(who).\nTrain, recover, eat, live — pick a coach or just talk."
        case .calm:      return "Easy does it\(who).\nHow are you feeling?"
        case .pushed:    return "Rough day? That’s okay.\nI’m here for whatever you need."
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

            // Shared ARIA orb — same mark as the header, tab, and briefing.
            ZStack {
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

                Circle()
                    .fill(RadialGradient(
                        colors: [mood.accentColor.opacity(orbGlow ? 0.28 : 0.12), .clear],
                        center: .center, startRadius: 0, endRadius: 75
                    ))
                    .frame(width: 150, height: 150).blur(radius: 22)

                AuroraOrbView(state: .idle, amplitude: 0.28, mood: mood, size: 110)
            }
            .scaleEffect(appeared ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(FDS.Spring.floaty.delay(0.08), value: appeared)
            .padding(.bottom, 28)

            // Greeting
            VStack(spacing: 10) {
                Text(greeting)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundColor(.textPrimary)
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
            .animation(FDS.Spring.hero.delay(0.18), value: appeared)
            .padding(.horizontal, FDS.Spacing.lg)
            .padding(.bottom, 16)

            if let onVoiceTap {
                Button(action: onVoiceTap) {
                    HStack(spacing: 8) {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 13, weight: .semibold))
                        Text("Talk to ARIA")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 11)
                    .background(FDS.Gradient.emberDeep)
                    .clipShape(Capsule())
                    .shadow(color: Color.ember.opacity(0.4), radius: 10, y: 4)
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
                    Text("ARIA SUGGESTS")
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
            withAnimation(.easeOut(duration: 2.0).repeatForever(autoreverses: false)) { orbPulse = true }
            withAnimation(.easeInOut(duration: FDS.Duration.breathe).repeatForever(autoreverses: true)) { orbGlow = true }
        }
    }
}
